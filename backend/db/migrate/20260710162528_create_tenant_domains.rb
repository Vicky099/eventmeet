class CreateTenantDomains < ActiveRecord::Migration[8.0]
  def change
    # requirement.md §4.3: one row per subdomain/custom-domain a tenant is reachable on. The tenant's
    # {slug}.{platform_domain}.com admin-console subdomain gets its own row (kind: subdomain, verified
    # at creation) alongside any later custom domain (kind: custom, verified via DNS + Caddy on-demand
    # TLS, Phase 18) used by the Next.js public site.
    create_table :tenant_domains, id: :uuid, default: nil do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true

      t.string :domain, null: false
      t.integer :kind, null: false, default: 0 # subdomain / custom
      t.datetime :verified_at
      t.integer :tls_status, null: false, default: 0 # pending / active / failed

      t.timestamps
    end

    add_index :tenant_domains, :domain, unique: true
  end
end
