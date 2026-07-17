require "rails_helper"

# requirement.md revisit: "we should capture the event timezone and all the dates which are
# display in the UI should abey the tenant timezone." TenantResolvable#with_tenant_time_zone
# (app/controllers/concerns/tenant_resolvable.rb) is the actual mechanism — this spec proves it
# end to end through a real page render, not just that the concern sets Time.zone in isolation.
RSpec.describe "Tenant timezone applies to rendered dates", type: :request do
  # "Chennai" (a real ActiveSupport::TimeZone name, UTC+5:30) — a fixed, non-DST offset makes the
  # expected rendered string deterministic regardless of what time of year the suite runs.
  let!(:account) { create(:account, subdomain_slug: "acme", time_zone: "Chennai") }

  before { host! "acme.example.com" }

  def sign_in_with_role(role)
    user = create(:user, email: "#{role}@acme.example", password: "password123!")
    create(:account_membership, user: user, account: account, role: role)
    sign_in user, scope: :user
  end

  it "renders an event's starts_at in the account's own configured timezone, not UTC" do
    Current.account = account
    starts_at = Time.utc(2026, 6, 1, 10, 0, 0) # 10:00 UTC == 15:30 in Chennai (UTC+5:30)
    event = create(:event, account: account, starts_at: starts_at, ends_at: starts_at + 2.hours)
    sign_in_with_role(:owner)

    get admin_event_path(event)

    expected = ActiveSupport::TimeZone["Chennai"].at(starts_at).to_fs(:long)
    expect(response.body).to include(expected)
    expect(response.body).not_to include(starts_at.to_fs(:long)) # the raw UTC rendering
  end

  it "renders differently for two tenants with different configured timezones" do
    other_account = create(:account, subdomain_slug: "other", time_zone: "Pacific Time (US & Canada)")
    Current.account = account
    starts_at = Time.utc(2026, 6, 1, 10, 0, 0)
    event = create(:event, account: account, starts_at: starts_at, ends_at: starts_at + 2.hours)
    Current.account = other_account
    other_event = create(:event, account: other_account, starts_at: starts_at, ends_at: starts_at + 2.hours)

    sign_in_with_role(:owner)
    get admin_event_path(event)
    chennai_rendering = ActiveSupport::TimeZone["Chennai"].at(starts_at).to_fs(:long)
    expect(response.body).to include(chennai_rendering)

    other_user = create(:user, email: "owner@other.example", password: "password123!")
    create(:account_membership, user: other_user, account: other_account, role: :owner)
    sign_out :user
    sign_in other_user, scope: :user
    host! "other.example.com"
    get admin_event_path(other_event)
    pacific_rendering = ActiveSupport::TimeZone["Pacific Time (US & Canada)"].at(starts_at).to_fs(:long)
    expect(response.body).to include(pacific_rendering)
    expect(response.body).not_to include(chennai_rendering)
  end

  it "resets to the default zone after the request (never leaks into the next one on a reused connection)" do
    Current.account = account
    sign_in_with_role(:owner)

    get admin_events_path

    expect(Time.zone.name).to eq("UTC")
  end
end
