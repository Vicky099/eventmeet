# Phase 5 — Event Approval Workflow (requirement.md §5.2, §5.10). Phase 13 added the WhatsApp
# companion send (SuperAdmin::EventReviewsController#notify_rejection) and routed this mailer
# through Notifier/NotificationDeliveryJob for tracked pending/sent/failed delivery-state.
#
# Takes an explicit `to:` (one owner's email), not "every owner" derived internally — Notifier
# creates one Notification row per recipient per channel so each owner's delivery is tracked
# independently; deriving the full recipient list *inside* the mailer action would mean every
# owner gets emailed again on every other owner's own Notifier.email call (Notifier invokes this
# action once per intended recipient).
class EventMailer < ApplicationMailer
  def rejected(event, to)
    @event = event
    @tenant_account = event.account

    mail(to: to, subject: "#{event.name} needs changes before it can be approved")
  end
end
