FactoryBot.define do
  factory :print_agent do
    association :print_station
    account { print_station.account }
    event { print_station.event }
    sequence(:jti) { |n| "jti-#{n}-#{SecureRandom.hex(4)}" }
    paired_at { Time.current }
    connected { true }
    last_seen_at { Time.current }
  end
end
