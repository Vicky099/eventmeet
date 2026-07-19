require "rails_helper"

# Sidekiq::Web (config/routes.rb) — a real, destructive admin surface (list/retry/delete jobs,
# edit the cron schedule), gated behind the :platform_staff Warden scope specifically via Devise's
# `authenticated` routing helper, same as every other Platform Console controller. Only the gate
# itself is covered here, not a real render of Sidekiq::Web's own UI — this suite deliberately
# never talks to real Redis (config/environments/test.rb: jobs run inline via the ActiveJob test
# adapter), and Sidekiq::Web can't render without one; verified live instead (a real Sidekiq
# process, real Redis) that an authenticated platform_staff request actually reaches it.
RSpec.describe "Sidekiq::Web", type: :request do
  let!(:account) { create(:account, subdomain_slug: "acme") }
  let!(:user) { create(:user) }

  before { create(:account_membership, user: user, account: account, role: :event_admin) }

  # `authenticated` (not the throwing `authenticate`) — real bug caught live: the throwing variant
  # redirects to a broken, mount-relative login path from inside Sidekiq::Web's own dispatch
  # instead of the app root. This is a plain 404, same as any other undefined path — no broken
  # redirect, and no hint that a route exists there at all to an unauthenticated caller.
  it "404s for an unauthenticated request, never reaching Sidekiq::Web" do
    host! "example.com"

    get "/platform/sidekiq"

    expect(response).to have_http_status(:not_found)
  end

  # The tenant :user Warden scope shares the same underlying User model as :platform_staff — a
  # signed-in tenant admin must still be turned away, not just an outright-unauthenticated one.
  it "404s for a signed-in tenant user too (wrong Warden scope, not just unauthenticated)" do
    host! "example.com"
    sign_in user, scope: :user

    get "/platform/sidekiq"

    expect(response).to have_http_status(:not_found)
  end
end
