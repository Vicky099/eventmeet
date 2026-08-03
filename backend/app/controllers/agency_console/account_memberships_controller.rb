module AgencyConsole
  # A tenant Account's own admin roster, managed from its #show page (AgencyConsole::AccountsController
  # #show) — mirrors SuperAdmin::AgencyMembershipsController exactly, one tier down: #create adds a
  # new admin (AccountMembershipProvisioning handles the find-or-invite-by-email shape), #destroy
  # removes the AccountMembership, #resend_invite/#send_reset_password_instructions cover the two
  # "this person can't sign in" states (still-pending vs. forgotten-password) the same opposite-gated
  # pair that controller's own actions already establish.
  #
  # No AuditLog.record! calls here — same convention every other AgencyConsole:: controller already
  # follows (AgencyConsole::BaseController's own after_action only audits an *impersonated* session's
  # actions; an agency admin's own genuine actions were never separately audited to begin with).
  class AccountMembershipsController < BaseController
    before_action :set_account
    before_action :set_membership, only: [ :destroy, :resend_invite, :send_reset_password_instructions, :suspend, :reinstate ]

    def create
      email = params[:email].to_s.strip.downcase

      if email.blank?
        redirect_to agency_account_path(@account), alert: "Enter an email address."
        return
      end

      # presence_in against the real enum keys (not a bare params passthrough) — AccountMembership
      # #role is user input from here down, same "never trust a raw param into an enum column"
      # caution every other enum-backed form field in this app already takes.
      role = params[:role].to_s.presence_in(AccountMembership.roles.keys) || "event_admin"
      result = AccountMembershipProvisioning.call(account: @account, email: email, role: role)

      if result.success?
        redirect_to agency_account_path(@account), notice: "#{result.user.email} added as an admin for #{@account.name}."
      else
        redirect_to agency_account_path(@account), alert: @account.errors.full_messages.to_sentence.presence || "Couldn't add that email."
      end
    end

    def destroy
      removed_email = @membership.user.email
      @membership.destroy!
      redirect_to agency_account_path(@account), notice: "#{removed_email} removed from #{@account.name}'s admins."
    end

    # Same "not-yet-onboarded" gate SuperAdmin::AgencyMembershipsController#resend_invite already
    # takes — regenerates a temp password and re-sends the exact same welcome email
    # AccountMembershipProvisioning's own first-invite path sends.
    def resend_invite
      unless @membership.user.must_reset_password?
        redirect_to agency_account_path(@account), alert: "#{@membership.user.email} has already signed in — nothing to resend."
        return
      end

      temp_password = SecureRandom.base58(16)
      @membership.user.update!(password: temp_password)
      # Current.set(account:) — same reasoning AccountMembershipProvisioning's own identical
      # wrapper gives: Notification is TenantScoped, and this request runs under Current.agency,
      # not Current.account.
      Current.set(account: @account) do
        Notifier.email(
          mailer_class: AccountMailer, mailer_method: :welcome, mailer_args: [ @membership.user, @account, temp_password, @membership.role ],
          notifiable: @account, account: @account, to: @membership.user.email, subject: "Welcome to xEvent — #{@account.name} is ready"
        )
      end
      redirect_to agency_account_path(@account), notice: "Invite resent to #{@membership.user.email}."
    end

    # Same opposite-of-#resend_invite gate SuperAdmin::AgencyMembershipsController
    # #send_reset_password_instructions already takes, and the same Current.set reasoning that
    # controller's own version gives for `Current.agency` — User#send_devise_notification builds
    # the reset link's host off Current.account, which this Agency Console request never sets on
    # its own (Current.agency is set instead).
    def send_reset_password_instructions
      if @membership.user.must_reset_password?
        redirect_to agency_account_path(@account), alert: "#{@membership.user.email} hasn't signed in yet — use Resend Invite instead."
        return
      end

      Current.set(account: @account) { @membership.user.send_reset_password_instructions }
      redirect_to agency_account_path(@account), notice: "Password reset instructions sent to #{@membership.user.email}."
    end

    # requirement.md revisit: "agency can suspend client admin and client admin staff" — either
    # role, unlike Admin::TeamController#suspend one tier down (that one only ever targets
    # admin_staff — the Agency's own oversight here isn't limited that way). AccountMembership
    # #status is what User#authorized_for_current_host? actually checks at sign-in, so this takes
    # effect immediately (that model's own comment has the full enforcement-point reasoning).
    def suspend
      @membership.suspended!
      redirect_to agency_account_path(@account), notice: "#{@membership.user.email} suspended."
    end

    def reinstate
      @membership.active!
      redirect_to agency_account_path(@account), notice: "#{@membership.user.email} reinstated."
    end

    private

    def set_account
      @account = Current.agency.accounts.find(params[:account_id])
    end

    def set_membership
      @membership = @account.account_memberships.find(params[:id])
    end
  end
end
