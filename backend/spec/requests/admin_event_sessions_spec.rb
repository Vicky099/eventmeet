require "rails_helper"

# Phase 11 — Agenda, Speakers & Sessions (requirement.md §3.8, §5.6). Exercises
# Admin::EventSessionsController (routed as "sessions", named EventSessionsController to avoid
# colliding with Admin::SessionsController — Devise's login controller — see config/routes.rb).
#
# #index is a focused list of this event's own sessions (room/track/capacity) — the combined
# day/track timetable *with* talks lives on the separate Event Schedule step/Admin::SchedulesController
# now (see spec/requests/admin_schedules_spec.rb for that coverage), since the user asked for
# Sessions/Speaker/Event Schedule as three distinct wizard steps, not one combined agenda page.
RSpec.describe "Admin Console sessions (agenda)", type: :request do
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

    it "never lists another tenant's sessions" do
      other_account = create(:account)
      Current.account = other_account
      other_event = create(:event, account: other_account)
      create(:session, account: other_account, event: other_event, name: "Other Tenant's Session")

      event = create_event

      get admin_event_sessions_path(event)

      expect(response.body).not_to include("Other Tenant's Session")
    end
  end

  describe "role permissions" do
    it "event_manager can create a session, redirected back into the wizard's Sessions step (not a separate manage page)" do
      sign_in_with_role(:event_admin)
      event = create_event

      post admin_event_sessions_path(event), params: {
        session: { name: "Room A", starts_at: 1.day.from_now, ends_at: 1.day.from_now + 1.hour }
      }

      expect(response).to redirect_to(edit_admin_event_path(event, step: "sessions"))
    end

    it "finance_readonly cannot create a session" do
      sign_in_with_role(:admin_staff)
      event = create_event

      post admin_event_sessions_path(event), params: {
        session: { name: "Room A", starts_at: 1.day.from_now, ends_at: 1.day.from_now + 1.hour }
      }

      expect(response).to redirect_to(user_root_path)
    end
  end

  describe "GET /admin/events/:event_id/sessions" do
    before { sign_in_with_role(:event_admin) }

    it "lists this event's own sessions" do
      event = create_event
      Current.account = account
      create(:session, account: account, event: event, name: "Keynote Hall", track: "Track A")

      get admin_event_sessions_path(event)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Keynote Hall")
      expect(response.body).to include("Track A")
    end
  end

  describe "DELETE /admin/events/:event_id/sessions/:id" do
    before { sign_in_with_role(:event_admin) }

    it "refuses to remove a session with real check-in history, back on the wizard's Sessions step" do
      event = create_event
      Current.account = account
      session = create(:session, account: account, event: event)
      participant = create(:participant, account: account, event: event)
      ScanService.call(event: event, identifier: participant.hex_id, scan_type: :check_in, session: session)

      delete admin_event_session_path(event, session)

      expect(response).to redirect_to(edit_admin_event_path(event, step: "sessions"))
      Current.account = account
      expect(Session.exists?(session.id)).to be true
    end
  end
end
