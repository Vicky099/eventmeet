FactoryBot.define do
  factory :print_job do
    association :event
    account { event.account }
    print_station { association :print_station, event: event, account: account }
    participant { association :participant, event: event, account: account }
    status { :pending }
    source { :manual }
  end
end
