# Phase 9 (requirement.md §3.7, §5.6, §6 item 13). The unified "who scanned what, where, when"
# abstraction — check-in/out, on-demand print, and later lead-retrieval/triggered-content
# (Phase 12+) all write one of these instead of each having their own parallel scan endpoint.
class ScanEvent < ApplicationRecord
  include TenantScoped

  belongs_to :event
  belongs_to :participant
  # Phase 11 backfill (requirement.md §3.7, §3.8): nil means an event-level scan, present means a
  # session-level one — the same distinction Attendance#from's event/session enum makes.
  belongs_to :session, optional: true

  enum :scan_type, { check_in: 0, check_out: 1, print: 2, lead_retrieval: 3, triggered_content: 4 }
  # :system is ScanService/EventCompletionService's own addition, not in requirement.md §6 item
  # 13's literal source list — EventCompletionService's auto-checkout on an event's live→completed
  # transition isn't a human scan of any kind (kiosk/manual/agent all imply one).
  enum :source, { kiosk: 0, manual: 1, agent: 2, system: 3 }

  before_validation :default_scanned_at, on: :create

  validates :scanned_at, presence: true

  private

  def default_scanned_at
    self.scanned_at ||= Time.current
  end
end
