require "rails_helper"

RSpec.describe AgencyMembership, type: :model do
  it "is valid with a user, agency, and role" do
    expect(build(:agency_membership)).to be_valid
  end

  it "prevents the same user joining the same agency twice" do
    user = create(:user)
    agency = create(:agency)
    create(:agency_membership, user: user, agency: agency)

    duplicate = build(:agency_membership, user: user, agency: agency)

    expect(duplicate).not_to be_valid
  end

  it "rejects a platform_staff user (requirement.md §4.1)" do
    staff = build(:user, :platform_staff)

    expect(build(:agency_membership, user: staff)).not_to be_valid
  end
end
