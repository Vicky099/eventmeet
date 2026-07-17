# Phase 9 (requirement.md §4.10). ScanEvent/Attendance's monthly partitions are created a few
# months ahead at migration time (lib/monthly_range_partitioning.rb), but that window doesn't move
# on its own — without something extending it, inserts would eventually start failing once "now"
# outruns the last partition ever created. Self-reschedules the same way EventSchedulerJob does
# (no sidekiq-cron dependency); a monthly cadence is plenty since ensure_partitions! keeps several
# months of headroom on every run, not just one.
#
# Bootstrapping: same as EventSchedulerJob — something needs to call
# `PartitionMaintenanceJob.perform_later` once to start the chain.
class PartitionMaintenanceJob < ApplicationJob
  queue_as :default

  RESCHEDULE_INTERVAL = 30.days
  PARTITIONED_TABLES = { scan_events: :scanned_at, attendances: :occurred_at }.freeze

  def perform
    PARTITIONED_TABLES.each do |table_name, partition_column|
      MonthlyRangePartitioning.ensure_partitions!(
        ActiveRecord::Base.connection, table_name, partition_column: partition_column,
        months_behind: 1, months_ahead: 2
      )
    end
  ensure
    self.class.set(wait: RESCHEDULE_INTERVAL).perform_later
  end
end
