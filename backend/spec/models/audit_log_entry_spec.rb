require "rails_helper"

# Phase 23 — Audit Log & Super Admin Impersonation (doc/implementation_3.md). Created exclusively
# through AuditLog.record! (spec/services/audit_log_spec.rb) — this spec covers the model's own
# validations and its append-only shape.
RSpec.describe AuditLogEntry do
  it "requires an action" do
    entry = build(:audit_log_entry, action: nil)
    expect(entry).not_to be_valid
    expect(entry.errors[:action]).to be_present
  end

  it "requires an actor" do
    entry = build(:audit_log_entry, actor: nil)
    expect(entry).not_to be_valid
  end

  it "allows a nil target (a platform-wide action with nothing specific to point at)" do
    entry = build(:audit_log_entry, target: nil)
    expect(entry).to be_valid
  end

  it "auto-populates created_at on create despite having no updated_at column at all" do
    entry = create(:audit_log_entry)
    expect(entry.created_at).to be_within(2.seconds).of(Time.current)
    expect(entry).not_to respond_to(:updated_at)
  end

  it "stores arbitrary action-specific metadata as jsonb" do
    entry = create(:audit_log_entry, metadata: { count: 3, events_remaining: 6 })
    expect(entry.reload.metadata).to eq("count" => 3, "events_remaining" => 6)
  end
end
