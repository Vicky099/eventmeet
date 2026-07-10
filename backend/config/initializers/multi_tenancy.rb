# requirement.md §4.3: the domain a request arrives on is the single source of truth for both
# *who* it's for and *which* app handles it. platform_domain is the bare apex
# ({platform_domain}.com — Platform Console) that every tenant subdomain
# ({slug}.{platform_domain}.com — Admin Console) is built from.
#
# Rails only ever serves the apex and tenant-subdomain tiers — the public event site
# (events.{platform_domain}.com and custom domains) is Next.js (Phase 18), not this app.
Rails.application.config.x.platform_domain = ENV.fetch("PLATFORM_DOMAIN") do
  case Rails.env
  when "development" then "lvh.me" # *.lvh.me is public DNS that resolves to 127.0.0.1 — no /etc/hosts edits needed
  when "test" then "example.com" # matches Rails' integration-test default host
  else
    raise "PLATFORM_DOMAIN must be set explicitly in #{Rails.env} (requirement.md §4.3)"
  end
end
