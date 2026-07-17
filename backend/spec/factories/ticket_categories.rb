FactoryBot.define do
  factory :ticket_category do
    association :event
    account { event.account }
    sequence(:name) { |n| "Category #{n}" }
    total_count { 10 }
  end
end
