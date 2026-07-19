module Admin
  # Agency → Tenant account switch (requirement.md revisit): the redeem half of AccountSwitch —
  # AgencyConsole::AccountsController#switch mints the token and redirects here, on the target
  # tenant's own subdomain. Must be reachable while signed out (the whole point is establishing a
  # *new* session on this host) — same skip_before_action pair Admin::SessionsController/
  # Admin::PasswordsController already use.
  class AccountSwitchesController < BaseController
    skip_before_action :authenticate_user!
    skip_before_action :redirect_agency_context_to_agency_console

    def redeem
      # Scoped to `account: Current.account` (not a bare token lookup) — belt-and-suspenders
      # against a token being redeemed against the wrong resolved host, even though tokens are
      # already globally unique on their own.
      account_switch = AccountSwitch.find_by(token: params[:token], account: Current.account)

      if account_switch.nil? || !account_switch.redeemable?
        redirect_to new_user_session_path, alert: "This switch link has expired or already been used — please sign in." and return
      end

      user = account_switch.user
      account_switch.redeem!

      # Re-checked explicitly here, on top of whatever Devise/Warden's own
      # active_for_authentication? already enforces via sign_in below — covers an
      # AccountMembership/suspension change in the ~60s window between mint and redeem. Same
      # "layered defense" reasoning Admin::BaseController's own class comment already states.
      unless user.authorized_for_current_host?
        redirect_to new_user_session_path, alert: "You no longer have access to this tenant." and return
      end

      sign_in(user, scope: :user)
      redirect_to user_root_path, notice: "Switched to #{Current.account.name}."
    end
  end
end
