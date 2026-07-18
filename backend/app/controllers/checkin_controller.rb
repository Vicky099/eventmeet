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
  #
  # Phase 10 revisit — Print Agent (Electron) Integration (requirement.md §5.5.1): scan_type
  # "print" ("Print only," requirement.md: "an option to only print badge and not mark the
  # attendance check-in") bypasses ScanService entirely rather than calling it with scan_type:
  # "print" — ScanService would itself write a `print` ScanEvent for the debounce/log, and
  # PrintTriggerService's *own* debounce check would then immediately see that fresh row and
  # report :debounced on every single call. Going straight to PrintTriggerService keeps exactly
  # one print ScanEvent written per action, same as every other print path in this app.
  #
  # check_in/check_out still go through ScanService unchanged; "also print" (requirement.md: "if
  # admin selected print then it will make check-in and print badge") is a second, independent
  # call to PrintTriggerService afterward, only on a successful scan — never on a debounced/
  # not_found/session_full result, and it also fires unconditionally when the event's own
  # auto_print_enabled toggle is on (the real Phase 10 checklist "auto-print" flow; the kiosk
  # toggle is the per-operator manual override on top of it).
  def scan
    authorize @event, :create?, policy_class: ScanEventPolicy
    session = @event.sessions.find_by(id: params[:session_id]) if params[:session_id].present?

    if params[:scan_type] == "print"
      participant = Participant.find_by_identifier(@event, params[:identifier])
      if participant.nil?
        @result = ScanService::Result.new(status: :not_found)
      else
        @print_result = PrintTriggerService.call(event: @event, participant: participant, source: :kiosk)
        @result = ScanService::Result.new(status: :print_only, participant: participant)
      end
    else
      @result = ScanService.call(
        event: @event, identifier: params[:identifier], scan_type: params[:scan_type], source: :manual, session: session
      )
      if @result.ok? && (params[:print] == "1" || @event.auto_print_enabled?)
        @print_result = PrintTriggerService.call(event: @event, participant: @result.participant, source: :kiosk)
      end
    end

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
