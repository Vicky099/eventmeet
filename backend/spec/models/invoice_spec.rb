require "rails_helper"

RSpec.describe Invoice, type: :model do
  let(:account) { create(:account) }
  let(:platform_staff) { create(:user, platform_staff: true) }

  before { Current.account = account }

  describe ".generate_for" do
    # Fixed-hierarchy pivot (requirement.md revisit): every event's price comes from its account's
    # own Agency (no more per-tenant Quotation negotiation) — read fresh at completion time, not a
    # snapshot from whenever the event was created.
    it "creates a draft invoice for the event's Agency price/currency" do
      agency = create(:agency, price_per_event: 15_000, currency: "USD", events_granted: 1)
      agency_account = create(:account, agency: agency)
      Current.account = agency_account
      event = create(:event, account: agency_account)

      invoice = Invoice.generate_for(event)

      expect(invoice).to be_persisted
      expect(invoice).to be_draft
      expect(invoice.amount).to eq(15_000)
      expect(invoice.currency).to eq("USD")
      expect(invoice.event).to eq(event)
      expect(invoice.account).to eq(agency_account)
    end
  end

  describe ".generate_for_agency_contract" do
    it "creates a draft invoice for the agency's own annual_price/currency, with no event or account" do
      agency = create(:agency, billing_cycle: :annual, annual_price: 500_000, currency: "USD", price_per_event: nil, events_granted: 0)

      invoice = Invoice.generate_for_agency_contract(agency)

      expect(invoice).to be_persisted
      expect(invoice).to be_draft
      expect(invoice.amount).to eq(500_000)
      expect(invoice.currency).to eq("USD")
      expect(invoice.agency).to eq(agency)
      expect(invoice.event).to be_nil
      expect(invoice.account).to be_nil
    end
  end

  describe "#exactly_one_of_event_or_agency" do
    it "is invalid with neither an event nor an agency" do
      invoice = build(:invoice, event: nil, account: nil, agency: nil)

      expect(invoice).not_to be_valid
      expect(invoice.errors[:base]).to be_present
    end

    it "is invalid with both an event and an agency" do
      event = create(:event, account: account)
      agency = create(:agency, billing_cycle: :annual, annual_price: 100_000, price_per_event: nil, events_granted: 0)
      invoice = build(:invoice, event: event, account: account, agency: agency)

      expect(invoice).not_to be_valid
      expect(invoice.errors[:base]).to be_present
    end
  end

  describe "#send!" do
    it "moves draft straight to awaiting_payment" do
      event = create(:event, account: account)
      invoice = create(:invoice, event: event, account: account)

      invoice.send!

      expect(invoice).to be_awaiting_payment
    end
  end

  describe "#submit_payment!" do
    it "records the UTR/submitter and moves to under_review" do
      event = create(:event, account: account)
      invoice = create(:invoice, :awaiting_payment, event: event, account: account)
      tenant_user = create(:user)

      invoice.submit_payment!(utr_reference: "UTR987654321", receipt: nil, by: tenant_user)

      expect(invoice).to be_under_review
      expect(invoice.utr_reference).to eq("UTR987654321")
      expect(invoice.submitted_by).to eq(tenant_user)
      expect(invoice.submitted_at).to be_present
    end
  end

  describe "#verify!" do
    it "marks the invoice paid and clears any prior rejection reason" do
      event = create(:event, account: account)
      invoice = create(:invoice, :under_review, event: event, account: account, rejection_reason: "wrong UTR")

      invoice.verify!(by: platform_staff)

      expect(invoice).to be_paid
      expect(invoice.verified_by).to eq(platform_staff)
      expect(invoice.verified_at).to be_present
      expect(invoice.rejection_reason).to be_nil
    end
  end

  describe "#reject_payment!" do
    it "sends the invoice back to awaiting_payment with a reason, keeping the UTR for the tenant to see" do
      event = create(:event, account: account)
      invoice = create(:invoice, :under_review, event: event, account: account)

      invoice.reject_payment!(reason: "UTR doesn't match our records", by: platform_staff)

      expect(invoice).to be_awaiting_payment
      expect(invoice.rejection_reason).to eq("UTR doesn't match our records")
      expect(invoice.utr_reference).to be_present
    end
  end
end
