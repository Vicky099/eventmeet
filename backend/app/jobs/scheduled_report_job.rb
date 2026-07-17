# Phase 14 — Reporting, Import/Export & Analytics (requirement.md §5.11): "Scheduled report
# delivery (Sidekiq-cron or equivalent: emailed weekly/daily summary to organizers)." The
# "equivalent" this app actually uses: a self-rescheduling job, same as EventSchedulerJob/
# PartitionMaintenanceJob — no sidekiq-cron gem is installed, a deliberate choice those two jobs'
# own comments already explain (no external cron/schedule.yml to keep in sync with the code, and
# this app's own flagship differentiator is real-time-ish behavior anyway).
#
# Hourly, not daily/weekly itself — #due? is what actually decides whether *this* tick is a given
# event's turn, comparing Event#last_report_sent_at against a rolling window rather than a fixed
# calendar slot, so a job that started running slightly late (deploy, restart) never permanently
# skips a whole cycle the way a fixed "send at exactly 00:00" cron entry would.
#
# Bootstrapping: same as EventSchedulerJob — something needs to call
# `ScheduledReportJob.perform_later` once to start the self-rescheduling chain (a deploy step,
# `bin/jobs` boot hook, etc.) — deliberately left open rather than wired into an app boot hook
# here, which risks double-enqueuing across multiple Puma/Sidekiq processes with no locking
# mechanism in place yet.
class ScheduledReportJob < ApplicationJob
  queue_as :default

  RESCHEDULE_INTERVAL = 1.hour

  def perform
    Event.unscoped_across_tenants do
      Event.where.not(scheduled_report_frequency: :none).where.not(published_at: nil).find_each do |event|
        next unless due?(event)

        begin
          deliver_report!(event)
        rescue StandardError => e
          # One bad event shouldn't take down the whole tick — same reasoning as
          # EventSchedulerJob's own per-row rescue.
          Rails.logger.error("[ScheduledReportJob] failed for Event #{event.id}: #{e.message}")
        end
      end
    end
  ensure
    self.class.set(wait: RESCHEDULE_INTERVAL).perform_later
  end

  private

  def due?(event)
    window = event.report_daily? ? 1.day : 7.days
    event.last_report_sent_at.nil? || event.last_report_sent_at < window.ago
  end

  def deliver_report!(event)
    Current.account = event.account
    stats = build_stats(event)

    event.account.owner_users.each do |owner|
      Notifier.email(
        mailer_class: ReportMailer, mailer_method: :summary, mailer_args: [ event, stats, owner.email ],
        notifiable: event, to: owner.email, subject: "#{event.scheduled_report_frequency.capitalize} report — #{event.name}"
      )
    end

    # update_columns, not update! — a report send is bookkeeping about *this row*, not a user
    # edit; skipping validations/callbacks here matches GovtId#assign_to!'s own
    # update_column reasoning for the same kind of internal state write.
    event.update_columns(last_report_sent_at: Time.current)
  end

  def build_stats(event)
    registered_count = event.participants.count
    checked_in_count = event.checked_in_participant_count
    top_session = event.sessions.includes(:session_live_stats)
      .max_by { |session| session.session_live_stats&.checked_in_count || 0 }

    {
      registered_count: registered_count,
      new_registrations: event.participants.where("created_at > ?", event.last_report_sent_at || event.created_at).count,
      checked_in_count: checked_in_count,
      check_in_rate: registered_count.positive? ? ((checked_in_count.to_f / registered_count) * 100).round(1) : 0,
      currently_in_venue_count: event.currently_in_venue_count,
      top_session: top_session && top_session.session_live_stats&.checked_in_count.to_i.positive? ? top_session.name : nil
    }
  end
end
