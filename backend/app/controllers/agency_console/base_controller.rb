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

    layout "agency_console"

    private

    def require_agency_context!
      redirect_to user_root_path if Current.account
    end
  end
end
