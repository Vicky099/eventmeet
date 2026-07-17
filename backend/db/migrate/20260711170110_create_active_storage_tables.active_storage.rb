# This migration comes from active_storage (originally 20170806125915) — hand-edited to use uuid
# ids/foreign keys instead of the gem's own bigint default. Every one of our own tables uses
# `id: :uuid` with no DB-side default, because ApplicationRecord assigns a real UUIDv7 in Ruby on
# create (requirement.md §4.10) — but ActiveStorage::Blob/Attachment/VariantRecord are framework
# classes that inherit from ActiveStorage::Record, not our ApplicationRecord, so that hook never
# runs for them. These three get a real DB-side default instead (`gen_random_uuid()`, from the
# already-enabled pgcrypto extension) — a plain UUIDv4, not v7, which is fine: these are
# Rails-internal plumbing tables, not the tenant-facing/externally-exposed records §4.10's UUIDv7
# requirement is actually about. `active_storage_attachments.record_id` is a polymorphic FK that
# has to be able to hold a Participant/Event/etc.'s own uuid id, so a bigint column here would
# simply never match.
class CreateActiveStorageTables < ActiveRecord::Migration[7.0]
  def change
    create_table :active_storage_blobs, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string   :key,          null: false
      t.string   :filename,     null: false
      t.string   :content_type
      t.text     :metadata
      t.string   :service_name, null: false
      t.bigint   :byte_size,    null: false
      t.string   :checksum

      t.datetime :created_at, precision: 6, null: false

      t.index [ :key ], unique: true
    end

    create_table :active_storage_attachments, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string     :name,     null: false
      t.references :record,   null: false, polymorphic: true, index: false, type: :uuid
      t.references :blob,     null: false, type: :uuid

      t.datetime :created_at, precision: 6, null: false

      t.index [ :record_type, :record_id, :name, :blob_id ], name: :index_active_storage_attachments_uniqueness, unique: true
      t.foreign_key :active_storage_blobs, column: :blob_id
    end

    create_table :active_storage_variant_records, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.belongs_to :blob, null: false, index: false, type: :uuid
      t.string :variation_digest, null: false

      t.index [ :blob_id, :variation_digest ], name: :index_active_storage_variant_records_uniqueness, unique: true
      t.foreign_key :active_storage_blobs, column: :blob_id
    end
  end
end
