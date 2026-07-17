module Admin
  # The tenant Admin Console's authenticated landing page (requirement.md §5.14, Phase 3) —
  # supersedes the Phase 0 SmokeController at user_root_path.
  #
  # requirement.md revisit: "design the best Analytics for main dashboard" — this was still the
  # bare-bones Phase 3 stub (two KPI tiles, an empty-state card) long after Event/Participant/
  # ScanEvent existed. It's now the account's own portfolio overview, one level up from a single
  # event's own Analytics page (admin/events#show, Phase 14): what's live right now, what's
  # coming up, and account-wide trends across every event — never a second copy of one event's own
  # detail. Participant/ScanEvent are both TenantScoped, so `Participant.count` etc. here are
  # already scoped to Current.account with no explicit join needed.
  class DashboardController < BaseController
    def index
      events = Current.account.events

      @event_count = events.count
      @participant_count = Participant.count
      # Same "distinct participant, not a raw scan/counter" rule as Event#checked_in_participant_count
      # (app/models/event.rb) — applied account-wide instead of to one event.
      @checked_in_count = Participant.joins(:scan_events).merge(ScanEvent.check_in.where(session_id: nil)).distinct.count

      @live_events = events.live.order(:starts_at)
      @upcoming_events = events.up_coming.order(:starts_at).limit(5)
      @attention_events = events.where(approval_status: [ :pending, :rejected ]).order(:created_at)
      @status_counts = events.group(:status).count

      # Same "pluck + Ruby-side .to_date grouping" reasoning as Event#daily_registration_counts —
      # this app's configured Time.zone, not the stored value's own UTC zone — just account-wide
      # instead of scoped to one event.
      @registrations_by_day = Participant.where(created_at: 29.days.ago.beginning_of_day..).pluck(:created_at).map(&:to_date).tally
    end
  end
end
