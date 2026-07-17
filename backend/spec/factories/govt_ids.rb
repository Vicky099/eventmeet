FactoryBot.define do
  factory :govt_id do
    association :event
    account { event.account }
    sequence(:value) { |n| "GID-#{n}" }
  end
end
