require "rails_helper"

# Phase 4 — Event Lifecycle (requirement.md §3.2, §5.2).
RSpec.describe "Admin Console events", type: :request do
  include ActiveSupport::Testing::TimeHelpers

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
      sign_in_with_role(:admin_staff)

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
      sign_in_with_role(:admin_staff)
      Current.account = account
      event = create(:event, account: account)

      get edit_admin_event_path(event)

      expect(response).to redirect_to(user_root_path)
    end

    it "allows event_admin to create and edit events" do
      sign_in_with_role(:event_admin)

      expect {
        post admin_events_path, params: {
          event: { name: "Manager Event", mode: "on_site", starts_at: 1.day.from_now, ends_at: 2.days.from_now, address: "123 Main St", map_url: "https://maps.google.com/?q=123" }
        }
      }.to change { event_count }.by(1)

      event = Event.unscoped_across_tenants { Event.find_by!(name: "Manager Event") }
      Current.account = account
      get edit_admin_event_path(event)
      expect(response).to have_http_status(:ok)
    end

    # requirement.md revisit: "once event complete the tenant can not able to edit the event" —
    # locked for event_admin too, not just a lesser role (event_admin is already the tenant's
    # highest tier, EventPolicy#update?'s own comment). Sessions/Speaker/Schedule/Badge all
    # authorize through this same Event (EventPolicy's own comment), so this one check covers all
    # of them without a dedicated test per sub-resource.
    it "blocks event_admin from editing a completed event" do
      sign_in_with_role(:event_admin)
      Current.account = account
      event = create(:event, account: account, status: :completed)

      get edit_admin_event_path(event)
      expect(response).to redirect_to(user_root_path)

      patch admin_event_path(event), params: { event: { name: "Renamed" } }
      expect(response).to redirect_to(user_root_path)
      expect(event.reload.name).not_to eq("Renamed")
    end
  end

  # Fixed-hierarchy pivot (requirement.md revisit): every tenant's Account already has an Agency
  # (spec/factories/accounts.rb's own default) — no more Quotation, no per-event Super Admin
  # review, so creation is unconditional here (Event#agency_contract_must_be_active's own dedicated
  # pool-exhaustion coverage lives in spec/models/event_spec.rb; this file only needs the
  # request-level "no quotation field, no quotation picker" surface).
  describe "POST /admin/events" do
    before { sign_in_with_role(:event_admin) }

    it "creates the event and redirects to the wizard's first step, auto-approved, consuming one agency pool slot" do
      post admin_events_path, params: {
        event: {
          name: "Annual Meetup", mode: "on_site",
          starts_at: "2026-08-01T09:00", ends_at: "2026-08-01T17:00",
          address: "123 Main St", map_url: "https://maps.google.com/?q=123"
        }
      }

      event = Event.unscoped_across_tenants { Event.find_by!(name: "Annual Meetup") }
      expect(response).to redirect_to(edit_admin_event_path(event, step: "basic_info"))
      expect(event.account).to eq(account)
      expect(event.status).to eq("draft")
      Current.account = account
      expect(account.agency.reload.events_used).to eq(1)
    end

    it "re-renders the form with errors when invalid" do
      expect {
        post admin_events_path, params: { event: { name: "", mode: "on_site" } }
      }.not_to change { event_count }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "shows New Event as a plain link, with no quotation-picker modal, on the index" do
      get admin_events_path

      expect(response.body).to include(new_admin_event_path)
      expect(response.body).not_to include("new-event-modal")
    end

    it "renders the new-event form with no quotation field" do
      get new_admin_event_path

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('name="event[quotation_id]"')
    end

    it "blocks creation once the account's agency pool is exhausted" do
      Current.account = account
      account.agency.update!(events_granted: 0, events_used: 0)
      Current.account = nil

      expect {
        post admin_events_path, params: {
          event: { name: "Overflow Event", mode: "on_site", starts_at: 1.day.from_now, ends_at: 2.days.from_now, address: "123 Main St", map_url: "https://maps.google.com/?q=123" }
        }
      }.not_to change { event_count }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /admin/events/:id (wizard step save)" do
    before { sign_in_with_role(:event_admin) }

    it "saves the step and advances to the next one" do
      Current.account = account
      event = create(:event, account: account, name: "Original Name")

      patch admin_event_path(event), params: {
        step: "basic_info",
        event: { name: "Renamed", mode: "on_site", starts_at: event.starts_at, ends_at: event.ends_at, address: event.address }
      }

      expect(response).to redirect_to(edit_admin_event_path(event, step: "sessions"))
      expect(event.reload.name).to eq("Renamed")
    end

    # Phase 14 — Reporting, Import/Export & Analytics (requirement.md §5.11): "Scheduled report
    # delivery (emailed weekly/daily summary to organizers)" — organizer opt-in.
    it "saves the scheduled_report_frequency setting" do
      Current.account = account
      event = create(:event, account: account, name: "Original Name")

      patch admin_event_path(event), params: {
        step: "basic_info",
        event: { name: "Original Name", mode: "on_site", starts_at: event.starts_at, ends_at: event.ends_at, address: event.address, scheduled_report_frequency: "weekly" }
      }

      expect(event.reload.scheduled_report_frequency).to eq("weekly")
    end

    it "re-renders the same step with errors when invalid, instead of advancing" do
      Current.account = account
      event = create(:event, account: account)

      patch admin_event_path(event), params: { step: "basic_info", event: { name: "" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("can&#39;t be blank")
    end

    # UI note: "error should show below field in red color" — inline per-field errors
    # (Bootstrap's is-invalid/invalid-feedback pair, ApplicationHelper#field_error_class/
    # #field_error_feedback), not just the form's top-of-page summary list.
    it "shows an inline invalid-feedback message directly below each field that failed validation", :aggregate_failures do
      Current.account = account
      event = create(:event, account: account, mode: :on_site)

      patch admin_event_path(event), params: {
        step: "basic_info", event: { name: "", starts_at: "", ends_at: "", mode: "on_site", address: "", map_url: "" }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body.scan("is-invalid").size).to be >= 5
      expect(response.body.scan("invalid-feedback").size).to be >= 5
    end

    # No top-of-form error summary at all (user preference) — every field shows its own error
    # inline instead.
    it "has no top-of-form error summary" do
      Current.account = account
      event = create(:event, account: account, mode: :on_site)

      patch admin_event_path(event), params: {
        step: "basic_info",
        event: { name: "", mode: "on_site" }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).not_to include("alert-danger")
      expect(response.body.scan("invalid-feedback").size).to eq(1)
    end

    # participant_fields/custom_fields_attributes are no longer writable from this step (pending
    # the ticket-category-scoped registration-form builder, Phase 7.5) — a request that still
    # sends them is simply ignored, not applied. custom_fields_attributes doesn't even refer to
    # anything on Event anymore (CustomField was rescoped onto RegistrationForm) — this proves a
    # stale client payload carrying it is silently dropped by strong params, not a 500.
    it "ignores participant_fields and custom_fields_attributes if still sent" do
      Current.account = account
      event = create(:event, account: account, participant_fields: { "email" => true })

      patch admin_event_path(event), params: {
        event: {
          name: event.name, mode: event.mode, starts_at: event.starts_at, ends_at: event.ends_at, address: event.address,
          participant_fields: [ "company" ],
          custom_fields_attributes: { "0" => { label: "Dietary Needs", field_type: "text" } }
        }
      }

      expect(response).to redirect_to(edit_admin_event_path(event, step: "sessions"))
      expect(event.reload.participant_fields).to eq("email" => true)
      expect(RegistrationForm.unscoped_across_tenants { RegistrationForm.count }).to eq(0)
    end
  end

  describe "POST /admin/events/:id/publish" do
    before { sign_in_with_role(:event_admin) }

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

    it "can be re-published after an edit reverted it" do
      Current.account = account
      event = create(:event, account: account, starts_at: 1.day.from_now, ends_at: 2.days.from_now)
      post publish_admin_event_path(event)
      patch admin_event_path(event), params: {
        step: "basic_info",
        event: { name: "Edited Again", mode: event.mode, starts_at: event.starts_at, ends_at: event.ends_at, address: event.address }
      }
      expect(event.reload.published_at).to be_nil

      post publish_admin_event_path(event)

      expect(event.reload.published_at).to be_present
    end
  end

  describe "POST /admin/events/:id/duplicate" do
    before { sign_in_with_role(:event_admin) }

    it "clones name/mode/participant_fields/dates into a new draft event, consuming another agency pool slot" do
      Current.account = account
      original = create(:event, account: account, name: "Original", participant_fields: { "email" => true })
      Current.account = nil

      expect {
        post duplicate_admin_event_path(original)
      }.to change { event_count }.by(1)

      clone = Event.unscoped_across_tenants { Event.find_by!(name: "Copy of Original") }
      expect(clone.mode).to eq(original.mode)
      expect(clone.participant_fields).to eq(original.participant_fields)
      expect(clone.status).to eq("draft")
      expect(response).to redirect_to(edit_admin_event_path(clone))
      Current.account = account
      expect(account.agency.reload.events_used).to eq(2)
    end
  end

  # Phase 7.5 — the event-workspace landing page (requirement.md §5.14 v12): distinct from #edit
  # (the creation wizard), a read-only overview reachable from the Events index and every
  # event-scoped nav entry.
  describe "GET /admin/events/:id (show)" do
    before { sign_in_with_role(:event_admin) }

    it "renders the event's own overview" do
      Current.account = account
      event = create(:event, account: account, name: "Annual Meetup")
      create(:ticket_category, account: account, event: event)

      get admin_event_path(event)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Annual Meetup")
      expect(response.body).to include(event.status.humanize)
    end

    # requirement.md revisit: "once event complete the tenant can not able to edit the event" —
    # the workspace landing page's own "Continue Setup" link back into the wizard.
    it "disables Continue Setup for a completed event" do
      Current.account = account
      event = create(:event, account: account, status: :completed)

      get admin_event_path(event)

      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css("a[href='#{edit_admin_event_path(event)}']")).to be_nil
      expect(doc.css("button").map(&:text)).to include("Continue Setup")
    end

    # requirement.md §5.14 v12: "once inside an event's own workspace, the sidebar switches to
    # that event's context" — Dashboard/Design Registration Form/Participants/Export/Import/Check
    # In, every link carrying the real event_id, replacing the account-level sidebar entirely.
    it "switches the sidebar to the event-scoped nav" do
      Current.account = account
      event = create(:event, account: account)

      get admin_event_path(event)

      expect(response.body).to include("Design Registration Form")
      expect(response.body).to include(admin_event_registration_forms_path(event))
      expect(response.body).to include(admin_event_participants_path(event))
      expect(response.body).to include(admin_event_scan_events_path(event))
    end

    # Same "back to the list" pattern shopmate-backend's own sidebar uses once a tenant is
    # selected (shared/_console_shell's back_link local) — a real link back to the Events index,
    # not just the breadcrumb.
    it "shows a back-to-Events link in the sidebar" do
      Current.account = account
      event = create(:event, account: account)

      get admin_event_path(event)

      expect(response.body).to include("Back to Events")
      expect(response.body).to include(admin_events_path)
    end

    # Same tenant-identity-card shape shopmate-backend's own sidebar shows above its back link —
    # the selected event's own name/status, not just the back link on its own. Scoped to the
    # sidebar container specifically (Nokogiri), not a bare response.body match — the event name
    # legitimately appears elsewhere on the page too (the <title> tag, the page header), so a
    # plain string-ordering check against the whole body would pass even if the sidebar card
    # itself were missing entirely.
    it "shows the selected event's name and status as an identity card above the back link" do
      Current.account = account
      event = create(:event, account: account, name: "Annual Meetup")

      get admin_event_path(event)

      sidebar = Nokogiri::HTML(response.body).at_css(".vertical-menu").text
      expect(sidebar).to include("Annual Meetup")
      expect(sidebar).to include(event.status.humanize)
      expect(sidebar.index("Annual Meetup")).to be < sidebar.index("Back to Events")
    end

    # Regression: "Registrations by Ticket Category" must reflect real Participant rows, not
    # TicketCategory#sold_count — that column is derived solely from ticket_reservations (the
    # public self-registration hold/checkout flow) and never moves for a participant added
    # straight from the admin console's own "Add Participant" form, so a category with real
    # manually-added registrations previously still showed 0.
    it "counts manually-added participants toward the ticket-category registration chart" do
      Current.account = account
      event = create(:event, account: account)
      category = create(:ticket_category, account: account, event: event, total_count: 10)
      create_list(:participant, 2, account: account, event: event, ticket_category: category)

      get admin_event_path(event)

      expect(category.reload.sold_count).to eq(0) # unaffected by manual participant creation
      expect(response.body).to include("2 / 10")
    end

    # Phase 14 — Reporting, Import/Export & Analytics (requirement.md §5.11): "registrations-over-
    # time ... check-in rate, session popularity, engagement funnel" — merged onto this same
    # landing page (renamed "Analytics" below) rather than a second, separate dashboard page.
    it "labels the event-scoped nav's own landing-page link 'Analytics', not 'Dashboard'" do
      Current.account = account
      event = create(:event, account: account)

      get admin_event_path(event)

      sidebar = Nokogiri::HTML(response.body).at_css(".vertical-menu").text
      expect(sidebar).to include("Analytics")
      expect(sidebar).not_to include("Dashboard")
    end

    it "shows registrations-over-time, an engagement funnel, and session popularity" do
      Current.account = account
      event = create(:event, account: account)
      session = create(:session, account: account, event: event, name: "Keynote Hall")
      participant = create(:participant, account: account, event: event)
      ScanService.call(event: event, identifier: participant.hex_id, scan_type: "check_in", session: session)

      get admin_event_path(event)

      expect(response.body).to include("Registrations Over Time")
      expect(response.body).to include("Engagement Funnel")
      expect(response.body).to include("Attended a Session")
      expect(response.body).to include("Session Popularity")
      expect(response.body).to include("Keynote Hall")
      expect(response.body).to include("100") # check-in rate: 1 of 1 registered
    end

    it "adds Absent to the Check-in Funnel only once the event has completed" do
      travel_to(Time.zone.local(2026, 1, 1)) do
        Current.account = account
        event = create(:event, account: account, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
        create(:participant, account: account, event: event)
        Event.unscoped_across_tenants { event.update!(status: :live) }

        get admin_event_path(event)
        expect(response.body).not_to include("Absent")

        travel 2.hours
        # A real request resets Current.account once control returns to the spec (this file's own
        # top-of-file comment on #event_count already documents this) — reset it before the next
        # non-request call needs it.
        Current.account = account
        EventCompletionService.finalize_attendance!(event)
        Event.unscoped_across_tenants { event.update!(status: :completed) }

        get admin_event_path(event)
        expect(response.body).to include("Absent")
      end
    end

    it "handles an event with no participants or sessions gracefully" do
      Current.account = account
      event = create(:event, account: account)

      get admin_event_path(event)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No registrations yet")
      expect(response.body).to include("No sessions configured yet")
    end
  end

  describe "GET /admin/events/:id/edit (wizard step rendering)" do
    before { sign_in_with_role(:event_admin) }

    # Regression: `image_tag(attachment)` 500s the moment it's exercised against a real attached
    # photo ("no implicit conversion of ActiveStorage::Attached::One into String"), compounded by
    # this app's config/cloudinary.yml `enhance_image_tag: true` mangling any URL string fed to
    # image_tag instead — the Speaker step's roster table never exercised its own photo thumbnail
    # against a real attached photo in any spec until now. admin/events/_speaker_step.html.erb
    # renders a plain <img> via `tag.img src: speaker.photo.url` instead.
    it "renders a speaker's photo thumbnail on the Speaker step without error" do
      Current.account = account
      event = create(:event, account: account)
      speaker = create(:speaker, account: account, event: event)
      speaker.photo.attach(io: StringIO.new("fake photo"), filename: "photo.png", content_type: "image/png")

      get edit_admin_event_path(event, step: "speaker")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<img")
    end

    # Same regression, the Review step's own read-only copy of the speaker roster
    # (admin/events/_review_step.html.erb).
    it "renders a speaker's photo thumbnail on the Review step without error" do
      Current.account = account
      event = create(:event, account: account)
      speaker = create(:speaker, account: account, event: event)
      speaker.photo.attach(io: StringIO.new("fake photo"), filename: "photo.png", content_type: "image/png")

      get edit_admin_event_path(event, step: "review")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<img")
    end
  end

  describe "GET /admin/events (index)" do
    before { sign_in_with_role(:event_admin) }

    it "filters by status" do
      Current.account = account
      create(:event, account: account, name: "Draft Event")
      live = create(:event, account: account, name: "Live Event", starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      Event.unscoped_across_tenants { live.update!(status: :live) }

      get admin_events_path, params: { status: "live" }

      expect(response.body).to include("Live Event")
      expect(response.body).not_to include("Draft Event")
    end

    # requirement.md revisit: "once event complete the tenant can not able to edit the event" —
    # the row-level Edit link itself, not just the server-side block spec/requests/
    # admin_events_spec.rb's own "blocks event_admin from editing a completed event" test covers;
    # a completed event's row shows a disabled button instead of a link that would only ever
    # bounce back "not authorized."
    it "shows a disabled Edit button (not a link) for a completed event" do
      Current.account = account
      event = create(:event, account: account, name: "Wrapped Up Event", status: :completed)

      get admin_events_path

      row = Nokogiri::HTML(response.body).css("table tbody tr").find { |tr| tr.text.include?("Wrapped Up Event") }
      expect(row.at_css("a[href='#{edit_admin_event_path(event)}']")).to be_nil
      expect(row.at_css("button[disabled]")).to be_present
    end

    it "shows the account-level sidebar (no event in context yet)" do
      get admin_events_path

      expect(response.body).not_to include("Design Registration Form")
      expect(response.body).not_to include("Back to Events")
      expect(response.body).to include(admin_events_path)
    end
  end

  describe "cross-tenant isolation (requirement.md §4.2)" do
    it "404s when Account A requests Account B's event by slug" do
      other_account = create(:account, subdomain_slug: "other")
      Current.account = other_account
      other_event = create(:event, account: other_account, name: "Other Tenant Event")

      sign_in_with_role(:event_admin)

      # config.action_dispatch.show_exceptions = :rescuable in test (config/environments/test.rb)
      # — ActiveRecord::RecordNotFound is one of Rails' own "rescuable" exceptions, rendered as a
      # real 404 response rather than propagating as a Ruby exception.
      get edit_admin_event_path(other_event.slug)

      expect(response).to have_http_status(:not_found)
    end

    it "404s when Account A requests Account B's event's show page by slug" do
      other_account = create(:account, subdomain_slug: "other")
      Current.account = other_account
      other_event = create(:event, account: other_account, name: "Other Tenant Event")

      sign_in_with_role(:event_admin)

      get admin_event_path(other_event.slug)

      expect(response).to have_http_status(:not_found)
    end

    it "404s on update too, not just edit" do
      other_account = create(:account, subdomain_slug: "other2")
      Current.account = other_account
      other_event = create(:event, account: other_account, name: "Other Tenant Event 2")

      sign_in_with_role(:event_admin)

      patch admin_event_path(other_event.slug), params: { event: { name: "Hijacked" } }

      expect(response).to have_http_status(:not_found)
    end
  end
end
