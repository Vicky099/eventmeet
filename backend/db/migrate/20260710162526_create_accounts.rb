class CreateAccounts < ActiveRecord::Migration[8.0]
  def change
    # An Account is a tenant (requirement.md §4.1). Every Event/User-membership/branding/billing
    # record belongs to exactly one Account — this is the row-based isolation boundary (§4.2).
    create_table :accounts, id: :uuid, default: nil do |t|
      t.string :name, null: false

      # Reserved for the tenant Admin Console host: {subdomain_slug}.{platform_domain}.com (§4.3).
      # Format/reserved-word validation lives on the model (Account::RESERVED_SLUGS) — the DB unique
      # index here is the hard backstop, not the primary defense.
      t.string :subdomain_slug, null: false

      # active/suspended — a suspended Account's users cannot log in (Phase 1).
      t.integer :status, null: false, default: 0

      # Placeholder for requirement.md §4.6 (Plan structure: Basic/Pro/Business). Billing is per-event,
      # not per-Account, so this is fleshed out for real in Phase 15 (CapacityAdjustment/Quotation/etc.)
      # — kept nullable here since Phase 0 has no plan-assignment UI yet.
      t.string :plan

      t.timestamps
    end

    add_index :accounts, :subdomain_slug, unique: true
  end
end
