FactoryBot.define do
  factory :agency do
    sequence(:name) { |n| "Agency Events #{n}" }
    sequence(:subdomain_slug) { |n| "agency-#{n}" }
    status { :active }
    sequence(:contact_email) { |n| "contact#{n}@agency.example" }
    sequence(:contact_num) { |n| format("+1 555 %04d", n) }
    billing_cycle { :per_event }
    price_per_event { 10_000 }
    currency { "INR" }
    # High enough that ordinary specs creating a handful of events per account never hit
    # exhaustion by accident — specs that specifically want to test the pool running out
    # (Agency#consume_event_slot!, Event's own agency_contract_must_be_active) set a low
    # events_granted explicitly instead.
    events_granted { 1_000 }
    events_used { 0 }

    # Fixed-hierarchy pivot (requirement.md revisit): the "paid upfront" contract type — no pool at
    # all, gated on Agency#contract_active? (invoice&.paid?) instead. Builds an already-paid
    # contract Invoice by default (Invoice.generate_for_agency_contract mirrors this shape for
    # real, at AgencyProvisioning time) so a plain `create(:agency, :annual)` is immediately usable
    # the same way the default per_event agency already is; specs testing the *unpaid* gate itself
    # pass `annual_price:`/build their own unpaid invoice explicitly instead.
    trait :annual do
      billing_cycle { :annual }
      price_per_event { nil }
      events_granted { 0 }
      annual_price { 500_000 }

      after(:create) do |agency|
        agency.create_invoice!(amount: agency.annual_price, currency: agency.currency, status: :paid, verified_at: Time.current)
      end
    end
  end
end
