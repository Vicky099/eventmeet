require "rails_helper"

# Phase 10 — Print Agent (Electron) Integration (requirement.md §5.5.1, §8).
RSpec.describe "Admin Console print stations", type: :request do
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

  describe "POST /admin/events/:event_id/print_stations" do
    it "creates a station for owner/event_manager" do
      sign_in_with_role(:event_admin)
      event = create_event

      post admin_event_print_stations_path(event), params: { print_station: { name: "Front Desk 1" } }

      expect(response).to redirect_to(admin_event_print_stations_path(event))
      Current.account = account
      expect(event.print_stations.sole.name).to eq("Front Desk 1")
    end

    it "is not authorized for checkin_staff" do
      sign_in_with_role(:admin_staff)
      event = create_event

      post admin_event_print_stations_path(event), params: { print_station: { name: "Front Desk 1" } }

      expect(response).to redirect_to(user_root_path)
    end
  end

  describe "POST .../generate_pairing_code and .../revoke" do
    before { sign_in_with_role(:event_admin) }

    it "generates a pairing code" do
      event = create_event
      Current.account = account
      station = create(:print_station, account: account, event: event)

      post generate_pairing_code_admin_event_print_station_path(event, station)

      expect(station.reload.pairing_code).to be_present
    end

    # Regression (found live): stubbing `remote_connections.where` itself (the original version of
    # this spec) hid a real bug — Rails' RemoteConnections#where raises InvalidIdentifiersError
    # unless every identifier declared on ApplicationCable::Connection (current_user *and*
    # current_print_agent) is present as a hash key, not just the one being matched on. Letting the
    # real call run (no stub) is what actually exercises that validation.
    it "revokes the currently paired agent and disconnects it, without raising ActionCable's own identifier check" do
      event = create_event
      Current.account = account
      station = create(:print_station, :online, account: account, event: event)
      agent = station.current_agent

      post revoke_admin_event_print_station_path(event, station)

      expect(response).to redirect_to(admin_event_print_stations_path(event))
      expect(agent.reload.revoked_at).to be_present
    end
  end

  describe "PATCH .../update_settings" do
    it "saves auto_print_enabled and default_print_station_id" do
      sign_in_with_role(:event_admin)
      event = create_event
      Current.account = account
      station = create(:print_station, account: account, event: event)

      patch update_settings_admin_event_print_stations_path(event),
        params: { event: { auto_print_enabled: "1", default_print_station_id: station.id } }

      Current.account = account
      expect(event.reload).to be_auto_print_enabled
      expect(event.default_print_station).to eq(station)
    end

    # Regression (found live, requirement.md §5.5.1): update_columns (not update!) is what makes
    # this pass regardless of the rest of Event's own validity — originally caught via an event
    # predating the since-removed Quotation gate; a seat_limit left blank while has_seat_limit is
    # true (validates :seat_limit, presence: true, if: :has_seat_limit? — both columns nullable at
    # the DB level, only Rails validates the combination) exercises the identical "unrelated model
    # validation failure that update_columns bypasses" scenario now.
    it "saves successfully even when the event fails unrelated model validations" do
      sign_in_with_role(:event_admin)
      event = create_event
      Current.account = account
      event.update_columns(has_seat_limit: true, seat_limit: nil)
      station = create(:print_station, account: account, event: event)

      patch update_settings_admin_event_print_stations_path(event),
        params: { event: { auto_print_enabled: "1", default_print_station_id: station.id } }

      expect(response).to redirect_to(admin_event_print_stations_path(event))
      Current.account = account
      expect(event.reload).to be_auto_print_enabled
    end
  end
end
