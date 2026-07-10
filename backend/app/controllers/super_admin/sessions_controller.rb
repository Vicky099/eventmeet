module SuperAdmin
  # Super Admin login (requirement.md §4.9 item 1) — the :platform_staff Warden scope. Authorization
  # (must be platform_staff) is enforced at the model layer (User#active_for_authentication?).
  #
  # Devise::SessionsController's real ancestry is Devise::SessionsController < DeviseController <
  # Devise.parent_controller.constantize, which is config'd to "Admin::BaseController" (config/
  # initializers/devise.rb — the tenant :user scope is the one that needs a real base controller
  # to inherit; see that file's comment). That's correct for Admin::SessionsController but wrong
  # here: the apex domain has no subdomain to resolve, so resolve_tenant! would 404 every platform
  # login. Skip it and mark this a platform request instead (SuperAdmin::BaseController does the
  # same for every other SuperAdmin:: controller — this one just can't literally inherit from it,
  # since it must still be a Devise::SessionsController subclass for Devise's routing to work).
  class SessionsController < Devise::SessionsController
    skip_before_action :resolve_tenant!
    # Same inheritance quirk as above: this also picks up Admin::BaseController's authenticate_user!
    # even though that's the wrong scope entirely here — skip it too.
    skip_before_action :authenticate_user!
    include PlatformRequestScoped

    layout "auth"

    # See Admin::SessionsController's after_sign_out_path_for for why.
    def after_sign_out_path_for(resource_or_scope)
      new_platform_staff_session_path
    end

    # See Admin::SessionsController's after_sign_in_path_for for the full explanation — this is
    # the half of that bug that was actually visible: without this override, Devise's default
    # sent a successful platform_staff login to /admin (the :user scope's root, always what
    # Devise::Mapping.find_scope! resolves to for a bare User instance) instead of /platform.
    def after_sign_in_path_for(resource_or_scope)
      stored_location_for(resource_or_scope) || platform_staff_root_path
    end
  end
end
