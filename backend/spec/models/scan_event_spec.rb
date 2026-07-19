require "rails_helper"

RSpec.describe ScanEvent, type: :model do
  let(:account) { create(:account) }
  let(:event) { create(:event, account: account) }

  before { Current.account = account }

  it "defaults scanned_at to now when not given" do
    scan = create(:scan_event, event: event, scanned_at: nil)
    expect(scan.scanned_at).to be_within(2.seconds).of(Time.current)
  end

  it "exposes the unified scan_type/source enums (requirement.md §6 item 13)" do
    scan = create(:scan_event, event: event, scan_type: :print, source: :kiosk)
    expect(scan).to be_print
    expect(scan).to be_kiosk
  end

  it "never leaks another tenant's scan events (requirement.md §4.2)" do
    other_account = create(:account)
    Current.account = other_account
    other_event = create(:event, account: other_account)
    create(:scan_event, event: other_event, account: other_account)

    Current.account = account
    create(:scan_event, event: event, account: account)

    expect(ScanEvent.count).to eq(1)
  end
end
