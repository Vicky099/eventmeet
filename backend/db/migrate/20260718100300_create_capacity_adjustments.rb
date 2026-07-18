# Phase 15 — Platform Billing & Invoicing (requirement.md §4.6, §8): "the Super Admin can increase
# a specific event's participant cap ... every increase is logged as a CapacityAdjustment (event,
# previous cap, new cap, increased by, timestamp) and priced as extra participants beyond the
# plan's originally-included volume ... The per-extra-participant rate defaults to the plan's
# decided rate, but the Super Admin can override it per adjustment." `override_rate` nullable —
# absence is exactly what makes `EventBilling`'s pricing fall back to the plan's own standard
# overage rate (`Event#overage_amount`).
#
# Business-plan events never get one of these (no cap to adjust — validated at the model level,
# `CapacityAdjustment#event_must_have_a_cap`), so this doesn't carry its own `plan` snapshot.
class CreateCapacityAdjustments < ActiveRecord::Migration[8.0]
  def change
    create_table :capacity_adjustments, id: :uuid, default: nil do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.references :event, null: false, type: :uuid, foreign_key: true

      t.integer :previous_cap, null: false
      t.integer :new_cap, null: false
      t.decimal :override_rate, precision: 12, scale: 2
      t.references :increased_by, null: false, type: :uuid, foreign_key: { to_table: :users }

      t.timestamps
    end

    TenantRowLevelSecurity.enable!(self, :capacity_adjustments)
  end
end
