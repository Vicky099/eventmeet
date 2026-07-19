# Fixed-hierarchy pivot (requirement.md revisit, confirmed with the user): an Agency now gets its
# own subdomain — a third console tier alongside the Platform Console and tenant Admin Console
# (Hosting::TenantSubdomainConstraint already matches any syntactically valid subdomain; only
# TenantResolvable's own DB lookup distinguishes an Account slug from an Agency slug, see that
# concern's own comment) — and one of two billing contracts: `per_event` (the existing fixed pool,
# unchanged) or `annual` (new: unlimited events, one upfront lump-sum payment gates everything).
class AddSubdomainSlugAndBillingCycleToAgencies < ActiveRecord::Migration[8.0]
  def change
    add_column :agencies, :subdomain_slug, :string
    add_index :agencies, :subdomain_slug, unique: true

    add_column :agencies, :billing_cycle, :integer, null: false, default: 0
    add_column :agencies, :annual_price, :decimal, precision: 12, scale: 2

    # events_granted/events_used/price_per_event stay NOT NULL at the column level (unchanged) —
    # an `annual` agency just always has 0/0/whatever-was-last-set there, never read; Agency's own
    # model validations (not the DB) are what actually make price_per_event conditionally required
    # now (if: :per_event?).
    change_column_null :agencies, :price_per_event, true
  end
end
