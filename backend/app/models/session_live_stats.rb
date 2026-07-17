# Phase 11 (requirement.md §5.15, §8): per-session denormalized live counters, mirroring
# EventLiveStats exactly (app/models/event_live_stats.rb) — same atomic `update_counters`
# reasoning (avoid a read-modify-write race under concurrent scans), same
# "single source of truth for both initial dashboard load and live broadcast payload" role, this
# time scoped to a Session instead of an Event. No registered_count — see Session's own comment
# on why there's no per-session registration event to seed one from.
class SessionLiveStats < ApplicationRecord
  include TenantScoped

  belongs_to :event
  belongs_to :session

  def record_check_in!
    self.class.update_counters(id, checked_in_count: 1, occupancy_count: 1)
    reload
  end

  def record_check_out!
    self.class.update_counters(id, checked_out_count: 1, occupancy_count: -1)
    reload
  end
end
