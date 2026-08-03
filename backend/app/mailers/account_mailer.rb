# requirement.md §3.10, §4.7: sent once, at tenant-provisioning time (Phase 2,
# app/services/account_provisioning.rb) — the new tenant admin's only way to learn their
# subdomain URL and temp password, since there's no self-serve sign-up to discover either.
class AccountMailer < ApplicationMailer
  # role — a plain positional, not a keyword: every real call site here routes through
  # Notifier.email -> NotificationDeliveryJob#perform, which re-invokes this action as
  # `mailer_class.public_send(mailer_method, *mailer_args)` (that job's own comment) — a plain
  # splat, so a keyword arg here would never actually bind (Ruby doesn't auto-convert a trailing
  # Hash in `*args` into kwargs since 3.0), it'd raise "missing keyword: :role" instead. Required,
  # not defaulted, all the same — AccountMembershipProvisioning/AgencyConsole::
  # AccountMembershipsController#resend_invite can invite either an `event_admin` ("Admin," full
  # control) or `admin_staff` ("Staff," restricted by Account#staff_permission? — see that
  # column's own migration comment), and the email body needs to say which one this person
  # actually got, not always claim "admin" regardless (confirmed live: a Staff invite's email
  # read "you've been added as its admin," wrong and confusing for someone who's about to find
  # half the sidebar missing). AccountProvisioning's own call (a tenant's very first admin) is
  # always "event_admin" — still passed explicitly, not left to a default, so every call site says
  # what role it means in plain sight.
  def welcome(user, account, temp_password, role)
    @user = user
    @account = account
    @temp_password = temp_password
    @role_label = role.to_s == "admin_staff" ? "staff" : "admin"
    # See ApplicationMailer#default_url_options — required so every URL in this email (the
    # sign-in link) resolves to this Account's own subdomain, not the platform-wide default host.
    @tenant_account = account

    mail(to: user.email, subject: "Welcome to xEvent — #{account.name} is ready")
  end

  # AccountMembershipProvisioning's own "existing User added to another Account" branch — mirrors
  # AgencyMailer#added_to_agency exactly, one tier down: that person already has working
  # credentials elsewhere, so this is just notice, not a fresh temp_password the way #welcome
  # above is. Routed through Notifier.email (AccountMembershipProvisioning's own comment has the
  # full "why" — unlike Agency, an Account has a real Notification row to attribute this to), so
  # this is never called directly with `.deliver_later`. Same `role` reasoning as #welcome above
  # (a plain positional, not a keyword — that comment has the full "why").
  def added_to_account(user, account, role)
    @user = user
    @account = account
    # "a"/"an" baked in here, not left to the view — #welcome's own "added as its <label>" reads
    # fine with a bare noun (possessive, no article needed), but this one's own "You're now a/an
    # <label>" phrasing does need the article, and "a admin" is wrong.
    @role_phrase = role.to_s == "admin_staff" ? "a staff" : "an admin"
    @tenant_account = account

    mail(to: user.email, subject: "You've been added to #{account.name} on xEvent")
  end
end
