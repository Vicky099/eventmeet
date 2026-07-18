FactoryBot.define do
  factory :quotation do
    association :account
    sequence(:event_name) { |n| "Business Event #{n}" }
    expected_participant_count { 100 }
    association :requested_by, factory: :user

    trait :sent do
      current_amount { 30_000 }
      status { :pending }
      sent_at { Time.current }
    end

    trait :approved do
      current_amount { 30_000 }
      status { :approved }
      sent_at { Time.current }
      association :approved_by, factory: :user
      approved_at { Time.current }
    end
  end
end
