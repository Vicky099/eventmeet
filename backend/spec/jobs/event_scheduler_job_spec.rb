require "rails_helper"

RSpec.describe EventSchedulerJob, type: :job do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:account) { create(:account) }

  around do |example|
    travel_to(Time.zone.local(2026, 1, 1, 0, 0, 0)) { example.run }
  end

  # :published — this job (Event#publish!'s counterpart) only manages events that have already
  # been published at least once; an event still sitting in draft is invisible to it regardless
  # of schedule (see the "leaves an unpublished draft event untouched" spec below).
  def create_event(starts_at:, ends_at:)
    Current.account = account
    create(:event, :published, account: account, starts_at: starts_at, ends_at: ends_at)
  end

  it "transitions a draft event to up_coming once its start time hasn't arrived yet" do
    event = create_event(starts_at: 1.day.from_now, ends_at: 2.days.from_now)

    EventSchedulerJob.perform_now

    expect(Event.unscoped_across_tenants { event.reload }.status).to eq("up_coming")
  end

  it "transitions to live once now is between starts_at and ends_at" do
    event = create_event(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)

    EventSchedulerJob.perform_now

    expect(Event.unscoped_across_tenants { event.reload }.status).to eq("live")
  end

  it "transitions to completed once now is past ends_at" do
    event = create_event(starts_at: 2.days.ago, ends_at: 1.day.ago)

    EventSchedulerJob.perform_now

    expect(Event.unscoped_across_tenants { event.reload }.status).to eq("completed")
  end

  # Revisited (confirmed with the user): the draft Invoice is now raised synchronously the moment
  # an event lands on `completed` — not the next day (see InvoiceGenerationJob's own comment for
  # the superseded original requirement). No `.day.ago` wait involved anymore.
  describe "invoice generation on completion (requirement.md §4.6)" do
    it "raises a draft invoice the instant an event completes, straight from its account's own Agency price" do
      event = create_event(starts_at: 2.days.ago, ends_at: 1.hour.ago)

      EventSchedulerJob.perform_now

      Current.account = account
      invoice = event.reload.invoice
      expect(invoice).to be_present
      expect(invoice).to be_draft
      expect(invoice.amount).to eq(event.account.agency.price_per_event)
    end

    it "still raises the invoice for an event that skips live entirely" do
      event = create_event(starts_at: 3.days.ago, ends_at: 2.days.ago)

      EventSchedulerJob.perform_now

      Current.account = account
      expect(event.reload.invoice).to be_present
    end

    it "doesn't raise a second invoice for an event that already has one" do
      event = create_event(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      Current.account = account
      existing_invoice = create(:invoice, event: event, account: account)

      travel 2.hours
      EventSchedulerJob.perform_now

      Current.account = account
      expect(Event.unscoped_across_tenants { event.reload }.status).to eq("completed")
      expect(event.reload.invoice).to eq(existing_invoice)
    end

    # Fixed-hierarchy pivot (requirement.md revisit): unlimited/already-paid-for-up-front — never
    # gets a per-event Invoice at all.
    it "doesn't raise an invoice for an event whose agency is on an annual contract" do
      annual_agency = create(:agency, :annual)
      annual_account = create(:account, agency: annual_agency)
      Current.account = annual_account
      event = create(:event, :published, account: annual_account, starts_at: 2.days.ago, ends_at: 1.hour.ago)

      EventSchedulerJob.perform_now

      Current.account = annual_account
      expect(event.reload.invoice).to be_nil
    end
  end

  it "walks a single event through the full lifecycle as time advances" do
    event = create_event(starts_at: 1.day.from_now, ends_at: 2.days.from_now)

    EventSchedulerJob.perform_now
    expect(Event.unscoped_across_tenants { event.reload }.status).to eq("up_coming")

    # travel (relative), not a second travel_to — the outer `around` hook already has one active,
    # and nesting travel_to calls raises (Rails' own guard against confusing time-stubbing).
    travel 1.5.days
    EventSchedulerJob.perform_now
    expect(Event.unscoped_across_tenants { event.reload }.status).to eq("live")

    travel 1.5.days
    EventSchedulerJob.perform_now
    expect(Event.unscoped_across_tenants { event.reload }.status).to eq("completed")
  end

  it "never moves a completed event back to an earlier status" do
    event = create_event(starts_at: 2.days.ago, ends_at: 1.day.ago)
    Event.unscoped_across_tenants { event.update!(status: :completed) }

    EventSchedulerJob.perform_now

    expect(Event.unscoped_across_tenants { event.reload }.status).to eq("completed")
  end

  it "leaves an already-correct status untouched (no-op, not just idempotent)" do
    event = create_event(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    Event.unscoped_across_tenants { event.update!(status: :live) }
    original_updated_at = event.reload.updated_at

    EventSchedulerJob.perform_now

    expect(Event.unscoped_across_tenants { event.reload }.updated_at).to eq(original_updated_at)
  end

  it "processes events across every tenant, not just one" do
    other_account = create(:account)
    Current.account = account
    event_a = create(:event, :published, account: account, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    Current.account = other_account
    event_b = create(:event, :published, account: other_account, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)

    EventSchedulerJob.perform_now

    expect(Event.unscoped_across_tenants { event_a.reload }.status).to eq("live")
    expect(Event.unscoped_across_tenants { event_b.reload }.status).to eq("live")
  end

  it "leaves an unpublished draft event untouched regardless of its schedule" do
    Current.account = account
    event = create(:event, account: account, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)

    EventSchedulerJob.perform_now

    expect(Event.unscoped_across_tenants { event.reload }.status).to eq("draft")
  end

  # No more self-reschedule to test — sidekiq-cron (config/schedule.yml) is what re-triggers this
  # job now; a single tick just shouldn't blow up (and take the whole Sidekiq queue's error
  # handling with it) if one event's own transition raises.
  it "doesn't let a single event's transition failure propagate out of the tick" do
    event = create_event(starts_at: 1.day.from_now, ends_at: 2.days.from_now)
    allow_any_instance_of(Event).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(event))

    expect { EventSchedulerJob.perform_now }.not_to raise_error
  end

  # Phase 9 checklist: "EventScheduler job extended: auto-checkout/mark-absent attendees when an
  # event's live -> completed transition fires."
  describe "live -> completed attendance finalization (requirement.md §3.7)", :aggregate_failures do
    it "auto-checks-out a participant still checked in and marks a never-scanned one absent" do
      event = create_event(starts_at: 2.hours.ago, ends_at: 1.hour.from_now)
      Event.unscoped_across_tenants { event.update!(status: :live) }
      Current.account = account
      checked_in_participant = create(:participant, account: account, event: event)
      absent_participant = create(:participant, account: account, event: event)
      ScanService.call(event: event, identifier: checked_in_participant.hex_id, scan_type: :check_in)

      travel 2.hours
      EventSchedulerJob.perform_now

      Current.account = account
      expect(Event.unscoped_across_tenants { event.reload }.status).to eq("completed")
      expect(checked_in_participant.attendances.order(:occurred_at).pluck(:status)).to eq(%w[check_in manual_check_out])
      expect(absent_participant.attendances.pluck(:status)).to eq(%w[absent])
      expect(event.live_stats!.checked_out_count).to eq(1)
      expect(event.live_stats!.occupancy_count).to eq(0)
    end

    it "doesn't finalize attendance for an event that skips live entirely (draft published straight past its end)" do
      event = create_event(starts_at: 3.days.ago, ends_at: 2.days.ago)
      Current.account = account
      participant = create(:participant, account: account, event: event)

      EventSchedulerJob.perform_now

      Current.account = account
      expect(Event.unscoped_across_tenants { event.reload }.status).to eq("completed")
      expect(participant.attendances).to be_none
    end
  end
end
