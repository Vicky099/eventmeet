# Local-dev-only convenience for exercising Api::V1::Public:: directly from a browser (e.g. a
# `fetch` from a *.lvh.me tab's own JS console, or a one-off test page) — not needed by anything
# this app actually ships: the real Next.js client is a BFF (frontend/src/lib/server/rails.ts's
# own comment: "the browser only ever calls this app's own /api/* routes, never Rails directly"),
# so no production traffic ever needs this. Deliberately scoped two ways, matching
# requirement.md §7.4's own warning that a static wildcard origin is unsafe for the public API
# surface in general:
#   1. `Rails.env.development?` only — never loaded in test/staging/production.
#   2. `Api::V1::Public::` routes only — never the session-cookie-authenticated Admin/Agency
#      consoles, where allowing cross-origin JS reads of an authenticated session would be a real
#      CSRF-adjacent risk regardless of environment.
# Every one of these endpoints is already Doorkeeper-bearer-token-protected (or, for
# domain_resolutions#show, deliberately unauthenticated read-only lookup) — CORS only controls
# whether a *browser* is allowed to read the response of a cross-origin request, it grants no new
# access a same-origin `curl` couldn't already get.
if Rails.env.development?
  require "rack/cors"

  Rails.application.config.middleware.insert_before 0, Rack::Cors do
    allow do
      origins(/\Ahttps?:\/\/([a-z0-9-]+\.)*lvh\.me(:\d+)?\z/)

      resource "/api/v1/public/*",
        headers: :any,
        methods: %i[get post options],
        credentials: false
    end
  end
end
