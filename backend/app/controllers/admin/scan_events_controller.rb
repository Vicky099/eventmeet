module Admin
  # Phase 9 — Check-in, Attendance & Real-Time Live Dashboards (requirement.md §3.7, §5.6, §5.15),
  # revisited: this is now a read-only real-time dashboard only — live stats, session occupancy,
  # ticket-category breakdown, capacity, and the last 10 scans — plus a link out to the standalone
  # kiosk (CheckinController, its own screen/layout entirely) where scanning itself now happens.
  # #create moved there with it; this controller has no write action left at all.
  class ScanEventsController < BaseController
    include EventScoped

    def index
      authorize @event, policy_class: ScanEventPolicy
      @sessions = @event.sessions.order(:starts_at)
      # Top 10 (requirement.md revisit — previously 20; this is now a dashboard glance, not the
      # kiosk's own primary content).
      @recent_scans = @event.scan_events
        .where(scan_type: [ :check_in, :check_out ])
        .order(scanned_at: :desc)
        .limit(10)
        .includes(:participant, :session)
      @category_stats = ticket_category_stats
    end

    private

    # requirement.md revisit: "ticket category wise check-ins ... category wise ticket sold
    # data." Two group-by queries (not one per category — the same N+1-avoidance shape
    # Admin::EventsController#show's own @category_participant_counts already established),
    # mapped onto @event.ticket_categories once. "registered" mirrors that same dashboard's own
    # real Participant count (not TicketCategory#sold_count, which only reflects
    # ticket_reservations and undercounts anything added straight from the admin console — see
    # that controller's own comment).
    #
    # **Bug fix**: "checked_in" originally counted check_in *ScanEvents* per category (mirroring
    # EventLiveStats#checked_in_count's own event-wide "cumulative scans, not unique attendees"
    # semantics — a participant checking in twice counts twice there, by design, for that
    # specific running counter). Reusing that same semantics here produced a real, reported
    # confusion: "9 checked in · 3 registered" for a 3-person category, since a handful of repeat
    # scans on the same few people trivially outnumber the category's own headcount — nonsensical
    # to read at a glance, unlike the top-level KPI tile it was mirrored from (which never sits
    # directly next to its own "registered" ceiling the way this row does). `.distinct` here
    # counts *unique participants* who have at least one check_in scan instead — naturally
    # bounded by `registered`, matching what "N checked in" actually reads as on this specific row.
    def ticket_category_stats
      registered_counts = @event.participants.group(:ticket_category_id).count
      checked_in_counts = @event.participants.joins(:scan_events).merge(ScanEvent.check_in)
        .distinct.group(:ticket_category_id).count

      @event.ticket_categories.order(:created_at).map do |category|
        {
          category: category,
          registered: registered_counts[category.id] || 0,
          checked_in: checked_in_counts[category.id] || 0
        }
      end
    end
  end
end
