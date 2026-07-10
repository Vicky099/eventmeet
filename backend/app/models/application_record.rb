class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # requirement.md §4.10: every primary/public key is UUIDv7, not a raw sequential integer or plain
  # UUIDv4 — keeps B-tree index locality (time-ordered) while staying a standard UUID variant. Tables
  # are created with `id: :uuid` and no DB-side default (see db/migrate for the pattern); the id is
  # assigned here in Ruby via Ruby's native SecureRandom.uuid_v7 so every model gets it for free.
  before_create :assign_uuid_v7_primary_key

  private

  def assign_uuid_v7_primary_key
    return unless self.class.columns_hash["id"]&.sql_type == "uuid"

    self.id ||= SecureRandom.uuid_v7
  end
end
