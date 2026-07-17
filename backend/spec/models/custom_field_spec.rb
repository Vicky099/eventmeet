require "rails_helper"

RSpec.describe CustomField, type: :model do
  let(:account) { create(:account) }
  let(:event) { create(:event, account: account) }
  let(:registration_form) { create(:registration_form, account: account, event: event) }

  before { Current.account = account }

  it "is valid with the factory defaults" do
    expect(build(:custom_field, account: account, registration_form: registration_form)).to be_valid
  end

  it "requires a label" do
    expect(build(:custom_field, account: account, registration_form: registration_form, label: nil)).not_to be_valid
  end

  it "requires options for a dropdown field, but not other types" do
    dropdown = build(:custom_field, account: account, registration_form: registration_form, field_type: :dropdown, options: nil)
    text = build(:custom_field, account: account, registration_form: registration_form, field_type: :text, options: nil)

    expect(dropdown).not_to be_valid
    expect(text).to be_valid
  end

  it "does not collide with ActiveRecord's own .select class method" do
    # field_type: dropdown (not :select) precisely to avoid this — regression guard for the
    # boot-time ArgumentError Rails raises if an enum value shadows an existing class method.
    expect(CustomField.field_types.keys).to include("dropdown")
    expect(CustomField).to respond_to(:select) # still ActiveRecord's own, unclobbered
  end

  describe "#options_list" do
    it "parses newline-separated choices into an array" do
      field = build(:custom_field, account: account, registration_form: registration_form, options: "Vegetarian\nVegan\n\nGluten-Free\n")
      expect(field.options_list).to eq(%w[Vegetarian Vegan Gluten-Free])
    end

    it "is empty for a blank options value" do
      field = build(:custom_field, account: account, registration_form: registration_form, options: nil)
      expect(field.options_list).to eq([])
    end
  end
end
