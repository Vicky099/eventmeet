# Phase 15 — Platform Billing & Invoicing (requirement.md §4.6, §8): "Super Admin raises an Invoice
# for that event — base plan/quotation amount + tracked CapacityAdjustment overage — and sends it
# to the tenant." `status` carries all 5 values requirement.md §8 specifies (draft/sent/
# awaiting_payment/under_review/paid) — **documented simplification** (see Invoice#send! its own
# comment): `send!` transitions `draft` straight to `awaiting_payment`, there being no meaningful
# manual interval between "sent" and "awaiting payment" in a manual-invoicing workflow — `:sent`
# stays a valid enum value for doc fidelity, just never a persisted intermediate step.
#
# One Invoice per Event in practice (an event is only ever invoiced once it `completed?`, §4.6) —
# not enforced with a unique index, since a Super Admin correcting a mistake by raising a fresh
# draft after voiding is a real, if rare, operational need this schema shouldn't foreclose.
class CreateInvoices < ActiveRecord::Migration[8.0]
  def change
    create_table :invoices, id: :uuid, default: nil do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.references :event, null: false, type: :uuid, foreign_key: true

      t.decimal :base_amount, precision: 12, scale: 2, null: false
      t.decimal :overage_amount, precision: 12, scale: 2, null: false, default: 0
      t.decimal :total_amount, precision: 12, scale: 2, null: false
      t.integer :status, null: false, default: 0

      t.references :raised_by, null: false, type: :uuid, foreign_key: { to_table: :users }
      t.datetime :sent_at

      t.timestamps
    end

    TenantRowLevelSecurity.enable!(self, :invoices)
  end
end
