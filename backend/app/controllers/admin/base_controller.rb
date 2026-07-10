module Admin
  # Base controller for the tenant Admin Console (requirement.md §4.3) — every request here has
  # already been routed through Hosting::TenantSubdomainConstraint. Every controller under
  # Admin:: inherits from here, never directly from ApplicationController, so tenant resolution
  # and login are enforced by construction, not by each controller remembering to add them.
  #
  # Isolation from SuperAdmin:: (requirement: admin must never reach super_admin controllers/views
  # or vice versa) is enforced at three independent layers, not just this class:
  #   1. Routing — config/routes.rb only ever dispatches to Admin:: controllers under
  #      Hosting::TenantSubdomainConstraint, and to SuperAdmin:: under Hosting::ApexConstraint.
  #      Wrong-host requests never reach the wrong namespace's controller at all.
  #   2. This before_action chain — resolve_tenant! (404s a bad/nonexistent subdomain) then
  #      authenticate_user! (the :user Warden scope) — a SuperAdmin session carries no :user
  #      Warden state, so it can't satisfy this even if it somehow reached here.
  #   3. Current.account/Current.platform_request — mutually exclusive per request, gating
  #      TenantScoped's default_scope at the model layer as a last resort.
  class BaseController < ApplicationController
    include TenantResolvable

    # Declared after TenantResolvable so resolve_tenant! runs first — an unrecognized host should
    # never even reach an authentication check. Admin::SessionsController/Admin::PasswordsController
    # skip this (must be reachable while signed out).
    before_action :authenticate_user!

    include PunditAuthorizable

    layout "admin"

    private

    def authorization_fallback_path
      user_root_path
    end
  end
end
