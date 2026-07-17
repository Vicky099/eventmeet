# Phase 13 — Communications (requirement.md §3.10, §5.10, §8): "delivery-state tracking
# (state_of_mail: pending/sent/failed)" for email, generalized with a channel column so the exact
# same table also tracks WhatsApp (§8: "no new durable entity beyond extending the existing email
# delivery-state pattern... with a channel (email/whatsapp)"). One row per actual delivery
# attempt — created eagerly (status: pending) before NotificationDeliveryJob is even enqueued, so
# a row exists to show "pending" immediately rather than only once the job happens to run.
#
# notifiable (polymorphic) is what the notification is *about* — an Event for a rejection, a
# Participant for a registration confirmation — not who it's *to* (`to`, a plain string: an email
# address or a phone number depending on channel, matching requirement.md §8's "sent... to the
# recipient User's existing contact_num field" for WhatsApp specifically, and Participant#email/
# User#email for the email channel — two different owning models, so a single polymorphic
# "recipient" association would need to handle both anyway; a plain string is simpler and is all
# any caller actually needs to re-render/audit what was sent).
class CreateNotifications < ActiveRecord::Migration[8.0]
  def change
    create_table :notifications, id: :uuid, default: nil do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.references :notifiable, null: false, type: :uuid, polymorphic: true

      t.integer :channel, null: false
      t.integer :status, null: false, default: 0
      t.string :to, null: false
      t.string :subject
      t.text :body
      t.text :error_message
      t.datetime :sent_at

      t.timestamps
    end

    TenantRowLevelSecurity.enable!(self, :notifications)
  end
end
