require "rails_helper"

RSpec.describe SidekiqWebSameOriginShim do
  let(:downstream_env) { {} }
  let(:downstream) do
    lambda do |env|
      downstream_env.replace(env)
      [ 200, {}, [ "ok" ] ]
    end
  end
  let(:middleware) { described_class.new(downstream) }

  def call(headers = {})
    env = Rack::MockRequest.env_for("http://lvh.me:3000/platform/sidekiq/retries", method: "POST", **headers)
    middleware.call(env)
  end

  it "leaves the header alone when the browser already sent it (never overrides a real value)" do
    call("HTTP_SEC_FETCH_SITE" => "cross-site")

    expect(downstream_env["HTTP_SEC_FETCH_SITE"]).to eq("cross-site")
  end

  it "backfills same-origin when Origin matches this app's own host" do
    call("HTTP_ORIGIN" => "http://lvh.me:3000")

    expect(downstream_env["HTTP_SEC_FETCH_SITE"]).to eq("same-origin")
  end

  it "backfills same-origin when Referer matches this app's own host (no Origin header)" do
    call("HTTP_REFERER" => "http://lvh.me:3000/platform/sidekiq/retries")

    expect(downstream_env["HTTP_SEC_FETCH_SITE"]).to eq("same-origin")
  end

  it "does not backfill when Origin points at a different host (genuine cross-site request stays blocked)" do
    call("HTTP_ORIGIN" => "http://evil.example.com")

    expect(downstream_env["HTTP_SEC_FETCH_SITE"]).to be_nil
  end

  it "does not backfill with no Origin or Referer at all" do
    call

    expect(downstream_env["HTTP_SEC_FETCH_SITE"]).to be_nil
  end

  it "does not backfill on a malformed Origin header" do
    call("HTTP_ORIGIN" => "not a valid uri")

    expect(downstream_env["HTTP_SEC_FETCH_SITE"]).to be_nil
  end
end
