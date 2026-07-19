module SuperAdmin
  # Phase 23 — Audit Log & Super Admin Impersonation (doc/implementation_3.md). Mint half only —
  # mirrors AgencyConsole::AccountsController#switch's own mint half exactly (same
  # ImpersonationToken.generate_for/allow_other_host redirect shape), except the target user is
  # explicitly chosen from this account's own roster (super_admin/agencies/_tenant_modal.html.erb),
  # not implied. The redeem half lives on the tenant subdomain (Admin::ImpersonationsController),
  # same "mint here, redeem there" split AccountSwitch already established.
  class ImpersonationsController < BaseController
    def create
      account = Account.find(params[:account_id])
      user = account.users.find(params[:user_id])

      impersonation_token = ImpersonationToken.generate_for(platform_staff: current_platform_staff, user: user, account: account)

      # Logged at mint time, not redeem — this is the actual Super Admin decision being audited
      # (current_platform_staff is the real, Devise-authenticated actor here); redemption on the
      # tenant subdomain is just completing an already-recorded action, not a second one.
      AuditLog.record!(actor: current_platform_staff, action: "impersonation.start", target: account,
        metadata: { impersonated_user_email: user.email })

      redirect_to redeem_impersonation_url(
        host: "#{account.subdomain_slug}.#{Rails.application.config.x.platform_domain}",
        token: impersonation_token.token
      ), allow_other_host: true
    end
  end
end
