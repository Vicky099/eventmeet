require "rails_helper"

# Phase 13 — Communications (requirement.md §3.10, §5.10). The single entry point every tracked
# mailer/WhatsApp send routes through — NotificationDeliveryJob's own actual-send behavior is
# covered in spec/jobs/notification_delivery_job_spec.rb; this is just "does .email/.whatsapp
# create the right row and enqueue the right job."
RSpec.describe Notifier do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:event) { create(:event, account: account) }

  before { Current.account = account }

  describe ".email" do
    it "creates a pending email Notification and enqueues NotificationDeliveryJob" do
      expect {
        described_class.email(
          mailer_class: BillingMailer, mailer_method: :invoice_sent, mailer_args: [ create(:invoice, event: event, account: account), "owner@example.com" ],
          notifiable: event, to: "owner@example.com", subject: "Needs changes"
        )
      }.to change(Notification, :count).by(1).and have_enqueued_job(NotificationDeliveryJob)

      notification = Notification.last
      expect(notification.channel).to eq("email")
      expect(notification.status).to eq("pending")
      expect(notification.to).to eq("owner@example.com")
      expect(notification.subject).to eq("Needs changes")
      expect(notification.notifiable).to eq(event)
      expect(notification.account).to eq(account)
    end

    it "defaults account: to notifiable.account" do
      notification = described_class.email(
        mailer_class: BillingMailer, mailer_method: :invoice_sent, mailer_args: [ create(:invoice, event: event, account: account), "owner@example.com" ],
        notifiable: event, to: "owner@example.com"
      )

      expect(notification.account).to eq(event.account)
    end

    it "accepts an explicit account: override for a notifiable with no #account of its own (e.g. Account itself)" do
      notification = described_class.email(
        mailer_class: AccountMailer, mailer_method: :welcome, mailer_args: [ create(:user), account, "temp123" ],
        notifiable: account, account: account, to: "owner@example.com"
      )

      expect(notification.notifiable).to eq(account)
      expect(notification.account).to eq(account)
    end
  end

  describe ".whatsapp" do
    it "creates a pending whatsapp Notification and enqueues NotificationDeliveryJob when a phone number is given" do
      expect {
        described_class.whatsapp(notifiable: event, to: "+15550100", body: "Event rejected")
      }.to change(Notification, :count).by(1).and have_enqueued_job(NotificationDeliveryJob)

      notification = Notification.last
      expect(notification.channel).to eq("whatsapp")
      expect(notification.status).to eq("pending")
      expect(notification.body).to eq("Event rejected")
    end

    it "creates a failed Notification (no job enqueued) when there's no phone number on file" do
      expect {
        expect {
          described_class.whatsapp(notifiable: event, to: nil, body: "Event rejected")
        }.not_to have_enqueued_job(NotificationDeliveryJob)
      }.to change(Notification, :count).by(1)

      notification = Notification.last
      expect(notification.status).to eq("failed")
      expect(notification.error_message).to include("no contact number")
    end
  end
end
