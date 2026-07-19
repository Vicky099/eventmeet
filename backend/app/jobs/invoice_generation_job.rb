# Phase 15 — Platform Billing & Invoicing, revisited (requirement.md §4.6). Originally: "post
# successful event (end date of event) in next day System will generate the invoice." Superseded
# (confirmed with the user): EventSchedulerJob now raises the draft Invoice synchronously the
# moment an event lands on `completed` — see that job's own comment for why the "next day" wait
# no longer applies. This job is what's left: an hourly safety-net sweep (sidekiq-cron,
# config/schedule.yml, "0 * * * *") for any completed event that still has no invoice — e.g. one
# whose EventSchedulerJob tick raised on the invoice step specifically (still `completed`, since
# that update! already committed before the invoice call) — not the primary path anymore.
#
# Generates a `draft` Invoice only — does NOT send it (Invoice#send! is a separate, manual Super
# Admin action, `SuperAdmin::InvoicesController#deliver`). Confirmed with the user: the system
# auto-creates the invoice so nobody has to remember to "raise" one, but a human still reviews the
# computed amount before it actually reaches the tenant.
#
# Fixed-hierarchy pivot (requirement.md revisit): scoped to `per_event`-billing_cycle agencies
# only — an `annual` agency's events are truly unlimited/already paid for up front, so they never
# get a per-event Invoice at all; without this filter, every one of their completed events would
# keep matching `where.missing(:invoice)` and get re-checked (harmlessly, but pointlessly) on
# every single hourly tick forever.
class InvoiceGenerationJob < ApplicationJob
  queue_as :default

  def perform
    Event.unscoped_across_tenants do
      Event.joins(account: :agency).where(agencies: { billing_cycle: :per_event })
        .where(status: :completed).where.missing(:invoice).find_each do |event|
        begin
          Current.account = event.account
          Invoice.generate_for(event)
        rescue StandardError => e
          # One bad event shouldn't take down the whole tick — same reasoning as
          # EventSchedulerJob's own per-row rescue.
          Rails.logger.error("[InvoiceGenerationJob] failed to generate an invoice for Event #{event.id}: #{e.message}")
        end
      end
    end
  end
end
