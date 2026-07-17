# Phase 7 — Participant Lifecycle (requirement.md §3.4, §5.4, §8). ticket_category is optional at
# the DB level (nullable FK) — a manually-entered participant isn't always tied to one, unlike a
# TicketReservation's group hold (Phase 6). hex_id/client_participant_id are both generated
# server-side if left blank (Participant#generate_identifiers) and both unique — hex_id globally
# (it's the scan-anywhere internal identifier, §3.7), client_participant_id per event only (an
# organizer-supplied code only needs to be unique within their own event).
class CreateParticipants < ActiveRecord::Migration[8.0]
  def change
    create_table :participants, id: :uuid, default: nil do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.references :event, null: false, type: :uuid, foreign_key: true
      t.references :ticket_category, type: :uuid, foreign_key: true

      t.string :hex_id, null: false
      t.string :client_participant_id, null: false
      t.string :govt_id
      t.string :rf_id

      t.string :name, null: false
      t.string :email
      t.string :contact_num
      t.string :company
      t.string :department
      t.string :position
      t.string :nationality
      t.string :country

      # manual/upload/client_api (requirement.md §3.4) — client_api is a value only until Phase 16
      # actually wires an inbound API path that can set it.
      t.integer :source, null: false, default: 0
      # pending/confirmed — see Event#participant_approval_required above. Always confirmed when
      # that toggle is off; starts pending and needs an explicit admin approve when it's on.
      t.integer :status, null: false, default: 0

      # Custom-field responses (Phase 7 new item, CustomField) keyed by custom_field_id — not a
      # join table, same "jsonb blob keyed by a sibling record's id" shape Event#participant_fields
      # already uses for the Phase 4 fixed catalog.
      t.jsonb :custom_field_values, null: false, default: {}

      t.timestamps
    end

    add_index :participants, :hex_id, unique: true
    add_index :participants, [ :event_id, :client_participant_id ], unique: true
    # Not unique — these three back the dedupe *lookup* (govt ID -> email+name -> email -> phone),
    # which is deliberately not a hard DB constraint (a fuzzy chain needs to run application-side
    # to pick the right tier and produce a friendly "duplicate of X" reason, not just bounce on
    # whichever constraint an INSERT happens to hit first).
    add_index :participants, [ :event_id, :govt_id ]
    add_index :participants, [ :event_id, :email ]
    add_index :participants, [ :event_id, :contact_num ]

    TenantRowLevelSecurity.enable!(self, :participants)
  end
end
