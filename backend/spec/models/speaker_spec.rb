require "rails_helper"

RSpec.describe Speaker, type: :model do
  let(:account) { create(:account) }

  before { Current.account = account }

  it "is valid with the factory defaults" do
    expect(build(:speaker, account: account)).to be_valid
  end

  it "requires a name" do
    expect(build(:speaker, account: account, name: nil)).not_to be_valid
  end

  it "validates email format, allowing blank" do
    expect(build(:speaker, account: account, email: "not-an-email")).not_to be_valid
    expect(build(:speaker, account: account, email: nil)).to be_valid
  end

  # Gap-fill against the reference event_management system's speaker field list.
  it "captures country/nationality/contact_num/email/company_details" do
    speaker = create(:speaker, account: account,
      country: "UK", nationality: "British", contact_num: "555-0100",
      email: "ada@example.com", company_details: "Computing pioneers")

    expect(speaker.reload).to have_attributes(
      country: "UK", nationality: "British", contact_num: "555-0100",
      email: "ada@example.com", company_details: "Computing pioneers"
    )
  end

  describe "destroy protection (requirement.md §3.8)" do
    it "refuses to remove a speaker with a scheduled talk" do
      event = create(:event, account: account)
      speaker = create(:speaker, account: account)
      create(:schedule, account: account, event: event, speaker: speaker)

      expect(speaker.destroy).to be false
      expect(speaker.errors[:base]).to be_present
    end

    it "removes a speaker with no scheduled talks" do
      speaker = create(:speaker, account: account)

      expect(speaker.destroy).to be_truthy
    end
  end

  describe "tenant isolation (requirement.md §4.2)" do
    it "never returns another tenant's speakers" do
      other_account = create(:account)
      Current.account = other_account
      create(:speaker, account: other_account)

      Current.account = account
      create(:speaker, account: account)

      expect(Speaker.count).to eq(1)
    end
  end
end
