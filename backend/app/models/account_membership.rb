class AccountMembership < ApplicationRecord
  # Deliberately does NOT include TenantScoped: this table is queried from two directions that a
  # blanket Current.account default_scope would fight — "this tenant's team" (Current.account set,
  # scope via account.account_memberships) AND "this user's memberships across every tenant they
  # belong to" (Phase 17's account switcher, needed precisely while Current.account is set to ONE
  # of those tenants). Tenant isolation for the "team" access pattern comes from always querying
  # through the account/user association, not a bare AccountMembership.where(...).

  # requirement.md §5.1: configurable roles per Account. Owner has full control within the tenant;
  # the others narrow what a Pundit policy will allow (fleshed out per-module starting Phase 4).
  enum :role, { owner: 0, event_manager: 1, checkin_staff: 2, finance_readonly: 3 }

  belongs_to :user
  belongs_to :account

  validates :user_id, uniqueness: { scope: :account_id }
  validate :user_is_not_platform_staff

  private

  def user_is_not_platform_staff
    return unless user&.platform_staff?

    errors.add(:user, "platform staff cannot hold an AccountMembership (requirement.md §4.1)")
  end
end
