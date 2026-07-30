require "rails_helper"

# Phase 25 — Public Event Site API (doc/public_event_site_options.md).
RSpec.describe PublicSiteRevalidationJob, type: :job do
  let(:account) { create(:account) }
  let(:event) { create(:event, account: account) }

  before { Current.account = account }

  it "calls PublicSiteRevalidator with the event, working across the tenant boundary like other jobs" do
    expect(PublicSiteRevalidator).to receive(:call).with(event)

    described_class.perform_now(event.id)
  end

  it "does nothing for an event that no longer exists (e.g. destroyed before the job ran)" do
    event_id = event.id
    event.destroy!

    expect(PublicSiteRevalidator).not_to receive(:call)
    expect { described_class.perform_now(event_id) }.not_to raise_error
  end
end
