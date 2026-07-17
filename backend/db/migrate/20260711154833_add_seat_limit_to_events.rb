# Phase 6 — Ticketing (requirement.md §5.3, §8). Nullable, no cap by default — "capacity
# validated against event-level seat limit if one is set" (Phase 6 checklist). When present,
# TicketCategory validates that the sum of every category's total_count on the event doesn't
# exceed it. Also joins Event::CONTENT_ATTRIBUTES (Phase 4) — editing it on an already-published
# event reverts that event to draft, same as every other content field.
class AddSeatLimitToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :seat_limit, :integer
  end
end
