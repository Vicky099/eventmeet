FactoryBot.define do
  factory :event_page do
    association :event
    account { event.account }
    html { "<h1>{{not a real placeholder}}</h1><p>Join us!</p>" }
  end
end
