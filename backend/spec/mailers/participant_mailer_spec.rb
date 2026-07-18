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
    # exists ahead of Phase 12 itself, Account#logo. Counts <img tags, not a bare "includes <img"
    # — a QR <img> (below) is always present in the body regardless of logo, since Phase 13
    # revisited, so these assert specifically on the *logo* image's presence/absence.
    describe "tenant branding" do
      it "shows the tenant's own logo when one is attached" do
        Tempfile.create([ "logo", ".png" ]) do |tempfile|
          tempfile.binmode
          tempfile.write("fake logo bytes")
          tempfile.rewind
          account.attach_logo(Rack::Test::UploadedFile.new(tempfile.path, "image/png"))
        end

        expect(mail.html_part.body.to_s.scan("<img").size).to eq(2) # logo + QR
      end

      it "renders no logo image when the tenant has no logo, just the QR" do
        expect(account.logo).not_to be_attached
        expect(mail.html_part.body.to_s.scan("<img").size).to eq(1) # QR only
      end
    end

    # Phase 13 — Communications, revisited: "add the QRcode in mailer using placeholder ... show
    # that in the mail as well ... don't upload the QR code to cloudinary."
    describe "QR code" do
      it "shows the participant's own QR code inline in the default template, as a data: URI (never uploaded)" do
        expect(mail.html_part.body.to_s).to include(participant.qr_code_data_uri)
      end

      it "shows the QR code in a custom template that uses the $QRCODE$ placeholder" do
        create(:email_template, event: event, account: account, kind: :participant_registration,
          subject: "x", html_body: '<html><body><img src="$QRCODE$"></body></html>')

        expect(mail.html_part.body.decoded).to include(participant.qr_code_data_uri)
      end
    end

    # Phase 13 — Communications, revisited (requirement.md §3.10, §5.10): "customized email
    # template for participant registration," confirmed scoped per event, not shared tenant-wide.
    describe "with a custom EmailTemplate" do
      it "uses the event's own subject/HTML, with placeholders filled in, instead of the built-in view" do
        create(:email_template, event: event, account: account, kind: :participant_registration,
          subject: "Welcome, $FIRST_NAME$!", html_body: "<p>You're in for $EVENT_NAME$, $FIRST_NAME$.</p>")

        expect(mail.subject).to eq("Welcome, Jane!")
        expect(mail.html_part.body.decoded).to eq("<p>You're in for Annual Meetup, Jane.</p>")
      end

      # Attaching the registration PDF (below) makes every send multipart/mixed regardless of
      # branch — html_part is no longer nil the way a genuinely single-part message's would be —
      # so "no plain-text alternative for a custom template" is asserted directly via text_part
      # instead, plus the exact two parts (html + the PDF) this branch is expected to produce.
      it "has no plain-text alternative part for a custom template — only the HTML body and the PDF attachment" do
        create(:email_template, event: event, account: account, kind: :participant_registration,
          subject: "x", html_body: "<p>x</p>")

        expect(mail.text_part).to be_nil
        expect(mail.parts.map(&:content_type)).to contain_exactly(
          a_string_starting_with("text/html"), a_string_starting_with("application/pdf")
        )
      end

      it "falls back to the default built-in template when the custom one is disabled" do
        create(:email_template, event: event, account: account, kind: :participant_registration, active: false,
          subject: "Custom", html_body: "<p>Custom body</p>")

        expect(mail.subject).to include("Annual Meetup")
        expect(mail.html_part.body.to_s).to include("Annual Meetup")
      end

      it "ignores a custom template configured on a different event of the same tenant" do
        other_event = create(:event, account: account, name: "Different Event")
        create(:email_template, event: other_event, account: account, kind: :participant_registration,
          subject: "Should not apply", html_body: "<p>Should not apply</p>")

        expect(mail.subject).to include("Annual Meetup")
        expect(mail.html_part.body.to_s).to include("Annual Meetup")
      end
    end

    # Phase 13 — Communications, revisited: "each email we send the attachment as well ... in PDF
    # show same email template + QRcode for scanning purpose" — every send carries a PDF
    # (RegistrationPdfService), whether or not the tenant has customized this email's HTML.
    describe "PDF attachment" do
      it "attaches a single PDF named after the participant's own hex_id, on the default template" do
        expect(mail.attachments.size).to eq(1)
        attachment = mail.attachments.first
        expect(attachment.filename).to eq("registration-#{participant.hex_id}.pdf")
        expect(attachment.content_type).to start_with("application/pdf")
        expect(attachment.body.decoded[0, 5]).to eq("%PDF-")
      end

      it "attaches a single PDF built from the tenant's own custom template" do
        create(:email_template, event: event, account: account, kind: :participant_registration,
          subject: "x", html_body: "<html><body><p>Custom PDF content</p></body></html>")

        expect(mail.attachments.size).to eq(1)
        attachment = mail.attachments.first
        expect(attachment.filename).to eq("registration-#{participant.hex_id}.pdf")
        expect(attachment.content_type).to start_with("application/pdf")
        expect(attachment.body.decoded[0, 5]).to eq("%PDF-")
      end
    end
  end

  # Phase 13 — Communications, revisited: "Quick Email Send" — the broadcast, kind-agnostic
  # action QuickEmailSendJob calls per participant. Distinct from #confirmation: no built-in
  # fallback view (a template is required to send at all), no PDF attachment.
  describe "#quick_email" do
    let(:participant) { create(:participant, account: account, event: event, first_name: "Jane", email: "jane@example.com") }
    let(:email_template) do
      create(:email_template, account: account, event: event, kind: :quick_send,
        subject: "Reminder: $EVENT_NAME$ starts soon", html_body: "<html><body><p>Hi $FIRST_NAME$, see you at $EVENT_NAME$!</p></body></html>")
    end
    let(:mail) { described_class.quick_email(participant, email_template) }

    it "renders the given template's own subject/HTML, with placeholders filled in" do
      expect(mail.to).to eq([ "jane@example.com" ])
      expect(mail.subject).to eq("Reminder: Annual Meetup starts soon")
      expect(mail.body.decoded).to eq("<html><body><p>Hi Jane, see you at Annual Meetup!</p></body></html>")
    end

    it "attaches no PDF — a broadcast announcement isn't a check-in credential" do
      expect(mail.attachments).to be_empty
    end

    # Confirmed with the user: the modal can pick :participant_registration itself to re-blast to
    # everyone, not just the dedicated :quick_send kind — this action doesn't care which kind the
    # given EmailTemplate actually is, only that it has subject/html_body to render.
    it "works with any kind of EmailTemplate, not just :quick_send" do
      registration_template = create(:email_template, account: account, event: event, kind: :participant_registration,
        subject: "Resent: $EVENT_NAME$", html_body: "<p>Resent for $FIRST_NAME$</p>")

      resent_mail = described_class.quick_email(participant, registration_template)

      expect(resent_mail.subject).to eq("Resent: Annual Meetup")
      expect(resent_mail.attachments).to be_empty
    end
  end
end
