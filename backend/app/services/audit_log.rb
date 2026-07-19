# Phase 23 — Audit Log & Super Admin Impersonation (doc/implementation_3.md). The single entry
# point every cross-tenant Super Admin action routes through — same "one call-site shape" Notifier
# already established for mailer/WhatsApp sends (app/services/notifier.rb).
#
# actor: explicit, always the real platform_staff User — during impersonation this is deliberately
# NOT the impersonated user (Admin::BaseController's own around_action passes
# current_impersonator, not current_user, for exactly this reason; see that controller's comment).
class AuditLog
  def self.record!(actor:, action:, target: nil, metadata: {})
    AuditLogEntry.create!(actor: actor, action: action, target: target, metadata: metadata)
  end
end
