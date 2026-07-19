require "rails_helper"

# Phase 9 revisit (requirement.md §3.7, §5.6): the standalone check-in kiosk — "the actual event
# level check-in page should be out of admin panel and admin layout ... should require an
# authenticated session ... mobile friendly." Same tenant/auth/authorization wiring as the old
# Admin::ScanEventsController#create this replaced (ScanEventPolicy, ScanService), just reached at
# /checkin/:event_id instead of /admin/events/:event_id/scan_events, and rendered with its own
# layout (layouts/checkin.html.erb) instead of the admin console shell.
RSpec.describe "Check-in kiosk", type: :request do
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

  def scan_event_count
    ScanEvent.unscoped_across_tenants { ScanEvent.count }
  end

  describe "GET /checkin/:event_id" do
    it "redirects an unauthenticated request to the tenant login" do
      event = create_event

      get checkin_event_path(event)

      expect(response).to redirect_to(new_user_session_path)
    end

    it "admin_staff can reach the kiosk (requirement.md §5.1)" do
      sign_in_with_role(:admin_staff)
      event = create_event

      get checkin_event_path(event)

      expect(response).to have_http_status(:ok)
    end

    it "owner/event_manager can reach it too" do
      sign_in_with_role(:event_admin)
      event = create_event

      get checkin_event_path(event)

      expect(response).to have_http_status(:ok)
    end

    it "renders its own standalone layout, not the admin console shell" do
      sign_in_with_role(:event_admin)
      event = create_event(name: "Dubai Expo")

      get checkin_event_path(event)

      expect(response.body).to include("Dubai Expo")
      expect(response.body).not_to include('class="vertical-menu"')
      expect(response.body).not_to include("isvertical-topbar")
      expect(response.body).to include('name="viewport" content="width=device-width,initial-scale=1"')
    end

    it "404s when Account A requests Account B's event" do
      other_account = create(:account, subdomain_slug: "other")
      Current.account = other_account
      other_event = create(:event, account: other_account)

      sign_in_with_role(:event_admin)

      get checkin_event_path(other_event.slug)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /checkin/:event_id/scan" do
    before { sign_in_with_role(:admin_staff) }

    it "records a check-in scan and responds with a Turbo Stream update" do
      event = create_event
      Current.account = account
      participant = create(:participant, account: account, event: event)

      post checkin_scan_path(event), params: { identifier: participant.hex_id, scan_type: "check_in" }, as: :turbo_stream

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("turbo-stream")
      expect(response.body).to include(participant.name)

      Current.account = account
      expect(event.reload.live_stats!.checked_in_count).to eq(1)
    end

    # requirement.md revisit: "checkout background will be in warning background" — check-in
    # keeps the "good" green (is-success); check-out gets the warning amber, not the success
    # green, so the operator can tell the two states apart at a glance.
    it "renders a check-out result with the warning banner, not the success one" do
      event = create_event
      Current.account = account
      participant = create(:participant, account: account, event: event)

      post checkin_scan_path(event), params: { identifier: participant.hex_id, scan_type: "check_out" }, as: :turbo_stream

      expect(response.body).to include("checkin-result is-warning")
      expect(response.body).not_to include("checkin-result is-success")
    end

    it "still renders a check-in result with the success banner" do
      event = create_event
      Current.account = account
      participant = create(:participant, account: account, event: event)

      post checkin_scan_path(event), params: { identifier: participant.hex_id, scan_type: "check_in" }, as: :turbo_stream

      expect(response.body).to include("checkin-result is-success")
    end

    # Regression: "there is no space between green background and scan button" — the response
    # must use the Turbo Stream `update` action (replaces #scan-result's *contents*), not
    # `replace` (swaps out #scan-result itself, along with the spacing class it carries — and,
    # since the replacement content has no id of its own, leaves nothing left for a second scan's
    # response to target at all). Two scans in a row is what actually exercises this — a single
    # scan looks identical either way.
    it "keeps the #scan-result wrapper (and its spacing) in place across repeated scans" do
      event = create_event
      Current.account = account
      first = create(:participant, account: account, event: event)
      second = create(:participant, account: account, event: event)

      post checkin_scan_path(event), params: { identifier: first.hex_id, scan_type: "check_in" }, as: :turbo_stream
      expect(response.body).to include('action="update"')
      expect(response.body).to include('target="scan-result"')

      post checkin_scan_path(event), params: { identifier: second.hex_id, scan_type: "check_in" }, as: :turbo_stream
      expect(response.body).to include(second.name)
    end

    it "surfaces a not-found message for an unrecognized identifier" do
      event = create_event

      post checkin_scan_path(event), params: { identifier: "nope", scan_type: "check_in" }, as: :turbo_stream

      expect(response.body).to include("No match")
    end

    # Regression: `image_tag(attachment)` — the shape a few other admin views in this codebase
    # use for a photo — 500s ("no implicit conversion of ActiveStorage::Attached::One into
    # String") the moment it's actually exercised against a real attached photo; on top of that,
    # this app's config/cloudinary.yml sets `enhance_image_tag: true`, which globally
    # monkey-patches image_tag to mangle even an already-correct URL string. checkin/_result.html.erb
    # renders a plain `tag.img src: participant.photo.url` instead, sidestepping both.
    it "renders a photo without error when the participant has one attached" do
      event = create_event
      Current.account = account
      participant = create(:participant, account: account, event: event, attach_photo: true)

      post checkin_scan_path(event), params: { identifier: participant.hex_id, scan_type: "check_in" }, as: :turbo_stream

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<img")
      expect(response.body).to include("checkin-result-photo")
    end

    # Phase 11 backfill (requirement.md §3.7, §3.8) — same session-aware behavior
    # Admin::ScanEventsController#create used to provide: a session_id checks the participant into
    # that room instead of the plain event-level check-in, capacity-gated by Session#seat_limit.
    it "checks a participant into a session instead of the event when session_id is given" do
      event = create_event
      Current.account = account
      session = create(:session, account: account, event: event, seat_limit: 1)
      participant = create(:participant, account: account, event: event)

      post checkin_scan_path(event), params: { identifier: participant.hex_id, scan_type: "check_in", session_id: session.id }, as: :turbo_stream

      Current.account = account
      expect(session.reload.live_stats!.checked_in_count).to eq(1)
      expect(event.reload.live_stats!.checked_in_count).to eq(0)
    end

    it "blocks scanning into a full session" do
      event = create_event
      Current.account = account
      session = create(:session, account: account, event: event, seat_limit: 1)
      already_in = create(:participant, account: account, event: event)
      ScanService.call(event: event, identifier: already_in.hex_id, scan_type: "check_in", session: session)
      newcomer = create(:participant, account: account, event: event)

      post checkin_scan_path(event), params: { identifier: newcomer.hex_id, scan_type: "check_in", session_id: session.id }, as: :turbo_stream

      expect(response.body).to include("is full")
    end

    it "surfaces the virtual-event meeting link on a successful check-in" do
      event = create_event(mode: :virtual, meeting_link: "https://meet.example/abc")
      Current.account = account
      participant = create(:participant, account: account, event: event)

      post checkin_scan_path(event), params: { identifier: participant.hex_id, scan_type: "check_in" }, as: :turbo_stream

      expect(response.body).to include("https://meet.example/abc")
    end
  end

  # Phase 10 — Print Agent (Electron) Integration, revisited (requirement.md §5.5.1).
  describe "POST /checkin/:event_id/scan — printing" do
    before { sign_in_with_role(:admin_staff) }

    it "'Print only' prints without marking attendance" do
      event = create_event
      Current.account = account
      create(:badge, account: account, event: event)
      participant = create(:participant, account: account, event: event)

      post checkin_scan_path(event), params: { identifier: participant.hex_id, scan_type: "print" }, as: :turbo_stream

      expect(response.body).to include(participant.name)
      Current.account = account
      expect(Attendance.where(participant: participant).count).to eq(0)
      expect(ScanEvent.where(participant: participant, scan_type: :print).count).to eq(1)
    end

    it "the 'also print' toggle prints alongside a normal check-in" do
      event = create_event
      Current.account = account
      create(:badge, account: account, event: event)
      participant = create(:participant, account: account, event: event)

      post checkin_scan_path(event), params: { identifier: participant.hex_id, scan_type: "check_in", print: "1" }, as: :turbo_stream

      Current.account = account
      expect(Attendance.where(participant: participant).count).to eq(1)
      expect(ScanEvent.where(participant: participant, scan_type: :print).count).to eq(1)
    end

    it "without the toggle and with auto_print_enabled off, a plain check-in triggers no print" do
      event = create_event
      Current.account = account
      create(:badge, account: account, event: event)
      participant = create(:participant, account: account, event: event)

      post checkin_scan_path(event), params: { identifier: participant.hex_id, scan_type: "check_in" }, as: :turbo_stream

      Current.account = account
      expect(ScanEvent.where(participant: participant, scan_type: :print).count).to eq(0)
    end

    # The literal Phase 10 Definition of Done line: "auto-print off -> no job pushed, badge still
    # available via the Phase 8 on-demand download" — and the flip side, on -> a job pushed with
    # no operator toggle at all.
    it "auto_print_enabled on the event prints automatically with no operator toggle" do
      event = create_event(auto_print_enabled: true)
      Current.account = account
      create(:badge, account: account, event: event)
      station = create(:print_station, :online, account: account, event: event)
      event.update!(default_print_station: station)
      participant = create(:participant, account: account, event: event)

      post checkin_scan_path(event), params: { identifier: participant.hex_id, scan_type: "check_in" }, as: :turbo_stream

      Current.account = account
      expect(PrintJob.sole).to have_attributes(participant: participant, status: "sent")
    end

    it "'Print only' does not debounce against a prior check-in's own ScanEvent" do
      event = create_event
      Current.account = account
      create(:badge, account: account, event: event)
      participant = create(:participant, account: account, event: event)
      post checkin_scan_path(event), params: { identifier: participant.hex_id, scan_type: "check_in" }, as: :turbo_stream

      post checkin_scan_path(event), params: { identifier: participant.hex_id, scan_type: "print" }, as: :turbo_stream

      expect(response.body).not_to include("Already printed")
    end
  end
end
