# Optional — a tenant Account may or may not sit under an Agency (requirement.md revisit: some
# tenants are still provisioned directly by the Super Admin, no agency involved at all).
class AddAgencyIdToAccounts < ActiveRecord::Migration[8.0]
  def change
    add_reference :accounts, :agency, type: :uuid, foreign_key: true, null: true
  end
end
