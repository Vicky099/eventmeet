module Api
  module V1
    module Public
      # Phase 25 — Public Event Site API (doc/public_event_site_options.md, requirement.md §4.3).
      # Called by the Next.js server itself (never the visitor's browser) at a fixed,
      # host-independent address — config/routes.rb nests this under Hosting::ApexConstraint, the
      # bare platform_domain — to answer "which Account does this arbitrary incoming Host belong
      # to." The one lookup that can't be tenant-subdomain-routed like everything else in this
      # app, since resolving *that* is the entire point: Next.js doesn't know the tenant yet.
      #
      # Deliberately unauthenticated for the base {account_slug, kind} payload — no OAuth token
      # could be correctly scoped here (that's exactly the chicken-and-egg this endpoint exists to
      # resolve), and that much reveals no more than an ordinary DNS lookup + page visit already
      # would (doc's own "no CORS/token needed, not sensitive" reasoning).
      #
      # requirement.md §4.9 item 4 ("the tenant's own OAuth application... the same credential the
      # Next.js BFF uses") left one real gap the original plan doc didn't spell out: Next.js is a
      # single shared deployment across every tenant, so it has no per-tenant client_id/secret
      # hardcoded anywhere — it has to look one up per request, for whichever tenant the incoming
      # Host resolves to. Bundled into this same call (not a second endpoint/round-trip) — the
      # `client_id`/`client_secret` fields only appear when the caller presents
      # PUBLIC_SITE_SHARED_SECRET, a second, distinct trust boundary from the base lookup above
      # (this is Next.js's server proving *it's* Next.js, not a visitor's browser hitting this
      # endpoint directly and fishing for credentials).
      class DomainResolutionsController < ActionController::Base
        skip_forgery_protection

        def show
          # Rack's own request.host (what Hosting::Resolver's every other caller passes) strips a
          # port automatically; a bare `?host=` query param doesn't get that for free, so it's
          # stripped explicitly here — confirmed live: a caller passing "tenant.lvh.me:5173"
          # 404ed silently otherwise, since neither the TenantDomain exact-match nor
          # Hosting::Resolver's own `end_with?(".#{platform_domain}")` check tolerate a port.
          host = params[:host].to_s.downcase.split(":").first.to_s

          if host.blank?
            head :not_found
            return
          end

          # Custom (or custom-domain-verified-as-subdomain-shaped) domain first — a plain
          # exact-string match handles an apex and a subdomain-shaped custom domain identically,
          # same reasoning this doc's own "Custom domain handling" section gives.
          if (tenant_domain = TenantDomain.where.not(verified_at: nil).find_by(domain: host))
            render json: payload_for(tenant_domain.account, tenant_domain.kind)
            return
          end

          # Falls back to the shared default domain's own `{slug}.platform_domain` shape — this
          # doesn't require a TenantDomain row to exist at all, since every Account already carries
          # its own subdomain_slug directly (Hosting::Resolver's same parsing every tenant-subdomain
          # request already goes through).
          slug = Hosting::Resolver.new(host).subdomain_label
          account = slug && Account.find_by(subdomain_slug: slug)

          if account
            render json: payload_for(account, "subdomain")
          else
            head :not_found
          end
        end

        private

        def payload_for(account, kind)
          payload = { account_slug: account.subdomain_slug, kind: kind }
          payload.merge!(oauth_credentials(account)) if shared_secret_presented?
          payload
        end

        def shared_secret_presented?
          secret = ENV["PUBLIC_SITE_SHARED_SECRET"]
          secret.present? && ActiveSupport::SecurityUtils.secure_compare(secret, request.headers["X-Public-Site-Secret"].to_s)
        end

        # nil (no oauth_application yet — shouldn't happen for any Account provisioned through
        # AccountProvisioning, but this is read-only lookup code, not the place to raise over it)
        # → omitted from the payload entirely, same "absent, not a null crash" shape the rest of
        # this response already takes for a not-found host.
        def oauth_credentials(account)
          application = account.oauth_application
          return {} if application.nil?

          { client_id: application.uid, client_secret: application.secret }
        end
      end
    end
  end
end
