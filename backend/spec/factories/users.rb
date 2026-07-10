FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123!" }
    platform_staff { false }

    trait :platform_staff do
      platform_staff { true }
    end

    trait :must_reset_password do
      must_reset_password { true }
    end
  end
end
