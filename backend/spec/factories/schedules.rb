FactoryBot.define do
  factory :schedule do
    association :event
    account { event.account }
    speaker { association :speaker, account: account, event: event }
    sequence(:title) { |n| "Talk #{n}" }
    starts_at { 1.day.from_now }
    ends_at { 1.day.from_now + 30.minutes }
  end
end
