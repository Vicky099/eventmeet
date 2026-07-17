require "rails_helper"

# Phase 13 — Communications (requirement.md §3.10, §5.10, §8). One row per actual delivery
# attempt — created/progressed exclusively through Notifier/NotificationDeliveryJob; this spec
# covers the model's own shape (validations, enums, state-transition helpers) in isolation.
RSpec.describe Notification, type: :model do
  let(:account) { create(:account) }
  let(:event) { create(:event, account: account) }

  before { Current.account = account }

  it "is valid with the factory defaults" do
    expect(build(:notification, account: account, notifiable: event)).to be_valid
  end

  it "requires a to" do
    notification = build(:notification, account: account, notifiable: event, to: nil)
    expect(notification).not_to be_valid
    expect(notification.errors[:to]).to be_present
  end

  it "exposes channel as email/whatsapp" do
    expect(described_class.channels).to eq("email" => 0, "whatsapp" => 1)
  end

  it "exposes status as pending/sent/failed, defaulting to pending" do
    expect(described_class.statuses).to eq("pending" => 0, "sent" => 1, "failed" => 2)
    expect(create(:notification, account: account, notifiable: event).status).to eq("pending")
  end

  describe "#mark_sent!" do
    it "moves to sent, stamps sent_at, and clears any prior error" do
      notification = create(:notification, account: account, notifiable: event, status: :failed, error_message: "boom")

      notification.mark_sent!

      expect(notification.status).to eq("sent")
      expect(notification.sent_at).to be_present
      expect(notification.error_message).to be_nil
    end
  end

  describe "#mark_failed!" do
    it "moves to failed and records the error message, truncated" do
      notification = create(:notification, account: account, notifiable: event)

      notification.mark_failed!(StandardError.new("a" * 2000))

      expect(notification.status).to eq("failed")
      expect(notification.error_message.length).to be <= 1000
    end
  end

  describe "tenant isolation (requirement.md §4.2)" do
    it "is scoped to Current.account" do
      other_account = create(:account)
      Current.account = other_account
      other_event = create(:event, account: other_account)
      create(:notification, account: other_account, notifiable: other_event)

      Current.account = account
      create(:notification, account: account, notifiable: event)

      expect(Notification.count).to eq(1)
    end
  end
end
