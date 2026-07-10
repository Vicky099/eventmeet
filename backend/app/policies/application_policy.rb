# frozen_string_literal: true

# requirement.md §5.1: configurable roles/permissions per Account. Tenant-scoping itself (never
# seeing another Account's rows) is already enforced at the ActiveRecord layer by TenantScoped
# (app/models/concerns/tenant_scoped.rb) — Pundit's job here is role-based *visibility within* a
# tenant (e.g. finance_readonly can't touch what owner can), not re-deriving isolation.
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

  def owner?
    account_membership&.owner?
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
