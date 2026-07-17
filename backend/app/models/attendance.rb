# Phase 9 (requirement.md §3.7): "Attendance direction (from: event vs. session) and status
# (check_in/check_out/manual_check_out/absent) tracked historically, not just as current state" —
# one row per attendance-relevant ScanEvent (check_in/check_out), plus manual_check_out/absent
# rows EventCompletionService writes when an event completes with participants still checked in
# or never scanned at all. Monthly range-partitioned on `occurred_at`
# (db/migrate/*_create_attendances.rb, lib/monthly_range_partitioning.rb) — same composite-primary-
# key reasoning as ScanEvent.
class Attendance < ApplicationRecord
  include TenantScoped

  # See ScanEvent's own comment on the identical line — Postgres' real primary key is the
  # composite (id, occurred_at) pair (required for a partitioned table), but Rails auto-detecting
  # that breaks ApplicationRecord's plain-UUID `id` assignment, so this is forced back to the
  # single-column form at the ActiveRecord metadata level only.
  self.primary_key = "id"

  belongs_to :event
  belongs_to :participant
  # Phase 11 backfill: nil for an event-level row, present for a session-level one — needed
  # alongside `from` (not redundant with it) because #compute_time_spent's pairing query must be
  # able to tell *which* session a session-level check-in/out belongs to, not just that it's
  # session-level at all (two different sessions' check-ins would otherwise collide).
  belongs_to :session, optional: true

  enum :from, { event: 0, session: 1 }
  enum :status, { check_in: 0, check_out: 1, manual_check_out: 2, absent: 3 }

  before_validation :default_occurred_at, on: :create
  before_create :compute_time_spent, if: -> { check_out? || manual_check_out? }

  validates :occurred_at, presence: true

  private

  def default_occurred_at
    self.occurred_at ||= Time.current
  end

  # requirement.md §3.7: "time-spent-in-event/time-spent-in-session computation from paired
  # check-in/check-out events." Pairs against this participant's most recent check_in Attendance
  # for the same event/from/session — correct under the alternating check-in-then-check-out flow
  # this phase's check-in stations produce (§3.7's own "toggle" framing); doesn't attempt to
  # reconcile a double-check-in edge case (two check-ins with no check-out between them) beyond
  # pairing against whichever check-in happened most recently. `session_id: session_id` (not just
  # `from: from`) is what keeps two different sessions' check-ins from pairing against each
  # other's rows — for an event-level row both sides are nil, matching as before.
  def compute_time_spent
    last_check_in = participant.attendances
      .where(event: event, from: from, session_id: session_id, status: :check_in)
      .order(occurred_at: :desc).first
    return unless last_check_in

    self.time_spent_seconds = (occurred_at - last_check_in.occurred_at).to_i
  end
end
