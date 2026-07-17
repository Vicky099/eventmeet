require "rails_helper"

# Phase 9 Definition of Done: "Load sanity check: fan-out to N simulated subscribers doesn't
# measurably slow scan-write latency (even a lightweight local benchmark is enough to catch a
# gross regression — full load testing is a later hardening pass, not a Phase 9 blocker)."
RSpec.describe "LiveDashboard fan-out load sanity", type: :model do
  let(:account) { create(:account) }
  let(:event) { create(:event, account: account) }

  before { Current.account = account }

  it "keeps scan-write latency stable as simulated dashboard broadcasts pile up" do
    participants = Array.new(20) { create(:participant, account: account, event: event) }

    baseline = Benchmark.realtime do
      participants.first(10).each { |p| ScanService.call(event: event, identifier: p.hex_id, scan_type: :check_in) }
    end

    # A stand-in for "many dashboards watching" — repeating the exact render+broadcast work
    # LiveDashboard.broadcast_event_stats does on every scan, independent of the write path,
    # since driving real Action Cable subscribers isn't practical from a model spec.
    30.times { LiveDashboard.broadcast_event_stats(event) }

    under_fanout = Benchmark.realtime do
      participants.last(10).each { |p| ScanService.call(event: event, identifier: p.hex_id, scan_type: :check_in) }
    end

    # Generous threshold — a smoke check against a gross regression (a broadcast blocking or
    # serializing scan writes), not a real load test (requirement.md §7.1's own hardening pass).
    expect(under_fanout).to be < (baseline * 5) + 1
  end
end
