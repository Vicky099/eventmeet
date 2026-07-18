# Phase 15 — Platform Billing & Invoicing (requirement.md §4.6, §8): "QuotationRevision (quotation,
# amount, rejection note, created by, created at) — one row per round of the reject-with-note ->
# Super Admin revises -> resend cycle, capped at 3 rounds." One row per *rejection* — `amount` is a
# snapshot of what was rejected (the audit trail: what was on the table when the tenant said no),
# `created_by` is always the tenant staffer who rejected (see Quotation#reject!) — the Super
# Admin's subsequent revised offer just updates `quotations.current_amount` directly rather than
# writing back onto this same row, since a "one row per action" shape is simpler than a two-phase
# row that two different actors each partially fill in. `quotation.quotation_revisions.count >= 3`
# is exactly what triggers `cancelled` — no separate counter column needed.
#
# `account_id` carried directly (not just reachable via `quotation.account`) — requirement.md
# §4.2's "every tenant-scoped table" carries it for RLS defense-in-depth, same as every other
# child-of-a-tenant-row table in this app (QuotationRevision holds real tenant business content —
# a rejection note — so it gets the same protection as everything else, not an exception).
class CreateQuotationRevisions < ActiveRecord::Migration[8.0]
  def change
    create_table :quotation_revisions, id: :uuid, default: nil do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.references :quotation, null: false, type: :uuid, foreign_key: true

      t.decimal :amount, precision: 12, scale: 2, null: false
      t.text :rejection_note, null: false
      t.references :created_by, null: false, type: :uuid, foreign_key: { to_table: :users }

      t.timestamps
    end

    TenantRowLevelSecurity.enable!(self, :quotation_revisions)
  end
end
