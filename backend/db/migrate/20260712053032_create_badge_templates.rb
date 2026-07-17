# Phase 8 — Badge Design & Printing (requirement.md §3.6, §5.5): "reusable/sharable templates
# across events within a tenant" — account-scoped, deliberately not nested under any one Event.
# `Badge` (next migration) is the per-event instantiation; a BadgeTemplate is only ever the
# starting point one gets copied from.
class CreateBadgeTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :badge_templates, id: :uuid, default: nil do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true

      t.string :name, null: false
      # Combined HTML+CSS (a GrapesJS canvas exports both together) — the one string
      # BadgeReformService substitutes tokens into and Grover renders straight to PDF.
      t.text :content, null: false, default: ""
      # $OTHER1$/$OTHER2$/$OTHER3$ -> which Participant attribute each slot pulls from (e.g.
      # {"OTHER1" => "company"}) — see Badge::MAPPABLE_FIELDS for the allowlist.
      t.jsonb :mapping, null: false, default: {}
      # badge/wristband (requirement.md §3.6)
      t.integer :output_type, null: false, default: 0
      t.decimal :width_cm, precision: 6, scale: 2, null: false
      t.decimal :height_cm, precision: 6, scale: 2, null: false

      t.timestamps
    end

    TenantRowLevelSecurity.enable!(self, :badge_templates)
  end
end
