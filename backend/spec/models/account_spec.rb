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

  # requirement.md revisit: "While registering the Tenant, we should capture ... contact email,
  # contact num ... sender email." on: :create only — see this validation's own comment.
  describe "tenant intake fields (contact_email/contact_num/sender_email)" do
    it "requires all three on create" do
      account = build(:account, contact_email: nil, contact_num: nil, sender_email: nil)

      expect(account).not_to be_valid
      expect(account.errors[:contact_email]).to be_present
      expect(account.errors[:contact_num]).to be_present
      expect(account.errors[:sender_email]).to be_present
    end

    it "rejects a malformed contact_email or sender_email" do
      account = build(:account, contact_email: "not-an-email", sender_email: "also-not-an-email")

      expect(account).not_to be_valid
      expect(account.errors[:contact_email]).to be_present
      expect(account.errors[:sender_email]).to be_present
    end

    it "does not require them on update — an account provisioned before this feature existed can still be edited" do
      account = create(:account)
      account.update_columns(contact_email: nil, contact_num: nil, sender_email: nil) # bypass validations, simulating a legacy row

      account.name = "Renamed"

      expect(account).to be_valid
    end
  end

  # requirement.md revisit: "we should capture the event timezone and all the dates which are
  # display in the UI should abey the tenant timezone."
  describe "time_zone" do
    it "defaults to UTC" do
      expect(Account.new.time_zone).to eq("UTC")
    end

    it "is required, even on update (unlike the contact fields above)" do
      account = create(:account)
      account.time_zone = nil

      expect(account).not_to be_valid
      expect(account.errors[:time_zone]).to be_present
    end

    it "rejects a value that isn't a real Rails timezone name" do
      account = build(:account, time_zone: "Not A Real Zone")

      expect(account).not_to be_valid
      expect(account.errors[:time_zone]).to be_present
    end

    it "accepts any real Rails timezone name" do
      expect(build(:account, time_zone: "Chennai")).to be_valid
    end
  end

  # requirement.md revisit: "While registering the Tenant, we should capture ... Logo."
  describe "#attach_logo" do
    def fixture_upload
      Tempfile.create([ "logo", ".png" ]) do |tempfile|
        tempfile.binmode
        tempfile.write("fake logo bytes")
        tempfile.rewind
        return Rack::Test::UploadedFile.new(tempfile.path, "image/png")
      end
    end

    it "attaches an uploaded file" do
      account = create(:account)

      account.attach_logo(fixture_upload)

      expect(account.logo).to be_attached
    end

    it "does nothing when given a blank value" do
      account = create(:account)

      expect { account.attach_logo(nil) }.not_to raise_error
      expect(account.logo).not_to be_attached
    end
  end
end
