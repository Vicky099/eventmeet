# requirement.md §3.10, §4.7: sent once, at tenant-provisioning time (Phase 2,
# app/services/account_provisioning.rb) — the new tenant admin's only way to learn their
# subdomain URL and temp password, since there's no self-serve sign-up to discover either.
class AccountMailer < ApplicationMailer
  def welcome(user, account, temp_password)
    @user = user
    @account = account
    @temp_password = temp_password
    # See ApplicationMailer#default_url_options — required so every URL in this email (the
    # sign-in link) resolves to this Account's own subdomain, not the platform-wide default host.
    @tenant_account = account

    mail(to: user.email, subject: "Welcome to EventMeet — #{account.name} is ready")
  end
end
