# Phase 11 (requirement.md §3.8): "Schedule items (talks) linked to a speaker, with start/end
# time and details." Event-scoped; `session` optional — a talk can be a room-less plenary/keynote
# item, or sit inside one of the event's breakout Sessions ("optionally a Session (track/room)"
# per the checklist).
class Schedule < ApplicationRecord
  include TenantScoped

  belongs_to :event
  belongs_to :speaker
  belongs_to :session, optional: true

  validates :title, presence: true
  validates :starts_at, :ends_at, presence: true
  validate :ends_at_after_starts_at

  # requirement.md Phase 11 checklist: "schedule overlap warnings (same speaker double-booked,
  # informational not blocking)" — a class-method lookup (mirrors Participant.duplicate_match's
  # cascade-lookup shape) rather than a validation, precisely because it must never block a save.
  # Scoped to the speaker's own schedules — since Speaker is event-scoped (one roster per event,
  # not shared across events), `speaker.schedules` is inherently already within this one event;
  # no separate cross-event case to worry about.
  def self.overlapping(speaker:, starts_at:, ends_at:, exclude_id: nil)
    scope = speaker.schedules.where("starts_at < ? AND ends_at > ?", ends_at, starts_at)
    scope = scope.where.not(id: exclude_id) if exclude_id
    scope
  end

  # Admin::SchedulesController calls this *after* a successful save to set a flash warning
  # alongside the normal success notice — never wired into `validate`, since a double-booking is
  # informational, not something that should stop the talk from being scheduled.
  def speaker_double_booked?
    Schedule.overlapping(speaker: speaker, starts_at: starts_at, ends_at: ends_at, exclude_id: id).exists?
  end

  private

  def ends_at_after_starts_at
    return if starts_at.blank? || ends_at.blank?

    errors.add(:ends_at, "must be after the start time") if ends_at <= starts_at
  end
end
