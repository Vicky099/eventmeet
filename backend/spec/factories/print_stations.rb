FactoryBot.define do
  factory :print_station do
    association :event
    account { event.account }
    sequence(:name) { |n| "Station #{n}" }

    # A station with an online, non-revoked agent — the common case specs actually want when they
    # say "a paired station." Plain `create(:print_station)` stays unpaired (matches a
    # freshly-admin-created row before anyone's typed a code into the Electron app).
    trait :online do
      after(:create) do |station|
        station.print_agents.create!(
          account: station.account, event: station.event, jti: SecureRandom.uuid,
          paired_at: Time.current, connected: true, last_seen_at: Time.current
        )
      end
    end
  end
end
