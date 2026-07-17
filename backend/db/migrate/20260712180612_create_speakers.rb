# Phase 11 — Agenda, Speakers & Sessions (requirement.md §3.8, §5.7): "Speakers with
# company/bio metadata and photo" — account-scoped and reusable across events (§5.7's
# "speaker portal" and cross-event reuse both assume one Speaker record, not a copy per event),
# same shape BadgeTemplate already established for account-level reusable records.
class CreateSpeakers < ActiveRecord::Migration[8.0]
  def change
    create_table :speakers, id: :uuid, default: nil do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true

      t.string :name, null: false
      t.string :company
      t.text :bio

      t.timestamps
    end

    TenantRowLevelSecurity.enable!(self, :speakers)
  end
end
