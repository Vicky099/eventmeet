# Phase 9 — Check-in, Attendance & Real-Time Live Dashboards (requirement.md §3.7, §5.6, §5.15,
# §6 item 13, §4.10). ScanEvent is the "unified single scan, many purposes" abstraction —
# check-in/out, on-demand print, lead-retrieval (Phase 12), triggered-content (Phase 12+) all
# write here instead of parallel scan endpoints.
class CreateScanEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :scan_events, id: :uuid, default: nil do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :event, type: :uuid, null: false, foreign_key: true
      t.references :participant, type: :uuid, null: false, foreign_key: true
      # check_in/check_out/print/lead_retrieval/triggered_content (requirement.md §6 item 13) —
      # default :check_in since that's by far the most common scan on the kiosk flow this phase
      # ships (ScanService always passes scan_type explicitly regardless).
      t.integer :scan_type, null: false, default: 0
      # kiosk/manual/agent/system — :system is this phase's own addition (not in the checklist's
      # literal list) for EventCompletionService's auto-checkout, which isn't a human scan at all.
      t.integer :source, null: false, default: 1
      t.datetime :scanned_at, null: false

      t.timestamps
    end

    add_index :scan_events, [ :event_id, :participant_id, :scan_type, :scanned_at ],
      name: "index_scan_events_on_event_participant_type_scanned_at"
    add_index :scan_events, [ :participant_id, :scan_type, :scanned_at ],
      name: "index_scan_events_on_participant_type_scanned_at"

    TenantRowLevelSecurity.enable!(self, :scan_events)
  end
end
