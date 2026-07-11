module SuperAdmin
  # The Platform Console's authenticated landing page (requirement.md §4.7, §5.14/§5.15, Phase 3)
  # — supersedes the Phase 0 SmokeController at platform_staff_root_path.
  class DashboardController < BaseController
    def index
      # Real data — Account has existed since Phase 0/provisioned since Phase 2, nothing stubbed
      # about this count.
      @tenant_count = Account.count
      # Event/approval_status doesn't exist until Phase 4/5 — nothing to count yet.
      @pending_approval_count = 0
    end
  end
end
