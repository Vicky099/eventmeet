# Fixed-hierarchy pivot (requirement.md revisit, confirmed with the user): "remove all the
# workflows where super admin allow to create the events." Every Event is now created directly
# under an Agency-linked tenant with no per-event pricing negotiation and no per-event content
# review — the whole Quotation gate and the pending/approved/rejected review cycle it fed are gone,
# not just bypassed. `approved_by_id`/`approved_at`/`submitted_at`/`rejection_reason` were only
# ever written by that removed workflow (Event#submit_for_review!/#approve!/#reject!, all deleted
# in this same pivot) — nothing else in the app ever wrote them.
class RemoveQuotationAndApprovalWorkflowFromEvents < ActiveRecord::Migration[8.0]
  def change
    remove_reference :events, :quotation, foreign_key: true, index: { unique: true }
    remove_column :events, :approval_status, :integer, default: 3, null: false
    remove_column :events, :submitted_at, :datetime
    remove_reference :events, :approved_by, foreign_key: { to_table: :users }
    remove_column :events, :approved_at, :datetime
    remove_column :events, :rejection_reason, :text
  end
end
