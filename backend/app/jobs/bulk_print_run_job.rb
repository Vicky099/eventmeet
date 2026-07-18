# Phase 10 revisit — Bulk Print (requirement.md §3.6/§5.5's baseline "bulk print queue," rebuilt
# against real PrintStation/PrintJob infrastructure). Selects up to the run's own `limit`
# participants for the event with no prior *succeeded* PrintJob, ordered by registration order —
# a stable, resumable queue: re-running Bulk Print after a paper jam naturally skips everything
# already printed, no separate "resume" button needed (BulkPrintRun#last_printed_participant is
# what an admin reads to know where a previous run actually stopped).
class BulkPrintRunJob < ApplicationJob
  queue_as :default

  def perform(bulk_print_run_id)
    run = BulkPrintRun.unscoped_across_tenants { BulkPrintRun.find(bulk_print_run_id) }
    Current.account = run.account
    run.update!(status: :processing)

    participants = unprinted_participants(run)
    participants.each_with_index do |participant, index|
      PrintTriggerService.call(
        event: run.event, participant: participant, source: :bulk,
        station: run.print_station, bulk_print_run: run, sequence: index + 1
      )
    end

    run.update!(status: :completed)
  rescue StandardError => e
    Rails.logger.error("[BulkPrintRunJob] failed for BulkPrintRun #{bulk_print_run_id}: #{e.message}")
    run&.update!(status: :failed)
  end

  private

  def unprinted_participants(run)
    already_printed_ids = run.event.print_jobs.succeeded.pluck(:participant_id)
    run.event.participants.where.not(id: already_printed_ids).order(:created_at).limit(run.limit)
  end
end
