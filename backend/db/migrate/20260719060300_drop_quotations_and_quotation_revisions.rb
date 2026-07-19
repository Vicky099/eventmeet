# Fixed-hierarchy pivot (requirement.md revisit): the per-tenant Business-tier pricing negotiation
# this table backed is fully replaced by agency-level contracts (Agency#price_per_event/
# #annual_price, set once by the Super Admin when provisioning the Agency, never negotiated per
# tenant or per event). quotation_revisions first (FK to quotations).
class DropQuotationsAndQuotationRevisions < ActiveRecord::Migration[8.0]
  def up
    TenantRowLevelSecurity.disable!(self, :quotation_revisions)
    TenantRowLevelSecurity.disable!(self, :quotations)
    drop_table :quotation_revisions
    drop_table :quotations
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
