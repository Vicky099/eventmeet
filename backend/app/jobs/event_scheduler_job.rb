# Phase 4 (requirement.md §3.2, baseline EventSchedularJob minus the auto-checkout piece — that
# belongs in Phase 9 once Attendance exists). Ports the baseline's daily cron-triggered scheduler,
# but self-reschedules every RESCHEDULE_INTERVAL instead of depending on external cron/
# sidekiq-cron (no such gem is installed, and this product's own flagship differentiator is
# real-time behavior — a `live` transition landing within minutes, not up to a day late, fits
# that better than baseline's daily cadence did).
#
# Revisited for the wizard's Publish gate (requirement.md §5.2, `Event#publish!`): this job now
# only manages events that have been published at least once (`published_at` present) — an
# event still sitting in draft, never published, is invisible to it and stays `draft` forever
# regardless of its schedule. Status is otherwise recomputed from scratch on every tick purely
# from `starts_at`/`ends_at` vs now (`Event#computed_status`); the update is skipped when that
# doesn't actually change anything, so most ticks touch zero rows.
#
# Bootstrapping: something needs to call `EventSchedulerJob.perform_later` once to start the
# self-rescheduling chain (a deploy step, `bin/jobs` boot hook, etc.) — deliberately left open
# rather than wired into an app boot hook here, which risks double-enqueuing across multiple
# Puma/Sidekiq processes with no locking mechanism in place yet.
class EventSchedulerJob < ApplicationJob
  queue_as :default

  RESCHEDULE_INTERVAL = 5.minutes

  def perform
    now = Time.current

    Event.unscoped_across_tenants do
      Event.where.not(status: :completed).where.not(published_at: nil).find_each do |event|
        target = event.computed_status(now)
        next if target == event.status

        begin
          event.update!(status: target)
        rescue StandardError => e
          # One bad row shouldn't take down the whole tick — or, via Sidekiq's own default
          # retry-on-raise behavior interacting badly with the unconditional reschedule below,
          # risk running two overlapping self-reschedule chains at once.
          Rails.logger.error("[EventSchedulerJob] failed to transition Event #{event.id}: #{e.message}")
        end
      end
    end
  ensure
    self.class.set(wait: RESCHEDULE_INTERVAL).perform_later
  end
end
