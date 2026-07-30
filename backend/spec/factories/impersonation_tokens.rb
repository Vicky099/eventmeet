FactoryBot.define do
  factory :impersonation_token do
    association :platform_staff, factory: [ :user, :platform_staff ]
    user
    account
    sequence(:token) { |n| "test-impersonation-token-#{n}" }
    expires_at { 60.seconds.from_now }
    redeemed_at { nil }

    # Agency Console impersonation (requirement.md revisit) — the other side of
    # ImpersonationToken#account_or_agency_present's exactly-one-present validation.
    trait :for_agency do
      account { nil }
      agency
    end
  end
end
