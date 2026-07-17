# Phase 9 (requirement.md §3.7, §5.6, §6 item 13), extended in Phase 11 with session-level
# check-in now that Session exists (requirement.md §3.8). The check-in kiosk's one write path —
# owns the debounce, the ScanEvent + paired Attendance write, the atomic EventLiveStats/
# SessionLiveStats counter update, and kicking off the live broadcast, all from one call so
# Admin::ScanEventsController stays a thin controller (same "service object owns the side
# effects" split TicketReservationService already established for reservations).
class ScanService
  Result = Struct.new(:status, :participant, :scan_event, :attendance, :session, :redirect_url, keyword_init: true) do
    def ok? = status == :ok
    def not_found? = status == :not_found
    def debounced? = status == :debounced
    def session_full? = status == :session_full
  end

  # requirement.md §3.7: "Toggle check-in/check-out with a 30-second anti-double-scan debounce."
  DEBOUNCE_WINDOW = 30.seconds

  def self.call(...) = new.call(...)

  def call(event:, identifier:, scan_type:, source: :manual, session: nil)
    scan_type = scan_type.to_s
    participant = Participant.find_by_identifier(event, identifier)
    return Result.new(status: :not_found) unless participant

    if debounced?(participant, scan_type, session)
      return Result.new(status: :debounced, participant: participant, session: session)
    end

    # requirement.md §3.7: "per-session seat-limit enforcement" — checked before creating
    # anything, same "reject, don't create a row and then undo it" shape debounce already uses.
    # Event-level check-in has no equivalent gate: Event#has_seat_limit?/#seat_limit caps
    # *registration* (Phase 6), not check-in — an already-registered participant can always check
    # into the event itself, only a specific session's room capacity is enforced here.
    if session && scan_type == "check_in" && session_full?(session)
      return Result.new(status: :session_full, participant: participant, session: session)
    end

    scan_event = attendance = nil
    ActiveRecord::Base.transaction do
      scan_event = ScanEvent.create!(
        account: event.account, event: event, participant: participant, session: session,
        scan_type: scan_type, source: source, scanned_at: Time.current
      )
      attendance = record_attendance!(event, participant, scan_event, session) if scan_type.in?(%w[check_in check_out])
      apply_counters!(event, session, scan_type)
    end

    LiveMetricBucket.increment!(event: event, metric: :check_in) if scan_type == "check_in"
    if session
      LiveDashboard.broadcast_session_stats(session)
    else
      LiveDashboard.broadcast_event_stats(event)
    end

    Result.new(
      status: :ok, participant: participant, scan_event: scan_event, attendance: attendance, session: session,
      redirect_url: virtual_redirect_url(event, scan_type)
    )
  end

  private

  def debounced?(participant, scan_type, session)
    ScanEvent.where(participant: participant, scan_type: scan_type, session_id: session&.id)
      .where(scanned_at: DEBOUNCE_WINDOW.ago..)
      .exists?
  end

  def session_full?(session)
    !session.unlimited? && session.live_stats!.occupancy_count >= session.seat_limit
  end

  def record_attendance!(event, participant, scan_event, session)
    Attendance.create!(
      account: event.account, event: event, participant: participant, scan_event_id: scan_event.id,
      session: session, from: session ? :session : :event, status: scan_event.scan_type, occurred_at: scan_event.scanned_at
    )
  end

  # requirement.md §5.15: "incremented in the same transaction as the triggering ... ScanEvent
  # write — the two paths must never disagree." apply_counters! runs inside the same transaction
  # as the ScanEvent/Attendance creates above.
  #
  # Deliberately independent branches, not a fallthrough — a session check-in does NOT also
  # increment EventLiveStats. §8 describes EventLiveStats/SessionLiveStats as parallel per-event/
  # per-session counters, not a roll-up of one into the other: an attendee checks into the event
  # once at the door, then separately into whichever sessions they attend through the day.
  def apply_counters!(event, session, scan_type)
    stats = session ? session.live_stats! : event.live_stats!
    case scan_type
    when "check_in" then stats.record_check_in!
    when "check_out" then stats.record_check_out!
    end
  end

  # requirement.md §3.7: "Virtual event redirect-on-check-in (scan badge -> auto-mark attendance
  # -> redirect to meeting link)." Hybrid events have a meeting_link too (Event#location_present_
  # for_mode requires it), so they redirect on check-in the same way a pure virtual event does.
  def virtual_redirect_url(event, scan_type)
    return unless scan_type == "check_in"
    return unless event.virtual? || event.hybrid?

    event.meeting_link
  end
end
