require "rails_helper"

RSpec.describe Invoice, type: :model do
  let(:account) { create(:account) }
  let(:platform_staff) { create(:user, platform_staff: true) }

  before { Current.account = account }

  describe ".generate_for" do
    it "creates a draft invoice for the event's approved quotation amount and currency" do
      quotation = create(:quotation, :approved, account: account, requested_by: create(:user), current_amount: 45_000, currency: "USD")
      event = create(:event, account: account, quotation: quotation)

      invoice = Invoice.generate_for(event)

      expect(invoice).to be_persisted
      expect(invoice).to be_draft
      expect(invoice.amount).to eq(45_000)
      expect(invoice.currency).to eq("USD")
      expect(invoice.event).to eq(event)
      expect(invoice.account).to eq(account)
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
