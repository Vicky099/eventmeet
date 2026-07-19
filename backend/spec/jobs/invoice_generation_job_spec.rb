require "rails_helper"

# Phase 15 — Platform Billing & Invoicing, revisited (requirement.md §4.6). Originally "next day";
# superseded (confirmed with the user) — EventSchedulerJob now raises the draft Invoice
# synchronously the moment an event completes (see that job's own spec). This job is only the
# hourly safety-net sweep for whatever slips past that — no day-old wait left to test here.
RSpec.describe InvoiceGenerationJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  let(:account) { create(:account) }

  def create_completed_event(ends_at:, **attrs)
    Current.account = account
    event = create(:event, account: account, starts_at: ends_at - 1.hour, ends_at: ends_at, **attrs)
    Event.unscoped_across_tenants { event.update_column(:status, :completed) }
    event
  end

  # Invoice is no longer TenantScoped (fixed-hierarchy pivot, an agency-contract invoice has no
  # account at all to scope against) — a plain Invoice.find_by works fine with no
  # unscoped_across_tenants wrapper needed, unlike Event above.
  it "generates a draft invoice for a completed event that has none yet" do
    event = create_completed_event(ends_at: 1.hour.ago)

    InvoiceGenerationJob.perform_now

    invoice = Invoice.find_by(event_id: event.id)
    expect(invoice).to be_present
    expect(invoice).to be_draft
    expect(invoice.amount).to eq(event.account.agency.price_per_event)
  end

  it "doesn't generate a second invoice for an event that already has one" do
    event = create_completed_event(ends_at: 2.days.ago)
    Current.account = account
    create(:invoice, event: event, account: account)

    InvoiceGenerationJob.perform_now

    expect(Invoice.where(event_id: event.id).count).to eq(1)
  end

  it "skips an event whose status isn't completed" do
    Current.account = account
    event = create(:event, account: account, starts_at: 3.days.ago, ends_at: 2.days.ago)

    InvoiceGenerationJob.perform_now

    expect(Invoice.where(event_id: event.id).count).to eq(0)
  end

  # Fixed-hierarchy pivot (requirement.md revisit): an annual agency's events are unlimited/already
  # paid for up front — never get a per-event Invoice at all.
  it "skips a completed event whose agency is on an annual contract" do
    annual_agency = create(:agency, :annual)
    annual_account = create(:account, agency: annual_agency)
    Current.account = annual_account
    event = create(:event, account: annual_account, starts_at: 2.hours.ago, ends_at: 1.hour.ago)
    Event.unscoped_across_tenants { event.update_column(:status, :completed) }

    InvoiceGenerationJob.perform_now

    expect(Invoice.where(event_id: event.id).count).to eq(0)
  end
end
