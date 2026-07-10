FactoryBot.define do
  factory :account do
    sequence(:name) { |n| "Acme Events #{n}" }
    sequence(:subdomain_slug) { |n| "acme-#{n}" }
    status { :active }
  end
end
