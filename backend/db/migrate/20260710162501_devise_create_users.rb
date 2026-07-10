# frozen_string_literal: true

class DeviseCreateUsers < ActiveRecord::Migration[8.0]
  def change
    # id: :uuid, default: nil — no DB-side default. ApplicationRecord#assign_uuid_v7_primary_key
    # (app/models/application_record.rb) assigns SecureRandom.uuid_v7 in Ruby before every insert,
    # per requirement.md §4.10 (UUIDv7 primary keys for index locality).
    create_table :users, id: :uuid, default: nil do |t|
      ## Database authenticatable
      t.string :email,              null: false, default: ""
      t.string :encrypted_password, null: false, default: ""

      ## Recoverable
      t.string   :reset_password_token
      t.datetime :reset_password_sent_at

      ## Rememberable
      t.datetime :remember_created_at

      ## requirement.md §4.1: platform_staff distinguishes Super Admin/Platform Console operators —
      ## these users hold no AccountMembership row at all and authenticate at the apex domain only.
      t.boolean :platform_staff, null: false, default: false

      ## requirement.md §8 (v10): used for WhatsApp/Gupshup delivery later (Phase 13) — no separate
      ## WhatsApp-specific field.
      t.string :contact_num

      ## requirement.md §3.1: forced password reset for newly created/invited users (temp password flow).
      t.boolean :must_reset_password, null: false, default: false

      t.timestamps null: false
    end

    add_index :users, :email,                unique: true
    add_index :users, :reset_password_token, unique: true
  end
end
