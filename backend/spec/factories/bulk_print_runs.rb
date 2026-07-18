FactoryBot.define do
  factory :bulk_print_run do
    association :event
    account { event.account }
    print_station { association :print_station, event: event, account: account }
    created_by { association :user }
    limit { 10 }
    status { :pending }
  end
end
