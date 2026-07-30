module AgencyConsole
  # Base controller for the Agency Console (fixed-hierarchy pivot, requirement.md revisit) — a
  # third console tier, sharing the exact same subdomain routing constraint
  # (Hosting::TenantSubdomainConstraint) and the exact same :user Devise scope/login form
  # (/admin/login) as the tenant Admin Console, since an agency_admin is an ordinary :user-scope
  # User who also needs to log into *tenant* subdomains with the same credentials — unlike
  # :platform_staff, which is a genuinely separate role/scope (§4.1: platform staff can never hold
  # an AccountMembership at all). TenantResolvable's own lenient resolution (Account first, then
  # Agency) is what actually tells the two consoles apart per request.
  #
  # Namespaced AgencyConsole:: (not Agency::) — Agency is already a top-level model class, and
  # Zeitwerk can't resolve a name as both a class and a controller namespace module.
  #
  # Not `< Admin::BaseController` — that class's own before_action chain assumes a *tenant*
  # context (redirect_agency_context_to_agency_console would bounce every request right back here).
  # `require_tenant_context!` below is this class's own mirror-image guard: a request that resolved
  # against a *tenant* subdomain instead (Current.account set, not Current.agency) has no business
  # reaching an AgencyConsole:: controller either.
  #
  # No PunditAuthorizable — same reasoning SuperAdmin::AccountsController's own comment gives for
  # skipping it: there's no role variation to speak of inside an agency (every AgencyMembership row
  # is `agency_admin`), so there's nothing for a policy to narrow beyond "is this user actually a
  # member of Current.agency at all," which is already enforced one layer down, at authentication
  # itself (User#authorized_for_current_host?'s own Current.agency branch).
  class BaseController < ApplicationController
    include TenantResolvable

    before_action :authenticate_user!
    before_action :require_agency_context!

    # requirement.md revisit ("super admin should have option to impersonate agency and login to
    # agency portal") — mirrors Admin::BaseController#audit_impersonated_action exactly, one tier
    # up: every state-changing request made while Admin::ImpersonationsController#redeem has
    # stashed a real platform_staff identity into this agency session gets audited the same way a
    # tenant-side impersonated action already does.
    after_action :audit_impersonated_action, if: -> { current_impersonator && !request.get? && !request.head? }

    layout "agency_console"

    # Real Super Admin identity behind an impersonated agency session — same shape and same
    # session key (session[:impersonator_platform_staff_id], set by
    # Admin::ImpersonationsController#redeem) as Admin::BaseController#current_impersonator; nil
    # for an ordinary, non-impersonated session. layouts/agency_console.html.erb calls this
    # directly, so it needs helper_method, same reasoning as the tenant console's own copy.
    def current_impersonator
      return @current_impersonator if defined?(@current_impersonator)

      @current_impersonator = session[:impersonator_platform_staff_id] && User.find_by(id: session[:impersonator_platform_staff_id])
    end
    helper_method :current_impersonator

    private

    def require_agency_context!
      redirect_to user_root_path if Current.account
    end

    def audit_impersonated_action
      AuditLog.record!(
        actor: current_impersonator,
        action: "impersonation.#{controller_name}##{action_name}",
        target: current_user,
        metadata: { impersonated_user_email: current_user.email, path: request.fullpath, method: request.method }
      )
    end
  end
end
