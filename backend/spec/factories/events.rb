FactoryBot.define do
  factory :event do
    association :account
    sequence(:name) { |n| "Event #{n}" }
    mode { :on_site }
    address { "123 Main St" }
    map_url { "https://maps.google.com/?q=123+Main+St" }
    starts_at { 1.day.from_now }
    ends_at { 2.days.from_now }
    # Event#clear_seat_limit_unless_flagged discards seat_limit unless has_seat_limit is true —
    # specs that pass seat_limit directly (create(:event, seat_limit: 50)) mean to set a real cap,
    # so infer the flag from it rather than making every such call also pass has_seat_limit: true.
    has_seat_limit { seat_limit.present? }
    # Fixed-hierarchy pivot (requirement.md revisit): no more Quotation — every Event's account
    # already has an Agency by default (spec/factories/accounts.rb's own comment), which is all
    # Event#agency_contract_must_be_active/#consume_agency_slot_if_metered need.

    # EventSchedulerJob only manages events that have been published at least once
    # (Event#published?) — most job/status specs want that gate already open.
    trait :published do
      published_at { Time.current }
    end
  end
end
