module Admin
  # Phase 0 smoke-test controller proving the tenant Admin Console's host resolution + layout
  # render correctly end to end — no longer at user_root_path (Admin::DashboardController takes
  # that since Phase 3) but kept live at /admin/__smoke as real, reusable test infrastructure
  # (Phase 0 DoD), not a one-off: spec/requests/hosting_spec.rb still exercises it directly.
  class SmokeController < BaseController
    def show
      # Surfaces the Postgres RLS session GUC (see lib/tenant_row_level_security.rb) so the
      # request spec can prove it was actually set to the resolved tenant *during* the request,
      # not just that it gets cleared afterward.
      @current_account_id_guc = ActiveRecord::Base.connection.select_value(
        "SELECT current_setting('app.current_account_id', true)"
      )
    end
  end
end
