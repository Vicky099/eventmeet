# Agency layer: Super Admin grants an Agency a fixed pool of N events at one fixed price; the
# Agency's own tenants then create events against that pool without a per-event Quotation/
# content-review round trip (see Event#agency_funded?). Platform-level, like Account itself — no
# account_id column, not TenantScoped, no TenantRowLevelSecurity (mirrors CreateAccounts, which
# has none either for the same reason: this table sits *above* the tenant boundary, not inside it).
class CreateAgencies < ActiveRecord::Migration[8.0]
  def change
    create_table :agencies, id: :uuid, default: nil do |t|
      t.string :name, null: false
      t.string :contact_email
      t.string :contact_num

      # active/suspended — mirrors Account#status exactly.
      t.integer :status, null: false, default: 0

      t.decimal :price_per_event, precision: 12, scale: 2, null: false
      t.string :currency, null: false, default: "INR"

      # Fixed decrementing pool: events_used increments (atomically, Agency#consume_event_slot!)
      # each time one of this agency's tenants creates an event; grant_more! is the only way
      # events_granted increases (Super Admin "top up" action).
      t.integer :events_granted, null: false, default: 0
      t.integer :events_used, null: false, default: 0

      t.timestamps
    end
  end
end
