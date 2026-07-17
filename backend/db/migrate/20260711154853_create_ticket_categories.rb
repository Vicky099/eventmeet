# Phase 6 — Ticketing (requirement.md §5.3, §8: "was Visitor, capacity only — no price field
# yet"). Capacity bucket per event, no pricing anywhere in this phase. sold_count/remain_count
# are derived from TicketReservation, not independently writable from outside
# TicketCategory#sync_counts! — kept as real columns (not computed on every read) so the Tickets
# step's list can render without an aggregate query per row, ported from the baseline's
# `Event#sync_tickets` idea of keeping a denormalized running total in sync via callback/service
# rather than recomputing from scratch on every read.
class CreateTicketCategories < ActiveRecord::Migration[8.0]
  def change
    create_table :ticket_categories, id: :uuid, default: nil do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.references :event, null: false, type: :uuid, foreign_key: true

      t.string :name, null: false
      t.integer :total_count, null: false
      t.integer :sold_count, null: false, default: 0
      t.integer :remain_count, null: false, default: 0
      t.boolean :document_required, null: false, default: false

      t.timestamps
    end

    TenantRowLevelSecurity.enable!(self, :ticket_categories)
  end
end
