# Phase 13 — Communications, revisited: "admin ask to have a customized email template for
# participant registration ... store that email template with placeholder and when we send the
# email on registration we fill those placeholders." Same shape as Badge (per-event instantiation,
# db/migrate/*_create_badges.rb) — customized per Event, not per tenant, since an admin running
# several events under one tenant wants a different registration email per event, not one shared
# tenant-wide template. `account_id` is still carried directly (not just reachable via `event.
# account`) because TenantScoped's default_scope filters on it, same as Badge's own account_id
# column alongside its event_id. `kind` is an enum from day one (starting with just
# participant_registration) so a future email trigger (rejection notice, resend invitation, ...)
# is a new enum value + a mailer branch, not a schema change. One row per kind per event (the
# unique index below) rather than a freeform library — an admin edits "the" template for a given
# trigger on a given event, there's no reason to ever have two.
class CreateEmailTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :email_templates, id: :uuid, default: nil do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.references :event, null: false, type: :uuid, foreign_key: true

      t.integer :kind, null: false
      t.string :subject, null: false
      t.text :html_body, null: false, default: ""
      # Lets an admin revert to the built-in default without losing their drafted HTML — distinct
      # from destroying the row entirely (the "Reset to Default" action).
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :email_templates, [ :event_id, :kind ], unique: true

    TenantRowLevelSecurity.enable!(self, :email_templates)
  end
end
