FactoryBot.define do
  factory :tenant_domain do
    account
    sequence(:domain) { |n| "tenant-#{n}.lvh.me" }
    kind { :subdomain }
    verified_at { Time.current }
  end
end
