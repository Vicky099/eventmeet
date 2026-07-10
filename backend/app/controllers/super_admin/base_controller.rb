module SuperAdmin
  # Base controller for the Platform Console (Super Admin, requirement.md §4.3) — every request
  # here has already been routed through Hosting::ApexConstraint. Every controller under
  # SuperAdmin:: inherits from here, never directly from ApplicationController, so the
  # platform-request marking and login are enforced by construction.
  #
  # See Admin::BaseController's comment for the full three-layer isolation argument — this is the
  # mirror image of it: routing never dispatches an apex request into Admin::, this before_action
  # chain requires the :platform_staff Warden scope specifically (a tenant :user session carries
  # none of that state), and Current.platform_request (not Current.account) is what's set here.
  class BaseController < ApplicationController
    include PlatformRequestScoped

    # SuperAdmin::SessionsController skips this (must be reachable while signed out) — it can't
    # inherit this class at all, see that controller's comment for why.
    before_action :authenticate_platform_staff!

    include PunditAuthorizable

    layout "super_admin"

    private

    def authorization_fallback_path
      platform_staff_root_path
    end
  end
end
