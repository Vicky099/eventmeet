require "rails_helper"

# Phase 5 — Event Approval Workflow. Phase 13 changed #rejected to take an explicit `to:` (one
# recipient), not derive "every owner" internally — see the mailer's own comment for why
# (Notifier invokes this action once per intended recipient; deriving the full list inside would
# duplicate-send to everyone on every other owner's own call).
RSpec.describe EventMailer, type: :mailer do
  let(:account) { create(:account, subdomain_slug: "acme") }
  let(:event) { create(:event, account: account, name: "Annual Meetup") }

  before { Current.account = account }

  describe "#rejected" do
    let(:mail) { described_class.rejected(event.tap { |e| e.update!(rejection_reason: "Missing venue address") }, "owner@acme.example") }

    it "addresses and subjects the mail to exactly the given recipient" do
      expect(mail.to).to eq([ "owner@acme.example" ])
      expect(mail.subject).to include("Annual Meetup")
    end

    it "includes the rejection reason and a link to resubmit" do
      expect(mail.html_part.body.to_s).to include("Missing venue address")
      expect(mail.html_part.body.to_s).to include("edit")
    end
  end
end
