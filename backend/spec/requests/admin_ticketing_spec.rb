require "rails_helper"

# Phase 6 — Ticketing (requirement.md §5.3).
RSpec.describe "Admin Console ticketing", type: :request do
  let!(:account) { create(:account, subdomain_slug: "acme") }

  before { host! "acme.example.com" }

  def sign_in_with_role(role)
    user = create(:user, email: "#{role}@acme.example", password: "password123!")
    create(:account_membership, user: user, account: account, role: role)
    sign_in user, scope: :user
    user
  end

  def create_event(**attrs)
    Current.account = account
    create(:event, account: account, **attrs)
  end

  def ticket_category_count
    Event.unscoped_across_tenants { TicketCategory.count }
  end

  # The Tickets step's own "Next" button — ticket categories are nested attributes on the Event
  # form (Event accepts_nested_attributes_for :ticket_categories), not a separate CRUD endpoint;
  # they only persist as part of this same PATCH, same as Basic Info's fields do.
  describe "PATCH /admin/events/:id (Tickets step)" do
    before { sign_in_with_role(:event_admin) }

    it "sets the event's seat_limit and creates a ticket category in the same save" do
      event = create_event

      expect {
        patch admin_event_path(event), params: {
          step: "tickets",
          event: { has_seat_limit: "1", seat_limit: "200", ticket_categories_attributes: { "0" => { name: "General", total_count: "100" } } }
        }
      }.to change { ticket_category_count }.by(1)

      event = Event.unscoped_across_tenants { event.reload }
      expect(event.seat_limit).to eq(200)
      expect(Event.unscoped_across_tenants { event.ticket_categories.sole.name }).to eq("General")
      expect(response).to redirect_to(edit_admin_event_path(event, step: "badge"))
    end

    it "clears seat_limit when the has_seat_limit toggle is switched off" do
      event = create_event(has_seat_limit: true, seat_limit: 75)

      patch admin_event_path(event), params: {
        step: "tickets",
        event: { has_seat_limit: "0", seat_limit: "75" }
      }

      event = Event.unscoped_across_tenants { event.reload }
      expect(event.has_seat_limit).to be false
      expect(event.seat_limit).to be_nil
    end

    it "rejects toggling has_seat_limit on without a seat_limit value" do
      event = create_event

      patch admin_event_path(event), params: {
        step: "tickets",
        event: { has_seat_limit: "1", seat_limit: "" }
      }

      expect(response).to have_http_status(:unprocessable_content)
      # Inline field error (field_error_feedback) — no attribute-name prefix, unlike full_messages;
      # the label sitting right above the field already supplies that context.
      expect(response.body).to include("can&#39;t be blank").or include("can't be blank")
    end

    it "updates an existing category in place" do
      event = create_event(has_seat_limit: true, seat_limit: 100)
      Current.account = account
      category = create(:ticket_category, account: account, event: event, name: "General", total_count: 10)

      patch admin_event_path(event), params: {
        step: "tickets",
        event: { ticket_categories_attributes: { "0" => { id: category.id, name: "VIP", total_count: "20" } } }
      }

      category = Event.unscoped_across_tenants { category.reload }
      expect(category.name).to eq("VIP")
      expect(category.total_count).to eq(20)
    end

    it "clears a category's total_count on save when the event has no seat limit (unlimited category)" do
      event = create_event(has_seat_limit: false)
      Current.account = account
      category = create(:ticket_category, account: account, event: event, name: "Visitor", total_count: 100)

      patch admin_event_path(event), params: {
        step: "tickets",
        event: { ticket_categories_attributes: { "0" => { id: category.id, name: "Visitor" } } }
      }

      category = Event.unscoped_across_tenants { category.reload }
      expect(category.total_count).to be_nil
      expect(category.remain_count).to be_nil
    end

    it "allows creating a category with no total_count when the event has no seat limit" do
      event = create_event(has_seat_limit: false)

      expect {
        patch admin_event_path(event), params: {
          step: "tickets",
          event: { ticket_categories_attributes: { "0" => { name: "General" } } }
        }
      }.to change { ticket_category_count }.by(1)

      expect(response).to redirect_to(edit_admin_event_path(event, step: "badge"))
    end

    it "removes a category via _destroy" do
      event = create_event
      Current.account = account
      category = create(:ticket_category, account: account, event: event)

      expect {
        patch admin_event_path(event), params: {
          step: "tickets",
          event: { ticket_categories_attributes: { "0" => { id: category.id, _destroy: "1" } } }
        }
      }.to change { ticket_category_count }.by(-1)
    end

    # Reported live: TicketCategory has `dependent: :restrict_with_error` on :participants, but
    # accepts_nested_attributes_for's own destroy machinery calls #destroy! under the hood — a
    # blocked restrict_with_error destroy raises ActiveRecord::RecordNotDestroyed there instead of
    # degrading gracefully the way it does for a plain #destroy call, which would otherwise crash
    # this request with an unhandled 500. Event#destroyed_categories_have_no_participants is a
    # real validation instead, catching this before any destroy is attempted at all.
    it "rejects removing a category that already has participants registered under it, without crashing" do
      event = create_event
      Current.account = account
      category = create(:ticket_category, account: account, event: event, name: "Visitor")
      create(:participant, account: account, event: event, ticket_category: category)

      expect {
        patch admin_event_path(event), params: {
          step: "tickets",
          event: { ticket_categories_attributes: { "0" => { id: category.id, _destroy: "1" } } }
        }
      }.not_to change { ticket_category_count }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("participants are already registered")
    end

    it "re-renders the step with an error instead of saving when a category would exceed the event's seat_limit" do
      event = create_event(seat_limit: 50)

      expect {
        patch admin_event_path(event), params: {
          step: "tickets",
          event: { ticket_categories_attributes: { "0" => { name: "General", total_count: "51" } } }
        }
      }.not_to change { ticket_category_count }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("seat limit")
    end

    # Reported live: seat_limit 100, three brand-new categories (60/50/40 = 150) added in one
    # Tickets-step "Next" — none exceeds 100 alone, only their sum does. Exercises the exact
    # request shape the Tickets step's nested-fields form actually submits (multiple indexed
    # rows in one PATCH), not just a single row.
    it "rejects three brand-new categories submitted together whose combined total exceeds the seat_limit" do
      event = create_event(seat_limit: 100)

      expect {
        patch admin_event_path(event), params: {
          step: "tickets",
          event: {
            ticket_categories_attributes: {
              "0" => { name: "General", total_count: "60" },
              "1" => { name: "VIP", total_count: "50" },
              "2" => { name: "Press", total_count: "40" }
            }
          }
        }
      }.not_to change { ticket_category_count }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("seat limit")
    end
  end

  describe "POST /admin/events/:event_id/ticket_categories/:ticket_category_id/ticket_reservations" do
    before { sign_in_with_role(:event_admin) }

    it "reserves seats against the category" do
      event = create_event
      Current.account = account
      category = create(:ticket_category, account: account, event: event, total_count: 5)

      post admin_event_ticket_category_ticket_reservations_path(event, category), params: {
        ticket_reservation: { seat_count: 2, holder_name: "Alice", holder_email: "alice@example.com" }
      }

      category = Event.unscoped_across_tenants { category.reload }
      expect(category.sold_count).to eq(2)
      expect(response).to redirect_to(edit_admin_event_path(event, step: "tickets"))
    end

    it "waitlists instead of rejecting when the category is full" do
      event = create_event
      Current.account = account
      category = create(:ticket_category, account: account, event: event, total_count: 1)
      create(:ticket_reservation, account: account, ticket_category: category, event: event, seat_count: 1)

      post admin_event_ticket_category_ticket_reservations_path(event, category), params: {
        ticket_reservation: { seat_count: 1, holder_name: "Bob", holder_email: "bob@example.com" }
      }

      reservation = Event.unscoped_across_tenants { TicketReservation.find_by!(holder_name: "Bob") }
      expect(reservation).to be_waitlisted
      follow_redirect!
      expect(response.body).to include("waitlisted")
    end
  end

  describe "PATCH /admin/events/:event_id/ticket_reservations/:id/cancel" do
    before { sign_in_with_role(:event_admin) }

    it "cancels the reservation and auto-promotes the next waitlisted one" do
      event = create_event
      Current.account = account
      category = create(:ticket_category, account: account, event: event, total_count: 1)
      first = create(:ticket_reservation, account: account, ticket_category: category, event: event, seat_count: 1, status: :reserved)
      second = create(:ticket_reservation, account: account, ticket_category: category, event: event, seat_count: 1, status: :waitlisted)

      patch cancel_admin_event_ticket_reservation_path(event, first)

      first = Event.unscoped_across_tenants { first.reload }
      second = Event.unscoped_across_tenants { second.reload }
      expect(first).to be_cancelled
      expect(second).to be_reserved
    end
  end
end
