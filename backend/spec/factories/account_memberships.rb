FactoryBot.define do
  factory :account_membership do
    user
    account
    role { :event_admin }
  end
end
