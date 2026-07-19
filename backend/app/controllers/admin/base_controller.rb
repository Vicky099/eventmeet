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
  #
  # Fixed-hierarchy pivot (requirement.md revisit): the same routing constraint and the same :user
  # Devise scope now also serve the Agency Console (AgencyConsole::BaseController's own comment) — a
  # fourth check, redirect_agency_context_to_agency_console below, is what keeps a signed-in agency
  # admin's own subdomain from reaching a *tenant*-only controller (Events, Invoices, ...) by
  # mistake; the mirror-image guard lives on AgencyConsole::BaseController.
  class BaseController < ApplicationController
    include TenantResolvable

    # Declared after TenantResolvable so resolve_tenant! runs first — an unrecognized host should
    # never even reach an authentication check. Admin::SessionsController/Admin::PasswordsController
    # skip this (must be reachable while signed out).
    before_action :authenticate_user!
    # Also skipped by Admin::SessionsController/Admin::PasswordsController — login/password-reset
    # must work identically on an agency subdomain (the same :user scope, same forced-reset flow)
    # as on a tenant one; only substantive tenant-only actions (Events, Invoices, ...) need to
    # bounce an agency-context request elsewhere.
    before_action :redirect_agency_context_to_agency_console

    # Phase 23 — Audit Log & Super Admin Impersonation (doc/implementation_3.md). Runs after every
    # state-changing (non-GET/HEAD) request made while Admin::ImpersonationsController#redeem has
    # stashed a real platform_staff identity into this tenant session — a generic after_action here
    # (not a call added to each individual controller action) is what guarantees nothing new added
    # to the Admin Console later can silently skip being audited while impersonating.
    after_action :audit_impersonated_action, if: -> { current_impersonator && !request.get? && !request.head? }

    include PunditAuthorizable

    layout "admin"

    # Real Super Admin identity behind an impersonated tenant session (session[:impersonator_platform_staff_id],
    # set by Admin::ImpersonationsController#redeem) — nil for an ordinary, non-impersonated
    # session. Deliberately distinct from current_user, which is the *impersonated* identity for
    # the duration of the visit; every audit entry/log line must attribute back to this, never
    # current_user, or the whole point of tracking impersonation is defeated (AuditLog's own
    # class comment).
    def current_impersonator
      return @current_impersonator if defined?(@current_impersonator)

      @current_impersonator = session[:impersonator_platform_staff_id] && User.find_by(id: session[:impersonator_platform_staff_id])
    end
    # layouts/admin.html.erb calls this directly (passed into shared/_console_shell as an explicit
    # local, same "layout-side data passed in, not looked up by the shared partial itself"
    # convention footer_text/nav_items/user_dropdown already establish) — a view-context call
    # needs helper_method, plain controller-method visibility alone isn't reachable from an ERB
    # template.
    helper_method :current_impersonator

    private

    def redirect_agency_context_to_agency_console
      redirect_to agency_root_path if Current.agency
    end

    def authorization_fallback_path
      user_root_path
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
