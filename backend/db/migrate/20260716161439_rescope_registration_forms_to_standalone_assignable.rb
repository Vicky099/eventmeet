# Phase 7.5 revisited — Dynamic Registration Form Builder (requirement.md §5.4/§5.14 v12).
# Flips the relationship the other way: a RegistrationForm used to `belong_to :ticket_category`
# (nil meaning "this event's default/shared form," per-category "custom" forms each a separate
# row) — organizer feedback was that this should instead read as "create a form first, then
# assign it to whichever ticket categories should use it, including all of them at once," which
# only works cleanly the other direction: `TicketCategory belongs_to :registration_form`. One
# form can now be the `registration_form_id` of any number of categories directly — "apply to
# every category" is just assigning the same form to all of them, not a separate nil-category
# concept, so the old two-partial-unique-index "at most one default, at most one per category"
# constraint is gone entirely; nothing here needs to be unique anymore.
#
# `up` clears existing rows rather than backfilling a `registration_form_id` onto every
# TicketCategory from the old `ticket_category_id`: the only path that ever wrote a
# RegistrationForm (Admin::RegistrationFormsController, rebuilt in the same pass as this
# migration) is being rebuilt with a different params shape anyway, so any row still in the
# table is dev/QA data from the old shape, not something worth a real backfill for. Same
# reasoning as the CustomField rescoping migration earlier in this phase. custom_fields rows are
# cleared first — they still `belong_to :registration_form` with a plain (RESTRICT-on-delete)
# foreign key, so deleting their parent first would otherwise fail outright.
class RescopeRegistrationFormsToStandaloneAssignable < ActiveRecord::Migration[8.0]
  def up
    execute "DELETE FROM custom_fields"
    execute "DELETE FROM registration_forms"

    # Postgres drops any index referencing a column automatically when that column itself is
    # dropped — both partial unique indexes (and the reference's own plain index) go away as a
    # side effect of remove_reference below; no separate remove_index calls needed (confirmed:
    # an explicit one here raised PG::UndefinedObject, already gone by the time it ran).
    remove_reference :registration_forms, :ticket_category, foreign_key: true, type: :uuid
    # null: false with no default needs no temp-default two-step here — the table is guaranteed
    # empty at this point (cleared above, in this same migration).
    add_column :registration_forms, :name, :string, null: false

    add_reference :ticket_categories, :registration_form, type: :uuid, foreign_key: true
  end

  def down
    remove_reference :ticket_categories, :registration_form, foreign_key: true, type: :uuid
    remove_column :registration_forms, :name

    add_reference :registration_forms, :ticket_category, type: :uuid, foreign_key: true
    add_index :registration_forms, [ :event_id, :ticket_category_id ], unique: true,
      where: "ticket_category_id IS NOT NULL", name: "index_registration_forms_on_event_and_category_uniqueness"
    add_index :registration_forms, :event_id, unique: true,
      where: "ticket_category_id IS NULL", name: "index_registration_forms_on_event_default_uniqueness"
  end
end
