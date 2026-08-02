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

  # doc/event_page_templates_plan.md, Stage 1 — nil is the existing default for every row created
  # before this column existed, and still means "Custom HTML" (the html column), not a new state.
  describe "template_key" do
    it "defaults to nil (Custom HTML) for the factory defaults" do
      expect(build(:event_page, event: event, account: account).template_key).to be_nil
    end

    it "accepts each of the 4 template values" do
      EventPage.template_keys.each_key do |key|
        event_page = build(:event_page, event: event, account: account, template_key: key)

        expect(event_page).to be_valid
        expect(event_page.template_key).to eq(key)
      end
    end

    it "rejects a template_key outside the known values" do
      expect { build(:event_page, template_key: "not_a_real_template") }.to raise_error(ArgumentError)
    end
  end
end
