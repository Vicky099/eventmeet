FactoryBot.define do
  factory :email_template do
    association :event
    account { event.account }
    kind { :participant_registration }
    subject { "You're registered for $EVENT_NAME$" }
    html_body { "<div>Hi $FIRST_NAME$, you're in for $EVENT_NAME$.</div>" }
    active { true }
  end
end
