require "rails_helper"

RSpec.describe BillingMailer, type: :mailer do
  let(:account) { create(:account, subdomain_slug: "acme") }
  let(:platform_staff) { create(:user, platform_staff: true) }

  before { Current.account = account }

  describe "#quotation_amount_sent" do
    it "includes the event name and amount" do
      quotation = create(:quotation, :sent, account: account, requested_by: create(:user), event_name: "Annual Summit")

      mail = described_class.quotation_amount_sent(quotation, "owner@acme.example")

      expect(mail.to).to eq([ "owner@acme.example" ])
      expect(mail.subject).to include("Annual Summit")
      expect(mail.html_part.body.to_s).to include("₹30,000.00")
    end
  end

  describe "#invoice_sent" do
    it "includes the event name and amount" do
      event = create(:event, account: account, name: "Annual Summit")
      invoice = create(:invoice, event: event, account: account, amount: 120)

      mail = described_class.invoice_sent(invoice, "owner@acme.example")

      expect(mail.subject).to include("Annual Summit")
      expect(mail.html_part.body.to_s).to include("120")
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
