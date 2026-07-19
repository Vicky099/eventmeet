require "rails_helper"

# Phase 23 — Audit Log & Super Admin Impersonation (doc/implementation_3.md). The single entry
# point every SuperAdmin:: controller action that touches tenant/agency data calls — this spec is
# just "does .record! create the right row," same scope Notifier's own spec takes for its own
# single-entry-point shape.
RSpec.describe AuditLog do
  describe ".record!" do
    it "creates an AuditLogEntry with the given actor/action/target/metadata" do
      staff = create(:user, :platform_staff)
      agency = create(:agency)

      expect {
        described_class.record!(actor: staff, action: "agency.suspend", target: agency, metadata: { reason: "non-payment" })
      }.to change(AuditLogEntry, :count).by(1)

      entry = AuditLogEntry.last
      expect(entry.actor).to eq(staff)
      expect(entry.action).to eq("agency.suspend")
      expect(entry.target).to eq(agency)
      expect(entry.metadata).to eq("reason" => "non-payment")
    end

    it "defaults metadata to an empty hash and target to nil" do
      staff = create(:user, :platform_staff)

      described_class.record!(actor: staff, action: "impersonation.start")

      entry = AuditLogEntry.last
      expect(entry.target).to be_nil
      expect(entry.metadata).to eq({})
    end
  end
end
