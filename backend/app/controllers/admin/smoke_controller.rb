module Admin
  # Temporary Phase 0 smoke-test controller proving the tenant Admin Console's host resolution +
  # layout render correctly end to end. Superseded by the real Admin Console dashboard in Phase 3.
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
