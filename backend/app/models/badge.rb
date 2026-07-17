# Phase 8 — Badge Design & Printing (requirement.md §3.6, §5.5). Per-event instantiation of a
# BadgeTemplate (or a fresh one, never linked to a template at all) — `badge_template_id` is only
# provenance, not a live reference; content/mapping/size are copied in at creation
# (.build_from_template) and edited independently from then on.
#
# `ticket_category` nullable is what makes conditional-by-category badges work (requirement.md
# §5.5: "VIP vs. Attendee vs. Speaker badge from one event without duplicating templates"): nil
# means "this event's default badge," used for any participant whose own category has no
# category-specific Badge of its own (see Event#badge_for).
class Badge < ApplicationRecord
  include TenantScoped
  include TenantScopedAttachment
  include HasBadgeMapping

  belongs_to :event
  belongs_to :ticket_category, optional: true
  belongs_to :badge_template, optional: true

  has_one_attached :background_image
  has_one_attached :logo

  validates :ticket_category_id, uniqueness: { scope: :event_id }, allow_nil: true
  validate :only_one_default_badge_per_event

  def self.build_from_template(template, event:, ticket_category: nil)
    badge = event.badges.build(
      account: event.account,
      ticket_category: ticket_category,
      badge_template: template,
      name: template.name,
      content: template.content,
      mapping: template.mapping,
      output_type: template.output_type,
      width_cm: template.width_cm,
      height_cm: template.height_cm
    )
    badge.background_image.attach(template.background_image.blob) if template.background_image.attached?
    badge.logo.attach(template.logo.blob) if template.logo.attached?
    badge
  end

  # "Copy to another ticket category" (Admin::BadgesController#copy) — designing the same badge
  # from scratch for every ticket category was the reported pain; this reduces it to "copy, then
  # review/adjust." Same shape .build_from_template already uses (content/mapping/size/background/
  # logo copied in, edited independently from then on — `.attach(source.blob)`, not a re-upload,
  # shares the existing blob across both records), just sourcing from another Badge instead of a
  # BadgeTemplate. `badge_template:` carries the source's own provenance forward, if it has one —
  # a copy of a copy is still ultimately "from" whatever template started the chain.
  #
  # `name:` is the one field deliberately NOT copied verbatim — defaults to the target category's
  # own name (or "Default" for the no-category slot) instead of inheriting the source badge's
  # name, so a tenant copying "VIP Badge" onto Student doesn't end up with a badge named "VIP
  # Badge" applying to students. Still just a starting value on an ordinary attribute — the
  # tenant's own review pass on the copy's editor (where this lands) can rename it to anything.
  def self.build_from_badge(source, ticket_category:)
    badge = source.event.badges.build(
      account: source.account,
      ticket_category: ticket_category,
      badge_template: source.badge_template,
      name: ticket_category&.name || "Default",
      content: source.content,
      mapping: source.mapping,
      output_type: source.output_type,
      width_cm: source.width_cm,
      height_cm: source.height_cm
    )
    badge.background_image.attach(source.background_image.blob) if source.background_image.attached?
    badge.logo.attach(source.logo.blob) if source.logo.attached?
    badge
  end

  def attach_background_image(uploaded_file)
    attach_tenant_scoped(:background_image, uploaded_file, "events", event_id, "badges", "background_image")
  end

  def attach_logo(uploaded_file)
    attach_tenant_scoped(:logo, uploaded_file, "events", event_id, "badges", "logo")
  end

  # Phase 7.5 — Dynamic Registration Form Builder (requirement.md §5.4/§5.14 v12): "whatever
  # fields are placed on a ticket category's badge design are automatically mandatory on that
  # category's registration form." This is the "which fields does this badge actually display"
  # half of that rule — TicketCategory#effective_catalog_fields is what applies the result.
  #
  # Only ever returns Event::PARTICIPANT_FIELD_CATALOG entries — the toggleable catalog a
  # RegistrationForm's own `catalog_fields` is keyed against — never an organizer-defined
  # CustomField. A badge has no mechanism to reference a custom field's jsonb value at all
  # (HasBadgeMapping::MAPPABLE_FIELDS, what $OTHER1$/$OTHER2$/$OTHER3$ can map to, is a fixed
  # Participant-column allowlist), so there's nothing to enforce there. `$NAME$`/`$GOVT_ID$`/QR/
  # barcode variants have no catalog counterpart at all — `$NAME$` is Participant's own derived
  # full name, not a directly editable column, and the rest are either non-form tokens or fields
  # the catalog never covered — and are silently ignored here; `$PHOTO$` does have one (`photo`
  # joined the catalog in the same v12 revisit that added this token mapping — "add photo and
  # document in the default form"; there's no equivalent `$DOCUMENT$` token, badges don't display
  # documents, so `document` only ever becomes mandatory via TicketCategory#document_required?,
  # not through this method). `$OTHER1$`/`$OTHER2$`/`$OTHER3$` come from `mapping` instead of
  # `content` (see HasBadgeMapping, BadgeReformService#other_field_value) — whatever
  # catalog-eligible field an organizer has mapped one of those slots to counts the same as a
  # direct token.
  TOKEN_TO_CATALOG_FIELD = {
    "TITLE" => "title", "FIRST_NAME" => "first_name", "LAST_NAME" => "last_name",
    "DESIGNATION" => "position", "PHOTO" => "photo"
  }.freeze

  def required_catalog_fields
    tokens = content.to_s.scan(BadgeReformService::TOKEN_PATTERN).flatten
    from_content = tokens.filter_map { |token| TOKEN_TO_CATALOG_FIELD[token] }
    from_mapping = mapping.values.select { |field| Event::PARTICIPANT_FIELD_CATALOG.include?(field) }

    (from_content + from_mapping).uniq
  end

  private

  # The partial unique index (db/migrate/*_create_badges.rb) is the real backstop — this is just
  # what turns a race-free duplicate into a friendly validation error instead of a raw
  # ActiveRecord::RecordNotUnique on save.
  def only_one_default_badge_per_event
    return if ticket_category_id.present?

    scope = Badge.where(event_id: event_id, ticket_category_id: nil)
    scope = scope.where.not(id: id) if persisted?
    errors.add(:base, "This event already has a default badge") if scope.exists?
  end
end
