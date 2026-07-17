# Phase 7.5 — Dynamic Registration Form Builder (requirement.md §5.4/§5.14 v12). Confirmed
# requirement: "I want to position each and every field ... order of the field should be
# configurable." CustomField already has a `position` column (RegistrationForm#custom_fields is
# already `-> { order(:position) }`) — nothing set it to anything but the schema's own `0`
# default, since the builder never exposed it. The fixed catalog has no equivalent column at all
# (Event::PARTICIPANT_FIELD_CATALOG is a plain Ruby array, always iterated in its own fixed
# order) — this jsonb hash is that missing piece, same field-name-keyed shape `catalog_fields`
# itself already uses, just integers instead of booleans. Deliberately a sibling column, not
# folded into `catalog_fields` itself — enabled/required-ness (what `catalog_fields` already
# drives, all the way through TicketCategory#effective_catalog_fields/Participant validation) and
# display order are independent concerns; keeping them separate means none of that existing
# enforcement logic needs to change at all for this.
class AddCatalogFieldPositionsToRegistrationForms < ActiveRecord::Migration[8.0]
  def change
    add_column :registration_forms, :catalog_field_positions, :jsonb, null: false, default: {}
  end
end
