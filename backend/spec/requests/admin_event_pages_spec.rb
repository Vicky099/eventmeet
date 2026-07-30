require "rails_helper"

# Phase 25.5 — Public Event Site (doc/public_event_site_options.md, Confirmed decisions #2-#4).
# One EventPage per Event (has_one, find-or-initialize) — this event's own raw public-page HTML,
# stored and rendered exactly as submitted, no sanitization, no draft/publish step of its own.
RSpec.describe "Admin Console event pages", type: :request do
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

  describe "GET /admin/events/:event_id/event_page/edit" do
    it "renders an empty form when no row exists yet" do
      event = create_event
      sign_in_with_role(:event_admin)

      get edit_admin_event_event_page_path(event)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Event Page")
    end

    it "prefills the stored HTML when a row already exists" do
      event = create_event
      Current.account = account
      create(:event_page, event: event, account: account, html: "<h1>Already saved</h1>")
      sign_in_with_role(:event_admin)

      get edit_admin_event_event_page_path(event)

      expect(response.body).to include("Already saved")
    end
  end

  describe "PATCH /admin/events/:event_id/event_page" do
    it "creates the row on first save (no separate new/create step), scoped to this event" do
      event = create_event
      sign_in_with_role(:event_admin)

      expect {
        patch admin_event_event_page_path(event), params: { event_page: { html: "<h1>Welcome</h1>" } }
      }.to change { EventPage.unscoped_across_tenants { EventPage.count } }.by(1)

      expect(response).to redirect_to(edit_admin_event_event_page_path(event))
      Current.account = account
      expect(event.event_page.html).to eq("<h1>Welcome</h1>")
    end

    it "enqueues a public-site revalidation, doc/public_event_site_options.md's own webhook contract" do
      event = create_event
      sign_in_with_role(:event_admin)

      expect {
        patch admin_event_event_page_path(event), params: { event_page: { html: "<h1>Welcome</h1>" } }
      }.to have_enqueued_job(PublicSiteRevalidationJob).with(event.id)
    end

    it "stores markup verbatim, with no sanitization — confirmed decision, not an oversight" do
      event = create_event
      sign_in_with_role(:event_admin)

      patch admin_event_event_page_path(event),
        params: { event_page: { html: "<script>alert(1)</script><div onclick=\"x()\">hi</div>" } }

      Current.account = account
      expect(event.event_page.html).to eq(%(<script>alert(1)</script><div onclick="x()">hi</div>))
    end

    it "updates the existing row in place rather than creating a second one" do
      event = create_event
      Current.account = account
      create(:event_page, event: event, account: account, html: "<p>old</p>")
      sign_in_with_role(:event_admin)

      expect {
        patch admin_event_event_page_path(event), params: { event_page: { html: "<p>new</p>" } }
      }.not_to change { EventPage.unscoped_across_tenants { EventPage.count } }

      Current.account = account
      expect(event.event_page.reload.html).to eq("<p>new</p>")
    end

    it "leaves the event's own status/published_at untouched — no draft/publish step of its own" do
      event = create_event(status: :up_coming)
      Current.account = account
      event.update!(published_at: Time.current)
      sign_in_with_role(:event_admin)

      patch admin_event_event_page_path(event), params: { event_page: { html: "<p>hi</p>" } }

      Current.account = account
      event.reload
      expect(event.published_at).to be_present
      expect(event.status).not_to eq("draft")
    end

    it "requires event_admin" do
      event = create_event
      sign_in_with_role(:admin_staff)

      patch admin_event_event_page_path(event), params: { event_page: { html: "<p>x</p>" } }

      expect(response).to redirect_to(user_root_path)
      expect(flash[:alert]).to eq("You are not authorized to do that.")
    end

    it "blocks editing on a completed event, with the real reason in the flash" do
      event = create_event(status: :completed)
      sign_in_with_role(:event_admin)

      patch admin_event_event_page_path(event), params: { event_page: { html: "<p>x</p>" } }

      expect(response).to redirect_to(user_root_path)
      expect(flash[:alert]).to eq("#{event.name} is completed and can no longer be edited.")
    end
  end
end
