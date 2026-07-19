# Phase 23 — Audit Log & Super Admin Impersonation (doc/implementation_3.md). Platform-level, like
# Agency/AccountSwitch — not TenantScoped, no account_id, no RLS: the whole point is it must
# survive and stay queryable regardless of which tenant (if any) the action touched, from the
# Platform Console (Current.platform_request), never a tenant subdomain.
#
# actor is always the real platform_staff User who did it — never the impersonated identity, even
# for an action taken *during* impersonation (see ImpersonationToken's own comment). target is
# polymorphic (Agency/Account/Invoice/AgencyMembership/...) — whichever record the action actually
# touched. metadata is a jsonb blob for action-specific detail that doesn't need its own column
# (an invoice rejection's reason, a grant's count) — same "jsonb blob, not a dedicated table," shape
# Event#participant_fields already established for this app's own free-form-but-structured data.
#
# created_at only, no updated_at — an append-only log that can be edited after the fact isn't an
# audit log. t.datetime :created_at directly (not t.timestamps) is what actually enforces that at
# the schema level; AuditLogEntry itself also sets ActiveRecord::Base's record_timestamps off a
# missing updated_at column gracefully (Rails only ever touches columns that exist).
class CreateAuditLogEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :audit_log_entries, id: :uuid, default: nil do |t|
      t.references :actor, null: false, type: :uuid, foreign_key: { to_table: :users }
      t.references :target, null: true, type: :uuid, polymorphic: true
      t.string :action, null: false
      t.jsonb :metadata, null: false, default: {}

      t.datetime :created_at, null: false
    end

    add_index :audit_log_entries, :action
    add_index :audit_log_entries, :created_at
  end
end
