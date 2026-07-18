require "rails_helper"

RSpec.describe EmailTemplate, type: :model do
  let(:account) { create(:account) }
  let(:event) { create(:event, account: account) }

  before { Current.account = account }

  it "is valid with the factory defaults" do
    expect(build(:email_template, event: event, account: account)).to be_valid
  end

  it "requires a subject" do
    expect(build(:email_template, event: event, account: account, subject: nil)).not_to be_valid
  end

  it "requires html_body" do
    expect(build(:email_template, event: event, account: account, html_body: nil)).not_to be_valid
  end

  it "only allows one row per kind per event" do
    create(:email_template, event: event, account: account, kind: :participant_registration)

    duplicate = build(:email_template, event: event, account: account, kind: :participant_registration)

    expect(duplicate).not_to be_valid
  end

  # Phase 13 — Communications, revisited: "create one add-on kind where we can send any email to
  # the participants" — a second kind, alongside :participant_registration, distinguished only by
  # never firing automatically (nothing in the app calls ParticipantMailer#quick_email except
  # QuickEmailSendJob, which only ever runs on an explicit admin click).
  it "allows both kinds on the same event, independently" do
    create(:email_template, event: event, account: account, kind: :participant_registration)

    expect(build(:email_template, event: event, account: account, kind: :quick_send)).to be_valid
  end

  it "allows the same kind across different events, even within the same account" do
    other_event = create(:event, account: account)
    create(:email_template, event: event, account: account, kind: :participant_registration)

    expect(build(:email_template, event: other_event, account: account, kind: :participant_registration)).to be_valid
  end

  it "defaults to active" do
    expect(create(:email_template, event: event, account: account)).to be_active
  end

  describe "#label and #placeholders" do
    it "resolves from EmailTemplate::KIND_LABELS/KIND_PLACEHOLDERS for a known kind" do
      template = build(:email_template, event: event, account: account, kind: :participant_registration)

      expect(template.label).to eq("Participant Registration Confirmation")
      expect(template.placeholders).to include("EVENT_NAME", "LOGO")
    end

    it "resolves :quick_send to its own label, sharing GENERIC_PLACEHOLDERS" do
      template = build(:email_template, event: event, account: account, kind: :quick_send)

      expect(template.label).to eq("Quick Email")
      expect(template.placeholders).to eq(EmailTemplate::GENERIC_PLACEHOLDERS)
    end
  end

  # Phase 13 — Communications, revisited: "Participant Registration Confirmation needed in the
  # quick send" — always offered in the "Quick Email Send" modal, unlike :quick_send, which needs
  # a configured row first (Admin::EmailTemplatesController#sendable_kind?).
  describe "::ALWAYS_SENDABLE_KINDS" do
    it "includes :participant_registration but not :quick_send" do
      expect(EmailTemplate::ALWAYS_SENDABLE_KINDS).to include("participant_registration")
      expect(EmailTemplate::ALWAYS_SENDABLE_KINDS).not_to include("quick_send")
    end
  end
end
