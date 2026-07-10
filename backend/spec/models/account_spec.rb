require "rails_helper"

RSpec.describe Account, type: :model do
  it "is valid with a name and a well-formed subdomain_slug" do
    expect(build(:account)).to be_valid
  end

  it "requires a name" do
    account = build(:account, name: nil)
    expect(account).not_to be_valid
    expect(account.errors[:name]).to be_present
  end

  it "requires a unique subdomain_slug, case-insensitively" do
    create(:account, subdomain_slug: "acme")
    duplicate = build(:account, subdomain_slug: "ACME")
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:subdomain_slug]).to be_present
  end

  it "rejects reserved-word slugs" do
    Account::RESERVED_SLUGS.each do |reserved|
      account = build(:account, subdomain_slug: reserved)
      expect(account).not_to be_valid
    end
  end

  it "rejects slugs with invalid characters" do
    account = build(:account, subdomain_slug: "not_valid!")
    expect(account).not_to be_valid
  end

  it "rejects slugs shorter than 3 characters" do
    account = build(:account, subdomain_slug: "ab")
    expect(account).not_to be_valid
  end

  it "downcases the slug before saving" do
    account = create(:account, subdomain_slug: "Acme-#{SecureRandom.hex(2)}")
    expect(account.subdomain_slug).to eq(account.subdomain_slug.downcase)
  end

  it "assigns a UUIDv7 primary key on create" do
    account = create(:account)
    expect(account.id).to match(/\A[0-9a-f-]{36}\z/)
  end
end
