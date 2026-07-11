# Phase 4 — Event Lifecycle (requirement.md §3.2, §5.2, §8). The first real TenantScoped +
# Postgres-RLS-protected table (app/models/concerns/tenant_scoped.rb, lib/
# tenant_row_level_security.rb) — both were built in Phase 0 specifically for this moment.
class CreateEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :events, id: :uuid, default: nil do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true

      t.string :name, null: false
      # friendly_id (:scoped, scope: :account_id, app/models/event.rb) — unique per account, not
      # globally: two different tenants each running their own "annual-meetup" must both be able
      # to use that slug.
      t.string :slug, null: false

      t.integer :mode, null: false, default: 0
      t.integer :status, null: false, default: 0
      # approval_status: column only, this phase — the review workflow itself (approved_by,
      # approved_at, rejection_reason, the SuperAdmin review queue) is Phase 5.
      t.integer :approval_status, null: false, default: 0
      t.integer :banner_orientation, null: false, default: 0

      # Required, not optional — EventSchedulerJob (Phase 4) needs both to compute status
      # transitions the moment an Event exists, and the tabbed builder's Basic Info tab is where
      # they're set (requirement.md §3.2's "configured start/end times").
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false

      # Mode-dependent presence (Event#location_present_for_mode) rather than NOT NULL — on_site
      # doesn't need meeting_link, virtual doesn't need address.
      t.text :address
      t.string :meeting_link

      t.jsonb :participant_fields, null: false, default: {}

      t.timestamps
    end

    add_index :events, [ :account_id, :slug ], unique: true

    TenantRowLevelSecurity.enable!(self, :events)
  end
end
