module Api
  module V1
    module Public
      # Phase 25 — Public Event Site API (doc/public_event_site_options.md, requirement.md §4.9
      # item 2). The Next.js BFF's own data source — OAuth2 client-credentials only (no
      # session/cookie auth at all, so no CSRF token to check), tenant-resolved the same way as
      # every other tenant-subdomain request (TenantResolvable — this is nested inside
      # Hosting::TenantSubdomainConstraint in config/routes.rb, same as Admin::/AgencyConsole::).
      # One extra belt-and-suspenders check no other tenant-subdomain controller needs: the
      # presented token's own Application must actually belong to *this* Account, not just be a
      # valid token for *some* tenant — a tenant's own client_id/client_secret only works against
      # its own subdomain (mirrors ImpersonationToken/AccountSwitch's own "re-check scope at
      # redemption time" precedent, just for a bearer token instead of a one-time code).
      class BaseController < ActionController::Base
        include TenantResolvable

        # No session/cookie auth on this controller at all (Bearer token only), so there's no CSRF
        # token to check — same reasoning ActionController::API skips this by default.
        skip_forgery_protection

        before_action :doorkeeper_authorize!
        before_action :verify_token_scoped_to_current_account!

        private

        def verify_token_scoped_to_current_account!
          head :unauthorized unless doorkeeper_token&.application&.account == Current.account
        end
      end
    end
  end
end
