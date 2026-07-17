# Phase 8 — Badge Design & Printing (requirement.md §3.6, §5.5). Per-event instantiation of a
# BadgeTemplate (or a fresh one) — `badge_template_id` is only provenance (which library entry it
# started from, if any); content/mapping/size are copied in at creation and edited independently
# from then on, same "copy, not a live link" relationship Phase 4's "Duplicate event" already
# established for events.
#
# `ticket_category_id` nullable is what makes conditional-by-category badges work (requirement.md
# §5.5: "VIP vs. Attendee vs. Speaker badge from one event without duplicating templates"): nil
# means "this event's default badge," a real id means "just for that category." The two partial
# unique indexes below enforce at most one badge per category and at most one default per event —
# a plain unique index on (event_id, ticket_category_id) wouldn't work here since Postgres treats
# every NULL as distinct from every other NULL, so it would happily allow multiple default badges.
class CreateBadges < ActiveRecord::Migration[8.0]
  def change
    create_table :badges, id: :uuid, default: nil do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.references :event, null: false, type: :uuid, foreign_key: true
      t.references :ticket_category, type: :uuid, foreign_key: true
      t.references :badge_template, type: :uuid, foreign_key: true

      t.string :name, null: false
      t.text :content, null: false, default: ""
      t.jsonb :mapping, null: false, default: {}
      t.integer :output_type, null: false, default: 0
      t.decimal :width_cm, precision: 6, scale: 2, null: false
      t.decimal :height_cm, precision: 6, scale: 2, null: false

      t.timestamps
    end

    add_index :badges, [ :event_id, :ticket_category_id ], unique: true,
      where: "ticket_category_id IS NOT NULL", name: "index_badges_on_event_and_category_uniqueness"
    add_index :badges, :event_id, unique: true,
      where: "ticket_category_id IS NULL", name: "index_badges_on_event_default_uniqueness"

    TenantRowLevelSecurity.enable!(self, :badges)
  end
end
