# Phase 23 — Audit Log & Super Admin Impersonation (doc/implementation_3.md). Append-only —
# created exclusively through AuditLog.record! (app/services/audit_log.rb), the single entry point
# every SuperAdmin:: controller action that touches tenant data calls, same "one call-site shape"
# precedent Notifier already established for mailer/WhatsApp sends. Never construct/update one
# directly from a controller. No updated_at column at all (this table's own migration comment) —
# Rails' normal timestamp handling only ever touches columns that actually exist, so created_at
# still auto-populates on create with no override needed here; there's simply nothing for an
# update to touch.
class AuditLogEntry < ApplicationRecord
  belongs_to :actor, class_name: "User"
  belongs_to :target, polymorphic: true, optional: true

  validates :action, presence: true
end
