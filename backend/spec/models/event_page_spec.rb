require "rails_helper"

# Phase 25.5 — Public Event Site (doc/public_event_site_options.md, Confirmed decisions #2/#4).
RSpec.describe EventPage, type: :model do
  let(:account) { create(:account) }
  let(:event) { create(:event, account: account) }

  before { Current.account = account }

  it "is valid with the factory defaults" do
    expect(build(:event_page, event: event, account: account)).to be_valid
  end

  it "only allows one row per event" do
    create(:event_page, event: event, account: account)

    duplicate = build(:event_page, event: event, account: account)

    expect(duplicate).not_to be_valid
  end

  it "stores html verbatim, with no sanitization applied" do
    raw = %(<script>alert(1)</script><div onclick="x()">hi</div>)
    event_page = create(:event_page, event: event, account: account, html: raw)

    expect(event_page.reload.html).to eq(raw)
  end
end
