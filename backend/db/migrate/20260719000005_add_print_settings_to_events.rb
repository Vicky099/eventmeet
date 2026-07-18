# Phase 10 — Print Agent (Electron) Integration (requirement.md §5.5.1: "auto-print on/off toggle
# per event"). auto_print_enabled is the real zero-click flow this phase's checklist describes —
# every qualifying check-in scan prints automatically when it's on, no operator interaction.
# default_print_station_id is what a manual Print click (participant list/show, no explicit
# station chosen) and check-in's own print actions target when nothing more specific is given —
# nullable, since an event can exist with print stations configured but none marked default yet
# (falls back to the PDF-download path, per PrintTriggerService).
class AddPrintSettingsToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :auto_print_enabled, :boolean, null: false, default: false
    add_reference :events, :default_print_station, type: :uuid, foreign_key: { to_table: :print_stations }
  end
end
