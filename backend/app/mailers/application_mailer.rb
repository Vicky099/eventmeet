class ApplicationMailer < ActionMailer::Base
  default from: "from@example.com"
  layout "mailer"

  # requirement.md §4.3: mail generated during a tenant request (e.g. Devise's reset-password
  # email, §4.9 item 1) must link back to that tenant's own subdomain, not the single static host
  # config.action_mailer.default_url_options provides platform-wide.
  #
  # All mail delivers via Sidekiq (deliver_later) — Current.account/Current.platform_request are
  # request-scoped and do NOT survive into the job's own process, so they're not a reliable source
  # here except as a same-request synchronous-delivery fallback. The reliable channel is explicit
  # instance variables set *before* `mail(...)` is called, inside whichever mailer action needs
  # them — @tenant_account/@tenant_platform_request — passed as real (GlobalID-serializable) job
  # arguments rather than ambient state. DeviseMailer (app/mailers/devise_mailer.rb) is the
  # existing example; any future mailer needing this should follow the same pattern:
  #   def some_notification(user, account)
  #     @tenant_account = account
  #     mail(to: user.email, subject: "...")
  #   end
  def default_url_options
    base = self.class.default_url_options

    if @tenant_account
      base.merge(host: "#{@tenant_account.subdomain_slug}.#{Rails.application.config.x.platform_domain}")
    elsif @tenant_platform_request
      base.merge(host: Rails.application.config.x.platform_domain)
    elsif Current.account
      base.merge(host: "#{Current.account.subdomain_slug}.#{Rails.application.config.x.platform_domain}")
    elsif Current.platform_request
      base.merge(host: Rails.application.config.x.platform_domain)
    else
      base
    end
  end
end
