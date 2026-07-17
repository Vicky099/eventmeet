# Reverses Phase 11's "account-wide reusable library" design (confirmed with user) — Speaker
# becomes event-scoped, one roster per event, same shape as Session/Schedule rather than
# BadgeTemplate. Clears the handful of existing dev-DB speaker rows first (this session's own QA
# data, not real) so the new `event_id` can be a real required column from the start, matching
# this app's established convention for a required belongs_to (see sessions/schedules'
# migrations) rather than a nullable column enforced only at the Rails level.
class AddEventToSpeakers < ActiveRecord::Migration[8.0]
  def up
    # schedules.speaker_id would otherwise block deleting the stale speaker rows below — also
    # this session's own QA data, not real.
    execute "DELETE FROM schedules"
    execute "DELETE FROM speakers"
    add_reference :speakers, :event, null: false, type: :uuid, foreign_key: true
  end

  def down
    remove_reference :speakers, :event
  end
end
