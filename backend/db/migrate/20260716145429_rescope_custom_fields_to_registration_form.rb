# Phase 7.5 — Dynamic Registration Form Builder (requirement.md §5.4/§5.14 v12). CustomField
# moves from Event to RegistrationForm — one form definition per TicketCategory (or per event
# default/shared form), not one per Event; see RegistrationForm and TicketCategory#registration_form.
#
# `up` deletes existing rows rather than backfilling them onto a new RegistrationForm: the only
# path that ever wrote a CustomField (the Basic Info step's nested-attributes form) was already
# removed in an earlier pass (Admin::EventsController#event_params no longer permits
# custom_fields_attributes), so any row still in the table is an orphaned relic of that retired
# UI, already unreachable from the app before this migration runs. Confirmed no real tenant data
# depends on it (implementation.md Phase 7.5).
class RescopeCustomFieldsToRegistrationForm < ActiveRecord::Migration[8.0]
  def up
    execute "DELETE FROM custom_fields"

    remove_reference :custom_fields, :event, foreign_key: true, type: :uuid
    add_reference :custom_fields, :registration_form, null: false, type: :uuid, foreign_key: true
  end

  def down
    remove_reference :custom_fields, :registration_form, foreign_key: true, type: :uuid
    add_reference :custom_fields, :event, null: false, type: :uuid, foreign_key: true
  end
end
