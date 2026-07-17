# requirement.md revisit: "While registering the Tenant, we should capture ... Name, contact
# email, contact num, Logo, sender email, subdomain, admin email" plus "the event timezone" (the
# tenant's own operating timezone — see Account#time_zone's own comment). Logo needs no column of
# its own (has_one_attached :logo, app/models/account.rb) — everything else here does.
#
# contact_email/contact_num/sender_email are nullable at the DB level deliberately: Account's own
# presence validation for them is scoped `on: :create` only, so an already-provisioned tenant
# (from before this migration) can still be edited/suspended/reinstated without being force-
# blocked until someone backfills these — only *new* tenant registrations require them. time_zone
# is the one exception — `null: false, default: "UTC"` — every existing row gets a real value
# immediately (Postgres applies the DEFAULT to existing rows as part of this same statement), so
# TenantResolvable's own Time.zone application never has to handle a blank tenant timezone at all.
class AddTenantIntakeFieldsToAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :accounts, :contact_email, :string
    add_column :accounts, :contact_num, :string
    add_column :accounts, :sender_email, :string
    add_column :accounts, :time_zone, :string, null: false, default: "UTC"
  end
end
