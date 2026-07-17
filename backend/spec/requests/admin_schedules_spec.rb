require "rails_helper"

# Phase 11 — Agenda, Speakers & Sessions (requirement.md §3.8). #index is the wizard's Event
# Schedule step content — the full day/track timetable (each session's talks, plus any
# room-less standalone ones).
RSpec.describe "Admin Console schedules (talks)", type: :request do
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
    before { sign_in_with_role(:owner) }

    it "never shows another tenant's talk" do
      other_account = create(:account)
      Current.account = other_account
      other_event = create(:event, account: other_account)
      other_speaker = create(:speaker, account: other_account, event: other_event)
      other_schedule = create(:schedule, account: other_account, event: other_event, speaker: other_speaker, title: "Other Tenant's Talk")

      event = create_event

      get edit_admin_event_schedule_path(event, other_schedule)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "role permissions" do
    it "finance_readonly cannot create a talk" do
      sign_in_with_role(:finance_readonly)
      event = create_event
      Current.account = account
      speaker = create(:speaker, account: account, event: event)

      post admin_event_schedules_path(event), params: {
        schedule: { title: "Keynote", speaker_id: speaker.id, starts_at: 1.day.from_now, ends_at: 1.day.from_now + 1.hour }
      }

      expect(response).to redirect_to(user_root_path)
    end
  end

  describe "POST /admin/events/:event_id/schedules (overlap warning, requirement.md Phase 11 checklist)" do
    before { sign_in_with_role(:owner) }

    it "saves successfully even when the speaker is double-booked, with a warning in the flash, back on the wizard's Event Schedule step" do
      event = create_event
      Current.account = account
      speaker = create(:speaker, account: account, event: event)
      create(:schedule, account: account, event: event, speaker: speaker,
        starts_at: 1.day.from_now, ends_at: 1.day.from_now + 1.hour)

      post admin_event_schedules_path(event), params: {
        schedule: {
          title: "Overlapping Talk", speaker_id: speaker.id,
          starts_at: 1.day.from_now + 30.minutes, ends_at: 1.day.from_now + 90.minutes
        }
      }

      expect(response).to redirect_to(edit_admin_event_path(event, step: "event_schedule"))
      follow_redirect!
      expect(response.body).to include("overlapping time")
      Current.account = account
      expect(Schedule.where(title: "Overlapping Talk")).to exist
    end
  end

  # Phase 11 checklist Manual QA: "build a 2-day, 2-track agenda with overlapping sessions in
  # different tracks, confirm the grid renders correctly" — made into a repeatable check. Moved
  # here from admin_event_sessions_spec.rb once Sessions/Event Schedule became distinct steps —
  # the combined day/track/talks timetable is this step's content now, not the plain Sessions list.
  describe "GET /admin/events/:event_id/schedules (the time-grid)" do
    before { sign_in_with_role(:owner) }

    it "groups a 2-day, 2-track agenda by day and by track" do
      event = create_event
      Current.account = account
      day1 = 1.day.from_now.change(hour: 10)
      day2 = 2.days.from_now.change(hour: 10)
      create(:session, account: account, event: event, name: "Day1 Track A Session", track: "Track A", starts_at: day1, ends_at: day1 + 1.hour)
      create(:session, account: account, event: event, name: "Day1 Track B Session", track: "Track B", starts_at: day1, ends_at: day1 + 1.hour)
      create(:session, account: account, event: event, name: "Day2 Track A Session", track: "Track A", starts_at: day2, ends_at: day2 + 1.hour)
      create(:session, account: account, event: event, name: "Day2 Track B Session", track: "Track B", starts_at: day2, ends_at: day2 + 1.hour)

      get admin_event_schedules_path(event)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(day1.strftime("%A, %B"))
      expect(response.body).to include(day2.strftime("%A, %B"))
      expect(response.body).to include("Track A")
      expect(response.body).to include("Track B")
      expect(response.body).to include("Day1 Track A Session")
      expect(response.body).to include("Day2 Track B Session")
    end

    it "lists talks with no session under a separate section" do
      event = create_event
      Current.account = account
      speaker = create(:speaker, account: account, event: event)
      create(:schedule, account: account, event: event, speaker: speaker, session: nil, title: "Standalone Keynote")

      get admin_event_schedules_path(event)

      expect(response.body).to include("Standalone Keynote")
    end
  end
end
