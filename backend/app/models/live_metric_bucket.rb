# Phase 9 (requirement.md §5.15): "a rolling per-minute bucket derived from ScanEvent/Participant
# timestamps ... to drive a live sparkline of registration/check-in velocity — cheap to compute
# incrementally." One row per event/metric/minute; ScanService and Participant#increment_live_stats!
# both call .increment! after their own write.
class LiveMetricBucket < ApplicationRecord
  include TenantScoped

  belongs_to :event

  enum :metric, { registration: 0, check_in: 1 }

  # Atomic upsert (requirement.md §5.15's "cheap to compute incrementally" — a single INSERT ...
  # ON CONFLICT DO UPDATE statement, not a read-then-write) — many concurrent scans in the same
  # minute must all land, not race each other the same way EventLiveStats#record_check_in! guards
  # against for its own counters.
  def self.increment!(event:, metric:, at: Time.current)
    bucket_at = at.change(sec: 0)

    connection.execute(<<~SQL.squish)
      INSERT INTO live_metric_buckets (id, account_id, event_id, metric, bucket_at, count, created_at, updated_at)
      VALUES (
        #{connection.quote(SecureRandom.uuid_v7)},
        #{connection.quote(event.account_id)},
        #{connection.quote(event.id)},
        #{connection.quote(metrics.fetch(metric.to_s))},
        #{connection.quote(bucket_at)},
        1,
        now(),
        now()
      )
      ON CONFLICT (event_id, metric, bucket_at)
      DO UPDATE SET count = live_metric_buckets.count + 1, updated_at = now()
    SQL
  end

  # Ordered, zero-filled series for the sparkline partial — `minutes` back from now, one point per
  # minute, so a quiet minute renders as a real 0 rather than a gap the partial would have to
  # special-case.
  def self.sparkline_series(event:, metric:, minutes: 30)
    now = Time.current.change(sec: 0)
    counts = where(event: event, metric: metric, bucket_at: (minutes - 1).minutes.ago(now)..now)
      .pluck(:bucket_at, :count).to_h

    (minutes - 1).downto(0).map do |offset|
      bucket_at = now - offset.minutes
      [ bucket_at, counts[bucket_at] || 0 ]
    end
  end
end
