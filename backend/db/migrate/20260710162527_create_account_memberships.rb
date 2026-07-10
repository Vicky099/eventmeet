class CreateAccountMemberships < ActiveRecord::Migration[8.0]
  def change
    # requirement.md §4.1: users can belong to more than one Account (e.g. an agency running events
    # for multiple clients), with a distinct role per membership — a join entity, not a single `role`
    # column on User. platform_staff Users (§4.1) hold NO AccountMembership row at all.
    create_table :account_memberships, id: :uuid, default: nil do |t|
      t.references :user,    null: false, type: :uuid, foreign_key: true
      t.references :account, null: false, type: :uuid, foreign_key: true

      # requirement.md §5.1: configurable roles per Account rather than a fixed platform-wide enum —
      # Owner/Event Manager/Check-in Staff/Finance-readonly to start; Pundit policies key off this.
      t.integer :role, null: false, default: 0

      t.timestamps
    end

    add_index :account_memberships, [ :user_id, :account_id ], unique: true
  end
end
