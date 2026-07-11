# Phase 5 — Event Approval Workflow (requirement.md §4.7 item 2, §5.2, §8). approved_by/
# approved_at/rejection_reason are the columns requirement.md §8 names explicitly; submitted_at
# isn't in that list but is load-bearing for the review queue's "sorted oldest-first, flags
# anything approaching the 24h SLA" requirement — approval_status alone can't answer "since when
# has this been pending," especially across a reject → edit → resubmit cycle where that clock
# needs to reset.
class AddApprovalWorkflowToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :submitted_at, :datetime
    add_reference :events, :approved_by, null: true, foreign_key: { to_table: :users }, type: :uuid
    add_column :events, :approved_at, :datetime
    add_column :events, :rejection_reason, :text

    add_index :events, [ :approval_status, :submitted_at ]
  end
end
