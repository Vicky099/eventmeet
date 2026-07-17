# Phase 7 — Participant Lifecycle (requirement.md §3.4, §5.4, §8) — "the deepest
# data-integrity-sensitive module carried from the baseline." Public self-registration is Phase
# 18's Next.js site; this phase is admin manual entry (Admin::ParticipantsController) plus bulk
# XLSX import (ParticipantImportJob), both funneling through the same dedupe chain and validations
# defined here so neither path can create a record the other would have rejected.
class Participant < ApplicationRecord
  include TenantScoped
  include TenantScopedAttachment
  include HasCountryFields

  belongs_to :event
  belongs_to :ticket_category, optional: true
  # Phase 9 (requirement.md §3.7). restrict_with_error, not destroy — scan/attendance history is
  # exactly the kind of record §3.7's "tracked historically, not just as current state" means to
  # protect; deleting a participant who's already been scanned should fail cleanly (same pattern
  # TicketCategory's own has_many :participants already uses) rather than silently discard it.
  has_many :scan_events, dependent: :restrict_with_error
  has_many :attendances, dependent: :restrict_with_error

  has_one_attached :photo
  has_one_attached :document
  # File-type CustomField responses (ticket_category.registration_form's own custom_fields, Phase
  # 7.5) land here, one attachment per field —
  # the specific blob for a given field is looked up via its signed_id stored in
  # custom_field_values (see Admin::ParticipantsController#apply_custom_field_values), since
  # has_many_attached doesn't support per-field named slots the way has_one_attached does.
  has_many_attached :custom_field_files

  # manual/upload/client_api (requirement.md §3.4) — client_api is a value only until Phase 16
  # wires a real inbound API path that sets it; nothing produces it yet.
  enum :source, { manual: 0, upload: 1, client_api: 2 }
  # pending/confirmed — see Event#participant_approval_required /
  # Event#default_participant_status, which decide which one a new Participant starts as.
  enum :status, { pending: 0, confirmed: 1 }

  before_validation :generate_identifiers, on: :create
  # first_name/last_name are the primary captured fields (the manual-entry form and bulk import
  # both write these, not `name` directly) — `name` stays a real, always-populated column derived
  # from them here, rather than becoming a virtual method, so every existing read site (dedupe
  # matching below, the badge $NAME$ token, index/scan-result displays) keeps working unchanged.
  # `title` (salutation) is deliberately excluded from the derived name — badges show it as its
  # own separate token.
  before_validation :derive_full_name
  after_create :increment_live_stats!
  # Phase 9 (requirement.md §5.15): "live registered-participant counts ... update instantly
  # across every connected dashboard." after_commit (not after_create) — the broadcast must only
  # fire once the row (and its EventLiveStats increment, same transaction) is actually durable;
  # broadcasting from inside the transaction risks a subscriber re-reading a row Postgres hasn't
  # committed yet, or a broadcast surviving a subsequent rollback.
  after_create_commit :broadcast_live_stats!
  # Event Basic Info gap-fill: "Allow to send email on Attendee registration?" — same
  # after_commit-not-after_create reasoning as broadcast_live_stats! above (never mail out a row
  # a subsequent rollback would undo).
  after_create_commit :send_registration_confirmation!
  # requirement.md revisit: "once participant registration start then the government ID will
  # start assign to participant" / "while uploading the govtID it should automatically assign to
  # the participant." after_commit, same reasoning as the two callbacks above — GovtId#assign_to!/
  # #claim_existing_value! write through a *second* table (the pool row) in their own follow-up
  # transaction, which must never run against a participant row a rollback could still undo.
  after_create_commit :sync_govt_id_with_pool!

  validates :first_name, presence: true
  validates :hex_id, presence: true, uniqueness: true
  validates :client_participant_id, presence: true, uniqueness: { scope: :event_id }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  # requirement.md revisit: "GOVT ID will be unique by event." #not_a_duplicate below already
  # covers this on create (it's that cascade's own highest-priority tier, with a friendlier
  # "Duplicate of X" message) — scoped to :update only so editing a participant's govt_id to
  # collide with another one in the same event is finally caught too (previously nothing
  # validated a govt_id changed after creation at all). The real backstop either way is the
  # partial unique DB index (db/migrate/..._add_unique_index_on_participants_govt_id.rb) — it's
  # what actually protects GovtId's own update_column writes, which skip Rails validations
  # entirely by design.
  validates :govt_id, uniqueness: { scope: :event_id }, allow_blank: true, on: :update

  validate :required_fixed_fields_present
  validate :required_custom_fields_present
  validate :not_a_duplicate, on: :create

  # requirement.md §3.11/§5.4: "fuzzy matching against existing records (govt ID -> email+name ->
  # email -> phone)" — a cascade, not four independent checks: try the highest-confidence
  # identifier first, and only fall through to the next tier if that one had nothing to check
  # (blank) or nothing to match. Scoped per event (requirement.md §3.4: "unique ... per event") —
  # the same person can register for two different events without conflict. Shared by both this
  # model's own validation and ParticipantImportJob, which needs the same lookup to report a
  # friendly "duplicate of X, matched on Y" reason per row instead of raising.
  #
  # requirement.md revisit: "we should have privilege to set the uniqueness for participant data
  # ... unique by email, unique by contact num or both ... same parameter should be used while
  # importing the data." uniqueness_fields (RegistrationForm::UNIQUENESS_FIELDS — a subset of
  # "email"/"contact_num", from TicketCategory#effective_uniqueness_fields) gates the email/
  # email+name/contact_num tiers below; nil (no organizer config found for this participant's
  # category) keeps every tier active, i.e. the original unconditional cascade — a plain email
  # match still only requires "email" to be enabled, not "email_and_name" too, since the latter is
  # strictly stricter and would never find a match the former wouldn't also find. govt_id is
  # deliberately NOT gated by uniqueness_fields — it's a real external identifier column, not one
  # of the two configurable dimensions the organizer chooses between.
  def self.duplicate_match(event:, govt_id: nil, email: nil, name: nil, contact_num: nil, exclude_id: nil, uniqueness_fields: nil)
    scope = event.participants
    scope = scope.where.not(id: exclude_id) if exclude_id
    fields = uniqueness_fields.presence || RegistrationForm::UNIQUENESS_FIELDS

    if govt_id.present?
      match = scope.find_by(govt_id: govt_id)
      return [ match, :govt_id ] if match
    end
    if fields.include?("email") && email.present? && name.present?
      match = scope.find_by(email: email, name: name)
      return [ match, :email_and_name ] if match
    end
    if fields.include?("email") && email.present?
      match = scope.find_by(email: email)
      return [ match, :email ] if match
    end
    if fields.include?("contact_num") && contact_num.present?
      match = scope.find_by(contact_num: contact_num)
      return [ match, :contact_num ] if match
    end
    [ nil, nil ]
  end

  # .countries/.nationalities (backing the Nationality/Country dropdowns on the admin manual-entry
  # form, app/views/admin/participants/_form.html.erb) come from HasCountryFields, shared with
  # Speaker — see that concern's own comment.

  # Phase 9 (requirement.md §3.7): "participant located by scanning any of: hex ID, government ID,
  # RFID, or client participant ID." Same cascade shape as .duplicate_match above, but a single
  # scanned string can only plausibly be one kind of identifier, so this doesn't need that method's
  # confidence-tiering — it just tries each column in turn and returns the first hit. hex_id/
  # client_participant_id are generated uppercase (see generate_unique_hex_id/
  # generate_unique_client_participant_id below), so the incoming value is upcased before those two
  # comparisons; govt_id/rf_id are free-text as entered and compared as-is.
  def self.find_by_identifier(event, identifier)
    value = identifier.to_s.strip
    return nil if value.blank?

    event.participants.find_by(hex_id: value.upcase) ||
      event.participants.find_by(govt_id: value) ||
      event.participants.find_by(rf_id: value) ||
      event.participants.find_by(client_participant_id: value.upcase)
  end

  # photo/document use TenantScopedAttachment#attach_tenant_scoped directly (Admin::
  # ParticipantsController#apply_uploads calls it with this model's own segment shape) — no
  # override needed here anymore. Same tenant-namespacing, but for custom_field_files specifically
  # (has_many_attached, so "attach one and read back .attachments.last" is ambiguous/order-
  # dependent when the owning Participant isn't persisted yet). Builds the blob directly first so
  # its signed_id — what custom_field_values actually stores per field, not the attachment row
  # itself — is known immediately and unambiguously.
  def attach_custom_field_file(field_id, uploaded_file)
    return if uploaded_file.blank?

    blob = ActiveStorage::Blob.create_and_upload!(**tenant_scoped_blob_attributes(:custom_field_files, uploaded_file))
    custom_field_files.attach(blob)
    custom_field_values[field_id.to_s] = blob.signed_id
  end

  private

  def tenant_scoped_blob_attributes(attachment_name, uploaded_file)
    {
      io: uploaded_file,
      filename: uploaded_file.original_filename,
      content_type: uploaded_file.content_type,
      key: tenant_scoped_blob_key("participants", event_id, attachment_name, filename: uploaded_file.original_filename)
    }
  end

  # Phase 7 checklist: "EventLiveStats row seeded/incremented on participant create." Not gated on
  # status (pending?/confirmed?), since "registered" means "a Participant record exists for this
  # event," independent of whether it still needs organizer approval.
  #
  # Phase 9: switched to the atomic `update_counters` EventLiveStats#record_check_in!/
  # #record_check_out! also use, for the same reason — a burst of concurrent registrations (e.g. a
  # bulk import) racing a plain increment! read-modify-write can silently lose counts.
  def increment_live_stats!
    stats = event.live_stats!
    EventLiveStats.update_counters(stats.id, registered_count: 1)
  end

  # Phase 9 (requirement.md §5.15). LiveMetricBucket feeds the registration-velocity sparkline;
  # LiveDashboard re-renders the event's live-stats partial to every subscribed dashboard.
  def broadcast_live_stats!
    LiveMetricBucket.increment!(event: event, metric: :registration)
    LiveDashboard.broadcast_event_stats(event)
  end

  # Guarded on the event's own toggle (organizer opt-in, off by default) and on actually having an
  # email to send to — email isn't a universally-required participant field (Event#participant_fields
  # decides that per event), so a participant with none simply gets no confirmation, not an error.
  def send_registration_confirmation!
    return unless event.send_registration_email? && email.present?

    ParticipantMailer.confirmation(self).deliver_later
  end

  # requirement.md revisit — see GovtId's own comment for the full two-directions story. Already
  # has a value (typed in manually, or from Participant Import's "Govt ID" column) → reconcile the
  # pool's own bookkeeping so it never hands that value out again; no value yet → claim the next
  # available one from this event's pool, if any. A no-op event that's never uploaded a govt ID
  # list at all behaves exactly as it did before this feature existed either way.
  def sync_govt_id_with_pool!
    if govt_id.present?
      GovtId.claim_existing_value!(self)
    else
      GovtId.assign_to!(self)
    end
  end

  def generate_identifiers
    self.hex_id ||= generate_unique_hex_id
    self.client_participant_id ||= generate_unique_client_participant_id
  end

  def derive_full_name
    self.name = [ first_name, last_name ].compact_blank.join(" ")
  end

  # Globally unique (not per-event/per-account) — requirement.md §3.7: check-in scans "any of hex
  # ID, government ID, RFID, or client participant ID," and a hex_id is meant to function like a
  # scan-anywhere internal identifier. 48 bits of randomness makes a collision astronomically
  # unlikely; the retry loop (and the DB's own unique index) exist purely as a correctness
  # backstop, not because collisions are expected in practice.
  def generate_unique_hex_id
    loop do
      candidate = SecureRandom.hex(6).upcase
      break candidate unless Participant.unscoped_across_tenants { Participant.exists?(hex_id: candidate) }
    end
  end

  def generate_unique_client_participant_id
    loop do
      candidate = "P-#{SecureRandom.alphanumeric(8).upcase}"
      break candidate unless event.participants.exists?(client_participant_id: candidate)
    end
  end

  # requirement.md §5.4: "Field-level requiredness driven by ... event config" — Phase 4's fixed
  # catalog (Event::PARTICIPANT_FIELD_CATALOG). Most of the catalog's keys match real column names
  # 1:1 (email/contact_num/company/department/position/nationality/country), so no separate
  # mapping table is needed here; photo/document are the two exceptions — has_one_attached
  # proxies, where `.blank?` is always false regardless of whether anything's actually attached
  # (ActiveStorage::Attached::One doesn't define #empty?, so ActiveSupport's generic
  # Object#blank? never treats it as blank), so those two check `.attached?` instead. Phase 7.5
  # (requirement.md §5.4/§5.14 v12) moved the *source* of which fields are actually required from
  # the event-wide Event#participant_fields onto this participant's own ticket_category
  # (TicketCategory#effective_catalog_fields — the organizer's configured catalog toggles unioned
  # with whatever fields that category's own badge design mandates, plus first_name/
  # ticket_category-required-document always forced true); no ticket_category selected yet means
  # nothing is enforced here at all, same as no RegistrationForm resolving means nothing's
  # enforced by #required_custom_fields_present below.
  ATTACHMENT_CATALOG_FIELDS = %w[photo document].freeze

  def required_fixed_fields_present
    return unless ticket_category

    fields = ticket_category.effective_catalog_fields
    Event::PARTICIPANT_FIELD_CATALOG.each do |field|
      next unless fields[field]

      present = ATTACHMENT_CATALOG_FIELDS.include?(field) ? public_send(field).attached? : public_send(field).present?
      errors.add(field, "can't be blank") unless present
    end
  end

  # requirement.md §5.4 new item — the other half of "requiredness": a CustomField marked
  # required: on this participant's own ticket_category (Phase 7.5 — rescoped from the old
  # event-wide Event#custom_fields; a category with no RegistrationForm of its own/no default form
  # configured yet simply has no custom fields to require). custom_field_values is keyed by the
  # CustomField's id (string, since jsonb keys are always strings) — see
  # Admin::ParticipantsController#apply_custom_field_values for how it gets populated from the
  # manual-entry form.
  def required_custom_fields_present
    custom_fields = ticket_category&.registration_form&.custom_fields
    return if custom_fields.blank?

    custom_fields.where(required: true).find_each do |field|
      errors.add(:base, "#{field.label} can't be blank") if custom_field_values[field.id.to_s].blank?
    end
  end

  def not_a_duplicate
    return unless event

    match, tier = Participant.duplicate_match(
      event: event, govt_id: govt_id, email: email, name: name, contact_num: contact_num, exclude_id: id,
      uniqueness_fields: ticket_category&.effective_uniqueness_fields
    )
    return unless match

    reason = { govt_id: "government ID", email_and_name: "email and name", email: "email", contact_num: "phone number" }.fetch(tier)
    errors.add(:base, "Duplicate of #{match.name} (matched on #{reason})")
  end
end
