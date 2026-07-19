require "rails_helper"

# Tenant Admin Console "forgot password" flow (requirement.md §4.9 item 1's :recoverable module).
# Regression coverage for a real bug caught in interactive QA: both :user and :platform_staff map
# to the same User class (class_name:), and Devise::Mapping.find_scope! — used internally by every
# Devise helper that infers scope from a bare resource rather than being told explicitly, e.g. the
# mailer's edit_password_url — resolves ties to whichever devise_for was registered first
# (config/routes.rb). :users must stay registered first, or this crashes with
# `undefined method 'edit_platform_staff_password_url'` (that scope has no password routes at all).
RSpec.describe "Tenant forgot-password", type: :request do
  let!(:account) { create(:account, subdomain_slug: "acme") }
  let!(:user) { create(:user, email: "owner@acme.example") }

  before do
    create(:account_membership, user: user, account: account, role: :event_admin)
    host! "acme.example.com"
  end

  it "enqueues a reset-password email (delivered via Sidekiq, not inline) without raising" do
    expect {
      post user_password_path, params: { user: { email: user.email } }
    }.to have_enqueued_job(ActionMailer::MailDeliveryJob)

    expect(response).to redirect_to(new_user_session_path)
  end

  it "delivers a reset-password email linking to this Account's own subdomain, not a static host" do
    # perform_enqueued_jobs genuinely round-trips the job's arguments through ActiveJob's
    # serialization (GlobalID for the Account) — this is what actually exercises
    # User#send_devise_notification/DeviseMailer's job-boundary handling, not just "was a job
    # enqueued." Current.account is unset by the time this runs (a real, separate `perform` call,
    # matching what Sidekiq would do) — if the tenant-account plumbing were broken, the link would
    # silently fall back to the static default host instead of failing loudly, which is exactly
    # what this asserts against.
    perform_enqueued_jobs do
      post user_password_path, params: { user: { email: user.email } }
    end

    mail = ActionMailer::Base.deliveries.last
    expect(mail).to be_present
    link = mail.body.encoded[%r{https?://[^"\s]+/admin/password/edit\?reset_password_token=\S+}]
    expect(link).to include("acme.example.com") # ApplicationMailer#default_url_options — not a static host
  end
end
