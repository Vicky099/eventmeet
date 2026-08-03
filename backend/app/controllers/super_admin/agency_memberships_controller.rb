module SuperAdmin
  # Agency layer (requirement.md revisit): the agency's own admin roster, managed from its #show
  # page — #create adds a new agency_admin (AgencyMembershipProvisioning handles the
  # find-or-invite-by-email + existing-tenant AccountMembership backfill), #destroy removes the
  # AgencyMembership only. Deliberately does NOT try to retroactively revoke the AccountMembership
  # rows that backfill already created on the agency's tenants — same "an explicit follow-up
  # action, not an automatic cascade" caution Invoice#reject_payment!'s own comment models; a Super
  # Admin who actually wants that person off a specific tenant removes them from that tenant
  # directly (whenever that per-tenant team-management UI exists — not built yet, same gap
  # AgencyMembershipProvisioning's own comment already flags for the *adding* side).
  class AgencyMembershipsController < BaseController
    before_action :set_agency
    before_action :set_membership, only: [ :destroy, :resend_invite, :send_reset_password_instructions ]

    def create
      email = params[:email].to_s.strip.downcase

      if email.blank?
        redirect_to platform_agency_path(@agency), alert: "Enter an email address."
        return
      end

      result = AgencyMembershipProvisioning.call(agency: @agency, email: email)

      if result.success?
        AuditLog.record!(actor: current_platform_staff, action: "agency_membership.create", target: @agency,
          metadata: { email: result.user.email })
        redirect_to platform_agency_path(@agency), notice: "#{result.user.email} added as an agency admin for #{@agency.name}."
      else
        redirect_to platform_agency_path(@agency), alert: @agency.errors.full_messages.to_sentence.presence || "Couldn't add that email."
      end
    end

    def destroy
      # metadata captures the removed member's own identity — target stays the Agency (not the
      # about-to-be-destroyed AgencyMembership) so this row stays legible after the fact without
      # needing a real FK, matching how @agency's own #show page already re-derives context that
      # way (polymorphic target is never actually FK-enforced by Postgres either way).
      removed_email = @membership.user.email
      @membership.destroy!
      AuditLog.record!(actor: current_platform_staff, action: "agency_membership.destroy", target: @agency,
        metadata: { email: removed_email })
      redirect_to platform_agency_path(@agency), notice: "#{removed_email} removed from #{@agency.name}'s agency admins."
    end

    # "Resend Invite" — a not-yet-onboarded agency_admin (User#must_reset_password still true,
    # meaning they've never actually signed in and reset it) may have lost, forgotten, or never
    # received their original temp password. Regenerates one and re-sends the exact same welcome
    # email AgencyMembershipProvisioning's own first-invite path sends — same forced-reset flow,
    # just re-triggerable on demand instead of only once at creation time. Deliberately guarded to
    # that pending state only: resending once someone has already set their own real password would
    # silently invalidate it out from under them, a surprise this action has no business causing —
    # a Super Admin who wants to reset an *active* admin's password has no path here on purpose.
    def resend_invite
      unless @membership.user.must_reset_password?
        redirect_to platform_agency_path(@agency), alert: "#{@membership.user.email} has already signed in — nothing to resend."
        return
      end

      temp_password = SecureRandom.base58(16)
      @membership.user.update!(password: temp_password)
      AgencyMailer.welcome(@membership.user, @agency, temp_password).deliver_later
      AuditLog.record!(actor: current_platform_staff, action: "agency_membership.resend_invite", target: @agency,
        metadata: { email: @membership.user.email })
      redirect_to platform_agency_path(@agency), notice: "Invite resent to #{@membership.user.email}."
    end

    # "Send reset password instructions" — the exact gap #resend_invite's own comment calls out
    # ("a Super Admin who wants to reset an *active* admin's password has no path here on
    # purpose"): an already-onboarded agency_admin who's simply forgotten their real password has
    # no self-service path from here — Devise's ordinary "forgot password?" form lives on each
    # tenant/agency's own subdomain login page, not the apex Platform Console. This triggers the
    # same Devise reset-token email on their behalf. Guarded to the opposite state #resend_invite
    # guards to — a still-pending invite has no real password yet to reset, and this would just
    # be a confusing second email on top of the welcome one.
    #
    # User#send_devise_notification (the actual mailer trigger, inside
    # #send_reset_password_instructions below) builds the reset link's host off `Current.agency` —
    # normally set by TenantResolvable when a request arrives on the agency's own subdomain, which
    # this apex-domain Super Admin request never does (`Current.platform_request` is set instead).
    # `Current.set` scopes `Current.agency` to just this one call so the mailer still resolves to
    # #{@agency.subdomain_slug}.#{platform_domain} (ApplicationMailer#default_url_options's own
    # `elsif @tenant_agency` branch) instead of falling back to the apex host, where
    # Admin::PasswordsController#edit isn't even routable at all.
    def send_reset_password_instructions
      if @membership.user.must_reset_password?
        redirect_to platform_agency_path(@agency), alert: "#{@membership.user.email} hasn't signed in yet — use Resend Invite instead."
        return
      end

      Current.set(agency: @agency) { @membership.user.send_reset_password_instructions }
      AuditLog.record!(actor: current_platform_staff, action: "agency_membership.send_reset_password_instructions", target: @agency,
        metadata: { email: @membership.user.email })
      redirect_to platform_agency_path(@agency), notice: "Password reset instructions sent to #{@membership.user.email}."
    end

    private

    def set_agency
      @agency = Agency.find(params[:agency_id])
    end

    def set_membership
      @membership = @agency.agency_memberships.find(params[:id])
    end
  end
end
