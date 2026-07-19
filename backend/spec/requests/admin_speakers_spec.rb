require "rails_helper"

# Speaker is event-scoped — one roster per event, not a shared account-wide library (confirmed
# with user, reversing Phase 11's original design). Exercises Admin::SpeakersController, nested
# under Event the same way Admin::EventSessionsController/Admin::SchedulesController are.
RSpec.describe "Admin Console speakers", type: :request do
  let!(:account) { create(:account, subdomain_slug: "acme") }

  before { host! "acme.example.com" }

  def sign_in_with_role(role)
    user = create(:user, email: "#{role}@acme.example", password: "password123!")
    create(:account_membership, user: user, account: account, role: role)
    sign_in user, scope: :user
  end

  def create_event(**attrs)
    Current.account = account
    create(:event, account: account, **attrs)
  end

  describe "tenant scoping" do
    before { sign_in_with_role(:event_admin) }

    it "never lists another tenant's speakers" do
      other_account = create(:account)
      Current.account = other_account
      other_event = create(:event, account: other_account)
      create(:speaker, account: other_account, event: other_event, name: "Other Tenant's Speaker")

      event = create_event

      get admin_event_speakers_path(event)

      expect(response.body).not_to include("Other Tenant's Speaker")
    end

    # Regression: `image_tag(attachment)` 500s the moment it's exercised against a real attached
    # photo ("no implicit conversion of ActiveStorage::Attached::One into String"), compounded by
    # this app's config/cloudinary.yml `enhance_image_tag: true` mangling any URL string fed to
    # image_tag instead — this row's own photo thumbnail was never exercised against a real
    # attached photo in any spec until now. admin/speakers/index.html.erb renders a plain <img>
    # via `tag.img src: speaker.photo.url` instead.
    it "renders a speaker's photo thumbnail without error" do
      event = create_event
      speaker = create(:speaker, account: account, event: event)
      speaker.photo.attach(io: StringIO.new("fake photo"), filename: "photo.png", content_type: "image/png")

      get admin_event_speakers_path(event)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<img")
    end
  end

  describe "role permissions (requirement.md §5.1)" do
    it "owner can create a speaker, redirected back into the wizard's Speaker step (not a separate manage page)" do
      sign_in_with_role(:event_admin)
      event = create_event

      expect {
        post admin_event_speakers_path(event), params: { speaker: { name: "Jane Doe", company: "Acme" } }
      }.to change { Current.account = account; Speaker.count }.by(1)

      expect(response).to redirect_to(edit_admin_event_path(event, step: "speaker"))
    end

    it "finance_readonly cannot create a speaker" do
      sign_in_with_role(:admin_staff)
      event = create_event

      post admin_event_speakers_path(event), params: { speaker: { name: "Jane Doe" } }

      expect(response).to redirect_to(user_root_path)
    end
  end

  describe "DELETE /admin/events/:event_id/speakers/:id" do
    before { sign_in_with_role(:event_admin) }

    it "removes a speaker with no scheduled talks" do
      event = create_event
      Current.account = account
      speaker = create(:speaker, account: account, event: event)

      delete admin_event_speaker_path(event, speaker)

      expect(response).to redirect_to(edit_admin_event_path(event, step: "speaker"))
      Current.account = account
      expect(Speaker.exists?(speaker.id)).to be false
    end

    it "refuses to remove a speaker who already has a scheduled talk" do
      event = create_event
      Current.account = account
      speaker = create(:speaker, account: account, event: event)
      create(:schedule, account: account, event: event, speaker: speaker)

      delete admin_event_speaker_path(event, speaker)

      expect(response).to redirect_to(edit_admin_event_path(event, step: "speaker"))
      Current.account = account
      expect(Speaker.exists?(speaker.id)).to be true
    end
  end
end
