# Included by the Platform Console's SuperAdmin::BaseController (and, directly,
# SuperAdmin::SessionsController, which can't inherit that class — see its own comment). The
# routing constraint (Hosting::ApexConstraint) already guarantees these requests arrived on the
# bare apex domain — this marks them as deliberately cross-tenant so TenantScoped models open up
# to `all` instead of raising (requirement.md §4.3: "every SuperAdmin:: controller is explicitly
# written to operate across tenants rather than being blocked by the row-level-isolation guard").
module PlatformRequestScoped
  extend ActiveSupport::Concern

  included do
    before_action :mark_platform_request!
  end

  private

  def mark_platform_request!
    Current.platform_request = true
  end
end
