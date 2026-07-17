FactoryBot.define do
  factory :custom_field do
    association :registration_form
    account { registration_form.account }
    sequence(:label) { |n| "Custom Field #{n}" }
    field_type { :text }
  end
end
