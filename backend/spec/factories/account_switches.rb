FactoryBot.define do
  factory :account_switch do
    user
    account
    sequence(:token) { |n| "test-switch-token-#{n}" }
    expires_at { 60.seconds.from_now }
    redeemed_at { nil }
  end
end
