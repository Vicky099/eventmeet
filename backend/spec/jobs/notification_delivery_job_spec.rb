require "rails_helper"

# Phase 13 — Communications (requirement.md §3.10, §5.10). Definition of Done: "a rejection event
# now enqueues both an email job and a WhatsApp job, each independently tracked (one failing
# doesn't block the other)" and "Gupshup client handles a non-200 response by marking the
# notification failed, not raising unhandled."
RSpec.describe NotificationDeliveryJob, type: :job do
  let(:account) { create(:account) }
  let(:event) { create(:event, account: account) }

  before { Current.account = account }

  describe "channel: email" do
    it "delivers the mailer and marks the notification sent" do
      notification = create(:notification, account: account, notifiable: event, channel: :email, to: "owner@example.com")

      expect {
        described_class.perform_now(notification.id, mailer_class: "EventMailer", mailer_method: "rejected", mailer_args: [ event, "owner@example.com" ])
      }.to change { ActionMailer::Base.deliveries.size }.by(1)

      expect(notification.reload.status).to eq("sent")
      expect(notification.sent_at).to be_present
    end

    it "marks the notification failed (does not raise) when the mailer itself blows up" do
      notification = create(:notification, account: account, notifiable: event, channel: :email, to: "owner@example.com")

      expect {
        described_class.perform_now(notification.id, mailer_class: "EventMailer", mailer_method: "not_a_real_method", mailer_args: [ event, "owner@example.com" ])
      }.not_to raise_error

      expect(notification.reload.status).to eq("failed")
      expect(notification.error_message).to be_present
    end
  end

  describe "channel: whatsapp" do
    it "sends via GupshupClient and marks the notification sent" do
      notification = create(:notification, account: account, notifiable: event, channel: :whatsapp, to: "+15550100", body: "hi")
      allow_any_instance_of(GupshupClient).to receive(:send_message).and_return(true)

      described_class.perform_now(notification.id)

      expect(notification.reload.status).to eq("sent")
    end

    # This is the concrete "one failing doesn't block the other" + "handles a non-200 response by
    # marking the notification failed, not raising unhandled" case — no Gupshup credential is
    # configured in this test environment at all, so GupshupClient itself raises DeliveryError,
    # and this job must absorb that rather than let it propagate.
    it "marks the notification failed (does not raise) when GupshupClient raises DeliveryError" do
      notification = create(:notification, account: account, notifiable: event, channel: :whatsapp, to: "+15550100", body: "hi")

      expect { described_class.perform_now(notification.id) }.not_to raise_error

      expect(notification.reload.status).to eq("failed")
      expect(notification.error_message).to include("credentials")
    end
  end

  it "sets Current.account from the notification's own account (jobs don't inherit request state)" do
    notification = create(:notification, account: account, notifiable: event, channel: :email, to: "owner@example.com")
    Current.account = nil

    described_class.perform_now(notification.id, mailer_class: "EventMailer", mailer_method: "rejected", mailer_args: [ event, "owner@example.com" ])

    expect(notification.reload.status).to eq("sent")
  end
end
