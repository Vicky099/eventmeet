require "rails_helper"

RSpec.describe BadgeTemplate, type: :model do
  let(:account) { create(:account) }

  before { Current.account = account }

  it "is valid with the factory defaults" do
    expect(build(:badge_template, account: account)).to be_valid
  end

  it "requires a name" do
    expect(build(:badge_template, account: account, name: nil)).not_to be_valid
  end

  it "requires content" do
    expect(build(:badge_template, account: account, content: nil)).not_to be_valid
  end

  it "requires positive width/height" do
    expect(build(:badge_template, account: account, width_cm: 0)).not_to be_valid
    expect(build(:badge_template, account: account, height_cm: -1)).not_to be_valid
  end

  describe "mapping validation (HasBadgeMapping)" do
    it "rejects an unknown token key" do
      template = build(:badge_template, account: account, mapping: { "OTHER4" => "email" })
      expect(template).not_to be_valid
      expect(template.errors[:mapping].first).to include("OTHER4")
    end

    it "rejects an unknown mapped field" do
      template = build(:badge_template, account: account, mapping: { "OTHER1" => "made_up_field" })
      expect(template).not_to be_valid
      expect(template.errors[:mapping].first).to include("made_up_field")
    end

    it "accepts a known token key mapped to a known field" do
      template = build(:badge_template, account: account, mapping: { "OTHER1" => "company" })
      expect(template).to be_valid
    end
  end

  it "defaults to output_type badge" do
    expect(create(:badge_template, account: account)).to be_badge
  end
end
