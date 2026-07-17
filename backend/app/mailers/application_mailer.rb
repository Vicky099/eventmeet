class ApplicationMailer < ActionMailer::Base
  # Brevo requires the From: address to be a verified sender on the account — same MAILER_FROM
  # env var shopmate-backend uses for its own platform-level fallback address. `.presence` (not
  # `ENV.fetch`'s default-only-if-*absent* semantics) — Figaro's config/application.yml always
  # sets the key, just to an empty string until a real value is filled in, so `ENV.fetch` would
  # never actually reach its own fallback.
  default from: -> { ENV["MAILER_FROM"].presence || "EventMeet <no-reply@eventmeet.example>" }
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

  # requirement.md revisit: "we should capture ... sender email" / "all the dates which are
  # display in the UI should abey the tenant timezone." Same @tenant_account convention
  # #default_url_options above already relies on (set explicitly, before `mail(...)` is called, by
  # every tenant-scoped mailer method — see that method's own comment for why Current.account
  # isn't reliable here) — reused for two more things a tenant-scoped email should get right:
  # the From: address (an explicit header always wins over the class-level `default from:`, so
  # this only applies when the tenant actually configured one) and the zone every date/time in the
  # rendered body appears in (mail rendering happens in Sidekiq's own process, not the original
  # request's, so nothing else would apply Account#time_zone here the way TenantResolvable does
  # for a real web request).
  def mail(headers = {}, &block)
    return super unless @tenant_account

    # `headers[:from] ||= value` (not a guarded `if value.present?`) would set the :from key to a
    # literal nil whenever the tenant hasn't configured a sender_email yet — and once :from is a
    # *present key* at all (even nil), ActionMailer treats it as explicitly provided and never
    # falls back to the class-level `default from:` above, silently sending headerless mail
    # instead of falling back the way the comment above promises.
    headers[:from] ||= @tenant_account.sender_email if @tenant_account.sender_email.present?
    Time.use_zone(@tenant_account.time_zone) { super(headers, &block) }
  end
end
