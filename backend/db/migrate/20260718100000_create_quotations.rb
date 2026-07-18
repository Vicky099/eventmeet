# Phase 15 — Platform Billing & Invoicing (requirement.md §4.6, §8). Business-tier quotation gate:
# "organizer requests a Business-tier event -> Super Admin sends amount -> tenant approves (event
# creation unblocked) or rejects-with-note ... up to 3 rejections." A Quotation is deliberately
# NOT `belongs_to :event` — the whole point of the gate is that no Event row exists yet when the
# request is made; `event_name` is just what the tenant is asking a quote *for*. The reverse
# association (`Event belongs_to :quotation, optional: true`, added in the next migration once
# this table exists) is what an approved Quotation gets consumed into once the Event is actually
# created.
#
# `status` — exactly the 4 values requirement.md §8 specifies (pending/approved/rejected/
# cancelled). `pending` deliberately covers two distinct waiting states (awaiting the Super Admin's
# first amount vs. awaiting the tenant's decision on a sent amount) — `current_amount.present?` is
# what tells them apart; a 5th enum value would just be redundant with that.
class CreateQuotations < ActiveRecord::Migration[8.0]
  def change
    create_table :quotations, id: :uuid, default: nil do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true

      t.string :event_name, null: false
      t.decimal :current_amount, precision: 12, scale: 2
      t.integer :status, null: false, default: 0

      t.references :requested_by, null: false, type: :uuid, foreign_key: { to_table: :users }
      t.references :approved_by, type: :uuid, foreign_key: { to_table: :users }
      t.datetime :sent_at
      t.datetime :approved_at

      t.timestamps
    end

    TenantRowLevelSecurity.enable!(self, :quotations)
  end
end
