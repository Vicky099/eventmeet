FactoryBot.define do
  factory :notification do
    association :account
    notifiable { association :event, account: account }
    channel { :email }
    status { :pending }
    to { "recipient@example.com" }
  end
end
