# Phase 5 revisited: the review queue (SuperAdmin::EventReviewsController) should only ever show
# events the organizer explicitly submitted, not every event from the moment it's created —
# `approval_status` previously defaulted straight to `pending` (0), which meant a brand-new,
# still-being-built event was already sitting in the queue with nothing to review. Adds a new
# `unsubmitted` state as the real default and reclassifies it as such (existing `pending: 0` rows
# never actually went through an explicit "submit for review" click under the old model — that
# gate didn't exist yet — so there's nothing to distinguish a genuinely-submitted row from one
# that's merely defaulted; every 0 becomes `unsubmitted`, submitted_at cleared to match).
#
# pending/approved/rejected keep their existing integer codes (1/2 already meant something real —
# an actual reject!/approve! call — so those rows are left alone); `unsubmitted` gets a fresh code
# (3) rather than reusing 0, so this is purely additive from the enum's point of view.
class AddUnsubmittedApprovalStatusToEvents < ActiveRecord::Migration[8.0]
  def up
    change_column_default :events, :approval_status, from: 0, to: 3
    execute "UPDATE events SET approval_status = 3, submitted_at = NULL WHERE approval_status = 0"
  end

  def down
    execute "UPDATE events SET approval_status = 0 WHERE approval_status = 3"
    change_column_default :events, :approval_status, from: 3, to: 0
  end
end
