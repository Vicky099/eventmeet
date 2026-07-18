# Phase 15 — Platform Billing & Invoicing, revisited (requirement.md §4.6): folded directly onto
# Invoice (utr_reference/receipt/submitted_at/verified_at, next migration) — one Invoice per event,
# exactly one payment attempt "slot" at a time (a rejection just clears it for resubmission via the
# same "Mark as Paid" modal) rather than a separate table tracking a history of attempts. Confirmed
# with the user: the simplified flow never mentions reviewing multiple past attempts, only
# "verify -> mark paid" or (kept, minimal) "reject -> resubmit."
class DropPaymentSubmissions < ActiveRecord::Migration[8.0]
  def up
    TenantRowLevelSecurity.disable!(self, :payment_submissions)
    drop_table :payment_submissions
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
