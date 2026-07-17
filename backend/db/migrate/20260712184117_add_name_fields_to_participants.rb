# Restructures Participant from a single `name` field to first_name/last_name as the primary
# captured fields, matching the reference event_management system — `name` stays as a real,
# always-populated column (derived from first/last, see Participant#derive_full_name) rather than
# becoming a virtual method, so every existing read site (dedupe matching, badge $NAME$ token,
# index/scan-result displays) keeps working unchanged. `title` is a separate salutation field
# (Mr./Ms./Dr.) for badge printing, deliberately excluded from the derived `name` itself.
class AddNameFieldsToParticipants < ActiveRecord::Migration[8.0]
  def change
    add_column :participants, :title, :string
    add_column :participants, :first_name, :string
    add_column :participants, :last_name, :string
  end
end
