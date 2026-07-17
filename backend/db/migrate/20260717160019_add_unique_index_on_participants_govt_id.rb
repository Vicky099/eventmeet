# requirement.md revisit: "GOVT ID will be unique by event." Participant.duplicate_match's govt_id
# tier (Participant#not_a_duplicate) already soft-enforces this on create; this is the hard DB-level
# backstop — same "ORM-layer default plus DB-layer defense-in-depth" shape TenantRowLevelSecurity
# already uses for tenant isolation. It's what actually protects GovtId#assign_to!/
# #claim_existing_value!'s own `update_column` writes, which bypass Rails validations entirely by
# design (see app/models/govt_id.rb).
#
# `where: "govt_id <> ''"` (not a plain `unique: true`) — govt_id IS NULL for the common
# "no government ID at all" case, but ParticipantImportJob's own #row_attributes stores an
# unrecognized/blank cell as "" (empty string), not nil; a plain unique index would treat every
# blank-string row as colliding with every other one. In Postgres, `x <> ''` evaluates to NULL
# (not TRUE) for NULL x, so this single predicate excludes both nil and "" from the constraint
# without needing an explicit `OR govt_id IS NULL`. Same index name as the existing plain
# (non-unique) index it replaces — this *is* that index, just now enforcing uniqueness too.
class AddUniqueIndexOnParticipantsGovtId < ActiveRecord::Migration[8.0]
  def change
    remove_index :participants, column: [ :event_id, :govt_id ], name: "index_participants_on_event_id_and_govt_id"
    add_index :participants, [ :event_id, :govt_id ], unique: true, where: "govt_id <> ''",
      name: "index_participants_on_event_id_and_govt_id"
  end
end
