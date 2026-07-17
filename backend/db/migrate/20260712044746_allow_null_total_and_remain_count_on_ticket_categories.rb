class AllowNullTotalAndRemainCountOnTicketCategories < ActiveRecord::Migration[8.0]
  # A category's own "Total seats" field only exists when its Event has a seat limit
  # (requirement.md §5.3 revisit) — an event with no seat limit has categories with no tracked
  # capacity at all ("unlimited"), which `total_count`/`remain_count` need to be able to represent
  # as nil rather than a real number.
  def change
    change_column_null :ticket_categories, :total_count, true
    change_column_null :ticket_categories, :remain_count, true
  end
end
