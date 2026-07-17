FactoryBot.define do
  factory :badge_template do
    association :account
    sequence(:name) { |n| "Badge Template #{n}" }
    content { "<div>$NAME$</div>" }
    width_cm { 8.5 }
    height_cm { 5.4 }
  end
end
