FactoryBot.define do
  factory :event do
    association :account
    sequence(:name) { |n| "Event #{n}" }
    mode { :on_site }
    address { "123 Main St" }
    starts_at { 1.day.from_now }
    ends_at { 2.days.from_now }
  end
end
