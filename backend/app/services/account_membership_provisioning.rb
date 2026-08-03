# Agency layer: adds a new admin to an EXISTING Account (AgencyConsole::AccountMembershipsController
# #create) — distinct from AccountProvisioning, which only ever creates a tenant's very first
# admin alongside the Account itself. Mirrors AgencyMembershipProvisioning exactly, one tier down
# (that service's own comment has the full "why find_or_initialize_by(email:)" reasoning — this
# app still has no general "invite a teammate" flow, so this covers both "a brand-new person" and
# "an existing platform User who already has other memberships elsewhere" the same way). No
# cross-account backfill here, unlike that one's own agency.accounts.each loop — there's nothing
# below a single Account to backfill into.
class AccountMembershipProvisioning
  Result = Struct.new(:account_membership, :user, :temp_password, :success, keyword_init: true) do
    alias_method :success?, :success
  end

  def self.call(...)
    new(...).call
  end

  def initialize(account:, email:, role: :event_admin)
    @account = account
    @role = role
    @user = User.find_or_initialize_by(email: email)
    @is_new_user = !@user.persisted?
    @temp_password = @is_new_user ? SecureRandom.base58(16) : nil
  end

  def call
    success = false
    membership = nil

    ActiveRecord::Base.transaction do
      if is_new_user
        user.password = temp_password
        user.must_reset_password = true
        unless user.save
          account.errors.merge!(user.errors)
          raise ActiveRecord::Rollback
        end
      end

      membership = AccountMembership.new(user: user, account: account, role: role)
      unless membership.save
        account.errors.merge!(membership.errors)
        raise ActiveRecord::Rollback
      end

      success = true
    end

    # Current.set(account:) — same reasoning AccountProvisioning's own identical wrapper gives:
    # Notification is TenantScoped, and this service runs from the Agency Console
    # (AgencyConsole::AccountMembershipsController), where Current.account is nil (Current.agency
    # is set instead) — this needs to be correct on its own regardless of who's calling it.
    if success
      Current.set(account: account) do
        if is_new_user
          Notifier.email(
            mailer_class: AccountMailer, mailer_method: :welcome, mailer_args: [ user, account, temp_password, role.to_s ],
            notifiable: account, account: account, to: user.email, subject: "Welcome to xEvent — #{account.name} is ready"
          )
        else
          Notifier.email(
            mailer_class: AccountMailer, mailer_method: :added_to_account, mailer_args: [ user, account, role.to_s ],
            notifiable: account, account: account, to: user.email, subject: "You've been added to #{account.name} on xEvent"
          )
        end
      end
    end

    Result.new(account_membership: membership, user: user, temp_password: temp_password, success: success)
  end

  private

  attr_reader :account, :role, :user, :is_new_user, :temp_password
end
