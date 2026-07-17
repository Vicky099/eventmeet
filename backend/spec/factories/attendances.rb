FactoryBot.define do
  factory :attendance do
    association :event
    account { event.account }
    participant { association :participant, event: event, account: account }
    from { :event }
    status { :check_in }
    occurred_at { Time.current }
  end
end
