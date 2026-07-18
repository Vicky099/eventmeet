require "rails_helper"

# Phase 13 — Communications, revisited (requirement.md §3.10, §5.10): confirmed per-event, not
# per-tenant — nested under Event the same way spec/requests/admin_badges_spec.rb tests :badges.
RSpec.describe "Admin Console email templates", type: :request do
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

  describe "GET /admin/events/:event_id/email_templates" do
    it "lists every known kind, including ones with no row yet" do
      event = create_event
      sign_in_with_role(:owner)

      get admin_event_email_templates_path(event)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Participant Registration Confirmation")
      expect(response.body).to include("Quick Email")
      expect(response.body).to include("Using default")
    end

    # Phase 13 — Communications, revisited: "Quick Email Send" button/modal. "Participant
    # Registration Confirmation needed in the quick send" — it's always offered (EmailTemplate::
    # ALWAYS_SENDABLE_KINDS), even with no row configured at all, so the button/modal are always
    # enabled in practice — :quick_send is the one that stays gated behind an actual configured row.
    it "enables Quick Email Send and offers Participant Registration Confirmation even with no row configured" do
      event = create_event
      sign_in_with_role(:owner)

      get admin_event_email_templates_path(event)

      expect(response.body).to include("quick-email-send-modal")
      expect(response.body).to include(%(<option value="participant_registration">Participant Registration Confirmation</option>))
      expect(response.body).not_to include(%(<option value="quick_send">))
    end

    it "adds Quick Email to the modal once it's configured and active, not before" do
      event = create_event
      sign_in_with_role(:owner)

      get admin_event_email_templates_path(event)
      expect(response.body).not_to include(%(<option value="quick_send">))

      Current.account = account
      create(:email_template, event: event, account: account, kind: :quick_send, subject: "x", html_body: "<p>x</p>")

      get admin_event_email_templates_path(event)
      expect(response.body).to include(%(<option value="quick_send">Quick Email</option>))
    end

    it "does not offer a deactivated Quick Email template" do
      event = create_event
      Current.account = account
      create(:email_template, event: event, account: account, kind: :quick_send, active: false, subject: "x", html_body: "<p>x</p>")
      sign_in_with_role(:owner)

      get admin_event_email_templates_path(event)

      expect(response.body).not_to include(%(<option value="quick_send">))
    end
  end

  describe "GET /admin/events/:event_id/email_templates/:kind/edit" do
    it "prefills the default template when no row exists yet" do
      event = create_event
      sign_in_with_role(:owner)

      get edit_admin_event_email_template_path(event, kind: "participant_registration")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("$EVENT_NAME$")
    end

    it "404s for an unknown kind" do
      event = create_event
      sign_in_with_role(:owner)

      # ActiveRecord::RecordNotFound is one of Rails' own "rescuable" exceptions, rendered as a
      # real 404 response rather than propagating — same convention spec/requests/admin_events_spec.rb
      # and others already use for this exact case.
      get edit_admin_event_email_template_path(event, kind: "not_a_real_kind")

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /admin/events/:event_id/email_templates/:kind" do
    it "creates the row on first save (no separate new/create step), scoped to this event" do
      event = create_event
      sign_in_with_role(:owner)

      expect {
        patch admin_event_email_template_path(event, kind: "participant_registration"),
          params: { email_template: { subject: "Hi $FIRST_NAME$", html_body: "<p>Welcome</p>", active: "1" } }
      }.to change { EmailTemplate.unscoped_across_tenants { EmailTemplate.count } }.by(1)

      expect(response).to redirect_to(admin_event_email_templates_path(event))
      Current.account = account
      template = event.email_templates.sole
      expect(template.subject).to eq("Hi $FIRST_NAME$")
    end

    it "requires owner/event_manager" do
      event = create_event
      sign_in_with_role(:checkin_staff)

      patch admin_event_email_template_path(event, kind: "participant_registration"),
        params: { email_template: { subject: "x", html_body: "<p>x</p>" } }

      expect(response).to redirect_to(user_root_path)
    end

    it "does not collide with the same kind customized on a different event" do
      event = create_event
      other_event = create_event
      Current.account = account
      create(:email_template, event: other_event, account: account, kind: :participant_registration, subject: "Other event's own")
      sign_in_with_role(:owner)

      patch admin_event_email_template_path(event, kind: "participant_registration"),
        params: { email_template: { subject: "This event's own", html_body: "<p>x</p>", active: "1" } }

      expect(response).to redirect_to(admin_event_email_templates_path(event))
      Current.account = account
      expect(event.email_templates.sole.subject).to eq("This event's own")
      expect(other_event.email_templates.sole.subject).to eq("Other event's own")
    end
  end

  describe "DELETE /admin/events/:event_id/email_templates/:kind" do
    it "resets to default by removing the row" do
      event = create_event
      Current.account = account
      create(:email_template, event: event, account: account, kind: :participant_registration)
      sign_in_with_role(:owner)

      delete admin_event_email_template_path(event, kind: "participant_registration")

      expect(response).to redirect_to(admin_event_email_templates_path(event))
      Current.account = account
      expect(event.email_templates.find_by(kind: :participant_registration)).to be_nil
    end
  end

  describe "POST /admin/events/:event_id/email_templates/:kind/preview" do
    it "renders unsaved editor content against sample data and the event's own real details" do
      event = create_event(name: "Annual Meetup")
      sign_in_with_role(:owner)

      post preview_admin_event_email_template_path(event, kind: "participant_registration"),
        params: { subject: "Hi $FIRST_NAME$", html_body: "<p>$PARTICIPANT_NAME$ — $EVENT_NAME$</p>" }.to_json,
        headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["subject"]).to eq("Hi Sample")
      expect(json["html"]).to include("Sample Participant")
      expect(json["html"]).to include("Annual Meetup")
    end
  end

  # Phase 13 — Communications, revisited: "Quick Email Send" — modal submit.
  describe "POST /admin/events/:event_id/email_templates/quick_send" do
    include ActiveJob::TestHelper

    it "enqueues QuickEmailSendJob(event_id, kind) for a configured, active :quick_send template" do
      event = create_event
      Current.account = account
      create(:email_template, event: event, account: account, kind: :quick_send, subject: "x", html_body: "<p>x</p>")
      sign_in_with_role(:owner)

      expect {
        post quick_send_admin_event_email_templates_path(event), params: { kind: "quick_send" }
      }.to have_enqueued_job(QuickEmailSendJob).with(event.id, "quick_send")

      expect(response).to redirect_to(admin_event_email_templates_path(event))
      follow_redirect!
      expect(response.body).to include("Quick Email")
    end

    # Confirmed with the user: :participant_registration is selectable here too, to deliberately
    # re-blast it to everyone rather than resend it one participant at a time — "Participant
    # Registration Confirmation needed in the quick send" means this must work with *no* row
    # configured too, unlike :quick_send above.
    it "allows selecting :participant_registration with no EmailTemplate row configured at all" do
      event = create_event
      sign_in_with_role(:owner)

      expect {
        post quick_send_admin_event_email_templates_path(event), params: { kind: "participant_registration" }
      }.to have_enqueued_job(QuickEmailSendJob).with(event.id, "participant_registration")

      expect(response).to redirect_to(admin_event_email_templates_path(event))
    end

    it "does not enqueue anything and shows an alert when the selected kind isn't configured" do
      event = create_event
      sign_in_with_role(:owner)

      expect {
        post quick_send_admin_event_email_templates_path(event), params: { kind: "quick_send" }
      }.not_to have_enqueued_job(QuickEmailSendJob)

      expect(response).to redirect_to(admin_event_email_templates_path(event))
    end

    it "rejects an unknown kind" do
      event = create_event
      sign_in_with_role(:owner)

      expect {
        post quick_send_admin_event_email_templates_path(event), params: { kind: "not_a_real_kind" }
      }.not_to have_enqueued_job(QuickEmailSendJob)

      expect(response).to redirect_to(admin_event_email_templates_path(event))
    end

    it "requires owner/event_manager" do
      event = create_event
      sign_in_with_role(:checkin_staff)

      expect {
        post quick_send_admin_event_email_templates_path(event), params: { kind: "participant_registration" }
      }.not_to have_enqueued_job(QuickEmailSendJob)

      expect(response).to redirect_to(user_root_path)
    end
  end
end
