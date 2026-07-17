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

  # perform_now doesn't run the self-rescheduled follow-up job (that's just enqueued, not
  # executed) — exactly what a single-tick assertion wants, no perform_enqueued_jobs needed.
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

  it "self-reschedules another run after completing" do
    create_event(starts_at: 1.day.from_now, ends_at: 2.days.from_now)

    expect { EventSchedulerJob.perform_now }
      .to have_enqueued_job(EventSchedulerJob).at(EventSchedulerJob::RESCHEDULE_INTERVAL.from_now)
  end

  it "still self-reschedules even if a single event's transition raises" do
    event = create_event(starts_at: 1.day.from_now, ends_at: 2.days.from_now)
    allow_any_instance_of(Event).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(event))

    expect { EventSchedulerJob.perform_now }.to have_enqueued_job(EventSchedulerJob)
  end

  # Phase 9 checklist: "EventScheduler job extended: auto-checkout/mark-absent attendees when an
  # event's live -> completed transition fires."
  describe "live -> completed attendance finalization (requirement.md §3.7)", :aggregate_failures do
    # The outer `around` block above freezes time to 2026-01-01 — outside the June-September 2026
    # window the initial migration provisioned partitions for (lib/monthly_range_partitioning.rb
    # creates partitions relative to whenever the migration actually ran, not relative to a test's
    # frozen clock). PartitionMaintenanceJob is what keeps this window moving in a real deployment;
    # here, just provision the one frozen month directly so ScanEvent/Attendance writes land
    # somewhere.
    before do
      MonthlyRangePartitioning.ensure_partitions!(ActiveRecord::Base.connection, :scan_events, partition_column: :scanned_at, months_behind: 0, months_ahead: 0)
      MonthlyRangePartitioning.ensure_partitions!(ActiveRecord::Base.connection, :attendances, partition_column: :occurred_at, months_behind: 0, months_ahead: 0)
    end

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
