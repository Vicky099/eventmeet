# Phase 9 — standard Rails Action Cable scaffolding, not generated until now since nothing used
# Action Cable before this phase (requirement.md §5.15). Identifies via Warden directly rather
# than Devise's own connection helpers, since this app runs two independent Warden scopes on one
# User class (:user for the tenant Admin Console, :platform_staff for the Platform Console — see
# config/routes.rb) and a cable connection needs to accept either, whichever the browser tab
# opening it happens to be signed in as.
#
# This is the connection-level authorization floor only (must be signed in as *something*) —
# Turbo::StreamsChannel's own signed stream names (derived from the page that rendered
# `turbo_stream_from`) are what keep a subscriber to one event's live stats from also being able
# to guess another tenant's; per-record authorization at the channel layer isn't added on top,
# same trust model the rest of the app already places in page-level Pundit checks.
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      warden = request.env["warden"]
      warden.user(:user) || warden.user(:platform_staff) || reject_unauthorized_connection
    end
  end
end
