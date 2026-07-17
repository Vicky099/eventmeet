# requirement.md revisit: "we will upload that [government ID] list, this will be stored in
# database somewhere. Then once participant registration starts the government ID will start
# assign to participant. One govt id will be assigned to one participant." A pre-loaded inventory
# of ids waiting to be claimed — participant_id is nil while a row sits unclaimed in the pool, and
# gets set exactly once (see GovtId.assign_to!/#claim_existing_value!) when a participant either
# grabs the next available one or already carries a value that happens to match a pooled row.
# Participant#govt_id itself stays the single source of truth for "what's this participant's
# government ID" (existing dedupe/check-in/badge code all reads that column already) — this table
# is inventory + assignment bookkeeping, not a second copy of the value.
class CreateGovtIds < ActiveRecord::Migration[8.0]
  def change
    create_table :govt_ids, id: :uuid, default: nil do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.references :event, null: false, type: :uuid, foreign_key: true
      t.string :value, null: false
      # nullable, set once — a pool row is "available" while nil, "assigned" once set. A plain
      # unique index (not partial) is enough: Postgres already treats every NULL as distinct from
      # every other NULL, so any number of still-unclaimed rows coexist fine, while an actual
      # value can only ever back one participant. index: { unique: true }, not a separate add_index
      # line — t.references already creates its own plain index, so a second explicit add_index on
      # the same column would collide with it.
      t.references :participant, null: true, type: :uuid, foreign_key: true, index: { unique: true }
      t.datetime :assigned_at

      t.timestamps
    end

    # requirement.md revisit: "GOVT ID will be unique by event." The pool's own inventory can
    # never contain the same value twice for one event.
    add_index :govt_ids, [ :event_id, :value ], unique: true

    TenantRowLevelSecurity.enable!(self, :govt_ids)
  end
end
