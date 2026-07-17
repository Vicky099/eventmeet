require "rails_helper"

RSpec.describe ScanService, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:account) { create(:account) }
  let(:event) { create(:event, account: account, mode: :on_site) }
  let(:participant) { create(:participant, account: account, event: event) }

  before { Current.account = account }

  describe "debounce (requirement.md §3.7: 30-second anti-double-scan)" do
    it "rejects a second identical scan within 30 seconds" do
      ScanService.call(event: event, identifier: participant.hex_id, scan_type: :check_in)

      result = ScanService.call(event: event, identifier: participant.hex_id, scan_type: :check_in)

      expect(result).to be_debounced
      expect(ScanEvent.count).to eq(1)
    end

    it "accepts a repeat scan once the debounce window has passed" do
      ScanService.call(event: event, identifier: participant.hex_id, scan_type: :check_in)

      travel(ScanService::DEBOUNCE_WINDOW + 1.second) do
        result = ScanService.call(event: event, identifier: participant.hex_id, scan_type: :check_in)
        expect(result).to be_ok
      end

      expect(ScanEvent.count).to eq(2)
    end

    it "doesn't debounce a different scan_type for the same participant" do
      ScanService.call(event: event, identifier: participant.hex_id, scan_type: :check_in)

      result = ScanService.call(event: event, identifier: participant.hex_id, scan_type: :check_out)

      expect(result).to be_ok
    end
  end

  it "returns not_found for an unrecognized identifier" do
    result = ScanService.call(event: event, identifier: "does-not-exist", scan_type: :check_in)
    expect(result).to be_not_found
  end

  it "finds a participant by any of hex ID, govt ID, RFID, or client participant ID (requirement.md §3.7)" do
    rfid_participant = create(:participant, account: account, event: event, rf_id: "RF-777")

    result = ScanService.call(event: event, identifier: "RF-777", scan_type: :check_in)

    expect(result.participant).to eq(rfid_participant)
  end

  it "finds a participant by hex ID regardless of scanned case" do
    result = ScanService.call(event: event, identifier: participant.hex_id.downcase, scan_type: :check_in)

    expect(result.participant).to eq(participant)
  end

  it "records a paired Attendance row and atomically updates EventLiveStats" do
    result = ScanService.call(event: event, identifier: participant.hex_id, scan_type: :check_in, source: :kiosk)

    expect(result.attendance).to be_check_in
    stats = event.reload.live_stats!
    expect(stats.checked_in_count).to eq(1)
    expect(stats.occupancy_count).to eq(1)
  end

  it "decrements occupancy (without touching checked_in_count) on check-out" do
    ScanService.call(event: event, identifier: participant.hex_id, scan_type: :check_in)

    ScanService.call(event: event, identifier: participant.hex_id, scan_type: :check_out)

    stats = event.reload.live_stats!
    expect(stats.checked_in_count).to eq(1)
    expect(stats.checked_out_count).to eq(1)
    expect(stats.occupancy_count).to eq(0)
  end

  it "doesn't create an Attendance row or touch counters for a print scan" do
    result = ScanService.call(event: event, identifier: participant.hex_id, scan_type: :print, source: :manual)

    expect(result.attendance).to be_nil
    expect(event.reload.live_stats!.checked_in_count).to eq(0)
  end

  describe "virtual redirect (requirement.md §3.7)" do
    let(:virtual_event) { create(:event, account: account, mode: :virtual, address: nil, meeting_link: "https://meet.example.com/abc") }
    let(:virtual_participant) { create(:participant, account: account, event: virtual_event) }

    it "returns the meeting link on check-in for a virtual event" do
      result = ScanService.call(event: virtual_event, identifier: virtual_participant.hex_id, scan_type: :check_in)

      expect(result.redirect_url).to eq("https://meet.example.com/abc")
    end

    it "doesn't redirect on check-out" do
      ScanService.call(event: virtual_event, identifier: virtual_participant.hex_id, scan_type: :check_in)

      result = ScanService.call(event: virtual_event, identifier: virtual_participant.hex_id, scan_type: :check_out)

      expect(result.redirect_url).to be_nil
    end

    it "doesn't redirect an on-site event" do
      result = ScanService.call(event: event, identifier: participant.hex_id, scan_type: :check_in)
      expect(result.redirect_url).to be_nil
    end
  end

  # Phase 11 backfill (requirement.md §3.7, §3.8): session-level check-in, now that Session
  # exists.
  describe "session-level check-in" do
    let(:session) { create(:session, account: account, event: event) }

    it "creates a session-scoped Attendance and a SessionLiveStats row, without touching EventLiveStats" do
      result = ScanService.call(event: event, identifier: participant.hex_id, scan_type: :check_in, session: session)

      expect(result).to be_ok
      expect(result.attendance).to be_session
      expect(session.reload.live_stats!.checked_in_count).to eq(1)
      expect(event.reload.live_stats!.checked_in_count).to eq(0)
    end

    it "enforces the session's own seat_limit, independent of event-level capacity (requirement.md §3.7)" do
      full_session = create(:session, account: account, event: event, seat_limit: 1)
      other_participant = create(:participant, account: account, event: event)
      ScanService.call(event: event, identifier: participant.hex_id, scan_type: :check_in, session: full_session)

      result = ScanService.call(event: event, identifier: other_participant.hex_id, scan_type: :check_in, session: full_session)

      expect(result).to be_session_full
      expect(ScanEvent.where(session: full_session).count).to eq(1)
    end

    it "never rejects for an unlimited session" do
      unlimited_session = create(:session, account: account, event: event, seat_limit: nil)
      5.times { |n| ScanService.call(event: event, identifier: create(:participant, account: account, event: event).hex_id, scan_type: :check_in, session: unlimited_session) }

      expect(unlimited_session.reload.live_stats!.checked_in_count).to eq(5)
    end

    it "debounces per-session, not globally — checking into two different sessions within 30s both succeed" do
      other_session = create(:session, account: account, event: event)

      result_a = ScanService.call(event: event, identifier: participant.hex_id, scan_type: :check_in, session: session)
      result_b = ScanService.call(event: event, identifier: participant.hex_id, scan_type: :check_in, session: other_session)

      expect(result_a).to be_ok
      expect(result_b).to be_ok
    end

    it "still debounces a repeat scan into the same session" do
      ScanService.call(event: event, identifier: participant.hex_id, scan_type: :check_in, session: session)

      result = ScanService.call(event: event, identifier: participant.hex_id, scan_type: :check_in, session: session)

      expect(result).to be_debounced
    end

    it "computes time_spent_seconds paired against this session's own check-in, not another session's" do
      other_session = create(:session, account: account, event: event)
      ScanService.call(event: event, identifier: participant.hex_id, scan_type: :check_in, session: other_session)

      travel(1.minute) do
        ScanService.call(event: event, identifier: participant.hex_id, scan_type: :check_in, session: session)
      end

      travel(3.minutes) do
        result = ScanService.call(event: event, identifier: participant.hex_id, scan_type: :check_out, session: session)
        expect(result.attendance.time_spent_seconds).to be_within(2).of(2.minutes.to_i)
      end
    end
  end

  # Phase 9 Definition of Done: "EventLiveStats counter matches a raw COUNT() after a burst of
  # concurrent scans (race-condition check — use increment_counter/atomic SQL, not
  # read-modify-write)." Real OS threads, each on its own DB connection — a read-modify-write
  # increment (the bug this guards against) would lose updates under exactly this pattern; the
  # atomic `update_counters` EventLiveStats#record_check_in! uses should not.
  describe "concurrency", :aggregate_failures do
    it "keeps EventLiveStats.checked_in_count consistent under concurrent check-in scans" do
      participants = Array.new(6) { create(:participant, account: account, event: event) }

      threads = participants.map do |p|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            Current.account = account
            ScanService.call(event: event, identifier: p.hex_id, scan_type: :check_in, source: :kiosk)
          end
        end
      end
      threads.each(&:join)

      expect(ScanEvent.check_in.count).to eq(6)
      expect(event.reload.live_stats!.checked_in_count).to eq(6)
      expect(event.live_stats!.occupancy_count).to eq(6)
    end
  end
end
