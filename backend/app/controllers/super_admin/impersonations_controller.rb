module SuperAdmin
  # Phase 23 — Audit Log & Super Admin Impersonation (doc/implementation_3.md). Mint half only —
  # mirrors AgencyConsole::AccountsController#switch's own mint half exactly (same
  # ImpersonationToken.generate_for/allow_other_host redirect shape), except the target user is
  # explicitly chosen from this account's own roster (super_admin/agencies/_tenant_modal.html.erb),
  # not implied. The redeem half lives on the tenant subdomain (Admin::ImpersonationsController),
  # same "mint here, redeem there" split AccountSwitch already established.
  #
  # requirement.md revisit ("super admin should have option to impersonate agency and login to
  # agency portal"): nested under both :accounts and :agencies (config/routes.rb) — the two
  # branches below share everything except which roster the target user comes off of, which
  # subdomain the redirect targets, and which model gets passed as the ImpersonationToken/AuditLog
  # target.
  class ImpersonationsController < BaseController
    def create
      if params[:agency_id]
        agency = Agency.find(params[:agency_id])
        user = agency.users.find(params[:user_id])
        impersonation_token = ImpersonationToken.generate_for(platform_staff: current_platform_staff, user: user, agency: agency)
        redeem_on(agency, impersonation_token, user)
      else
        account = Account.find(params[:account_id])
        user = account.users.find(params[:user_id])
        impersonation_token = ImpersonationToken.generate_for(platform_staff: current_platform_staff, user: user, account: account)
        redeem_on(account, impersonation_token, user)
      end
    end

    private

    # Shared by both branches above — Account and Agency each expose the same subdomain_slug/
    # AuditLog-target shape, so the only thing that differs between "impersonate this tenant's
    # user" and "impersonate this agency's admin" is which record actually gets minted against.
    def redeem_on(tenant, impersonation_token, user)
      # Logged at mint time, not redeem — this is the actual Super Admin decision being audited
      # (current_platform_staff is the real, Devise-authenticated actor here); redemption on the
      # target subdomain is just completing an already-recorded action, not a second one.
      AuditLog.record!(actor: current_platform_staff, action: "impersonation.start", target: tenant,
        metadata: { impersonated_user_email: user.email })

      redirect_to redeem_impersonation_url(
        host: "#{tenant.subdomain_slug}.#{Rails.application.config.x.platform_domain}",
        token: impersonation_token.token
      ), allow_other_host: true
    end
  end
end
