require "rails_helper"

# Phase 25 — Public Event Site API (doc/public_event_site_options.md). Same "stub Net::HTTP, never
# hit the real network" shape spec/services/gupshup_client_spec.rb already uses for its own
# outbound call — here `Net::HTTP.start` is stubbed to yield a double instead of returning a
# canned response directly (GupshupClient's own simpler shape), since this spec also wants to
# inspect the actual request built (path/headers/body), not just the response handling.
RSpec.describe PublicSiteRevalidator do
  let(:account) { create(:account) }
  let(:event) { create(:event, account: account) }

  before { Current.account = account }

  around do |example|
    original_url = ENV["PUBLIC_SITE_REVALIDATE_URL"]
    original_secret = ENV["PUBLIC_SITE_REVALIDATE_SECRET"]
    example.run
    ENV["PUBLIC_SITE_REVALIDATE_URL"] = original_url
    ENV["PUBLIC_SITE_REVALIDATE_SECRET"] = original_secret
  end

  def stub_http_start(&respond_with)
    allow(Net::HTTP).to receive(:start) do |*_args, &block|
      http = instance_double(Net::HTTP)
      allow(http).to receive(:request) { |req| respond_with.call(req) }
      block.call(http)
    end
  end

  it "does nothing when no revalidate URL is configured — the expected default state" do
    ENV["PUBLIC_SITE_REVALIDATE_URL"] = nil

    expect(Net::HTTP).not_to receive(:start)
    expect { described_class.call(event) }.not_to raise_error
  end

  it "POSTs the event's own tag to the configured URL with the shared secret header" do
    ENV["PUBLIC_SITE_REVALIDATE_URL"] = "https://public-site.example.com/api/revalidate"
    ENV["PUBLIC_SITE_REVALIDATE_SECRET"] = "shh"
    response = instance_double(Net::HTTPSuccess, is_a?: true)
    captured_request = nil
    stub_http_start { |req| captured_request = req; response }

    described_class.call(event)

    expect(captured_request.path).to eq("/api/revalidate")
    expect(captured_request["X-Revalidate-Secret"]).to eq("shh")
    expect(JSON.parse(captured_request.body)).to eq("tag" => "event:#{account.subdomain_slug}:#{event.slug}")
  end

  it "scopes the tag by account, not just the event's own slug — two tenants can share a slug (Event's own scoped friendly_id)" do
    ENV["PUBLIC_SITE_REVALIDATE_URL"] = "https://public-site.example.com/api/revalidate"
    other_account = create(:account, subdomain_slug: "other-tenant")
    Current.account = other_account
    other_event = create(:event, account: other_account, name: event.name)
    Current.account = account
    captured_tags = []
    stub_http_start { |req| captured_tags << JSON.parse(req.body)["tag"]; instance_double(Net::HTTPSuccess, is_a?: true) }

    described_class.call(event)
    described_class.call(other_event)

    expect(other_event.slug).to eq(event.slug)
    expect(captured_tags.uniq.size).to eq(2)
  end

  it "logs a warning (never raises) on a non-2xx response" do
    ENV["PUBLIC_SITE_REVALIDATE_URL"] = "https://public-site.example.com/api/revalidate"
    response = instance_double(Net::HTTPBadRequest, code: "400", is_a?: false)
    stub_http_start { response }
    allow(Rails.logger).to receive(:warn)

    expect { described_class.call(event) }.not_to raise_error
    expect(Rails.logger).to have_received(:warn).with(/400/)
  end

  it "logs a warning (never raises) when the request itself fails" do
    ENV["PUBLIC_SITE_REVALIDATE_URL"] = "https://public-site.example.com/api/revalidate"
    allow(Net::HTTP).to receive(:start).and_raise(Net::OpenTimeout)
    allow(Rails.logger).to receive(:warn)

    expect { described_class.call(event) }.not_to raise_error
    expect(Rails.logger).to have_received(:warn).with(/OpenTimeout/)
  end
end
