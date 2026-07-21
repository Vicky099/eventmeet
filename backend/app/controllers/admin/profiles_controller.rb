module Admin
  # requirement.md revisit: the sidebar's own "Profile" entry (AdminHelper#admin_nav_items) used
  # to be a "#" stub — this is current_user's own account (details + password change), not an
  # Account-scoped resource, so nothing here goes through Pundit — editing your own record is
  # always allowed for any signed-in AccountMembership role.
  class ProfilesController < BaseController
    def show
    end

    def update
      if current_user.update(profile_params)
        redirect_to admin_profile_path, notice: "Profile updated."
      else
        render :show, status: :unprocessable_content
      end
    end

    # Devise's own current_password-gated update (Devise::Models::DatabaseAuthenticatable) — same
    # method Devise::RegistrationsController#update would call, if it were mounted here (it isn't;
    # config/routes.rb's devise_for :users skip: [:registrations]). Its own separate action/form
    # from #update above: update_with_password requires current_password on every call regardless
    # of which attributes are changing, which the plain contact-details form has no reason to ask
    # a user for.
    def password
      if current_user.update_with_password(password_params)
        # Devise's session serializer keys off authenticatable_salt (derived from
        # encrypted_password) — without re-signing in here, the very next request would silently
        # fail that check and sign the user straight back out of the account they just changed
        # the password for. Same call Devise::RegistrationsController#update itself makes.
        bypass_sign_in(current_user)
        redirect_to admin_profile_path, notice: "Password updated."
      else
        render :show, status: :unprocessable_content
      end
    end

    private

    def profile_params
      params.require(:user).permit(:contact_num)
    end

    def password_params
      params.require(:user).permit(:current_password, :password, :password_confirmation)
    end
  end
end
