# Phase 9 revisit (requirement.md §3.7, §5.6): the check-in kiosk, deliberately standalone from
# the Admin Console — "the actual event level check-in page should be out of admin panel and
# admin layout." Not Admin::-namespaced and does not inherit Admin::BaseController (which hardcodes
# `layout "admin"` and the full sidebar/topbar console shell); instead pulls in exactly the same
# tenant-resolution/authentication/authorization wiring that base class assembles, so this is
# still a fully authenticated, tenant-scoped, Pundit-checked controller — just with its own
# `layout "checkin"` (a lightweight header/footer chrome built for a phone or tablet at a check-in
# desk, not the admin console's sidebar). Reuses ScanEventPolicy/ScanService/EventScoped as-is —
# this is the same check-in capability Admin::ScanEventsController used to also expose the scan
# form for, just relocated to its own screen; the dashboard at admin_event_scan_events_path now
# only reads (live stats, breakdowns, recent scans) and links out here to actually scan.
class CheckinController < ApplicationController
  include TenantResolvable

  before_action :authenticate_user!

  include PunditAuthorizable
  include EventScoped

  layout "checkin"

  def show
    authorize @event, :index?, policy_class: ScanEventPolicy
    @sessions = @event.sessions.order(:starts_at)
  end

  # Mirrors Admin::ScanEventsController#create exactly (same ScanService call, same optional
  # session_id resolution) — the only thing that moved is which screen this response renders back
  # into (checkin/_result, not admin/scan_events/_scan_result).
  def scan
    authorize @event, :create?, policy_class: ScanEventPolicy
    session = @event.sessions.find_by(id: params[:session_id]) if params[:session_id].present?
    @result = ScanService.call(
      event: @event, identifier: params[:identifier], scan_type: params[:scan_type], source: :manual, session: session
    )
    @sessions = @event.sessions.order(:starts_at)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to checkin_event_path(@event) }
    end
  end

  private

  def authorization_fallback_path
    user_root_path
  end
end
