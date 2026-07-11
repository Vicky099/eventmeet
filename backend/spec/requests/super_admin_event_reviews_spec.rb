require "rails_helper"

# Phase 5 — Event Approval Workflow (requirement.md §4.7 item 2, §5.2).
RSpec.describe "Platform Console event reviews", type: :request do
  include ActiveJob::TestHelper

  let!(:staff) { create(:user, :platform_staff) }
  let!(:account) { create(:account, subdomain_slug: "acme") }

  before { host! "example.com" }

  # :pending_review — the queue only ever shows events the tenant explicitly submitted
  # (Event#submit_for_review!, approval_status: pending), not every event from creation.
  def create_event(**attrs)
    Current.account = account
    create(:event, :pending_review, account: account, **attrs)
  end

  describe "access control" do
    it "redirects a signed-out request to the Platform Console login" do
      get platform_event_reviews_path
      expect(response).to redirect_to(new_platform_staff_session_path)
    end

    it "blocks a tenant admin (not platform_staff) even for their own event" do
      event = create_event
      tenant_user = create(:user, email: "owner@acme.example")
      create(:account_membership, user: tenant_user, account: account, role: :owner)
      sign_in tenant_user, scope: :user

      get platform_event_review_path(event)

      expect(response).to redirect_to(new_platform_staff_session_path)
    end
  end

  describe "GET /platform/event_reviews" do
    before { sign_in staff, scope: :platform_staff }

    it "lists pending events oldest-submitted-first, across every tenant" do
      older = create_event(name: "Older Event", submitted_at: 2.days.ago)
      newer = create_event(name: "Newer Event", submitted_at: 1.hour.ago)
      approved = create_event(name: "Already Approved")
      Event.unscoped_across_tenants { approved.approve!(by: staff) }

      get platform_event_reviews_path

      expect(response.body.index("Older Event")).to be < response.body.index("Newer Event")
      expect(response.body).not_to include("Already Approved")
    end

    it "never lists an event the tenant hasn't submitted for review yet" do
      Current.account = account
      never_submitted = create(:event, account: account, name: "Still Being Built")

      get platform_event_reviews_path

      expect(never_submitted.approval_status).to eq("unsubmitted")
      expect(response.body).not_to include("Still Being Built")
    end
  end

  describe "POST /platform/event_reviews/:id/approve" do
    before { sign_in staff, scope: :platform_staff }

    it "approves the event and records who approved it" do
      event = create_event

      post approve_platform_event_review_path(event)

      event = Event.unscoped_across_tenants { event.reload }
      expect(event.approval_status).to eq("approved")
      expect(event.approved_by).to eq(staff)
      expect(response).to redirect_to(platform_event_reviews_path)
    end
  end

  describe "POST /platform/event_reviews/:id/reject" do
    before { sign_in staff, scope: :platform_staff }

    it "rejects the event, sets the reason, and emails the tenant owner" do
      event = create_event(name: "Needs Work")
      owner = create(:user, email: "owner@acme.example")
      create(:account_membership, user: owner, account: account, role: :owner)

      perform_enqueued_jobs do
        post reject_platform_event_review_path(event), params: { rejection_reason: "Missing venue address" }
      end

      event = Event.unscoped_across_tenants { event.reload }
      expect(event.approval_status).to eq("rejected")
      expect(event.rejection_reason).to eq("Missing venue address")
      expect(ActionMailer::Base.deliveries.last.to).to eq([ "owner@acme.example" ])
      expect(ActionMailer::Base.deliveries.last.subject).to include("Needs Work")
    end

    it "refuses to reject without a reason, and sends no email" do
      event = create_event

      post reject_platform_event_review_path(event), params: { rejection_reason: "" }

      event = Event.unscoped_across_tenants { event.reload }
      expect(event.approval_status).to eq("pending")
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end
end
