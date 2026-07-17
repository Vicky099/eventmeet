FactoryBot.define do
  factory :scan_event do
    association :event
    account { event.account }
    participant { association :participant, event: event, account: account }
    scan_type { :check_in }
    source { :manual }
    scanned_at { Time.current }
  end
end
