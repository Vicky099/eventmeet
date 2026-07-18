# Phase 4 (requirement.md §3.2). Ports the baseline's daily cron-triggered scheduler, at a much
# tighter cadence — this product's own flagship differentiator is real-time behavior, a `live`
# transition landing within minutes, not up to a day late.
#
# Revisited (confirmed with the user): fired by sidekiq-cron on a fixed schedule
# (config/schedule.yml, "*/5 * * * *") instead of the self-rescheduling pattern this job (and
# EventCompletionService's own sibling jobs) originally used — that pattern's real gap, no
# bootstrap step anywhere actually called the first `.perform_later`, meant this job never ran
# outside a spec. No self-reschedule left here at all; sidekiq-cron's own persisted schedule is
# what re-triggers every tick now.
#
# Revisited for the wizard's Publish gate (requirement.md §5.2, `Event#publish!`): this job now
# only manages events that have been published at least once (`published_at` present) — an
# event still sitting in draft, never published, is invisible to it and stays `draft` forever
# regardless of its schedule. Status is otherwise recomputed from scratch on every tick purely
# from `starts_at`/`ends_at` vs now (`Event#computed_status`); the update is skipped when that
# doesn't actually change anything, so most ticks touch zero rows.
#
# Revisited again (confirmed with the user): the draft Invoice is now raised synchronously,
# right here, the moment an event lands on `completed` — not "the next day" (InvoiceGenerationJob's
# own comment has the superseded original requirement). Every event now goes through the
# quotation flow (`belongs_to :quotation`, requirement.md §4.6), so there's no plan-tier reason
# left to wait — the tenant's already-approved quotation amount is all `Invoice.generate_for`
# needs. Fires for any transition landing on `completed`, not just from `live` (an event
# published straight past its own end date still needs an invoice, even though it has no
# in-progress attendance for EventCompletionService to finalize). InvoiceGenerationJob itself
# stays as an hourly safety-net sweep for whatever this misses.
class EventSchedulerJob < ApplicationJob
  queue_as :default

  def perform
    now = Time.current

    Event.unscoped_across_tenants do
      Event.where.not(status: :completed).where.not(published_at: nil).find_each do |event|
        target = event.computed_status(now)
        next if target == event.status

        begin
          was_live = event.live?
          event.update!(status: target)
          next unless target == "completed"

          # Phase 9 checklist: "auto-checkout/mark-absent attendees when an event's live ->
          # completed transition fires" — exactly this transition, not "any event that ends up
          # completed" (an event published straight past its own end date, skipping `live`
          # entirely, has no in-progress attendance to finalize).
          EventCompletionService.finalize_attendance!(event) if was_live
          Current.account = event.account
          Invoice.generate_for(event) if event.invoice.nil?
        rescue StandardError => e
          # One bad row shouldn't take down the whole tick — sidekiq-cron's own schedule is what
          # guarantees the next tick, not a `rescue`-defeating raise here.
          Rails.logger.error("[EventSchedulerJob] failed to transition Event #{event.id}: #{e.message}")
        end
      end
    end
  end
end
