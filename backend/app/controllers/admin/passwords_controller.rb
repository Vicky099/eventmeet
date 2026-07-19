module Admin
  # Tenant Admin Console password reset (requirement.md §3.1's forced-reset flow, and ordinary
  # self-service "forgot password"). Reuses Devise's own reset-password-token mechanism for both:
  # Admin::SessionsController#create mints a token and redirects here directly (no email) when
  # must_reset_password is set; the ordinary #create action below still emails a token normally.
  class PasswordsController < Devise::PasswordsController
    # Must be reachable while signed out (ordinary forgot-password flow, and the forced-reset
    # flow, which explicitly signs the user out before redirecting here — see
    # Admin::SessionsController#create).
    skip_before_action :authenticate_user!
    # Fixed-hierarchy pivot (requirement.md revisit) — same reasoning as
    # Admin::SessionsController's own identical skip: password reset must work on an agency
    # subdomain exactly as it does on a tenant one.
    skip_before_action :redirect_agency_context_to_agency_console

    layout "auth"

    def update
      super do |resource|
        resource.update_column(:must_reset_password, false) if resource.errors.empty?
      end
    end
  end
end
