FactoryBot.define do
  factory :account do
    sequence(:name) { |n| "Acme Events #{n}" }
    sequence(:subdomain_slug) { |n| "acme-#{n}" }
    status { :active }
    sequence(:contact_email) { |n| "contact#{n}@acme.example" }
    sequence(:contact_num) { |n| format("+1 555 %04d", n) }
    sequence(:sender_email) { |n| "sender#{n}@acme.example" }
    time_zone { "UTC" }
    # Fixed-hierarchy pivot (requirement.md revisit): every tenant Account belongs to an Agency now
    # (AgencyConsole::AccountsController is the only place a new one is created) — defaulted here rather
    # than via a trait, so the hundreds of specs that just need *an* event-capable account don't
    # each have to wire one up (same "don't make every spec do this by hand" reasoning the old
    # per-event Quotation default already established). A spec that specifically wants a legacy
    # standalone (no-agency) account passes `agency: nil` explicitly to override.
    agency

    # Kept as an explicit, readable alias for specs that want to call out "this account has an
    # agency" even though it's the default now — equivalent to no trait at all.
    trait :with_agency do
      agency
    end
  end
end
