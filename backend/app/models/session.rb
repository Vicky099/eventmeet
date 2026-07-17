# Phase 11 (requirement.md §3.8, §5.6): "Sessions (breakout rooms/tracks) with independent seat
# capacity and their own check-in." Event-scoped, capacity shape mirrors TicketCategory's
# total_count/unlimited? convention (app/models/ticket_category.rb) — seat_limit nil means
# unlimited, no cap enforced.
#
# A Session is a checkable-into *space* (a room during a time block), independent of which
# Schedule (talk) is happening in it — ScanService checks a participant into a Session, never
# into a Schedule item directly (requirement.md §3.7's from: event/session enum has no third
# "schedule" value). Session check-in is capacity-gated (#seat_limit), not enrollment-gated: any
# of the event's participants can be scanned into any of its sessions, exactly like event-level
# check-in — there's no per-participant session registration concept anywhere in this app.
class Session < ApplicationRecord
  include TenantScoped

  belongs_to :event
  # nullify, not destroy/restrict — a talk losing its room assignment is a normal edit (see
  # Schedule#session_id, "optionally a Session"), not something that should block removing the
  # session or cascade-delete real agenda content.
  has_many :schedules, dependent: :nullify
  has_one :session_live_stats, dependent: :destroy
  # restrict_with_error, not destroy — real check-in history, same protection
  # Participant#scan_events/#attendances already gives event-level scans.
  has_many :scan_events, dependent: :restrict_with_error
  has_many :attendances, dependent: :restrict_with_error

  validates :name, presence: true
  validates :starts_at, :ends_at, presence: true
  validates :seat_limit, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :ends_at_after_starts_at

  def unlimited?
    seat_limit.nil?
  end

  # Same lazy-seed-on-first-use pattern as Event#live_stats! — most of a session's life happens
  # before its first check-in scan, no reason every Session needs a stats row from creation.
  def live_stats!
    session_live_stats || create_session_live_stats!(account: account, event: event)
  end

  private

  def ends_at_after_starts_at
    return if starts_at.blank? || ends_at.blank?

    errors.add(:ends_at, "must be after the start time") if ends_at <= starts_at
  end
end
