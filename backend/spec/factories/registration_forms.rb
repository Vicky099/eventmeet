FactoryBot.define do
  factory :registration_form do
    association :event
    account { event.account }
    sequence(:name) { |n| "Registration Form #{n}" }
    uniqueness_fields { %w[email contact_num] }
  end
end
