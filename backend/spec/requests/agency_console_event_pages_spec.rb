require "rails_helper"

# doc/event_page_templates_plan.md, Stage 3 — moved off Admin::EventPagesController (deleted this
# same stage, was spec/requests/admin_event_pages_spec.rb) to the Agency Console: a tenant's own
# event_admin has no path to this screen anymore, only an agency admin does.
RSpec.describe "Agency Console event pages", type: :request do
  let!(:agency) { create(:agency, subdomain_slug: "acme-agency") }
  let!(:agency_user) { create(:user) }
  let!(:account) { create(:account, agency: agency, subdomain_slug: "acme-tenant") }

  before do
    create(:agency_membership, user: agency_user, agency: agency)
    host! "acme-agency.example.com"
    sign_in agency_user, scope: :user
  end

  def create_event(**attrs)
    Current.account = account
    event = create(:event, account: account, **attrs)
    Current.account = nil
    event
  end

  describe "GET .../event_page/edit" do
    it "renders an empty form when no row exists yet" do
      event = create_event

      get edit_agency_account_event_event_page_path(account, event)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Event Page")
    end

    it "prefills the stored HTML when a Custom HTML row already exists" do
      event = create_event
      Current.account = account
      create(:event_page, event: event, account: account, html: "<h1>Already saved</h1>")
      Current.account = nil

      get edit_agency_account_event_event_page_path(account, event)

      expect(response.body).to include("Already saved")
    end

    it "404s for an event belonging to a different agency's tenant" do
      other_agency = create(:agency, subdomain_slug: "other-agency")
      other_account = create(:account, agency: other_agency, subdomain_slug: "other-tenant")
      Current.account = other_account
      other_event = create(:event, account: other_account)
      Current.account = nil

      get edit_agency_account_event_event_page_path(other_account, other_event)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH .../event_page" do
    it "creates the row on first save (no separate new/create step), scoped to this event" do
      event = create_event

      expect {
        patch agency_account_event_event_page_path(account, event), params: { event_page: { html: "<h1>Welcome</h1>" } }
      }.to change { EventPage.unscoped_across_tenants { EventPage.count } }.by(1)

      expect(response).to redirect_to(edit_agency_account_event_event_page_path(account, event))
      Current.account = account
      expect(event.event_page.html).to eq("<h1>Welcome</h1>")
      Current.account = nil
    end

    it "enqueues a public-site revalidation, doc/public_event_site_options.md's own webhook contract" do
      event = create_event

      expect {
        patch agency_account_event_event_page_path(account, event), params: { event_page: { html: "<h1>Welcome</h1>" } }
      }.to have_enqueued_job(PublicSiteRevalidationJob).with(event.id)
    end

    it "stores Custom HTML markup verbatim, with no sanitization — confirmed decision, not an oversight" do
      event = create_event

      patch agency_account_event_event_page_path(account, event),
        params: { event_page: { html: "<script>alert(1)</script><div onclick=\"x()\">hi</div>" } }

      Current.account = account
      expect(event.event_page.html).to eq(%(<script>alert(1)</script><div onclick="x()">hi</div>))
      Current.account = nil
    end

    it "updates the existing row in place rather than creating a second one" do
      event = create_event
      Current.account = account
      create(:event_page, event: event, account: account, html: "<p>old</p>")
      Current.account = nil

      expect {
        patch agency_account_event_event_page_path(account, event), params: { event_page: { html: "<p>new</p>" } }
      }.not_to change { EventPage.unscoped_across_tenants { EventPage.count } }

      Current.account = account
      expect(event.event_page.reload.html).to eq("<p>new</p>")
      Current.account = nil
    end

    it "leaves the event's own status/published_at untouched — no draft/publish step of its own" do
      event = create_event(status: :up_coming)
      Current.account = account
      event.update!(published_at: Time.current)
      Current.account = nil

      patch agency_account_event_event_page_path(account, event), params: { event_page: { html: "<p>hi</p>" } }

      Current.account = account
      event.reload
      expect(event.published_at).to be_present
      expect(event.status).not_to eq("draft")
      Current.account = nil
    end

    # doc/event_page_templates_plan.md, Stage 1's data-model note + Stage 3's controller note:
    # a numbered template and stored Custom HTML markup are never simultaneously "live" — picking
    # a template blanks out `html` at save time (EventPage#clear_html_when_template_selected).
    it "assigning a numbered template clears any previously stored Custom HTML" do
      event = create_event
      Current.account = account
      create(:event_page, event: event, account: account, html: "<p>old custom page</p>")
      Current.account = nil

      patch agency_account_event_event_page_path(account, event), params: { event_page: { template_key: "template_3" } }

      Current.account = account
      event.event_page.reload
      expect(event.event_page.template_key).to eq("template_3")
      expect(event.event_page.html).to eq("")
      Current.account = nil
    end

    # The select's blank option ("Custom HTML") submits template_key as "" — must resolve to nil,
    # not raise or persist a bogus enum value.
    it "selecting Custom HTML from the dropdown clears any previously assigned template" do
      event = create_event
      Current.account = account
      create(:event_page, event: event, account: account, template_key: :template_2)
      Current.account = nil

      patch agency_account_event_event_page_path(account, event),
        params: { event_page: { template_key: "", html: "<p>hand-authored</p>" } }

      Current.account = account
      event.event_page.reload
      expect(event.event_page.template_key).to be_nil
      expect(event.event_page.html).to eq("<p>hand-authored</p>")
      Current.account = nil
    end

    it "404s trying to update an event belonging to a different agency's tenant" do
      other_agency = create(:agency, subdomain_slug: "other-agency")
      other_account = create(:account, agency: other_agency, subdomain_slug: "other-tenant")
      Current.account = other_account
      other_event = create(:event, account: other_account)
      Current.account = nil

      patch agency_account_event_event_page_path(other_account, other_event), params: { event_page: { html: "<p>x</p>" } }

      expect(response).to have_http_status(:not_found)
    end
  end

  # doc/event_page_templates_plan.md, Stage 3 — the route was genuinely removed, not just
  # unlinked; spec/requests/admin_events_spec.rb's own "no longer shows an Event Page nav entry
  # or route" covers the route-helper half, this covers hitting the literal old URL directly.
  it "the old tenant-side URL no longer resolves to anything" do
    event = create_event

    get "/admin/events/#{event.to_param}/event_page/edit"

    expect(response).to have_http_status(:not_found)
  end
end
