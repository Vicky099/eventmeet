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

  describe "GET /platform/event_reviews/:id (full event detail for the approval decision)" do
    before { sign_in staff, scope: :platform_staff }

    it "shows ticket categories, badges, speakers, and agenda alongside the basic event summary" do
      event = create_event(name: "Detail Check")
      Current.account = account
      category = create(:ticket_category, account: account, event: event, name: "VIP", total_count: 50)
      badge = create(:badge, account: account, event: event, ticket_category: nil, name: "Default Badge")
      speaker = create(:speaker, account: account, event: event, name: "Ada Lovelace", company: "Analytical Engines")
      session = create(:session, account: account, event: event, name: "Keynote Hall")
      create(:schedule, account: account, event: event, session: session, speaker: speaker, title: "Opening Talk")

      get platform_event_review_path(event)

      expect(response.body).to include("VIP")
      expect(response.body).to include(category.total_count.to_s)
      expect(response.body).to include(badge.name)
      expect(response.body).to include("Ada Lovelace")
      expect(response.body).to include("Analytical Engines")
      expect(response.body).to include("Keynote Hall")
      expect(response.body).to include("Opening Talk")
    end

    # Regression: `image_tag(attachment)` 500s the moment it's exercised against a real attached
    # photo ("no implicit conversion of ActiveStorage::Attached::One into String"), compounded by
    # this app's config/cloudinary.yml `enhance_image_tag: true` mangling any URL string fed to
    # image_tag instead — this speaker roster's own photo thumbnail was never exercised against a
    # real attached photo in any spec until now. super_admin/event_reviews/show.html.erb renders a
    # plain <img> via `tag.img src: speaker.photo.url` instead.
    it "renders a speaker's photo thumbnail without error" do
      event = create_event
      Current.account = account
      speaker = create(:speaker, account: account, event: event)
      speaker.photo.attach(io: StringIO.new("fake photo"), filename: "photo.png", content_type: "image/png")

      get platform_event_review_path(event)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<img")
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

    it "does not publish the event — that's the tenant's own subsequent manual step" do
      event = create_event
      expect(event.published?).to be false

      post approve_platform_event_review_path(event)

      event = Event.unscoped_across_tenants { event.reload }
      expect(event.published?).to be false
      follow_redirect!
      expect(response.body).not_to include("published")
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

    # Phase 13 — Communications (requirement.md §5.2, §5.10): "the organizer is notified by email
    # and WhatsApp." Two owners → four Notification rows (one per owner per channel), each tracked
    # independently — the WhatsApp send fails in this test environment (no Gupshup credential
    # configured at all), which must NOT prevent either owner's email from still going out.
    it "tracks an email and a WhatsApp Notification per owner, and the WhatsApp failure doesn't block email" do
      event = create_event(name: "Needs Work")
      owner_a = create(:user, email: "owner-a@acme.example", contact_num: "+15550100")
      owner_b = create(:user, email: "owner-b@acme.example", contact_num: "+15550101")
      create(:account_membership, user: owner_a, account: account, role: :owner)
      create(:account_membership, user: owner_b, account: account, role: :owner)

      perform_enqueued_jobs do
        post reject_platform_event_review_path(event), params: { rejection_reason: "Missing venue address" }
      end

      notifications = Notification.unscoped_across_tenants { Notification.where(notifiable: event) }
      expect(notifications.count).to eq(4)
      expect(notifications.email.pluck(:to)).to contain_exactly("owner-a@acme.example", "owner-b@acme.example")
      expect(notifications.email.pluck(:status)).to all(eq("sent"))
      expect(notifications.whatsapp.pluck(:to)).to contain_exactly("+15550100", "+15550101")
      expect(notifications.whatsapp.pluck(:status)).to all(eq("failed")) # no Gupshup credential in test
      expect(ActionMailer::Base.deliveries.map(&:to).flatten).to include("owner-a@acme.example", "owner-b@acme.example")
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
