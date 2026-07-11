# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_07_11_132926) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "account_memberships", id: :uuid, default: nil, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.uuid "account_id", null: false
    t.integer "role", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_account_memberships_on_account_id"
    t.index ["user_id", "account_id"], name: "index_account_memberships_on_user_id_and_account_id", unique: true
    t.index ["user_id"], name: "index_account_memberships_on_user_id"
  end

  create_table "accounts", id: :uuid, default: nil, force: :cascade do |t|
    t.string "name", null: false
    t.string "subdomain_slug", null: false
    t.integer "status", default: 0, null: false
    t.string "plan"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["subdomain_slug"], name: "index_accounts_on_subdomain_slug", unique: true
  end

  create_table "event_staff_assignments", id: :uuid, default: nil, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "event_id", null: false
    t.uuid "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_event_staff_assignments_on_account_id"
    t.index ["event_id", "user_id"], name: "index_event_staff_assignments_on_event_id_and_user_id", unique: true
    t.index ["event_id"], name: "index_event_staff_assignments_on_event_id"
    t.index ["user_id"], name: "index_event_staff_assignments_on_user_id"
  end

  create_table "events", id: :uuid, default: nil, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.integer "mode", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.integer "approval_status", default: 0, null: false
    t.integer "banner_orientation", default: 0, null: false
    t.datetime "starts_at", null: false
    t.datetime "ends_at", null: false
    t.text "address"
    t.string "meeting_link"
    t.jsonb "participant_fields", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "map_url"
    t.index ["account_id", "slug"], name: "index_events_on_account_id_and_slug", unique: true
    t.index ["account_id"], name: "index_events_on_account_id"
  end

  create_table "oauth_access_grants", force: :cascade do |t|
    t.uuid "resource_owner_id", null: false
    t.bigint "application_id", null: false
    t.string "token", null: false
    t.integer "expires_in", null: false
    t.text "redirect_uri", null: false
    t.string "scopes", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "revoked_at"
    t.index ["application_id"], name: "index_oauth_access_grants_on_application_id"
    t.index ["resource_owner_id"], name: "index_oauth_access_grants_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_grants_on_token", unique: true
  end

  create_table "oauth_access_tokens", force: :cascade do |t|
    t.uuid "resource_owner_id"
    t.bigint "application_id", null: false
    t.string "token", null: false
    t.string "refresh_token"
    t.integer "expires_in"
    t.string "scopes"
    t.datetime "created_at", null: false
    t.datetime "revoked_at"
    t.string "previous_refresh_token", default: "", null: false
    t.index ["application_id"], name: "index_oauth_access_tokens_on_application_id"
    t.index ["refresh_token"], name: "index_oauth_access_tokens_on_refresh_token", unique: true
    t.index ["resource_owner_id"], name: "index_oauth_access_tokens_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_tokens_on_token", unique: true
  end

  create_table "oauth_applications", force: :cascade do |t|
    t.string "name", null: false
    t.string "uid", null: false
    t.string "secret", null: false
    t.text "redirect_uri", default: "", null: false
    t.string "scopes", default: "", null: false
    t.boolean "confidential", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "account_id", null: false
    t.index ["account_id"], name: "index_oauth_applications_on_account_id", unique: true
    t.index ["uid"], name: "index_oauth_applications_on_uid", unique: true
  end

  create_table "tenant_domains", id: :uuid, default: nil, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "domain", null: false
    t.integer "kind", default: 0, null: false
    t.datetime "verified_at"
    t.integer "tls_status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_tenant_domains_on_account_id"
    t.index ["domain"], name: "index_tenant_domains_on_domain", unique: true
  end

  create_table "users", id: :uuid, default: nil, force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.boolean "platform_staff", default: false, null: false
    t.string "contact_num"
    t.boolean "must_reset_password", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "account_memberships", "accounts"
  add_foreign_key "account_memberships", "users"
  add_foreign_key "event_staff_assignments", "accounts"
  add_foreign_key "event_staff_assignments", "events"
  add_foreign_key "event_staff_assignments", "users"
  add_foreign_key "events", "accounts"
  add_foreign_key "oauth_access_grants", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_grants", "users", column: "resource_owner_id"
  add_foreign_key "oauth_access_tokens", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_tokens", "users", column: "resource_owner_id"
  add_foreign_key "oauth_applications", "accounts"
  add_foreign_key "tenant_domains", "accounts"
end
