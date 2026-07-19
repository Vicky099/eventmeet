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

# requirement.md revisit: "as whatsApp is paid i want to track the usage and the approx amount" —
# Gupshup bills per-message, not per-tenant, and there's no per-message cost anywhere in this
# app's own data (Notification just tracks delivery state, requirement.md §3.10). This is a flat,
# platform-wide approximation, not a real Gupshup invoice reconciliation — a stakeholder-set
# figure (INR — the platform's own default currency, Currency module's own comment), ENV-
# overridable once the actual Gupshup plan/rate is known, ₹0.80 in the meantime as a placeholder
# in the ballpark of a Gupshup utility-template conversation.
Rails.application.config.x.whatsapp_message_cost = BigDecimal(ENV.fetch("WHATSAPP_MESSAGE_COST", "0.80"))
