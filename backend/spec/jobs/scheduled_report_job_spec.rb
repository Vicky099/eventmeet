require "rails_helper"

# Phase 14 — Reporting, Import/Export & Analytics (requirement.md §5.11): "Scheduled report
# delivery (Sidekiq-cron or equivalent: emailed weekly/daily summary to organizers)." Self-
# rescheduling (EventSchedulerJob's own pattern) — #perform's own `ensure` unconditionally
# re-enqueues itself, so a bare `perform_enqueued_jobs { described_class.perform_now }` recurses
# forever within that one block (each drained self-reschedule immediately enqueues another).
# `only: NotificationDeliveryJob` is what actually fixes it — only the *notification* sends this
# job triggers get drained/executed; its own self-reschedule stays queued, unexamined, and gets
# swept away by the `clear_enqueued_jobs` below.
#
# Current.account = account after every perform_now/perform_enqueued_jobs call below, before any
# further Event/Notification query — same "Current is only set for the *duration* of the job's
# own execution, reset by Rails' executor once #perform returns" reasoning
# spec/requests/admin_events_spec.rb's own event_count helper already documents for requests;
# ActiveJob's perform_now is wrapped in that same executor boundary.
RSpec.describe ScheduledReportJob, type: :job do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }

  before { Current.account = account }

  def create_event(**attrs)
    create(:event, :published, account: account, **attrs)
  end

  around do |example|
    example.run
    clear_enqueued_jobs
  end

  it "does nothing for events with scheduled_report_frequency: none (the default)" do
    create_event(scheduled_report_frequency: :none)

    perform_enqueued_jobs(only: NotificationDeliveryJob) { described_class.perform_now }
    Current.account = account

    expect(Notification.count).to eq(0)
  end

  it "sends a report to every owner for a daily event with no last_report_sent_at yet" do
    event = create_event(scheduled_report_frequency: :daily, name: "Annual Meetup")
    owner = create(:user, email: "owner@acme.example")
    create(:account_membership, user: owner, account: account, role: :owner)

    perform_enqueued_jobs(only: NotificationDeliveryJob) { described_class.perform_now }
    Current.account = account

    notifications = Notification.where(notifiable: event)
    expect(notifications.count).to eq(1)
    expect(notifications.first.to).to eq("owner@acme.example")
    expect(notifications.first.status).to eq("sent")
    expect(event.reload.last_report_sent_at).to be_present
  end

  it "skips a daily event whose last report was sent less than a day ago" do
    event = create_event(scheduled_report_frequency: :daily, last_report_sent_at: 2.hours.ago)

    perform_enqueued_jobs(only: NotificationDeliveryJob) { described_class.perform_now }
    Current.account = account

    expect(Notification.count).to eq(0)
    expect(event.reload.last_report_sent_at).to be_within(1.second).of(2.hours.ago)
  end

  it "sends a daily event whose last report was sent more than a day ago" do
    event = create_event(scheduled_report_frequency: :daily, last_report_sent_at: 25.hours.ago)
    create(:account_membership, user: create(:user), account: account, role: :owner)

    perform_enqueued_jobs(only: NotificationDeliveryJob) { described_class.perform_now }
    Current.account = account

    expect(Notification.count).to eq(1)
    expect(event.reload.last_report_sent_at).to be_within(5.seconds).of(Time.current)
  end

  it "skips a weekly event whose last report was sent less than 7 days ago" do
    event = create_event(scheduled_report_frequency: :weekly, last_report_sent_at: 3.days.ago)

    perform_enqueued_jobs(only: NotificationDeliveryJob) { described_class.perform_now }
    Current.account = account

    expect(Notification.count).to eq(0)
    expect(event.reload.last_report_sent_at).to be_within(1.second).of(3.days.ago)
  end

  it "sends a weekly event whose last report was sent more than 7 days ago" do
    event = create_event(scheduled_report_frequency: :weekly, last_report_sent_at: 8.days.ago)
    create(:account_membership, user: create(:user), account: account, role: :owner)

    perform_enqueued_jobs(only: NotificationDeliveryJob) { described_class.perform_now }
    Current.account = account

    expect(Notification.count).to eq(1)
  end

  it "skips an unpublished event even with a frequency set" do
    event = create(:event, account: account, scheduled_report_frequency: :daily, published_at: nil)
    create(:account_membership, user: create(:user), account: account, role: :owner)

    perform_enqueued_jobs(only: NotificationDeliveryJob) { described_class.perform_now }
    Current.account = account

    expect(Notification.count).to eq(0)
    expect(event.reload.last_report_sent_at).to be_nil
  end

  it "one event blowing up doesn't block another event's report" do
    broken = create_event(scheduled_report_frequency: :daily, name: "Broken Event")
    healthy = create_event(scheduled_report_frequency: :daily, name: "Healthy Event")
    create(:account_membership, user: create(:user), account: account, role: :owner)
    # AR's own `==` compares by class+id, so this matches the *row* even though the job's own
    # find_each loads a fresh Ruby object, not this exact instance.
    allow(Notifier).to receive(:email).and_wrap_original do |original, **kwargs|
      raise StandardError, "boom" if kwargs[:notifiable] == broken

      original.call(**kwargs)
    end

    perform_enqueued_jobs(only: NotificationDeliveryJob) { described_class.perform_now }
    Current.account = account

    expect(broken.reload.last_report_sent_at).to be_nil
    expect(healthy.reload.last_report_sent_at).to be_present
  end

  describe "report content" do
    it "includes registration/check-in stats and the most-attended session" do
      event = create_event(scheduled_report_frequency: :daily)
      owner = create(:user, email: "owner@acme.example")
      create(:account_membership, user: owner, account: account, role: :owner)
      session = create(:session, account: account, event: event, name: "Keynote Hall")
      participant = create(:participant, account: account, event: event)
      # Event-level check-in (session_id: nil) — Event#checked_in_participant_count's own scope,
      # deliberately distinct from a session check-in (see Session's own model comment); need both
      # for a 100% check-in *rate* and a non-zero session-popularity count in the same test.
      ScanService.call(event: event, identifier: participant.hex_id, scan_type: "check_in")
      ScanService.call(event: event, identifier: participant.hex_id, scan_type: "check_in", session: session)

      perform_enqueued_jobs(only: NotificationDeliveryJob) { described_class.perform_now }
      Current.account = account

      mail = ActionMailer::Base.deliveries.last
      expect(mail.html_part.body.to_s).to include("Keynote Hall")
      expect(mail.html_part.body.to_s).to include("100.0") # check-in rate: 1 of 1 registered
    end
  end
end
