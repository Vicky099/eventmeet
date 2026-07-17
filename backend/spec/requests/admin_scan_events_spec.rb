require "rails_helper"

# Phase 9 — Check-in, Attendance & Real-Time Live Dashboards (requirement.md §3.7, §5.6),
# revisited: this is now purely the read-only dashboard (live stats, capacity, breakdowns, recent
# scans) plus a link out to the standalone kiosk (CheckinController, spec/requests/checkin_spec.rb)
# — the actual scan POST moved there with it, so there's no "POST /scan_events" describe block
# here anymore.
RSpec.describe "Admin Console check-in dashboard", type: :request do
  include ActiveSupport::Testing::TimeHelpers

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

  describe "GET /admin/events/:event_id/scan_events" do
    it "checkin_staff can reach the dashboard (requirement.md §5.1)" do
      sign_in_with_role(:checkin_staff)
      event = create_event

      get admin_event_scan_events_path(event)

      expect(response).to have_http_status(:ok)
    end

    it "owner/event_manager can reach it too" do
      sign_in_with_role(:event_manager)
      event = create_event

      get admin_event_scan_events_path(event)

      expect(response).to have_http_status(:ok)
    end

    it "finance_readonly is not authorized" do
      sign_in_with_role(:finance_readonly)
      event = create_event

      get admin_event_scan_events_path(event)

      expect(response).to redirect_to(user_root_path)
    end

    it "links out to the standalone check-in kiosk instead of embedding a scan form" do
      sign_in_with_role(:owner)
      event = create_event

      get admin_event_scan_events_path(event)

      expect(response.body).to include(checkin_event_path(event))
      expect(response.body).not_to include('id="scan-result"')
    end

    # requirement.md revisit: "Arrived today ... ticket category wise check-ins ... overall how
    # much full and category wise ticket sold data."
    it "shows arrived-today, overall capacity, and ticket-category-wise check-in breakdowns" do
      sign_in_with_role(:owner)
      event = create_event(has_seat_limit: true, seat_limit: 50)
      Current.account = account
      category = create(:ticket_category, account: account, event: event, total_count: 10)
      participant = create(:participant, account: account, event: event, ticket_category: category)
      ScanService.call(event: event, identifier: participant.hex_id, scan_type: "check_in")

      get admin_event_scan_events_path(event)

      expect(response.body).to include("Arrived Today")
      expect(response.body).to include("Overall Capacity")
      expect(response.body).to include("Check-ins by Ticket Category")
      expect(response.body).to include(category.name)
      expect(response.body).to include("1 checked in")
    end

    # Regression: "9 checked in · 3 registered" — reported confusing (and it was: the category
    # breakdown was counting every check_in *scan*, not unique attendees, so a handful of repeat
    # scans on the same few people trivially outnumbered the category's own headcount). One
    # participant scanned in/out/in again (each past the 30s debounce window) must still read as
    # 1 checked in, not 3 — never more than that category's own `registered` count.
    it "counts a repeatedly-scanned participant once, not once per scan" do
      sign_in_with_role(:owner)
      event = create_event
      Current.account = account
      category = create(:ticket_category, account: account, event: event)
      participant = create(:participant, account: account, event: event, ticket_category: category)

      ScanService.call(event: event, identifier: participant.hex_id, scan_type: "check_in")
      travel(ScanService::DEBOUNCE_WINDOW + 1.second) do
        ScanService.call(event: event, identifier: participant.hex_id, scan_type: "check_out")
      end
      travel(2 * (ScanService::DEBOUNCE_WINDOW + 1.second)) do
        ScanService.call(event: event, identifier: participant.hex_id, scan_type: "check_in")
      end

      get admin_event_scan_events_path(event)

      expect(response.body).to include("1 checked in")
      expect(response.body).not_to include("3 checked in")
    end

    # Regression: "Registered, Checked In, Arrived Today & Currently In Venue values are not
    # respect the registered one" — confirmed live: EventLiveStats#registered_count had drifted
    # to 10 against a real participant count of 5. The Registered tile must reflect real
    # Participant rows, not that denormalized (and here, deliberately corrupted) counter.
    it "shows the real participant count for Registered, not a stale denormalized counter" do
      sign_in_with_role(:owner)
      event = create_event
      Current.account = account
      create_list(:participant, 3, account: account, event: event)
      event.live_stats!.update!(registered_count: 999)

      get admin_event_scan_events_path(event)

      expect(stat_tile_value(response.body, "Registered")).to eq(3)
    end

    # Same regression, the other half: Checked In / Currently In Venue must be real headcounts
    # (bounded by Registered), not cumulative scan counts that can run past it once someone gets
    # scanned more than once — check in, check out, check in again (each past the debounce
    # window) on the event's one and only participant must still read 1 across the board, not 2
    # or 3.
    it "never shows Checked In or Currently In Venue higher than Registered, even with repeat scans" do
      sign_in_with_role(:owner)
      event = create_event
      Current.account = account
      participant = create(:participant, account: account, event: event)

      ScanService.call(event: event, identifier: participant.hex_id, scan_type: "check_in")
      travel(ScanService::DEBOUNCE_WINDOW + 1.second) do
        ScanService.call(event: event, identifier: participant.hex_id, scan_type: "check_out")
      end
      travel(2 * (ScanService::DEBOUNCE_WINDOW + 1.second)) do
        ScanService.call(event: event, identifier: participant.hex_id, scan_type: "check_in")
      end

      get admin_event_scan_events_path(event)

      expect(stat_tile_value(response.body, "Registered")).to eq(1)
      expect(stat_tile_value(response.body, "Checked In")).to eq(1)
      expect(stat_tile_value(response.body, "Currently In Venue")).to eq(1)
    end
  end

  def stat_tile_value(html, label)
    Nokogiri::HTML(html).at_xpath("//h6[normalize-space(text())='#{label}']/following-sibling::h4").text.strip.to_i
  end
end
