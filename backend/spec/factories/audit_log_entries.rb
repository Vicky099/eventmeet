FactoryBot.define do
  factory :audit_log_entry do
    association :actor, factory: [ :user, :platform_staff ]
    action { "agency.suspend" }
    metadata { {} }
  end
end
