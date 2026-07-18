FactoryBot.define do
  factory :quotation_revision do
    association :quotation
    account { quotation.account }
    amount { 30_000 }
    rejection_note { "Too expensive for this event's expected turnout." }
    association :created_by, factory: :user
  end
end
