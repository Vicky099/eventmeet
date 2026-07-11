# Phase 5 — Event Approval Workflow (requirement.md §5.2, §5.10). WhatsApp/Gupshup piece for the
# same notification is deferred to Phase 13, per its own dependency on Gupshup credentials —
# email-only for now, same "pending/sent/failed" delivery semantics ActionMailer's deliver_later
# already gives every mailer in this app (a dedicated delivery-log model is Phase 13/15's
# concern, once there's more than one notification type to track).
class EventMailer < ApplicationMailer
  def rejected(event)
    @event = event
    @tenant_account = event.account

    recipients = event.account.account_memberships.owner.includes(:user).map { |m| m.user.email }
    mail(to: recipients, subject: "#{event.name} needs changes before it can be approved")
  end
end
