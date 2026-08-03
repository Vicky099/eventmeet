class AddStatusToAccountMemberships < ActiveRecord::Migration[8.0]
  def change
    add_column :account_memberships, :status, :integer, null: false, default: 0
  end
end
