require "rails_helper"

# Phase 13 — Communications, revisited: "Quick Email Send" — enqueued by Admin::
# EmailTemplatesController#quick_send rather than looping over participants inline in the request.
RSpec.describe QuickEmailSendJob, type: :job do
  let(:account) { create(:account) }
  let(:event) { create(:event, account: account) }

  before { Current.account = account }

  describe "kind: :quick_send (needs a configured, active EmailTemplate row)" do
    it "enqueues one tracked delivery per participant with an email on file" do
      create(:participant, account: account, event: event, email: "a@example.com")
      create(:participant, account: account, event: event, email: "b@example.com")
      create(:participant, account: account, event: event, email: nil) # deliver_quick_email!'s own guard skips this one
      create(:email_template, account: account, event: event, kind: :quick_send,
        subject: "Reminder", html_body: "<html><body><p>hi</p></body></html>")

      expect { described_class.perform_now(event.id, "quick_send") }
        .to have_enqueued_job(NotificationDeliveryJob).exactly(2).times
    end

    it "creates one Notification per participant, addressed to that participant's own email" do
      create(:participant, account: account, event: event, email: "a@example.com")
      create(:email_template, account: account, event: event, kind: :quick_send,
        subject: "Reminder", html_body: "<html><body><p>hi</p></body></html>")

      expect { described_class.perform_now(event.id, "quick_send") }.to change { Notification.count }.by(1)
      expect(Notification.last.to).to eq("a@example.com")
    end

    it "sends nothing when no active :quick_send template exists (e.g. deactivated after enqueue)" do
      create(:participant, account: account, event: event, email: "a@example.com")

      expect { described_class.perform_now(event.id, "quick_send") }.not_to change { Notification.count }
    end
  end

  # Phase 13 — Communications, revisited: "Participant Registration Confirmation needed in the
  # quick send" — sendable even with no EmailTemplate row at all (EmailTemplate::
  # ALWAYS_SENDABLE_KINDS), unlike :quick_send above.
  describe "kind: :participant_registration" do
    it "sends the built-in confirmation email (PDF+QR included) when no custom template is configured" do
      participant = create(:participant, account: account, event: event, email: "a@example.com")

      expect { described_class.perform_now(event.id, "participant_registration") }
        .to have_enqueued_job(NotificationDeliveryJob)

      notification = Notification.last
      expect(notification.to).to eq("a@example.com")
      expect(notification.notifiable).to eq(participant)
    end

    it "uses the custom template when one is configured, exactly like a real registration send" do
      create(:participant, account: account, event: event, email: "a@example.com")
      create(:email_template, account: account, event: event, kind: :participant_registration,
        subject: "Custom subject", html_body: "<html><body><p>Custom body</p></body></html>")

      expect { described_class.perform_now(event.id, "participant_registration") }
        .to have_enqueued_job(NotificationDeliveryJob)
    end
  end

  it "works from a plain job process with no ambient Current.account (sets it from the event's own account)" do
    create(:participant, account: account, event: event, email: "a@example.com")
    Current.account = nil # simulates a fresh Sidekiq process — the job must set this itself

    expect { described_class.perform_now(event.id, "participant_registration") }.not_to raise_error
  end
end
