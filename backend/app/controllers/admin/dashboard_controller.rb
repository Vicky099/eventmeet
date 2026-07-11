module Admin
  # The tenant Admin Console's authenticated landing page (requirement.md §5.14, Phase 3) —
  # supersedes the Phase 0 SmokeController at user_root_path.
  class DashboardController < BaseController
    def index
      # Real as of Phase 4 (was hardcoded 0 in Phase 3 — Event didn't exist yet).
      @event_count = Current.account.events.count
      # Participant doesn't exist until Phase 7 — nothing to count yet.
      @participant_count = 0
    end
  end
end
