FactoryBot.define do
  factory :account_membership do
    user
    account
    role { :owner }
  end
end
