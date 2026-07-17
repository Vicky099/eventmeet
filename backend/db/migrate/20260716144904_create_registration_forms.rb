# Phase 7.5 — Dynamic Registration Form Builder (requirement.md §5.4/§5.14 v12). Replaces the
# event-level "Required Participant Fields" catalog (Event#participant_fields) and event-level
# CustomField list as the organizer-facing way to shape a registration form — this table is the
# new home for that configuration, scoped per TicketCategory instead of per Event.
#
# `ticket_category_id` nullable, same "default vs. specific" shape Phase 8's Badge already
# established (db/migrate/*_create_badges.rb): a real id means "just for that category," nil
# means "this event's own default/shared form" — one row doing double duty as both "what a
# category falls back to when it hasn't designed its own" and "the one form every category uses"
# when the organizer wants uniformity, rather than a separate boolean for "shared." The two
# partial unique indexes below are copied from that same Badge migration for the identical
# reason: a plain unique index on (event_id, ticket_category_id) wouldn't work here since Postgres
# treats every NULL as distinct from every other NULL, so it would happily allow multiple default
# forms per event.
#
# `catalog_fields` jsonb mirrors Event#participant_fields' old shape exactly (a hash keyed by
# Event::PARTICIPANT_FIELD_CATALOG, boolean values) — only its owner moves, the shape doesn't
# change. CustomField's own rescoping (event_id -> registration_form_id) is a separate migration.
class CreateRegistrationForms < ActiveRecord::Migration[8.0]
  def change
    create_table :registration_forms, id: :uuid, default: nil do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.references :event, null: false, type: :uuid, foreign_key: true
      t.references :ticket_category, type: :uuid, foreign_key: true

      t.jsonb :catalog_fields, null: false, default: {}

      t.timestamps
    end

    add_index :registration_forms, [ :event_id, :ticket_category_id ], unique: true,
      where: "ticket_category_id IS NOT NULL", name: "index_registration_forms_on_event_and_category_uniqueness"
    add_index :registration_forms, :event_id, unique: true,
      where: "ticket_category_id IS NULL", name: "index_registration_forms_on_event_default_uniqueness"

    TenantRowLevelSecurity.enable!(self, :registration_forms)
  end
end
