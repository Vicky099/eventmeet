# requirement.md §4.2: "row-level isolation via a mandatory account_id on every tenant-scoped
# table, enforced at the ORM layer (default-scoped, never optional) plus database-level Row Level
# Security as defense-in-depth."
#
# TenantScoped (app/models/concerns/tenant_scoped.rb) is the primary defense — it's what makes an
# application bug (a forgotten .where(account_id: ...)) impossible by construction. This is the
# second, independent layer: even a raw SQL query or a bug in TenantScoped itself still can't read
# another tenant's rows, because Postgres itself refuses at the row level.
#
# Usage in a migration, once a tenant-scoped table exists (starting Phase 4's Event):
#
#   class CreateEvents < ActiveRecord::Migration[8.0]
#     def change
#       create_table :events, id: :uuid, default: nil do |t|
#         t.references :account, null: false, type: :uuid, foreign_key: true
#         ...
#       end
#
#       TenantRowLevelSecurity.enable!(self, :events)
#     end
#   end
#
# The policy checks the `app.current_account_id` session variable, which
# TenantResolvable (app/controllers/concerns) sets for the duration of every tenant-scoped request
# via around_action — see that file for the request-cycle half of this mechanism.
module TenantRowLevelSecurity
  def self.enable!(migration, table_name)
    migration.execute <<~SQL.squish
      ALTER TABLE #{table_name} ENABLE ROW LEVEL SECURITY;
    SQL

    migration.execute <<~SQL.squish
      CREATE POLICY tenant_isolation ON #{table_name}
        USING (account_id = current_setting('app.current_account_id', true)::uuid);
    SQL
  end

  def self.disable!(migration, table_name)
    migration.execute "DROP POLICY IF EXISTS tenant_isolation ON #{table_name};"
    migration.execute "ALTER TABLE #{table_name} DISABLE ROW LEVEL SECURITY;"
  end
end
