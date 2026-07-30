# Phase 25.5 — Public Event Site (doc/public_event_site_options.md, Confirmed decisions #2/#4):
# one row per Event, holding that event's own public-page HTML — stored and rendered verbatim, no
# sanitization, no draft/publish step of its own (Event's own status/published_at is untouched by
# this). A dedicated table, not a column on `events` — this is a genuinely unbounded,
# untrusted-markup blob that most Event queries have no reason to load, same "own table, not a
# column" shape Invoice/Badge already take for their own event-scoped, occasionally-large content.
class CreateEventPages < ActiveRecord::Migration[8.0]
  def change
    create_table :event_pages, id: :uuid, default: nil do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.references :event, null: false, type: :uuid, foreign_key: true, index: { unique: true }

      t.text :html, null: false, default: ""

      t.timestamps
    end

    TenantRowLevelSecurity.enable!(self, :event_pages)
  end
end
