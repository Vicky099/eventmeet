# Phase 14 — Reporting, Import/Export & Analytics (requirement.md §5.11): "Scheduled report
# delivery (emailed weekly/daily summary to organizers)." Mirrors EventMailer's own shape exactly
# (@tenant_account for the tenant-subdomain URL host) — ScheduledReportJob is the only caller,
# routing through Notifier/NotificationDeliveryJob for tracked delivery-state the same way every
# other mailer in this app does since Phase 13.
class ReportMailer < ApplicationMailer
  def summary(event, stats, to)
    @event = event
    @stats = stats
    @tenant_account = event.account

    mail(to: to, subject: "#{event.scheduled_report_frequency.capitalize} report — #{event.name}")
  end
end
