# Phase 9 (requirement.md §5.15: "keep a lightweight time-series — a rolling per-minute bucket —
# to drive a live sparkline of registration/check-in velocity"). Plain (non-partitioned) table —
# unlike ScanEvent/Attendance this isn't an unbounded event log, it's one row per event per metric
# per minute, small and cheap to retain.
class CreateLiveMetricBuckets < ActiveRecord::Migration[8.0]
  def change
    create_table :live_metric_buckets, id: :uuid, default: nil do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :event, type: :uuid, null: false, foreign_key: true
      # registration/check_in — the two velocities requirement.md §5.15 calls out by name.
      t.integer :metric, null: false
      t.datetime :bucket_at, null: false
      t.integer :count, null: false, default: 0

      t.timestamps
    end

    add_index :live_metric_buckets, [ :event_id, :metric, :bucket_at ], unique: true,
      name: "index_live_metric_buckets_on_event_metric_bucket"

    TenantRowLevelSecurity.enable!(self, :live_metric_buckets)
  end
end
