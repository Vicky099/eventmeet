# Phase 9 (requirement.md §3.7, §5.6, §6 item 13). The unified "who scanned what, where, when"
# abstraction — check-in/out, on-demand print, and later lead-retrieval/triggered-content
# (Phase 12+) all write one of these instead of each having their own parallel scan endpoint.
# Monthly range-partitioned on `scanned_at` (db/migrate/*_create_scan_events.rb,
# lib/monthly_range_partitioning.rb) — composite primary key `[:id, :scanned_at]`, so this is
# never looked up via a bare `ScanEvent.find(uuid)` anywhere in the app, only `find_by(id:)`/
# `where(...)`.
class ScanEvent < ApplicationRecord
  include TenantScoped

  # Postgres' actual primary key here is the composite (id, scanned_at) pair (required for a
  # partitioned table — see lib/monthly_range_partitioning.rb), but Rails auto-detecting that and
  # treating this as a *composite_primary_key?* model breaks in a much more specific way than
  # "some finder helpers behave differently": Rails' attribute-methods layer special-cases the
  # literal name "id" to always mean "the primary key," composite or not — so even
  # ApplicationRecord's own `self.id ||= SecureRandom.uuid_v7` (or a `self[:id] ||=` workaround)
  # ends up trying to write a bare UUID into what Rails now expects to be a 2-element tuple.
  # Forcing this back to the plain, single-column form sidesteps that entirely: `id` behaves
  # exactly like it does on every other model in this app (ApplicationRecord's UUID assignment
  # works unmodified), and nothing here relies on Rails' own composite-PK-aware finder behavior —
  # every read goes through `where(...)`/`find_by(...)`, never a bare `ScanEvent.find(uuid)`.
  # Postgres still enforces the real composite uniqueness regardless of what Rails believes its
  # primary_key is; this is purely an ActiveRecord-side metadata override.
  self.primary_key = "id"

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
