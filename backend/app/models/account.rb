class Account < ApplicationRecord
  # requirement.md §4.3: blocked so a tenant can never claim a slug that would collide with a
  # platform route (apex, api, admin app chrome, the shared public-site subdomain, etc.).
  RESERVED_SLUGS = %w[
    www api admin app mail events login platform
  ].freeze

  enum :status, { active: 0, suspended: 1 }

  # requirement.md revisit: "While registering the Tenant, we should capture ... Logo." No
  # TenantScopedAttachment#attach_tenant_scoped here — that concern is for resources *belonging
  # to* an account (Participant#photo, Badge#logo, ...), keyed by `account.subdomain_slug`; here
  # the account itself IS that account, so #attach_logo below calls TenantScopedAttachment's own
  # module-level .blob_key directly, passing `self`, for the exact same tenant-namespaced
  # Cloudinary folder shape every other attachment in this app already uses.
  has_one_attached :logo

  has_many :account_memberships, dependent: :destroy
  has_many :users, through: :account_memberships
  has_many :tenant_domains, dependent: :destroy
  # Fixed-hierarchy pivot (requirement.md revisit, confirmed with the user): every new Account is
  # created from inside its Agency's own console now (AgencyConsole::AccountsController, AccountProvisioning's
  # agency: kwarg) — `optional: true` only because legacy standalone accounts provisioned before
  # this pivot (agency: nil) are left alone in the DB, not migrated onto one; the Super Admin's own
  # tenant-creation form is gone (§2), so no *new* standalone Account can come into existence.
  belongs_to :agency, optional: true
  # requirement.md §4.9 item 4: one OAuth application per Account, auto-created at provisioning
  # time (Phase 2). association extended onto Doorkeeper::Application in
  # config/initializers/doorkeeper_application_account.rb.
  has_one :oauth_application, class_name: "Doorkeeper::Application", dependent: :destroy
  # Phase 4: Event is TenantScoped (default-scoped to Current.account) — that's orthogonal to
  # this association, which just adds the plain `WHERE account_id = ?` regardless of which
  # console/context is asking, same as every other has_many here.
  has_many :events, dependent: :destroy
  has_many :event_staff_assignments, dependent: :destroy
  # Unlike TicketCategory/Participant/etc. (which cascade transitively through Event), a
  # BadgeTemplate (Phase 8) has no Event parent to cascade through — it's account-scoped
  # directly, as a reusable library — so it needs its own explicit dependent: :destroy here.
  has_many :badge_templates, dependent: :destroy
  # Phase 15 — Platform Billing & Invoicing, revisited (requirement.md §4.6, confirmed with the
  # user): same "no Event parent to cascade through" reasoning as badge_templates above — a
  # Quotation exists *before* any Event can (that's the whole point of the gate, Event's own
  # quotation_must_be_approved_and_available), so it's account-scoped directly. Invoice doesn't get
  # its own entry here — it belongs_to :event, so it already cascades transitively through
  # `has_many :events` above, same as every other Event-child table.
  has_many :quotations, dependent: :destroy
  # Phase 10 — Print Agent (Electron) Integration (requirement.md §5.5.1). Already cascades
  # transitively through `has_many :events, dependent: :destroy` above (PrintStation belongs_to
  # :event) — this association exists only so PrintAgentController#pair can look a pairing code
  # up across every event in the tenant that arrived on (`Current.account.print_stations.find_by`),
  # not because it needs its own destroy behavior.
  has_many :print_stations

  validates :name, presence: true
  validates :subdomain_slug, presence: true,
                              uniqueness: { case_sensitive: false },
                              format: {
                                with: /\A[a-z0-9]([a-z0-9-]*[a-z0-9])?\z/,
                                message: "must be lowercase alphanumeric with hyphens, no leading/trailing hyphen"
                              },
                              length: { minimum: 3, maximum: 63 },
                              exclusion: { in: RESERVED_SLUGS, message: "is a reserved word" }
  # Cross-table counterpart to Agency's own identical check — see that model's own comment for why
  # (TenantResolvable's Account-then-Agency lookup needs an unambiguous answer).
  validate :subdomain_slug_not_taken_by_an_agency

  # requirement.md revisit: "While registering the Tenant, we should capture ... contact email,
  # contact num ... sender email." on: :create only — a tenant provisioned before this feature
  # existed can still be edited/suspended/reinstated without first being forced to backfill these;
  # only a *new* registration actually requires them, matching the requirement's own wording.
  # Presence and format are deliberately two SEPARATE `validates` calls per field, not one shared
  # call with `allow_blank: true` tacked on — Rails' `validates` macro merges any option declared
  # outside the per-validator-type hashes into *every* validator in that same call, so a combined
  # `validates :x, presence: { on: :create }, format: {...}, allow_blank: true` silently neuters
  # its own presence check (a blank value would short-circuit past PresenceValidator too, the one
  # validator whose entire job is flagging blank values). format's own allow_blank is what lets a
  # still-blank legacy value skip the format check without also skipping presence on create.
  validates :contact_email, presence: { on: :create }
  validates :contact_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :sender_email, presence: { on: :create }
  validates :sender_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :contact_num, presence: { on: :create }

  # requirement.md revisit: "we should capture the event timezone and all the dates which are
  # display in the UI should abey the tenant timezone." One zone per tenant (not per event) —
  # TenantResolvable#with_tenant_time_zone (app/controllers/concerns/tenant_resolvable.rb) applies
  # it to every tenant-scoped request via Time.use_zone, and ApplicationMailer#mail applies it to
  # every tenant-scoped mailer the same way — between Rails' own time_zone_aware_attributes
  # (default on) and both of those, every existing strftime/to_fs call anywhere in this app
  # already renders in the tenant's own zone with no per-view changes needed. Always required
  # (not on: :create) — the "UTC" DB default (see this column's own migration) means every
  # pre-existing row already satisfies this, and a blank value here would silently break Time.zone
  # application for every future request, unlike the three contact fields above which only affect
  # what's displayed, never how it's computed.
  validates :time_zone, presence: true, inclusion: { in: ActiveSupport::TimeZone.all.map(&:name) }

  before_validation { self.subdomain_slug = subdomain_slug&.downcase }

  # Phase 13/14 — Communications/Reporting (requirement.md §3.10, §5.10, §5.11): "the organizer is
  # notified" recurs across event rejection (Phase 13), and now scheduled report delivery (Phase
  # 14) — same recipient set both times, previously inlined separately at each call site. Renamed
  # from #owner_users (Agency layer role remap, requirement.md revisit) — the `owner` role no
  # longer exists; `event_admin` is its merged replacement (AccountMembership's own comment) and,
  # for an agency-linked tenant, already includes that agency's own staff too (every agency_admin
  # gets an event_admin AccountMembership auto-created on each of their agency's tenants —
  # AccountProvisioning's own comment), so this needs no agency-specific branch of its own.
  def admin_users
    account_memberships.event_admin.includes(:user).map(&:user)
  end

  def attach_logo(uploaded_file)
    return if uploaded_file.blank?

    logo.attach(
      io: uploaded_file,
      filename: uploaded_file.original_filename,
      content_type: uploaded_file.content_type,
      key: TenantScopedAttachment.blob_key(self, "logo", filename: uploaded_file.original_filename)
    )
  end

  private

  def subdomain_slug_not_taken_by_an_agency
    return if subdomain_slug.blank?

    errors.add(:subdomain_slug, "has already been taken") if Agency.where("lower(subdomain_slug) = ?", subdomain_slug).exists?
  end
end
