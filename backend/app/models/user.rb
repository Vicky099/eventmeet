class User < ApplicationRecord
  # requirement.md §6 (v6 decision): no :registerable — there is no public self-serve sign-up.
  # Every User is provisioned either by the Super Admin (tenant admins, Phase 2) or by a tenant's
  # own admins (invited teammates, Phase 4.1) — both flows create the record directly, never a
  # Devise sign-up form.
  devise :database_authenticatable, :recoverable, :rememberable, :validatable

  has_many :account_memberships, dependent: :destroy
  has_many :accounts, through: :account_memberships

  validate :platform_staff_has_no_account_memberships

  # requirement.md §4.1: platform_staff Users authenticate at the apex domain and are never a
  # member of any tenant Account.
  def platform_staff?
    platform_staff
  end

  # Devise calls this on every warden authentication attempt — login, and remember-me-cookie
  # re-auth on a fresh browser session — for BOTH scopes (:platform_staff and :user, §4.9 item 1),
  # since they share this one User model. Current.account/Current.platform_request are already
  # set by the host-resolution before_action (app/controllers/concerns) by the time this runs, so
  # this is what actually enforces "wrong console for this account" and "suspended Account" at
  # the authentication layer rather than leaving it to a controller to remember to check.
  def active_for_authentication?
    super && authorized_for_current_host?
  end

  # Kept deliberately worded identically to a wrong-password failure in devise.en.yml — doesn't
  # confirm to a guesser whether an email exists, is platform staff, or belongs to this tenant.
  def inactive_message
    authorized_for_current_host? ? super : :not_authorized_for_this_console
  end

  # Devise's default is deliver_now (synchronous, within the triggering request) — switched to
  # deliver_later (Sidekiq) so a slow/down SMTP connection never blocks a request. The one thing
  # that breaks by going async: Current.account/Current.platform_request are request-scoped
  # CurrentAttributes and do NOT survive into a Sidekiq job's own process — so the reset-password
  # email's link-back-to-this-tenant's-subdomain logic (ApplicationMailer#default_url_options)
  # would silently fall back to the static default host once mail actually renders inside the job.
  # Fixed by capturing them here — still inside the original request — and threading them through
  # as real job arguments (an ActiveRecord object in a Hash argument round-trips fine via
  # ActiveJob's GlobalID serialization), not relying on ambient state to survive the job boundary.
  # DeviseMailer (app/mailers/devise_mailer.rb) is what actually reads these back out.
  def send_devise_notification(notification, *args)
    args << {} unless args.last.is_a?(Hash)
    args.last[:tenant_account] = Current.account
    args.last[:tenant_platform_request] = Current.platform_request
    devise_mailer.send(notification, self, *args).deliver_later
  end

  private

  def authorized_for_current_host?
    if Current.platform_request
      platform_staff?
    elsif Current.account
      Current.account.active? && account_memberships.exists?(account: Current.account)
    else
      true
    end
  end

  def platform_staff_has_no_account_memberships
    return unless platform_staff? && account_memberships.any?

    errors.add(:base, "platform staff cannot hold an AccountMembership (requirement.md §4.1)")
  end
end
