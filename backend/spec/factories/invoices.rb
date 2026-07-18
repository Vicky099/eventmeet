FactoryBot.define do
  factory :invoice do
    association :event
    account { event.account }
    amount { 25_000 }

    trait :awaiting_payment do
      status { :awaiting_payment }
    end

    trait :under_review do
      status { :under_review }
      utr_reference { "UTR123456789" }
      association :submitted_by, factory: :user
      submitted_at { Time.current }
    end

    trait :paid do
      status { :paid }
      utr_reference { "UTR123456789" }
      association :submitted_by, factory: :user
      submitted_at { Time.current }
      association :verified_by, factory: :user
      verified_at { Time.current }
    end
  end
end
