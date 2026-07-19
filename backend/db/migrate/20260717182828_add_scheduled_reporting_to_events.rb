# Phase 14 — Reporting, Import/Export & Analytics (requirement.md §3.11, §5.11): "Scheduled
# report delivery (emailed weekly/daily summary to organizers)." Organizer opt-in, per event
# (none by default) — `last_report_sent_at` is what ScheduledReportJob's own due? check compares
# against, the same "track when it last ran, not a fixed calendar slot" shape a self-rescheduling
# job needs (see that job's own comment on why this app uses that pattern instead of sidekiq-cron
# at all, following EventSchedulerJob's own precedent).
class AddScheduledReportingToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :scheduled_report_frequency, :integer, null: false, default: 0
    add_column :events, :last_report_sent_at, :datetime
  end
end
