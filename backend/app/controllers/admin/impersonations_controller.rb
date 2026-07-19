module Admin
  # Phase 23 — Audit Log & Super Admin Impersonation (doc/implementation_3.md). The redeem half of
  # ImpersonationToken — SuperAdmin::ImpersonationsController#create mints the token and redirects
  # here, on the target tenant's own subdomain, mirroring Admin::AccountSwitchesController#redeem's
  # own shape almost exactly. The one real difference: this also stashes the real Super Admin's
  # identity into the tenant session (session[:impersonator_platform_staff_id]) so it survives the
  # *whole* impersonated visit, not just this one redirect — Admin::BaseController#current_impersonator
  # reads it back on every subsequent request for the banner and the audit-log after_action.
  class ImpersonationsController < BaseController
    skip_before_action :authenticate_user!
    skip_before_action :redirect_agency_context_to_agency_console

    def redeem
      # Scoped to `account: Current.account`, same belt-and-suspenders host check
      # Admin::AccountSwitchesController#redeem already applies.
      impersonation_token = ImpersonationToken.find_by(token: params[:token], account: Current.account)

      if impersonation_token.nil? || !impersonation_token.redeemable?
        redirect_to new_user_session_path, alert: "This impersonation link has expired or already been used." and return
      end

      user = impersonation_token.user
      platform_staff = impersonation_token.platform_staff
      impersonation_token.redeem!

      # Re-checked explicitly, same reasoning Admin::AccountSwitchesController#redeem's own
      # comment gives — covers an AccountMembership/suspension change in the window between mint
      # and redeem.
      unless user.authorized_for_current_host?
        redirect_to new_user_session_path, alert: "This user no longer has access to this tenant." and return
      end

      sign_in(user, scope: :user)
      session[:impersonator_platform_staff_id] = platform_staff.id
      redirect_to user_root_path, notice: "Now viewing as #{user.email}."
    end

    # "Stop Impersonating" (shared/_impersonation_banner.html.erb) — clears the stashed identity
    # and signs the impersonated :user session out. Deliberately does NOT need to re-sign the
    # Super Admin back in: their own :platform_staff session is a separate, still-live host-only
    # cookie on the apex domain (Phase 1's cookie-isolation model) — this redirect never touches
    # it, so landing back on the Platform Console just works, no second login.
    def destroy
      session.delete(:impersonator_platform_staff_id)
      sign_out(:user)
      redirect_to platform_staff_root_url(host: Rails.application.config.x.platform_domain),
        allow_other_host: true, notice: "Stopped impersonating."
    end
  end
end
