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

    # EventSchedulerJob only manages events that have been published at least once
    # (Event#published?) — most job/status specs want that gate already open.
    trait :published do
      published_at { Time.current }
    end

    # SuperAdmin::EventReviewsController's queue only shows approval_status: pending events — the
    # default is unsubmitted (Event#submit_for_review! is what makes the transition for real).
    # Specs that need an event already sitting in the queue use this instead of going through the
    # controller action, same shortcut :published already is for status.
    trait :pending_review do
      approval_status { :pending }
      submitted_at { Time.current }
    end
  end
end
