require "rails_helper"

# Phase 14 — Reporting, Import/Export & Analytics (requirement.md §5.11): "Scheduled report
# delivery (emailed weekly/daily summary to organizers)." ScheduledReportJob's own spec covers
# the full end-to-end trigger/content path — this is just the mailer's own rendering contract.
RSpec.describe ReportMailer, type: :mailer do
  let(:account) { create(:account, subdomain_slug: "acme") }
  let(:event) { create(:event, account: account, name: "Annual Meetup", scheduled_report_frequency: :weekly) }
  let(:stats) do
    { registered_count: 42, new_registrations: 5, checked_in_count: 30, check_in_rate: 71.4, currently_in_venue_count: 12, top_session: "Keynote Hall" }
  end

  before { Current.account = account }

  describe "#summary" do
    let(:mail) { described_class.summary(event, stats, "owner@acme.example") }

    it "addresses and subjects the mail to the given recipient" do
      expect(mail.to).to eq([ "owner@acme.example" ])
      expect(mail.subject).to include("Weekly report", "Annual Meetup")
    end

    it "includes every stat in the body" do
      body = mail.html_part.body.to_s
      expect(body).to include("42") # registered_count
      expect(body).to include("5") # new_registrations
      expect(body).to include("30") # checked_in_count
      expect(body).to include("71.4")
      expect(body).to include("12") # currently_in_venue_count
      expect(body).to include("Keynote Hall")
    end

    it "omits the top-session line when there isn't one" do
      mail_without_session = described_class.summary(event, stats.merge(top_session: nil), "owner@acme.example")
      expect(mail_without_session.html_part.body.to_s).not_to include("Most attended session")
    end

    it "links to the event's own live dashboard, on the tenant's own subdomain" do
      expect(mail.html_part.body.to_s).to include("acme.example.com#{admin_event_path(event)}")
    end
  end
end
