require "rails_helper"

RSpec.describe BadgeReformService, type: :model do
  let(:account) { create(:account) }
  let(:event) { create(:event, account: account) }

  before { Current.account = account }

  let(:badge) do
    build(:badge, account: account, event: event, mapping: { "OTHER1" => "company", "OTHER2" => "department" },
      content: <<~HTML)
        <div>
          <span class="name">$NAME$</span>
          <img class="photo" src="$PHOTO$" />
          <img class="qr" src="$QRCODE$" />
          <img class="barcode" src="$BARCODE$" />
          <span class="other1">$OTHER1$</span>
          <span class="other2">$OTHER2$</span>
          <span class="other3">$OTHER3$</span>
        </div>
      HTML
  end

  def data_uri_bytes(html, css_class)
    src = html[/class="#{css_class}"[^>]*src="([^"]+)"/, 1]
    Base64.decode64(src.split(",", 2).last)
  end

  it "substitutes $NAME$ with the participant's (HTML-escaped) name" do
    participant = create(:participant, account: account, event: event, first_name: "Alice", last_name: "<B> Smith")

    html = described_class.render(badge: badge, participant: participant)

    expect(html).to include("<span class=\"name\">Alice &lt;B&gt; Smith</span>")
  end

  it "substitutes $QRCODE$ with a base64-inlined PNG encoding the participant's hex_id" do
    participant = create(:participant, account: account, event: event)

    html = described_class.render(badge: badge, participant: participant)

    expect(html).to match(%r{class="qr" src="data:image/png;base64,[A-Za-z0-9+/=]+"})
    expect(data_uri_bytes(html, "qr")[0, 8].bytes).to eq([ 137, 80, 78, 71, 13, 10, 26, 10 ]) # PNG magic bytes
  end

  it "substitutes $BARCODE$ with a base64-inlined PNG encoding govt_id when present" do
    participant = create(:participant, account: account, event: event, govt_id: "GID123")

    html = described_class.render(badge: badge, participant: participant)

    expect(data_uri_bytes(html, "barcode")[0, 8].bytes).to eq([ 137, 80, 78, 71, 13, 10, 26, 10 ])
  end

  it "falls back $BARCODE$ to client_participant_id when govt_id is blank (two independent scan slots)" do
    participant = create(:participant, account: account, event: event, govt_id: nil)

    html = described_class.render(badge: badge, participant: participant)

    # Still produces a valid, independent barcode image even with no govt_id collected.
    expect(data_uri_bytes(html, "barcode")[0, 8].bytes).to eq([ 137, 80, 78, 71, 13, 10, 26, 10 ])
  end

  # Regression coverage for a real bug (badge_reform_service.rb's own comment on
  # BLANK_PIXEL_PNG): this used to only assert the first 8 bytes matched the generic PNG
  # file-signature magic number — true of *any* valid PNG, which is exactly how a fully *opaque
  # black* pixel (every photo-less badge's actual printed result, for as long as this constant was
  # wrong) passed undetected. Decoding through ChunkyPNG and asserting the actual alpha channel is
  # what would have caught it — asserting on file-format bytes alone proved nothing about what the
  # image actually looks like.
  it "substitutes $PHOTO$ with a blank transparent pixel when no photo is attached" do
    participant = create(:participant, account: account, event: event, attach_photo: false)

    html = described_class.render(badge: badge, participant: participant)
    png = ChunkyPNG::Image.from_blob(data_uri_bytes(html, "photo"))

    expect(png.pixels.size).to eq(1)
    expect(ChunkyPNG::Color.a(png[0, 0])).to eq(0)
  end

  it "substitutes $PHOTO$ with the participant's actual attached photo" do
    participant = create(:participant, account: account, event: event)
    png_bytes = ChunkyPNG::Image.new(2, 2, ChunkyPNG::Color::WHITE).to_blob
    participant.photo.attach(io: StringIO.new(png_bytes), filename: "photo.png", content_type: "image/png")

    html = described_class.render(badge: badge, participant: participant)

    expect(data_uri_bytes(html, "photo")).to eq(png_bytes)
  end

  # Admin::BadgesController#preview's `sample: true` — the preview modal's synthetic participant
  # never has a real photo attached, and a badge rarely has a real logo attached anymore (no
  # organizer-facing upload field for it, HasBadgeMapping's own comment) — without this, a badge
  # that actually places either token looked broken/empty in preview even though it's fine.
  describe "sample: true (Admin::BadgesController#preview)" do
    it "substitutes $PHOTO$ with a visible placeholder instead of a blank pixel when unattached" do
      participant = create(:participant, account: account, event: event, attach_photo: false)

      html = described_class.render(badge: badge, participant: participant, sample: true)
      png = ChunkyPNG::Image.from_blob(data_uri_bytes(html, "photo"))

      expect(ChunkyPNG::Color.a(png[0, 0])).to be > 0
    end

    it "still prefers a real attached photo over the sample placeholder" do
      participant = create(:participant, account: account, event: event)
      png_bytes = ChunkyPNG::Image.new(2, 2, ChunkyPNG::Color::WHITE).to_blob
      participant.photo.attach(io: StringIO.new(png_bytes), filename: "photo.png", content_type: "image/png")

      html = described_class.render(badge: badge, participant: participant, sample: true)

      expect(data_uri_bytes(html, "photo")).to eq(png_bytes)
    end

    it "does not substitute a sample placeholder for $PHOTO$ when sample is false (the default, real prints)" do
      participant = create(:participant, account: account, event: event, attach_photo: false)

      html = described_class.render(badge: badge, participant: participant)
      png = ChunkyPNG::Image.from_blob(data_uri_bytes(html, "photo"))

      expect(ChunkyPNG::Color.a(png[0, 0])).to eq(0)
    end
  end

  it "substitutes $OTHER1$/$OTHER2$ per the badge's mapping, and leaves an unmapped $OTHER3$ blank" do
    participant = create(:participant, account: account, event: event, company: "Acme Inc", department: "Sales")

    html = described_class.render(badge: badge, participant: participant)

    expect(html).to include("<span class=\"other1\">Acme Inc</span>")
    expect(html).to include("<span class=\"other2\">Sales</span>")
    expect(html).to include("<span class=\"other3\"></span>")
  end

  # Gap-fill against the reference event_management system's badge field list — Title/First Name/
  # Last Name/Designation/Org ID/Govt ID/Logo/dedicated Govt-ID/Org-ID QR/barcode variants.
  describe "gap-fill tokens" do
    let(:gap_fill_badge) do
      build(:badge, account: account, event: event, content: <<~HTML)
        <div>
          <span class="title">$TITLE$</span>
          <span class="first-name">$FIRST_NAME$</span>
          <span class="last-name">$LAST_NAME$</span>
          <span class="designation">$DESIGNATION$</span>
          <span class="org-id">$ORG_ID$</span>
          <span class="govt-id">$GOVT_ID$</span>
          <img class="logo" src="$LOGO$" />
          <img class="qr-govt" src="$QRCODE_GOVT_ID$" />
          <img class="qr-org" src="$QRCODE_ORG_ID$" />
          <img class="barcode-govt" src="$BARCODE_GOVT_ID$" />
          <img class="barcode-org" src="$BARCODE_ORG_ID$" />
        </div>
      HTML
    end

    it "substitutes the new text tokens from their respective Participant columns" do
      participant = create(:participant, account: account, event: event,
        title: "Dr.", first_name: "Jane", last_name: "Doe", position: "Engineer", govt_id: "GID123")

      html = described_class.render(badge: gap_fill_badge, participant: participant)

      expect(html).to include("<span class=\"title\">Dr.</span>")
      expect(html).to include("<span class=\"first-name\">Jane</span>")
      expect(html).to include("<span class=\"last-name\">Doe</span>")
      expect(html).to include("<span class=\"designation\">Engineer</span>")
      expect(html).to include("<span class=\"org-id\">#{participant.client_participant_id}</span>")
      expect(html).to include("<span class=\"govt-id\">GID123</span>")
    end

    it "substitutes $LOGO$ with a blank transparent pixel when the badge has no logo attached" do
      participant = create(:participant, account: account, event: event)

      html = described_class.render(badge: gap_fill_badge, participant: participant)
      png = ChunkyPNG::Image.from_blob(data_uri_bytes(html, "logo"))

      expect(ChunkyPNG::Color.a(png[0, 0])).to eq(0)
    end

    it "substitutes $LOGO$ with the badge's actual attached logo" do
      participant = create(:participant, account: account, event: event)
      logo_badge = create(:badge, account: account, event: event, content: gap_fill_badge.content)
      png_bytes = ChunkyPNG::Image.new(2, 2, ChunkyPNG::Color::WHITE).to_blob
      logo_badge.logo.attach(io: StringIO.new(png_bytes), filename: "logo.png", content_type: "image/png")

      html = described_class.render(badge: logo_badge, participant: participant)

      expect(data_uri_bytes(html, "logo")).to eq(png_bytes)
    end

    it "substitutes $LOGO$ with a visible sample placeholder (sample: true) when the badge has no logo attached" do
      participant = create(:participant, account: account, event: event)

      html = described_class.render(badge: gap_fill_badge, participant: participant, sample: true)
      png = ChunkyPNG::Image.from_blob(data_uri_bytes(html, "logo"))

      expect(ChunkyPNG::Color.a(png[0, 0])).to be > 0
    end

    it "still prefers a real attached logo over the sample placeholder" do
      participant = create(:participant, account: account, event: event)
      logo_badge = create(:badge, account: account, event: event, content: gap_fill_badge.content)
      png_bytes = ChunkyPNG::Image.new(2, 2, ChunkyPNG::Color::WHITE).to_blob
      logo_badge.logo.attach(io: StringIO.new(png_bytes), filename: "logo.png", content_type: "image/png")

      html = described_class.render(badge: logo_badge, participant: participant, sample: true)

      expect(data_uri_bytes(html, "logo")).to eq(png_bytes)
    end

    it "encodes govt_id (not hex_id) into $QRCODE_GOVT_ID$/$BARCODE_GOVT_ID$, distinct from the generic $QRCODE$/$BARCODE$" do
      participant = create(:participant, account: account, event: event, govt_id: "GID123")

      html = described_class.render(badge: gap_fill_badge, participant: participant)

      expect(data_uri_bytes(html, "qr-govt")[0, 8].bytes).to eq([ 137, 80, 78, 71, 13, 10, 26, 10 ])
      expect(data_uri_bytes(html, "barcode-govt")[0, 8].bytes).to eq([ 137, 80, 78, 71, 13, 10, 26, 10 ])
    end

    it "encodes client_participant_id into $QRCODE_ORG_ID$/$BARCODE_ORG_ID$" do
      participant = create(:participant, account: account, event: event)

      html = described_class.render(badge: gap_fill_badge, participant: participant)

      expect(data_uri_bytes(html, "qr-org")[0, 8].bytes).to eq([ 137, 80, 78, 71, 13, 10, 26, 10 ])
      expect(data_uri_bytes(html, "barcode-org")[0, 8].bytes).to eq([ 137, 80, 78, 71, 13, 10, 26, 10 ])
    end

    it "leaves the existing $QRCODE$/$BARCODE$ tokens' meaning unchanged (hex_id / govt_id-or-fallback)" do
      participant = create(:participant, account: account, event: event, govt_id: "GID123")

      html = described_class.render(badge: badge, participant: participant)

      expect(data_uri_bytes(html, "qr")[0, 8].bytes).to eq([ 137, 80, 78, 71, 13, 10, 26, 10 ])
      expect(data_uri_bytes(html, "barcode")[0, 8].bytes).to eq([ 137, 80, 78, 71, 13, 10, 26, 10 ])
    end
  end
end
