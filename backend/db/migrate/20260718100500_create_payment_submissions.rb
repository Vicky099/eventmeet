# Phase 15 — Platform Billing & Invoicing (requirement.md §4.6, §8): "Tenant submits payment proof:
# uploads the UTR (bank transaction reference) and/or a receipt, creating a PaymentSubmission
# linked to the invoice, status pending_review ... Super Admin verifies ... marks paid, or rejects
# it back to the tenant with a reason for resubmission." Multiple rows per Invoice over time (not a
# `has_one`) — a rejection is resubmittable, and the full attempt history (what UTR was tried, who
# reviewed it, why it was rejected) is worth keeping rather than overwritten in place.
class CreatePaymentSubmissions < ActiveRecord::Migration[8.0]
  def change
    create_table :payment_submissions, id: :uuid, default: nil do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.references :invoice, null: false, type: :uuid, foreign_key: true

      t.string :utr_reference, null: false
      t.integer :status, null: false, default: 0
      t.references :submitted_by, null: false, type: :uuid, foreign_key: { to_table: :users }
      t.references :reviewed_by, type: :uuid, foreign_key: { to_table: :users }
      t.datetime :reviewed_at
      t.text :rejection_reason

      t.timestamps
    end

    TenantRowLevelSecurity.enable!(self, :payment_submissions)
  end
end
