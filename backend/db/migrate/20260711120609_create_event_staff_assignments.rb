# Phase 4 (requirement.md §5.1 new item): per-event staff assignment — a check-in volunteer only
# needs access to one event, not the whole Account. Modeled now as a plain join table; no admin UI
# to assign staff yet (that lands with a later phase), but the data model and RLS protection exist
# from day one.
class CreateEventStaffAssignments < ActiveRecord::Migration[8.0]
  def change
    create_table :event_staff_assignments, id: :uuid, default: nil do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.references :event, null: false, type: :uuid, foreign_key: true
      t.references :user, null: false, type: :uuid, foreign_key: true

      t.timestamps
    end

    add_index :event_staff_assignments, [ :event_id, :user_id ], unique: true

    TenantRowLevelSecurity.enable!(self, :event_staff_assignments)
  end
end
