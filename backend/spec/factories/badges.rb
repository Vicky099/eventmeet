FactoryBot.define do
  factory :badge do
    association :event
    account { event.account }
    sequence(:name) { |n| "Badge #{n}" }
    content { "<div>$NAME$</div>" }
    width_cm { 8.5 }
    height_cm { 5.4 }
  end
end
