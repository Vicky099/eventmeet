# requirement.md §4.1, §4.6, §4.7: the only way a tenant Account comes into existence — never
# self-serve. Fixed-hierarchy pivot (requirement.md revisit): provisioned from the agency's own
# console now (AgencyConsole::AccountsController), not the Platform Console — the Super Admin no
# longer creates tenants directly at all (SuperAdmin::AccountsController lost that ability, and
# now its whole standalone page, in the same pivot). One call creates the Account, its first
# (event_admin) admin User with a temp password (reuses
# Phase 1's forced-reset flow, User#must_reset_password), the AccountMembership tying them
# together, and the Account's one Doorkeeper::Application (§4.9 item 4) — all in one transaction,
# so a partial provision (e.g. an Account with no admin user) can never exist.
class AccountProvisioning
  Result = Struct.new(:account, :admin_user, :temp_password, :success, keyword_init: true) do
    alias_method :success?, :success
  end

  def self.call(...)
    new(...).call
  end

  # requirement.md revisit: "While registering the Tenant, we should capture ... Logo." logo: is
  # the raw uploaded file (or nil) — Account#attach_logo itself already no-ops on blank, so this
  # never needs its own presence check either.
  #
  # agency: (Agency layer, requirement.md revisit) — optional; when given, the new Account is
  # linked under it (Account#agency) AND every existing agency_admin of that agency gets an
  # event_admin AccountMembership on this brand-new tenant too, in the same transaction — this is
  # what lets an agency's own staff log into a tenant the moment it's provisioned, using nothing but
  # an ordinary tenant Devise session (no new auth machinery — see Agency's own model comment).
  def initialize(account_attributes:, admin_email:, logo: nil, agency: nil)
    @account = Account.new(account_attributes.merge(agency: agency))
    @logo = logo
    @agency = agency
    @temp_password = SecureRandom.base58(16)
    @admin_user = User.new(email: admin_email, password: @temp_password, must_reset_password: true)
  end

  def call
    success = false

    # `ActiveRecord::Rollback` unwinds the DB transaction without re-raising, but the in-memory
    # `account`/`admin_user` objects don't un-set their own persisted?/id state when that happens
    # (a well-known ActiveRecord quirk) — `success` is a plain local, not derived from those
    # objects afterwards, specifically so the caller can't be misled by that into treating a
    # rolled-back provision as real.
    ActiveRecord::Base.transaction do
      raise ActiveRecord::Rollback unless account.save

      account.attach_logo(logo)

      unless admin_user.save
        admin_user.errors.each { |error| account.errors.add(:admin_email, error.message) }
        raise ActiveRecord::Rollback
      end

      AccountMembership.create!(user: admin_user, account: account, role: :event_admin)
      agency&.users&.each do |agency_staff|
        next if agency_staff == admin_user # already just added, and would violate the AccountMembership uniqueness index

        AccountMembership.create!(user: agency_staff, account: account, role: :event_admin)
      end
      account.create_oauth_application!(name: "#{account.name} API")
      success = true
    end

    # Current.set(account:), not relying on the caller (AgencyConsole::AccountsController, running
    # under Current.agency, not Current.account — the new tenant itself doesn't exist yet for that
    # to be set to) having set any tenant context of its own — Notification includes TenantScoped,
    # whose default_scope runs even for a plain #create! (it pre-populates scope-derived
    # attributes on `.new`), so this
    # service needs to be correct on its own regardless of who's calling it.
    if success
      Current.set(account: account) do
        Notifier.email(
          mailer_class: AccountMailer, mailer_method: :welcome, mailer_args: [ admin_user, account, temp_password ],
          notifiable: account, account: account, to: admin_user.email, subject: "Welcome to xEvent — #{account.name} is ready"
        )
      end
    end

    Result.new(account: account, admin_user: admin_user, temp_password: temp_password, success: success)
  end

  private

  attr_reader :account, :admin_user, :temp_password, :logo, :agency
end
