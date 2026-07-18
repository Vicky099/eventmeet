# Sidekiq::Web (>= 7.1, this app's own Gemfile.lock: 8.1.6) requires the browser's own
# `Sec-Fetch-Site: same-origin` Fetch Metadata header on every non-GET/HEAD/OPTIONS/TRACE
# request — its own CSRF replacement (Sidekiq's Changes.md: "Remove CSRF code, use Sec-Fetch-Site
# header"), hardcoded in `Sidekiq::Web#safe_request?`/`#deny` with no config toggle to disable in
# this version. Confirmed live: an already-authenticated (platform_staff-only,
# config/routes.rb's own `authenticated` gate) Super Admin request to delete a retry got a bare
# "Forbidden," even though the click genuinely came from this same page — reproduced with a
# controlled `curl` request: identical POST, missing header -> 403; header added -> no more 403.
# Modern Chromium sends this header automatically on a same-origin form POST; when it's missing,
# it's virtually always a browser extension, corporate proxy, or older/non-Chromium browser
# stripping Fetch Metadata headers, not an actual cross-site attack.
#
# Since this route is already gated behind Devise's :platform_staff authentication before this
# middleware (or Sidekiq::Web itself) ever runs, Sec-Fetch-Site here is a second, defense-in-depth
# layer, not the only thing standing between an attacker and this page — this backfills it from
# Origin/Referer instead of disabling the check outright, so a genuine cross-site POST (forged
# from another site, whose Origin/Referer won't match this app's own host) is still rejected
# exactly the way it always was.
class SidekiqWebSameOriginShim
  def initialize(app)
    @app = app
  end

  def call(env)
    if env["HTTP_SEC_FETCH_SITE"].nil?
      request = Rack::Request.new(env)
      source = request.get_header("HTTP_ORIGIN") || request.get_header("HTTP_REFERER")
      env["HTTP_SEC_FETCH_SITE"] = "same-origin" if source && same_host?(source, request.host)
    end

    @app.call(env)
  end

  private

  def same_host?(source_url, expected_host)
    URI.parse(source_url).host == expected_host
  rescue URI::InvalidURIError
    false
  end
end
