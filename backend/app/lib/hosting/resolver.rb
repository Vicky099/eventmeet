module Hosting
  # Parses a request's Host header exactly once against the configured platform_domain
  # (requirement.md §4.3) to answer: is this the apex (Platform Console), a tenant subdomain
  # (Admin Console), or neither (not something Rails serves — Next.js's territory or garbage).
  class Resolver
    def initialize(host)
      @host = host.to_s.downcase
    end

    def apex?
      @host == platform_domain
    end

    def tenant_subdomain?
      subdomain_label.present? && !reserved_label?
    end

    # The bit before ".{platform_domain}" on a tenant subdomain host, e.g. "acme" for
    # "acme.lvh.me". Nil if the host isn't a (single-level) subdomain of platform_domain at all.
    def subdomain_label
      return nil unless @host.end_with?(".#{platform_domain}")

      label = @host.delete_suffix(".#{platform_domain}")
      label.include?(".") ? nil : label.presence
    end

    private

    def platform_domain
      Rails.application.config.x.platform_domain
    end

    def reserved_label?
      Account::RESERVED_SLUGS.include?(subdomain_label)
    end
  end
end
