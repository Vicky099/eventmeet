# Agency → Tenant account switch (single sign-on handoff): a short-lived, single-use token that
# lets an agency admin, already signed in on their own Agency Console subdomain, land signed in on
# one of their own tenant's Admin Console subdomains too — without a second login. Platform-level,
# like Account/Agency themselves — no account_id-scoped TenantScoped/RLS, since it's created while
# Current.agency is set and Current.account is nil (AccountSwitch#generate_for's own comment).
class CreateAccountSwitches < ActiveRecord::Migration[8.0]
  def change
    create_table :account_switches, id: :uuid, default: nil do |t|
      t.references :user, null: false, type: :uuid, foreign_key: true
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.string :token, null: false
      t.datetime :expires_at, null: false
      t.datetime :redeemed_at

      t.timestamps
    end

    add_index :account_switches, :token, unique: true
  end
end
