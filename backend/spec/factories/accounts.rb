FactoryBot.define do
  factory :account do
    sequence(:name) { |n| "Acme Events #{n}" }
    sequence(:subdomain_slug) { |n| "acme-#{n}" }
    status { :active }
    sequence(:contact_email) { |n| "contact#{n}@acme.example" }
    sequence(:contact_num) { |n| format("+1 555 %04d", n) }
    sequence(:sender_email) { |n| "sender#{n}@acme.example" }
    time_zone { "UTC" }
  end
end
