module SuperAdmin
  # Phase 0 smoke-test controller proving the Platform Console's apex-domain routing + layout
  # render correctly end to end — no longer at platform_staff_root_path
  # (SuperAdmin::DashboardController takes that since Phase 3) but kept live at /platform/__smoke
  # as real, reusable test infrastructure (Phase 0 DoD), not a one-off: spec/requests/
  # hosting_spec.rb still exercises it directly.
  class SmokeController < BaseController
    def show
    end
  end
end
