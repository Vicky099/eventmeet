# frozen_string_literal: true

# requirement.md §5.1: configurable roles/permissions per Account. Tenant-scoping itself (never
# seeing another Account's rows) is already enforced at the ActiveRecord layer by TenantScoped
# (app/models/concerns/tenant_scoped.rb) — Pundit's job here is role-based *visibility within* a
# tenant (e.g. admin_staff can't touch what event_admin can), not re-deriving isolation.
class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index?
    false
  end

  def show?
    false
  end

  def create?
    false
  end

  def new?
    create?
  end

  def update?
    false
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  private

  # requirement.md §4.3: SuperAdmin:: controllers explicitly operate across tenants — the Super
  # Admin bypass every subclass's checks should short-circuit through, e.g.
  # `def update? = platform_staff? || owner?`.
  def platform_staff?
    user&.platform_staff?
  end

  def account_membership
    return nil unless Current.account && user

    @account_membership ||= user.account_memberships.find_by(account: Current.account)
  end

  def event_admin?
    account_membership&.event_admin?
  end

  def admin_staff?
    account_membership&.admin_staff?
  end

  # Agency layer (requirement.md revisit): true for a user with an AgencyMembership on ANY agency —
  # nothing in this app scopes a request to "one specific agency" the way Current.account scopes a
  # tenant request, so unlike account_membership above there's no single row to narrow to; every
  # actual access decision this app makes still runs through the tenant's own AccountMembership
  # (auto-created on every one of an agency's tenants — AccountProvisioning's own comment), so this
  # exists for completeness/future use, not because any policy in this app calls it yet.
  def agency_admin?
    user&.agency_memberships&.exists?
  end

  class Scope
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    # Tenant scoping is already applied by TenantScoped's default_scope before this ever runs —
    # subclasses override this only to narrow further by role, not to re-scope by account.
    def resolve
      scope.all
    end

    private

    attr_reader :user, :scope
  end
end
