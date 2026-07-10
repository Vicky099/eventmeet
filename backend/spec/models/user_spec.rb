require "rails_helper"

RSpec.describe User, type: :model do
  it "is valid with an email and password" do
    expect(build(:user)).to be_valid
  end

  it "is not platform_staff by default" do
    expect(create(:user)).not_to be_platform_staff
  end

  it "rejects a platform_staff user holding an AccountMembership (requirement.md §4.1)" do
    staff = create(:user, :platform_staff)
    membership = build(:account_membership, user: staff)

    expect(membership).not_to be_valid
    expect(membership.errors[:user]).to be_present
  end

  it "rejects marking an already-member user as platform_staff" do
    user = create(:user)
    create(:account_membership, user: user)

    user.platform_staff = true

    expect(user).not_to be_valid
    expect(user.errors[:base]).to be_present
  end

  describe "#active_for_authentication? (requirement.md §4.9 item 1)" do
    it "is active for a platform_staff user when Current.platform_request is set" do
      Current.platform_request = true
      staff = build(:user, :platform_staff)

      expect(staff).to be_active_for_authentication
    end

    it "is inactive for a non-platform_staff user when Current.platform_request is set" do
      Current.platform_request = true
      user = build(:user)

      expect(user).not_to be_active_for_authentication
      expect(user.inactive_message).to eq(:not_authorized_for_this_console)
    end

    it "is active for a user with an AccountMembership on Current.account" do
      account = create(:account)
      user = create(:user)
      create(:account_membership, user: user, account: account)
      Current.account = account

      expect(user).to be_active_for_authentication
    end

    it "is inactive for a user with no AccountMembership on Current.account" do
      account = create(:account)
      user = create(:user)
      Current.account = account

      expect(user).not_to be_active_for_authentication
      expect(user.inactive_message).to eq(:not_authorized_for_this_console)
    end

    it "is inactive when Current.account is suspended, even with a valid AccountMembership" do
      account = create(:account, status: :suspended)
      user = create(:user)
      create(:account_membership, user: user, account: account)
      Current.account = account

      expect(user).not_to be_active_for_authentication
    end
  end
end
