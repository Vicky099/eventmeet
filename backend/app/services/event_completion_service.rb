# Phase 9 checklist: "EventScheduler job extended: auto-checkout/mark-absent attendees when an
# event's live -> completed transition fires." Called once, from EventSchedulerJob, exactly at the
# moment that transition happens for a given event — never on a schedule of its own.
class EventCompletionService
  def self.finalize_attendance!(...) = new.finalize_attendance!(...)

  def finalize_attendance!(event)
    event.participants.find_each do |participant|
      last = participant.attendances.where(event: event, from: :event).order(occurred_at: :desc).first

      if last.nil?
        mark_absent!(event, participant)
      elsif last.check_in?
        auto_check_out!(event, participant)
      end
    end
  end

  private

  # requirement.md §3.7's status list includes `absent` for exactly this case — a participant who
  # registered but never scanned in at all by the time the event ends. No EventLiveStats counter
  # change: an absent participant was never counted as checked in, so there's nothing to reverse.
  def mark_absent!(event, participant)
    Attendance.create!(
      account: event.account, event: event, participant: participant,
      from: :event, status: :absent, occurred_at: event.ends_at || Time.current
    )
  end

  # Attendance#compute_time_spent (before_create) pairs this against the same last check_in row
  # this method's caller already found, deriving the same time-spent-in-event figure a real
  # check-out scan would have.
  def auto_check_out!(event, participant)
    ActiveRecord::Base.transaction do
      Attendance.create!(
        account: event.account, event: event, participant: participant,
        from: :event, status: :manual_check_out, occurred_at: event.ends_at || Time.current
      )
      event.live_stats!.record_check_out!
    end
  end
end
