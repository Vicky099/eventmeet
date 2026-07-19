# Phase 9 (requirement.md §5.15): the single place that pushes a Turbo Streams broadcast — every
# write path (Participant#broadcast_live_stats!, ScanService, EventCompletionService) calls in
# here rather than broadcasting for itself, so there's exactly one rendering of each live partial
# to keep in sync with EventLiveStats' own atomic counters.
#
# Built on turbo-rails' own Turbo::StreamsChannel (Turbo::Broadcastable's underlying channel)
# rather than a hand-rolled ApplicationCable::Channel — it's already backed by the Redis adapter
# configured in config/cable.yml, and the view side just needs `turbo_stream_from` (see
# app/views/admin/scan_events/index.html.erb, app/views/super_admin/dashboard/index.html.erb) with
# no custom JS. requirement.md's literal "event:{event_id}:live channel" wording maps onto
# `turbo_stream_from event` — a distinct, signed stream name per Event, functionally the same
# channel-per-event shape over the same Redis pub/sub transport.
class LiveDashboard
  # A plain string streamable (not tied to any one Account/Event) for the Super Admin's
  # cross-tenant view — requirement.md §5.15: "aggregate registrations/check-ins across all
  # currently-live events platform-wide."
  PLATFORM_STREAM = "platform_live_pulse".freeze

  def self.broadcast_event_stats(event)
    Turbo::StreamsChannel.broadcast_replace_to(
      event,
      target: "live-stats-#{event.id}",
      partial: "admin/scan_events/live_stats",
      locals: { event: event }
    )

    # requirement.md revisit: "admin should understand how many participant came event in
    # realtime" — the Check-in Arrivals card (admin/scan_events/_arrivals_chart.html.erb,
    # rendered on both admin/scan_events/index.html.erb and admin/events/show.html.erb, both
    # subscribed to this same `event` stream) updates on every scan the same way the KPI tiles
    # above already do.
    Turbo::StreamsChannel.broadcast_replace_to(
      event,
      target: "arrivals-chart-#{event.id}",
      partial: "admin/scan_events/arrivals_chart",
      locals: { event: event }
    )

    if event.live?
      broadcast_platform_pulse
      broadcast_agency_pulse(event.account.agency)
    end
  end

  # Phase 11 backfill (requirement.md §5.15: "the same mechanism extends to per-session
  # occupancy"). Mirrors #broadcast_event_stats exactly, one level down — deliberately does NOT
  # also call #broadcast_event_stats/#broadcast_platform_pulse, since a session check-in never
  # touches EventLiveStats (see ScanService#apply_counters!'s own comment on why the two counters
  # stay independent).
  def self.broadcast_session_stats(session)
    Turbo::StreamsChannel.broadcast_replace_to(
      session,
      target: "live-stats-session-#{session.id}",
      partial: "admin/scan_events/session_live_stats",
      locals: { session: session, stats: session.live_stats! }
    )
  end

  def self.broadcast_platform_pulse
    Turbo::StreamsChannel.broadcast_replace_to(
      PLATFORM_STREAM,
      target: "platform-live-pulse",
      partial: "super_admin/dashboard/live_pulse",
      locals: { pulse: platform_pulse }
    )
  end

  # requirement.md revisit: "design the agency analytics dashboard" — the Agency Console's own
  # cross-tenant-but-single-agency mirror of #broadcast_platform_pulse/#platform_pulse above, one
  # tier down: every currently-live event across just this agency's own tenants, not the whole
  # platform. Guarded on `agency` being present — a legacy standalone Account (requirement.md
  # revisit's own "left alone, not migrated" carve-out) has none, and a live event on one of those
  # has nothing to broadcast to here.
  def self.broadcast_agency_pulse(agency)
    return unless agency

    Turbo::StreamsChannel.broadcast_replace_to(
      agency_stream(agency),
      target: "agency-live-pulse",
      partial: "agency_console/dashboard/live_pulse",
      locals: { pulse: agency_pulse(agency) }
    )
  end

  def self.agency_pulse(agency)
    EventLiveStats.unscoped_across_tenants do
      live_stats = EventLiveStats.joins(:event).merge(Event.live.where(account_id: agency.accounts.select(:id)))
      {
        live_event_count: live_stats.count,
        registered_count: live_stats.sum(:registered_count),
        checked_in_count: live_stats.sum(:checked_in_count),
        occupancy_count: live_stats.sum(:occupancy_count)
      }
    end
  end

  # A plain string streamable, same shape as PLATFORM_STREAM above, just parameterized per
  # agency — AgencyConsole::DashboardController's own view signs this same literal name via
  # turbo_stream_from.
  def self.agency_stream(agency)
    "agency_live_pulse_#{agency.id}"
  end

  # requirement.md §5.15: aggregate across every currently-live event, every tenant — read by
  # SuperAdmin::DashboardController for the first paint, and by #broadcast_platform_pulse above for
  # every subsequent update. unscoped_across_tenants is the deliberate cross-tenant escape hatch
  # (see TenantScoped) — this is exactly the "explicit, narrow" case it exists for.
  def self.platform_pulse
    EventLiveStats.unscoped_across_tenants do
      live_stats = EventLiveStats.joins(:event).merge(Event.live)
      {
        live_event_count: live_stats.count,
        registered_count: live_stats.sum(:registered_count),
        checked_in_count: live_stats.sum(:checked_in_count),
        occupancy_count: live_stats.sum(:occupancy_count)
      }
    end
  end
end
