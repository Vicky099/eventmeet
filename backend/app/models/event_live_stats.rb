# Phase 7 — Participant Lifecycle (requirement.md §8): per-event denormalized live counters.
# registered_count is kept correct starting this phase (Participant#increment_live_stats!);
# checked_in_count/checked_out_count/occupancy_count exist as columns already (so Phase 9 doesn't
# need another migration) but stay 0 until ScanEvent exists to write them.
#
# Phase 9 (requirement.md §5.15): "the single source of truth for both the initial dashboard load
# and its Action Cable broadcast payload" — ScanService/EventCompletionService call
# #record_check_in!/#record_check_out! immediately after writing the triggering ScanEvent/
# Attendance row, in the same DB transaction, then LiveDashboard broadcasts this row's fresh state.
class EventLiveStats < ApplicationRecord
  include TenantScoped

  belongs_to :event

  # Atomic single-statement SQL increments (`update_counters`, not `increment!`) — the Phase 9
  # Definition of Done requires this row to match a raw COUNT() after a burst of concurrent scans,
  # which a read-modify-write increment (load the row, add 1 in Ruby, write it back) can silently
  # lose under real concurrency.
  def record_check_in!
    self.class.update_counters(id, checked_in_count: 1, occupancy_count: 1)
    reload
  end

  def record_check_out!
    self.class.update_counters(id, checked_out_count: 1, occupancy_count: -1)
    reload
  end
end
