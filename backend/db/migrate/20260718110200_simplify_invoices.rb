# Phase 15 — Platform Billing & Invoicing, revisited (requirement.md §4.6). Redesigned around the
# simplified flow confirmed with the user:
#   event completes -> next day the system auto-generates a draft Invoice (no more manual "raise"
#   step, InvoiceGenerationJob) -> Super Admin reviews and sends it -> tenant submits UTR + a
#   receipt via a "Mark as Paid" modal -> Super Admin verifies and marks paid (or rejects, clearing
#   the slot for one resubmission).
#
# `base_amount`/`overage_amount` are gone — there's only ever one number now (the approved
# Quotation's own `current_amount`, no plan-tier/overage math left to compute). `raised_by` is
# gone too — nothing here is "raised" by a person anymore, the system generates it. PaymentSubmission
# is folded directly on: `utr_reference`, `receipt` (has_one_attached, added via the model, not a
# column here), `submitted_at`/`submitted_by`, `verified_at`/`verified_by`, `rejection_reason`. One
# invoice per event — enforced with a unique index, matching "one quotation -> one event" already
# enforced on `events.quotation_id`.
class SimplifyInvoices < ActiveRecord::Migration[8.0]
  def change
    remove_column :invoices, :base_amount, :decimal, precision: 12, scale: 2, null: false
    remove_column :invoices, :overage_amount, :decimal, precision: 12, scale: 2, null: false, default: 0
    rename_column :invoices, :total_amount, :amount
    remove_reference :invoices, :raised_by, foreign_key: { to_table: :users }

    # events.references already indexed event_id (non-unique, from the original create_invoices
    # migration) — replace it with a unique one rather than stacking a second index on the same
    # column.
    remove_index :invoices, :event_id
    add_index :invoices, :event_id, unique: true

    add_column :invoices, :utr_reference, :string
    add_reference :invoices, :submitted_by, type: :uuid, foreign_key: { to_table: :users }
    add_column :invoices, :submitted_at, :datetime
    add_reference :invoices, :verified_by, type: :uuid, foreign_key: { to_table: :users }
    add_column :invoices, :verified_at, :datetime
    add_column :invoices, :rejection_reason, :text
  end
end
