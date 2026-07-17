# Phase 7 — Participant Lifecycle (requirement.md §5.4 new item): "organizer-defined fields
# (text/select/checkbox/file) stored per event, rendered dynamically on the admin manual-entry
# form — generalizes the baseline's fixed participant_fields catalog from Phase 4." Phase 4's
# fixed catalog (Event#participant_fields) is untouched — this is a second, additive mechanism for
# fields the fixed catalog doesn't cover, not a replacement.
class CreateCustomFields < ActiveRecord::Migration[8.0]
  def change
    create_table :custom_fields, id: :uuid, default: nil do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.references :event, null: false, type: :uuid, foreign_key: true

      t.string :label, null: false
      # text/select/checkbox/file — a file-type field renders a file_field on the manual-entry
      # form and its upload lands in Participant#custom_field_files (has_many_attached), keyed by
      # signed blob id inside custom_field_values so it can be looked back up per field.
      t.integer :field_type, null: false, default: 0
      # Newline-separated choices, only meaningful for field_type: select — plain text rather than
      # a jsonb array since it's edited as a single textarea on the builder form.
      t.text :options
      t.boolean :required, null: false, default: false
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    TenantRowLevelSecurity.enable!(self, :custom_fields)
  end
end
