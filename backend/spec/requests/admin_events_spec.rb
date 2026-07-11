require "rails_helper"

# Phase 4 — Event Lifecycle (requirement.md §3.2, §5.2).
RSpec.describe "Admin Console events", type: :request do
  let!(:account) { create(:account, subdomain_slug: "acme") }

  before { host! "acme.example.com" }

  def sign_in_with_role(role)
    user = create(:user, email: "#{role}@acme.example", password: "password123!")
    create(:account_membership, user: user, account: account, role: role)
    sign_in user, scope: :user
    user
  end

  # Current (and so Event's TenantScoped default_scope) is only set for the *duration* of a real
  # request — reset by Rails' executor once `post`/`get`/`patch` returns control to the spec (see
  # spec/support/current_attributes.rb). Any Event query in the spec body itself, before or after
  # that request, needs this — including inside a `change { ... }` block, which is why the plain
  # `change(Event, :count)` form (evaluated outside any request) can't be used here.
  def event_count
    Event.unscoped_across_tenants { Event.count }
  end

  describe "access control" do
    it "redirects an unauthenticated request to the tenant login" do
      get admin_events_path
      expect(response).to redirect_to(new_user_session_path)
    end

    # PunditAuthorizable (Phase 1) rejects with a redirect + flash, not a bare HTTP 403 — the
    # same shared infrastructure every other policy in this app already uses; "(403)" in the
    # Phase 4 checklist means "the action is blocked," not a literal status code override just
    # for this one policy.
    it "blocks checkin_staff from creating an event" do
      sign_in_with_role(:checkin_staff)

      expect {
        post admin_events_path, params: {
          event: { name: "Blocked Event", mode: "on_site", starts_at: 1.day.from_now, ends_at: 2.days.from_now, address: "123 Main St" }
        }
      }.not_to change { event_count }

      expect(response).to redirect_to(user_root_path)
      follow_redirect!
      expect(response.body).to include("not authorized")
    end

    it "blocks finance_readonly from editing an event" do
      sign_in_with_role(:finance_readonly)
      Current.account = account
      event = create(:event, account: account)

      get edit_admin_event_path(event)

      expect(response).to redirect_to(user_root_path)
    end

    it "allows event_manager to create and edit events" do
      sign_in_with_role(:event_manager)

      expect {
        post admin_events_path, params: {
          event: { name: "Manager Event", mode: "on_site", starts_at: 1.day.from_now, ends_at: 2.days.from_now, address: "123 Main St" }
        }
      }.to change { event_count }.by(1)

      event = Event.unscoped_across_tenants { Event.find_by!(name: "Manager Event") }
      Current.account = account
      get edit_admin_event_path(event)
      expect(response).to have_http_status(:ok)
    end

    it "allows owner to create and edit events" do
      sign_in_with_role(:owner)

      post admin_events_path, params: {
        event: { name: "Owner Event", mode: "on_site", starts_at: 1.day.from_now, ends_at: 2.days.from_now, address: "123 Main St" }
      }

      expect(response).to redirect_to(%r{/admin/events/owner-event/edit})
    end
  end

  describe "POST /admin/events" do
    before { sign_in_with_role(:owner) }

    it "creates the event and redirects to the wizard's first step" do
      post admin_events_path, params: {
        event: {
          name: "Annual Meetup", mode: "on_site",
          starts_at: "2026-08-01T09:00", ends_at: "2026-08-01T17:00",
          address: "123 Main St"
        }
      }

      event = Event.unscoped_across_tenants { Event.find_by!(name: "Annual Meetup") }
      expect(response).to redirect_to(edit_admin_event_path(event, step: "basic_info"))
      expect(event.account).to eq(account)
      expect(event.status).to eq("draft")
    end

    it "re-renders the form with errors when invalid" do
      expect {
        post admin_events_path, params: { event: { name: "", mode: "on_site" } }
      }.not_to change { event_count }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /admin/events/:id (wizard step save)" do
    before { sign_in_with_role(:owner) }

    it "saves the step and advances to the next one" do
      Current.account = account
      event = create(:event, account: account, name: "Original Name")

      patch admin_event_path(event), params: {
        step: "basic_info",
        event: { name: "Renamed", mode: "on_site", starts_at: event.starts_at, ends_at: event.ends_at, address: event.address }
      }

      expect(response).to redirect_to(edit_admin_event_path(event, step: "agenda"))
      expect(event.reload.name).to eq("Renamed")
    end

    it "re-renders the same step with errors when invalid, instead of advancing" do
      Current.account = account
      event = create(:event, account: account)

      patch admin_event_path(event), params: { step: "basic_info", event: { name: "" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("can&#39;t be blank")
    end

    it "normalizes participant_fields against the fixed catalog, defaulting unchecked fields to false" do
      Current.account = account
      event = create(:event, account: account, participant_fields: { "email" => true })

      patch admin_event_path(event), params: {
        event: {
          name: event.name, mode: event.mode, starts_at: event.starts_at, ends_at: event.ends_at, address: event.address,
          participant_fields: { "company" => "true" }
        }
      }

      expect(event.reload.participant_fields).to eq(
        "email" => false, "contact_num" => false, "company" => true,
        "department" => false, "position" => false, "nationality" => false, "country" => false
      )
    end
  end

  describe "POST /admin/events/:id/publish" do
    before { sign_in_with_role(:owner) }

    it "publishes a complete event and computes its current status from the schedule" do
      Current.account = account
      event = create(:event, account: account, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)

      post publish_admin_event_path(event)

      event.reload
      expect(event.published_at).to be_present
      expect(event.status).to eq("live")
      expect(response).to redirect_to(edit_admin_event_path(event, step: "review"))
    end

    it "refuses to publish an incomplete event" do
      # basic_info_complete? mirrors the same presence/location rules the model already validates
      # on every save, so a *persisted* Event can't normally fail it — stubbed here purely to
      # exercise the controller's guard branch in isolation.
      Current.account = account
      event = create(:event, account: account)
      allow_any_instance_of(Event).to receive(:basic_info_complete?).and_return(false)

      post publish_admin_event_path(event)

      expect(event.reload.published_at).to be_nil
      expect(response).to redirect_to(edit_admin_event_path(event, step: "review"))
    end

    it "reverts a published event back to draft once any content field is edited again" do
      Current.account = account
      event = create(:event, account: account, starts_at: 1.day.from_now, ends_at: 2.days.from_now)
      post publish_admin_event_path(event)
      expect(event.reload.status).to eq("up_coming")

      patch admin_event_path(event), params: {
        step: "basic_info",
        event: { name: "Edited After Publish", mode: event.mode, starts_at: event.starts_at, ends_at: event.ends_at, address: event.address }
      }

      event.reload
      expect(event.published_at).to be_nil
      expect(event.status).to eq("draft")
    end
  end

  describe "POST /admin/events/:id/submit_for_review" do
    before { sign_in_with_role(:owner) }

    it "submits a brand-new (unsubmitted) event for review, putting it in the queue for the first time" do
      Current.account = account
      event = create(:event, account: account)
      expect(event.approval_status).to eq("unsubmitted")

      post submit_for_review_admin_event_path(event)

      event.reload
      expect(event.approval_status).to eq("pending")
      expect(event.submitted_at).to be_present
      expect(response).to redirect_to(edit_admin_event_path(event, step: "review"))
    end

    it "resubmits a rejected event back to pending and clears the previous rejection" do
      Current.account = account
      event = create(:event, account: account)
      event.reject!(reason: "Fix the schedule")

      post submit_for_review_admin_event_path(event)

      event.reload
      expect(event.approval_status).to eq("pending")
      expect(event.rejection_reason).to be_nil
      expect(response).to redirect_to(edit_admin_event_path(event, step: "review"))
    end

    it "refuses to submit an incomplete event" do
      Current.account = account
      event = create(:event, account: account)
      allow_any_instance_of(Event).to receive(:basic_info_complete?).and_return(false)

      post submit_for_review_admin_event_path(event)

      expect(event.reload.approval_status).to eq("unsubmitted")
      expect(response).to redirect_to(edit_admin_event_path(event, step: "review"))
    end
  end

  describe "POST /admin/events/:id/duplicate" do
    before { sign_in_with_role(:owner) }

    it "clones name/mode/participant_fields/dates into a new draft, unsubmitted event" do
      Current.account = account
      original = create(:event, account: account, name: "Original", participant_fields: { "email" => true })

      expect {
        post duplicate_admin_event_path(original)
      }.to change { event_count }.by(1)

      clone = Event.unscoped_across_tenants { Event.find_by!(name: "Copy of Original") }
      expect(clone.mode).to eq(original.mode)
      expect(clone.participant_fields).to eq(original.participant_fields)
      expect(clone.status).to eq("draft")
      expect(clone.approval_status).to eq("unsubmitted")
      expect(response).to redirect_to(edit_admin_event_path(clone))
    end
  end

  describe "GET /admin/events (index)" do
    before { sign_in_with_role(:owner) }

    it "filters by status" do
      Current.account = account
      create(:event, account: account, name: "Draft Event")
      live = create(:event, account: account, name: "Live Event", starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      Event.unscoped_across_tenants { live.update!(status: :live) }

      get admin_events_path, params: { status: "live" }

      expect(response.body).to include("Live Event")
      expect(response.body).not_to include("Draft Event")
    end
  end

  describe "cross-tenant isolation (requirement.md §4.2)" do
    it "404s when Account A requests Account B's event by slug" do
      other_account = create(:account, subdomain_slug: "other")
      Current.account = other_account
      other_event = create(:event, account: other_account, name: "Other Tenant Event")

      sign_in_with_role(:owner)

      # config.action_dispatch.show_exceptions = :rescuable in test (config/environments/test.rb)
      # — ActiveRecord::RecordNotFound is one of Rails' own "rescuable" exceptions, rendered as a
      # real 404 response rather than propagating as a Ruby exception.
      get edit_admin_event_path(other_event.slug)

      expect(response).to have_http_status(:not_found)
    end

    it "404s on update too, not just edit" do
      other_account = create(:account, subdomain_slug: "other2")
      Current.account = other_account
      other_event = create(:event, account: other_account, name: "Other Tenant Event 2")

      sign_in_with_role(:owner)

      patch admin_event_path(other_event.slug), params: { event: { name: "Hijacked" } }

      expect(response).to have_http_status(:not_found)
    end
  end
end
