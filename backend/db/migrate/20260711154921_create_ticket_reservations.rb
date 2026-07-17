# Phase 6 — Ticketing (requirement.md §5.3): "one reservation holds N spots against a category,
# with per-seat detail fillable later" — a group/bulk hold, not one row per attendee. Phase 7's
# real Participant records (individual per-seat detail) attach to one of these once that phase
# builds the claim-link/manual-entry flow that fills them in; claim_token exists now as the thin
# stub the checklist calls for, not yet backed by any consumption flow.
class CreateTicketReservations < ActiveRecord::Migration[8.0]
  def change
    create_table :ticket_reservations, id: :uuid, default: nil do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.references :event, null: false, type: :uuid, foreign_key: true
      t.references :ticket_category, null: false, type: :uuid, foreign_key: true

      t.integer :seat_count, null: false
      t.string :holder_name, null: false
      t.string :holder_email, null: false
      # reserved/waitlisted/cancelled — no "paid"/"confirmed" distinction, no payment gateway
      # exists yet (requirement.md §5.3 scope note): a reservation with a seat is already final.
      t.integer :status, null: false, default: 0
      t.string :claim_token, null: false
      t.datetime :cancelled_at

      t.timestamps
    end

    add_index :ticket_reservations, :claim_token, unique: true
    # Waitlist promotion (TicketReservationService) scans exactly this shape: a category's
    # waitlisted rows, oldest first.
    add_index :ticket_reservations, [ :ticket_category_id, :status, :created_at ]

    TenantRowLevelSecurity.enable!(self, :ticket_reservations)
  end
end
