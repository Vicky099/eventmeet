# Mirrors CreateAccountMemberships exactly, one level up: an agency_admin User can manage more
# than one Agency in principle (the join table, not a column on User, keeps that option open even
# though today's provisioning flow only ever creates one row per new agency_admin).
class CreateAgencyMemberships < ActiveRecord::Migration[8.0]
  def change
    create_table :agency_memberships, id: :uuid, default: nil do |t|
      t.references :user,   null: false, type: :uuid, foreign_key: true
      t.references :agency, null: false, type: :uuid, foreign_key: true

      # Single role for now (agency_admin) — a real enum (not a boolean) so it mirrors
      # AccountMembership's own shape and can grow further roles later without a schema change.
      t.integer :role, null: false, default: 0

      t.timestamps
    end

    add_index :agency_memberships, [ :user_id, :agency_id ], unique: true
  end
end
