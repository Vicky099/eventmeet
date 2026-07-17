FactoryBot.define do
  factory :ticket_reservation do
    association :ticket_category
    event { ticket_category.event }
    account { ticket_category.account }
    seat_count { 1 }
    sequence(:holder_name) { |n| "Holder #{n}" }
    sequence(:holder_email) { |n| "holder#{n}@example.com" }
  end
end
