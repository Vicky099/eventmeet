require "rails_helper"

RSpec.describe ParticipantExportFields do
  let(:account) { create(:account) }
  let(:event) { create(:event, account: account) }

  before { Current.account = account }

  describe "#groups" do
    it "always includes the standard participant details" do
      groups = described_class.groups(event)

      details = groups.find { |group| group[:name] == "Participant Details" }
      expect(details[:fields].map { |field| field[:key] }).to include("first_name", "email", "status")
    end

    it "omits the Custom Fields / Attendance sections' dynamic-only entries when there are none" do
      groups = described_class.groups(event)

      expect(groups.map { |group| group[:name] }).not_to include("Custom Fields")
    end

    it "lists each of the event's own sessions as a Time in: <session> field" do
      session = create(:session, account: account, event: event, name: "Keynote Hall")

      groups = described_class.groups(event)

      attendance = groups.find { |group| group[:name] == "Attendance & Time Analytics" }
      expect(attendance[:fields]).to include(key: "session_time:#{session.id}", label: "Time in: Keynote Hall")
    end

    it "lists each distinct custom field across the event's registration forms" do
      form = create(:registration_form, account: account, event: event)
      field = create(:custom_field, account: account, registration_form: form, label: "Dietary Needs")

      groups = described_class.groups(event)

      custom = groups.find { |group| group[:name] == "Custom Fields" }
      expect(custom[:fields]).to include(key: "custom_field:#{field.id}", label: "Dietary Needs")
    end

    it "never lists another event's sessions or custom fields" do
      other_event = create(:event, account: account)
      create(:session, account: account, event: other_event, name: "Someone Else's Session")

      groups = described_class.groups(event)

      attendance = groups.find { |group| group[:name] == "Attendance & Time Analytics" }
      expect(attendance[:fields].map { |field| field[:label] }).not_to include("Time in: Someone Else's Session")
    end
  end

  describe "#label_for" do
    it "resolves a known key to its label" do
      expect(described_class.label_for(event, "first_name")).to eq("First Name")
    end

    it "falls back to the raw key for something not in this event's current field list" do
      expect(described_class.label_for(event, "session_time:no-longer-exists")).to eq("session_time:no-longer-exists")
    end
  end
end
