# requirement.md revisit: "client also create event but event created by client requires a
# agency approval." AgencyConsole::EventsController#approve/#reject are the only callers — sent to
# every one of the event's own Account#admin_users (the client's own event_admin roster), never
# the agency (they're the ones acting, not being notified). Routed through Notifier.email
# (AgencyConsole::EventsController's own comment has the full "why" — same reasoning
# AccountMembershipProvisioning's identical Current.set(account:) wrapper already established:
# Notification is TenantScoped, and this fires from the Agency Console, where Current.account is
# nil), so neither method here is ever called directly with `.deliver_later`.
class EventMailer < ApplicationMailer
  def approved(event, to)
    @event = event
    @tenant_account = event.account

    mail(to: to, subject: "#{event.name} approved")
  end

  def rejected(event, to)
    @event = event
    @tenant_account = event.account

    mail(to: to, subject: "#{event.name} needs changes")
  end
end
