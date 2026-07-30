# Shared by Admin::BaseController and SuperAdmin::BaseController — identical in both (Pundit
# wiring + the not-authorized fallback don't differ by audience), so it lives here once instead
# of being copy-pasted into each BaseController.
module PunditAuthorizable
  extend ActiveSupport::Concern

  included do
    include Pundit::Authorization
    rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized
  end

  private

  # There's no bare root_path to fall back to — every route carries its console's /admin or
  # /platform namespace (config/routes.rb) — so each including BaseController defines this to
  # point at its own scope's root (user_root_path / platform_staff_root_path). Keeps this concern
  # oblivious to which audience it's mixed into, rather than branching on Current.platform_request.
  def authorization_fallback_path
    raise NotImplementedError, "#{self.class} must implement #authorization_fallback_path"
  end

  # requirement.md revisit: "instead show the real reason in flash" — a bare "not authorized" is
  # right for an actual role/permission gap, but misleading for a business-rule gate like
  # EventPolicy#update?'s "completed events can't be edited" (real report: an event_admin, who
  # unambiguously *is* allowed to edit events in general, hit this on a completed one and had no
  # way to tell the two apart). ApplicationPolicy#reason_for is the optional per-policy hook —
  # policies that don't define one (the common case) fall through to the generic message here.
  def user_not_authorized(exception)
    message = exception.policy.reason_for(exception.query)
    redirect_back fallback_location: authorization_fallback_path, alert: message || "You are not authorized to do that."
  end
end
