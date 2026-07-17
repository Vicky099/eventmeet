# Phase 7 — Participant Lifecycle (requirement.md §5.4): "Approval-based registration toggle per
# event (organizer must approve before a participant is considered confirmed)." Off by default —
# a manually-created Participant is immediately `confirmed` unless the organizer opts in.
class AddParticipantApprovalRequiredToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :participant_approval_required, :boolean, null: false, default: false
  end
end
