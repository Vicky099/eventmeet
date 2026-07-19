class AccountMembership < ApplicationRecord
  # Deliberately does NOT include TenantScoped: this table is queried from two directions that a
  # blanket Current.account default_scope would fight — "this tenant's team" (Current.account set,
  # scope via account.account_memberships) AND "this user's memberships across every tenant they
  # belong to" (User#authorized_for_current_host?'s own Current.account branch, and — the real
  # cross-tenant use case this shape exists for — an agency admin's own AccountSwitch, requirement.md
  # revisit, which reads current_user.accounts from the Agency Console, not a tenant one). Tenant
  # isolation for the "team" access pattern comes from always querying through the account/user
  # association, not a bare AccountMembership.where(...).

  # requirement.md §5.1, remapped (Agency layer requirement.md revisit): originally 4 roles (owner/
  # event_manager/checkin_staff/finance_readonly); collapsed to 2 to make room for the new
  # agency_admin tier above it (Agency/AgencyMembership) — every existing Pundit policy already
  # checked `owner? || event_manager?` and `checkin_staff?`/`finance_readonly?` read-only access as
  # one unit each, never distinguishing within a pair, so this merges two already-equivalent
  # permission sets rather than changing behavior. event_admin: full tenant administrative control
  # (was owner + event_manager). admin_staff: operate/view only — check-in, bulk print, viewing
  # everything — no create/edit/destroy rights (was checkin_staff + finance_readonly). See
  # db/migrate/20260719050300_remap_account_membership_roles.rb for the data migration.
  enum :role, { event_admin: 0, admin_staff: 1 }

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
