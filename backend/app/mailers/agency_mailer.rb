# Agency layer (requirement.md revisit): sent once, at agency-provisioning time
# (app/services/agency_provisioning.rb) — the new agency_admin's only way to learn their temp
# password, mirrors AccountMailer#welcome. Sent directly via #deliver_later, not through
# Notifier.email (app/services/notifier.rb) — Notifier's own Notification row is TenantScoped
# (belongs_to :account, non-optional) and an Agency has no Account to attribute one to; it isn't a
# tenant-scoped event this app's Notification history is meant to track.
class AgencyMailer < ApplicationMailer
  # Fixed-hierarchy pivot (requirement.md revisit): the Agency Console is now a real subdomain with
  # its own :user login (Agency#subdomain_slug, shared devise_for :users — see
  # TenantResolvable/AgencyConsole::BaseController's own comments), so this can always point the CTA
  # straight at the agency's own sign-in page — no more "wait until a tenant exists" workaround.
  # @tenant_agency (ApplicationMailer#default_url_options' own new branch) is what resolves
  # new_user_session_url to `#{agency.subdomain_slug}.{platform_domain}/admin/login`.
  def welcome(user, agency, temp_password)
    @user = user
    @agency = agency
    @temp_password = temp_password
    @tenant_agency = agency

    mail(to: user.email, subject: "Welcome to xEvent — #{agency.name} is ready")
  end

  # AgencyMembershipProvisioning's own "existing User added to another Agency" branch — that
  # person already has working credentials elsewhere, so this is just notice, not a fresh
  # temp_password the way #welcome above is.
  def added_to_agency(user, agency)
    @user = user
    @agency = agency
    @tenant_agency = agency

    mail(to: user.email, subject: "You've been added to #{agency.name} on xEvent")
  end
end
