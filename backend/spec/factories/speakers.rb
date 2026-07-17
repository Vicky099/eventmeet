FactoryBot.define do
  factory :speaker do
    association :event
    account { event.account }
    sequence(:name) { |n| "Speaker #{n}" }
    company { "Acme Co" }
  end
end
