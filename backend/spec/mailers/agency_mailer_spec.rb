require "rails_helper"

RSpec.describe AgencyMailer, type: :mailer do
  describe "#welcome" do
    it "includes the temp password and a working sign-in link to the agency's own subdomain" do
      agency = create(:agency, name: "Acme Agency", subdomain_slug: "acmeagency")
      user = create(:user, email: "agency-admin@example.com")

      mail = described_class.welcome(user, agency, "TempPass123")

      expect(mail.to).to eq([ "agency-admin@example.com" ])
      expect(mail.subject).to include("Acme Agency")
      expect(mail.html_part.body.to_s).to include("TempPass123")
      expect(mail.html_part.body.to_s).to include("Sign in to xEvent")
      expect(mail.html_part.body.to_s).to include("acmeagency.example.com")
    end
  end
end
