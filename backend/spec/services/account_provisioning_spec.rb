require "rails_helper"

# requirement.md §4.1, §4.6, §4.7, §4.9 item 4 — the only way a tenant Account comes into
# existence. Companion to spec/requests/super_admin_accounts_spec.rb, which covers the
# controller/HTTP layer this service sits behind.
RSpec.describe AccountProvisioning, type: :model do
  include ActiveJob::TestHelper

  def call(name: "Acme Events", subdomain_slug: "acme-#{SecureRandom.hex(3)}", admin_email: "owner@acme.example")
    described_class.call(
      account_attributes: {
        name: name, subdomain_slug: subdomain_slug,
        contact_email: "contact@acme.example", contact_num: "+1 555 0100", sender_email: "sender@acme.example"
      },
      admin_email: admin_email
    )
  end

  it "creates the Account, an owner User with a temp password, the AccountMembership, and the Doorkeeper::Application, all associated" do
    result = call

    expect(result).to be_success
    expect(result.account).to be_persisted
    expect(result.admin_user).to be_persisted
    expect(result.admin_user.must_reset_password).to be true
    expect(result.admin_user.valid_password?(result.temp_password)).to be true

    membership = result.account.account_memberships.find_by(user: result.admin_user)
    expect(membership).to be_present
    expect(membership).to be_owner

    expect(result.account.oauth_application).to be_a(Doorkeeper::Application)
    expect(result.account.oauth_application.uid).to be_present
    expect(result.account.oauth_application.plaintext_secret).to be_present
  end

  it "enqueues exactly one welcome email to the new admin, linking to their tenant subdomain" do
    result = nil

    perform_enqueued_jobs do
      result = call(subdomain_slug: "provisioned-#{SecureRandom.hex(3)}", admin_email: "new-owner@acme.example")
    end

    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq([ "new-owner@acme.example" ])
    expect(mail.body.encoded).to include(result.temp_password)
    expect(mail.body.encoded).to include("#{result.account.subdomain_slug}.")
  end

  it "rolls back the whole transaction and does not send a welcome email when the slug is reserved" do
    result = nil

    perform_enqueued_jobs do
      result = call(subdomain_slug: "www")
    end

    expect(result).not_to be_success
    expect(result.account.errors[:subdomain_slug]).to be_present
    expect(User.exists?(email: "owner@acme.example")).to be false
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "rolls back the whole transaction when the slug is already taken by another Account" do
    create(:account, subdomain_slug: "taken")

    result = call(subdomain_slug: "taken")

    expect(result).not_to be_success
    expect(result.account.errors[:subdomain_slug]).to be_present
  end

  it "rolls back the whole transaction (including the Account) when the admin email is already taken" do
    existing = create(:user, email: "dup@example.com")
    slug = "acme-#{SecureRandom.hex(3)}"

    result = call(subdomain_slug: slug, admin_email: existing.email)

    expect(result).not_to be_success
    expect(result.account.errors[:admin_email]).to be_present
    expect(Account.exists?(subdomain_slug: slug)).to be false
  end
end
