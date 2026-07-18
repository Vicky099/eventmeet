# Phase 10 — Print Agent (Electron) Integration (requirement.md §5.5.1). The one place printing
# actually happens — every print-producing surface (participant list/show's manual Print button,
# BulkPrintRunJob, check-in's "also print"/"print only") calls through here instead of
# re-implementing badge resolution, debounce, or the dispatched-vs-fallback branch. Mirrors
# ScanService's own "one service owns the side effects" shape.
#
# Two real outcomes, deliberately not three: `dispatched` (a paired, online station exists —
# PrintJob queued and pushed) or `fallback` (no station, or the station isn't currently online —
# render/stream the badge PDF exactly like Phase 8's pre-existing #badge action always has,
# confirmed as the manual-print fallback behavior). `no_badge`/`debounced` are the same two
# not-actually-printing states the single-badge download and check-in scan flows already have to
# handle elsewhere in this app.
class PrintTriggerService
  Result = Struct.new(:status, :station, :badge, :print_job, :participant, keyword_init: true) do
    def dispatched? = status == :dispatched
    def fallback? = status == :fallback
    def debounced? = status == :debounced
    def no_badge? = status == :no_badge
  end

  # Same 30-second window ScanService uses for check-in/check-out — a double-tap of the same
  # Print button (or a check-in "also print" toggle firing twice off one physical scan) shouldn't
  # queue two PrintJobs for the same badge.
  DEBOUNCE_WINDOW = ScanService::DEBOUNCE_WINDOW

  def self.call(...) = new.call(...)

  def call(event:, participant:, source:, station: nil, bulk_print_run: nil, sequence: nil)
    station ||= event.default_print_station

    return Result.new(status: :debounced, participant: participant) if debounced?(event, participant)

    badge = event.badge_for(participant)
    return Result.new(status: :no_badge, participant: participant) if badge.nil?

    if station&.online?
      dispatch(event: event, participant: participant, station: station, badge: badge,
        source: source, bulk_print_run: bulk_print_run, sequence: sequence)
    else
      log_print_scan!(event, participant, source_for_scan_event(source))
      Result.new(status: :fallback, badge: badge, participant: participant)
    end
  end

  private

  def debounced?(event, participant)
    event.scan_events.where(participant: participant, scan_type: :print)
      .where(scanned_at: DEBOUNCE_WINDOW.ago..).exists?
  end

  def dispatch(event:, participant:, station:, badge:, source:, bulk_print_run:, sequence:)
    print_job = PrintJob.create!(
      account: event.account, event: event, print_station: station, participant: participant,
      bulk_print_run: bulk_print_run, sequence: sequence, status: :pending, source: source
    )

    PrintJobsChannel.broadcast_to(station, "action" => "print_job", "job_id" => print_job.id, "participant_name" => participant.name)
    print_job.update!(status: :sent, sent_at: Time.current)
    log_print_scan!(event, participant, :agent)

    Result.new(status: :dispatched, station: station, badge: badge, print_job: print_job, participant: participant)
  end

  # requirement.md §6 item 13: printing subscribes to the same unified ScanEvent abstraction the
  # existing on-demand #badge download already writes to — one consistent "this badge was
  # printed" signal regardless of which of the (now several) paths produced it.
  def log_print_scan!(event, participant, scan_source)
    ScanEvent.create!(
      account: event.account, event: event, participant: participant,
      scan_type: :print, source: scan_source, scanned_at: Time.current
    )
  end

  # PrintJob#source (manual/kiosk/bulk, this service's own caller-facing vocabulary) doesn't map
  # 1:1 onto ScanEvent#source (kiosk/manual/agent/system) — a *dispatched* print (agent actually
  # produced it) is always logged as :agent regardless of who triggered it; a *fallback* download
  # keeps the caller's own source (manual/kiosk), matching what the pre-existing #badge action
  # already logs for a plain manual download.
  def source_for_scan_event(source)
    source == :bulk ? :agent : source
  end
end
