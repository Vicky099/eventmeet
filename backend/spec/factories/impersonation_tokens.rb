FactoryBot.define do
  factory :impersonation_token do
    association :platform_staff, factory: [ :user, :platform_staff ]
    user
    account
    sequence(:token) { |n| "test-impersonation-token-#{n}" }
    expires_at { 60.seconds.from_now }
    redeemed_at { nil }
  end
end
