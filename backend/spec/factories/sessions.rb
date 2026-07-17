FactoryBot.define do
  factory :session do
    association :event
    account { event.account }
    sequence(:name) { |n| "Session #{n}" }
    starts_at { 1.day.from_now }
    ends_at { 1.day.from_now + 1.hour }
  end
end
