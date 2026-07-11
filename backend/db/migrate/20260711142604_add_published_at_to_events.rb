# The publish gate the stepper wizard's Review step drives (Event#publish!) — nil means still
# draft and invisible to EventSchedulerJob (which now only manages events that have been
# published at least once); a later edit to any content field clears it back to nil
# (Event#revert_to_draft_if_published_content_changed), same as un-publishing.
class AddPublishedAtToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :published_at, :datetime
  end
end
