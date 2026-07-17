class AddHasSeatLimitToEvents < ActiveRecord::Migration[8.0]
  def up
    add_column :events, :has_seat_limit, :boolean, null: false, default: false
    # Backfill: any event that already had a seat_limit set was implicitly "has a seat limit" —
    # the new toggle just makes that explicit instead of inferring it from presence.
    execute "UPDATE events SET has_seat_limit = true WHERE seat_limit IS NOT NULL"
  end

  def down
    remove_column :events, :has_seat_limit
  end
end
