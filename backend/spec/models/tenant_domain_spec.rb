require "rails_helper"

RSpec.describe TenantDomain, type: :model do
  it "is valid with an account and a domain" do
    expect(build(:tenant_domain)).to be_valid
  end

  it "requires a unique domain, case-insensitively" do
    create(:tenant_domain, domain: "acme.lvh.me")
    duplicate = build(:tenant_domain, domain: "ACME.lvh.me")

    expect(duplicate).not_to be_valid
  end

  it "is unverified without a verified_at timestamp" do
    domain = build(:tenant_domain, verified_at: nil)
    expect(domain).not_to be_verified
  end

  it "is verified once verified_at is set" do
    domain = build(:tenant_domain, verified_at: Time.current)
    expect(domain).to be_verified
  end
end
