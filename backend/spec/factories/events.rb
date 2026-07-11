FactoryBot.define do
  factory :event do
    association :account
    sequence(:name) { |n| "Event #{n}" }
    mode { :on_site }
    address { "123 Main St" }
    starts_at { 1.day.from_now }
    ends_at { 2.days.from_now }

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
