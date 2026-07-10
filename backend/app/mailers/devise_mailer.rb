# Wired via `config.mailer` in config/initializers/devise.rb. Devise::Mailer's own #devise_mail
# merges the whole opts hash into the *mail headers* (subject/to/from/etc, see
# Devise::Mailers::Helpers#headers_for) — :tenant_account/:tenant_platform_request need to be
# pulled out first, or they'd end up as (harmless but meaningless) custom mail headers instead of
# reaching ApplicationMailer#default_url_options. See User#send_devise_notification for where
# these actually get set.
class DeviseMailer < Devise::Mailer
  def devise_mail(record, action, opts = {}, &block)
    @tenant_account = opts.delete(:tenant_account)
    @tenant_platform_request = opts.delete(:tenant_platform_request)
    super
  end
end
