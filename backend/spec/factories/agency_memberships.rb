FactoryBot.define do
  factory :agency_membership do
    user
    agency
    role { :agency_admin }
  end
end
