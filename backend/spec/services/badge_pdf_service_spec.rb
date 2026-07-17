require "rails_helper"

RSpec.describe BadgePdfService, type: :model do
  let(:account) { create(:account) }
  let(:event) { create(:event, account: account) }
  let(:participant) { create(:participant, account: account, event: event) }

  before { Current.account = account }

  it "renders a PDF sized to the badge's configured physical dimensions" do
    badge = create(:badge, account: account, event: event, width_cm: 8.5, height_cm: 5.4)

    pdf = described_class.render(badge: badge, participant: participant)

    reader = PDF::Reader.new(StringIO.new(pdf))
    media_box = reader.pages.first.attributes[:MediaBox]
    points_per_cm = 28.3465
    expect(media_box[2] / points_per_cm).to be_within(0.2).of(8.5)
    expect(media_box[3] / points_per_cm).to be_within(0.2).of(5.4)
  end

  # **Bug fix**: badge.background_image was uploaded and stored since Phase 8 but never actually
  # applied anywhere — genuinely inert. Asserting on the rendered PDF's byte size is a coarse but
  # honest check (a real image encoded into the page makes it meaningfully bigger); the JPEG/PNG
  # bytes themselves get re-encoded by Chrome's PDF renderer, so byte-for-byte content comparison
  # isn't meaningful the way it is for BadgeReformService's own HTML-level data-URI assertions.
  describe "background_image" do
    it "produces a larger PDF once a background image is attached, proving it's actually rendered" do
      badge = create(:badge, account: account, event: event)
      without_background = described_class.render(badge: badge, participant: participant)

      png_bytes = ChunkyPNG::Image.new(50, 50, ChunkyPNG::Color.rgb(200, 50, 50)).to_blob
      badge.background_image.attach(io: StringIO.new(png_bytes), filename: "bg.png", content_type: "image/png")
      with_background = described_class.render(badge: badge, participant: participant)

      expect(with_background.bytesize).to be > without_background.bytesize
    end

    it "renders normally (no error) when no background image is attached" do
      badge = create(:badge, account: account, event: event)

      expect { described_class.render(badge: badge, participant: participant) }.not_to raise_error
    end

    # **Bug fix**: "in preview it is looking perfect but then i download it in pdf the background
    # image is not looks good." The Grover `width`/`height` options (asserted above) only set the
    # PDF's *paper* size — they don't constrain the *layout viewport* Puppeteer renders the page
    # at before printing, so `background-size: cover` was being computed against Puppeteer's own
    # default viewport (an unrelated aspect ratio), cropping the background into the wrong frame
    # even though the badge editor canvas and Admin::BadgesController#preview (which both size
    # their own body/iframe explicitly) looked correct. body now carries an explicit width/height
    # matching the badge's own physical size, same as that preview modal already does.
    it "sizes body to the badge's own physical dimensions, not just the PDF paper size" do
      badge = create(:badge, account: account, event: event, width_cm: 8.5, height_cm: 5.4)
      service = described_class.new(badge: badge, participant: participant)

      html = service.send(:wrap_html, "<div></div>")

      expect(html).to include("width:8.5cm;height:5.4cm;")
    end
  end
end
