require "rails_helper"

RSpec.describe AccountMembership, type: :model do
  it "is valid with a user, account, and role" do
    expect(build(:account_membership)).to be_valid
  end

  it "prevents the same user joining the same account twice" do
    user = create(:user)
    account = create(:account)
    create(:account_membership, user: user, account: account)

    duplicate = build(:account_membership, user: user, account: account)

    expect(duplicate).not_to be_valid
  end

  it "allows the same user to belong to two different accounts (agency use case, §4.1)" do
    user = create(:user)
    create(:account_membership, user: user, account: create(:account))
    second = build(:account_membership, user: user, account: create(:account))

    expect(second).to be_valid
  end
end
