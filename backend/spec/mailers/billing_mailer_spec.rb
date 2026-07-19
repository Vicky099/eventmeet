require "rails_helper"

RSpec.describe BillingMailer, type: :mailer do
  let(:account) { create(:account, subdomain_slug: "acme") }
  let(:platform_staff) { create(:user, platform_staff: true) }

  before { Current.account = account }

  describe "#invoice_sent" do
    it "includes the event name and amount" do
      event = create(:event, account: account, name: "Annual Summit")
      invoice = create(:invoice, event: event, account: account, amount: 120)

      mail = described_class.invoice_sent(invoice, "owner@acme.example")

      expect(mail.subject).to include("Annual Summit")
      expect(mail.html_part.body.to_s).to include("120")
    end

    # Fixed-hierarchy pivot (requirement.md revisit): an annual agency's own upfront contract
    # invoice has no event/account at all — same mailer, a different subject/body branch.
    it "includes the agency name and amount for an agency-contract invoice with no event" do
      agency = create(:agency, name: "Acme Agency", billing_cycle: :annual, annual_price: 500_000, price_per_event: nil, events_granted: 0)
      invoice = Invoice.generate_for_agency_contract(agency)

      mail = described_class.invoice_sent(invoice, "agency-admin@example.com")

      expect(mail.subject).to include("annual contract")
      expect(mail.html_part.body.to_s).to include("Acme Agency")
      expect(mail.html_part.body.to_s).to include("500,000")
    end
  end

  describe "#payment_rejected" do
    it "includes the rejection reason" do
      event = create(:event, account: account, name: "Annual Summit")
      invoice = create(:invoice, :awaiting_payment, event: event, account: account,
        utr_reference: "UTR123", rejection_reason: "UTR doesn't match")

      mail = described_class.payment_rejected(invoice, "owner@acme.example")

      expect(mail.subject).to include("Annual Summit")
      expect(mail.text_part.body.to_s).to include("UTR doesn't match") # text_part, not html_part — ERB HTML-escapes the apostrophe there (&#39;)
    end
  end
end
