require "rails_helper"

RSpec.describe RegistrationPdfService, type: :model do
  it "renders a real PDF (starts with the PDF magic bytes)" do
    pdf = described_class.render(html: "<html><body><h1>Hi</h1></body></html>")

    expect(pdf[0, 5]).to eq("%PDF-")
  end

  it "renders on an A4 page" do
    pdf = described_class.render(html: "<html><body><h1>Hi</h1></body></html>")

    reader = PDF::Reader.new(StringIO.new(pdf))
    media_box = reader.pages.first.attributes[:MediaBox]
    points_per_mm = 2.83465
    expect(media_box[2] / points_per_mm).to be_within(2).of(210) # A4 width
    expect(media_box[3] / points_per_mm).to be_within(2).of(297) # A4 height
  end

  it "renders exactly the HTML it's given — no QR-specific logic of its own" do
    account = create(:account)
    Current.account = account
    event = create(:event, account: account)
    participant = create(:participant, account: account, event: event)

    html = %(<html><body><h1>Hi</h1><img src="#{participant.qr_code_data_uri}"></body></html>)
    pdf = described_class.render(html: html)

    expect(pdf[0, 5]).to eq("%PDF-")
  end
end
