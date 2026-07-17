# requirement.md §4.10: "ScanEvent/Attendance partitioning: monthly range partitioning on the
# write timestamp — the standard approach for time-series/event-log-style tables." Native Postgres
# declarative partitioning, not a gem (pg 1.6.3/Rails 8.0.5 need nothing extra) — mirrors
# lib/tenant_row_level_security.rb's shape: a small helper called from migrations, not a DSL of
# its own.
#
# Postgres requires a partitioned table's primary key to include the partition column, so these
# tables get a *composite* primary key `(id, <partition_column>)` instead of the bare `id` every
# other table in this app uses (ApplicationRecord's UUIDv7 assignment still works unchanged — it
# only cares that a plain `id` column with sql_type "uuid" exists, not that it's the sole PK).
# That composite PK is also why nothing in app code ever calls `ScanEvent.find(uuid)`/
# `Attendance.find(uuid)` (single-arg find expects the full composite key) — `find_by(id: ...)`/
# `where(id: ...)` work fine, since `id` remains a real, effectively-unique column even without a
# database-enforced global unique constraint on it alone (same accepted collision-probability
# argument Participant#generate_unique_hex_id already makes for a random identifier that isn't
# backed by a real DB-wide unique index).
#
# A consequence of no partition-spanning unique index on bare `id`: nothing can hold a real
# foreign key *into* one of these tables (Postgres requires the referenced columns to be covered
# by a unique constraint) — see Attendance#scan_event_id's own comment for the concrete case.
module MonthlyRangePartitioning
  # Creates the partitioned parent table plus one child partition per calendar month from
  # `months_behind` before the current month through `months_ago` after it (inclusive), and
  # enables the same tenant-isolation RLS policy every other tenant-scoped table gets.
  #
  # `columns` receives the same block a normal `create_table` would — callers add every column
  # except `id`/the partition column, both of which this method adds itself so every partitioned
  # table gets them the same way.
  def self.create_parent!(migration, table_name, partition_column:, months_behind: 1, months_ahead: 2, &columns)
    migration.execute <<~SQL.squish
      CREATE TABLE #{table_name} (
        id uuid NOT NULL,
        #{partition_column} timestamp(6) without time zone NOT NULL,
        PRIMARY KEY (id, #{partition_column})
      ) PARTITION BY RANGE (#{partition_column});
    SQL

    migration.change_table table_name, &columns if columns

    TenantRowLevelSecurity.enable!(migration, table_name)

    ensure_partitions!(migration, table_name, partition_column: partition_column,
      months_behind: months_behind, months_ahead: months_ahead)
  end

  # Idempotent — safe to call repeatedly (a migration's initial call, then PartitionMaintenanceJob
  # ticking forward over the table's lifetime). Creates whatever calendar-month partitions in the
  # requested window don't already exist yet; never touches/drops an existing one.
  def self.ensure_partitions!(migration_or_connection, table_name, partition_column:, months_behind: 1, months_ahead: 2)
    connection = migration_or_connection.respond_to?(:execute) ? migration_or_connection : migration_or_connection.connection

    (-months_behind..months_ahead).each do |offset|
      month_start = offset.months.since(Date.current.beginning_of_month)
      create_partition_for!(connection, table_name, month_start, partition_column: partition_column)
    end
  end

  def self.create_partition_for!(connection, table_name, date, partition_column:)
    month_start = date.beginning_of_month
    month_end = month_start.next_month
    partition_name = "#{table_name}_#{month_start.strftime('%Y_%m')}"

    return if connection.table_exists?(partition_name)

    connection.execute <<~SQL.squish
      CREATE TABLE #{partition_name} PARTITION OF #{table_name}
        FOR VALUES FROM ('#{month_start.to_fs(:db)}') TO ('#{month_end.to_fs(:db)}');
    SQL
  end
end
