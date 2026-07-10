module Hosting
  # Routing constraint: matches any syntactically valid tenant subdomain of platform_domain
  # (requirement.md §4.3) — Admin Console territory. Whether the subdomain actually belongs to a
  # real Account is resolved downstream by TenantResolvable (app/controllers/concerns); this
  # constraint only rules out the apex and reserved-word hosts from ever reaching tenant routes.
  class TenantSubdomainConstraint
    def matches?(request)
      Resolver.new(request.host).tenant_subdomain?
    end
  end
end
