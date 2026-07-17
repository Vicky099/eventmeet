require "rails_helper"

RSpec.describe ParticipantMailer, type: :mailer do
  let(:account) { create(:account, subdomain_slug: "acme") }
  let(:event) do
    create(:event, account: account, name: "Annual Meetup", address: "123 Main St",
      starts_at: Time.zone.local(2026, 8, 1, 9, 0), ends_at: Time.zone.local(2026, 8, 1, 17, 0))
  end

  before { Current.account = account }

  describe "#confirmation" do
    let(:participant) { create(:participant, account: account, event: event, first_name: "Jane", last_name: "Doe", email: "jane@example.com") }
    let(:mail) { described_class.confirmation(participant) }

    it "addresses and subjects the mail to the participant, for their event" do
      expect(mail.to).to eq([ "jane@example.com" ])
      expect(mail.subject).to include("Annual Meetup")
    end

    it "includes the event's schedule and the participant's own registration ID" do
      expect(mail.html_part.body.to_s).to include("Annual Meetup")
      expect(mail.html_part.body.to_s).to include("123 Main St")
      expect(mail.html_part.body.to_s).to include(participant.client_participant_id)
    end

    # requirement.md revisit: "we should capture ... sender email" / "all the dates which are
    # display in the UI should abey the tenant timezone" — ApplicationMailer#mail applies both
    # from @tenant_account, which ParticipantMailer#confirmation already sets (@tenant_account =
    # @event.account) for its own #default_url_options needs.
    context "with the account's own sender_email and time_zone configured" do
      let(:account) { create(:account, subdomain_slug: "acme", sender_email: "hello@acme.example", time_zone: "Chennai") }

      it "sends from the account's own sender_email" do
        expect(mail.from).to eq([ "hello@acme.example" ])
      end

      it "renders the event schedule in the account's own timezone, not UTC" do
        # Time.utc(...), not event.starts_at — reading the attribute here (before the mail's own
        # Time.use_zone block runs) would cache its time-zone-cast value under whatever Time.zone
        # is ambient *right now*, a real ActiveRecord behavior (time_zone_aware_attributes casts
        # once and caches, not on every read) — a poisoned read here would still show the stale
        # cached value once #confirmation reads the very same association's attribute later, even
        # under the correct Time.zone by then. Matches this file's own starts_at literally: 09:00.
        expected_start = ActiveSupport::TimeZone["Chennai"].at(Time.utc(2026, 8, 1, 9, 0)).strftime("%B %-d, %Y %H:%M")
        expect(mail.html_part.body.to_s).to include(expected_start)
      end
    end

    it "falls back to the platform default From: address when the account has no sender_email configured" do
      account.update_columns(sender_email: nil) # the factory sets one by default — this test is specifically about its absence
      expect(mail.from).to eq([ "no-reply@eventmeet.example" ])
    end

    # Phase 13 — Communications (requirement.md §3.10, §5.10): "registration-confirmation email
    # using Phase 12's tenant/sponsor branding layering" — the one piece of tenant branding that
    # exists ahead of Phase 12 itself, Account#logo.
    describe "tenant branding" do
      it "shows the tenant's own logo when one is attached" do
        Tempfile.create([ "logo", ".png" ]) do |tempfile|
          tempfile.binmode
          tempfile.write("fake logo bytes")
          tempfile.rewind
          account.attach_logo(Rack::Test::UploadedFile.new(tempfile.path, "image/png"))
        end

        expect(mail.html_part.body.to_s).to include("<img")
      end

      it "renders nothing extra when the tenant has no logo" do
        expect(account.logo).not_to be_attached
        expect(mail.html_part.body.to_s).not_to include("<img")
      end
    end
  end
end
