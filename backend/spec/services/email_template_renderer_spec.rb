require "rails_helper"

RSpec.describe EmailTemplateRenderer, type: :model do
  let(:account) { create(:account, name: "Acme Events") }
  let(:event) do
    create(:event, account: account, name: "Annual Meetup", address: "123 Main St",
      meeting_link: "https://meet.example.com/annual",
      starts_at: Time.zone.local(2026, 8, 1, 9, 0), ends_at: Time.zone.local(2026, 8, 1, 17, 0))
  end

  before { Current.account = account }

  let(:participant) do
    create(:participant, account: account, event: event, first_name: "Alice", last_name: "<B> Smith", email: "alice@example.com")
  end

  it "substitutes participant/event/tenant tokens, HTML-escaping text values" do
    rendered = described_class.render_email(
      subject: "Hi $FIRST_NAME$, welcome to $EVENT_NAME$",
      html_body: "<p>$PARTICIPANT_NAME$ ($PARTICIPANT_EMAIL$) — $ORG_ID$ — $TENANT_NAME$</p>",
      participant: participant, event: event, account: account
    )

    expect(rendered[:subject]).to eq("Hi Alice, welcome to Annual Meetup")
    expect(rendered[:html]).to include("Alice &lt;B&gt; Smith")
    expect(rendered[:html]).to include("alice@example.com")
    expect(rendered[:html]).to include(participant.client_participant_id)
    expect(rendered[:html]).to include("Acme Events")
  end

  it "substitutes event schedule/location tokens" do
    rendered = described_class.render_email(
      subject: "x", html_body: "$EVENT_START$ - $EVENT_END$ @ $EVENT_ADDRESS$ ($EVENT_MEETING_LINK$)",
      participant: participant, event: event, account: account
    )

    expect(rendered[:html]).to include("August 1, 2026 09:00")
    expect(rendered[:html]).to include("123 Main St")
    expect(rendered[:html]).to include("https://meet.example.com/annual")
  end

  it "substitutes $LOGO$ with the tenant's logo URL when attached" do
    # A real controller/mailer call sets this automatically (ActiveStorage::SetCurrent /
    # ApplicationMailer#mail) before ever reaching EmailTemplateRenderer — this direct service spec
    # has to set it itself, same gap ActiveStorage::Blob#url always has outside a real request.
    ActiveStorage::Current.url_options = { host: "example.com" }
    account.logo.attach(io: StringIO.new("fake logo"), filename: "logo.png", content_type: "image/png")

    rendered = described_class.render_email(
      subject: "x", html_body: '<img src="$LOGO$">', participant: participant, event: event, account: account
    )

    expect(rendered[:html]).to match(%r{<img src="https?://[^"]+">})
  end

  it "substitutes $LOGO$ with an empty string when no logo is attached" do
    rendered = described_class.render_email(
      subject: "x", html_body: '<img src="$LOGO$">', participant: participant, event: event, account: account
    )

    expect(rendered[:html]).to eq('<img src="">')
  end

  # Phase 13 — Communications, revisited: "add the QRcode in mailer using placeholder ... show
  # that in the mail as well ... don't upload the QR code to cloudinary" — a base64 data: URI
  # (Participant#qr_code_data_uri), never an uploaded/attached file, unlike $LOGO$ above.
  it "substitutes $QRCODE$ with a base64-inlined PNG data URI encoding the participant's hex_id" do
    rendered = described_class.render_email(
      subject: "x", html_body: '<img src="$QRCODE$">', participant: participant, event: event, account: account
    )

    expect(rendered[:html]).to eq(%(<img src="#{participant.qr_code_data_uri}">))
  end

  it "leaves an unrecognized token as-is rather than blanking it" do
    rendered = described_class.render_email(
      subject: "x", html_body: "$NOT_A_REAL_TOKEN$", participant: participant, event: event, account: account
    )

    expect(rendered[:html]).to eq("$NOT_A_REAL_TOKEN$")
  end
end
