# frozen_string_literal: true

# Customized from the generated Doorkeeper template (requirement.md §4.9 item 4/§5.1):
#   - resource_owner references are `type: :uuid` with a real foreign key to `users` — the
#     generator defaults to bigint, but the resource owner here is always `User`
#     (id: uuid, see ApplicationRecord) for both Warden scopes (:user and :platform_staff).
#   - oauth_applications/oauth_access_grants/oauth_access_tokens keep the gem's own bigint `id`
#     — deliberately not forced onto the app's UUIDv7 convention (requirement.md §4.10): these
#     rows are never referenced by their own `id` outside Doorkeeper's internal associations, the
#     public-facing identifier a client actually uses is `uid`/`secret` (already opaque, generated
#     by the gem), and reopening Doorkeeper's models to swap PK generation is a lot of gem-internals
#     surface area for a purely-internal id column. account_id (added in the next migration) is
#     what ties an Application back to the UUID domain model.
class CreateDoorkeeperTables < ActiveRecord::Migration[8.0]
  def change
    create_table :oauth_applications do |t|
      t.string  :name,    null: false
      t.string  :uid,     null: false
      # Remove `null: false` or use conditional constraint if you are planning to use public clients.
      t.string  :secret,  null: false

      # default: "" (not the generator's plain `null: false`) — MVP only enables the
      # client_credentials grant flow (config/initializers/doorkeeper.rb), which doesn't use a
      # redirect URI at all; the model-level validation already allows it blank for that flow
      # (Doorkeeper::RedirectUriValidator + allow_blank_redirect_uri's default), but the column
      # still needs a non-null value to write blank rather than nil.
      t.text    :redirect_uri, null: false, default: ""
      t.string  :scopes,       null: false, default: ''
      t.boolean :confidential, null: false, default: true
      t.timestamps             null: false
    end

    add_index :oauth_applications, :uid, unique: true

    create_table :oauth_access_grants do |t|
      t.references :resource_owner,  null: false, type: :uuid
      t.references :application,     null: false
      t.string   :token,             null: false
      t.integer  :expires_in,        null: false
      t.text     :redirect_uri,      null: false
      t.string   :scopes,            null: false, default: ''
      t.datetime :created_at,        null: false
      t.datetime :revoked_at
    end

    add_index :oauth_access_grants, :token, unique: true
    add_foreign_key(
      :oauth_access_grants,
      :oauth_applications,
      column: :application_id
    )

    create_table :oauth_access_tokens do |t|
      t.references :resource_owner, index: true, type: :uuid

      # Remove `null: false` if you are planning to use Password
      # Credentials Grant flow that doesn't require an application.
      t.references :application,    null: false

      # If you use a custom token generator you may need to change this column
      # from string to text, so that it accepts tokens larger than 255
      # characters. More info on custom token generators in:
      # https://github.com/doorkeeper-gem/doorkeeper/tree/v3.0.0.rc1#custom-access-token-generator
      #
      # t.text :token, null: false
      t.string :token, null: false

      t.string   :refresh_token
      t.integer  :expires_in
      t.string   :scopes
      t.datetime :created_at, null: false
      t.datetime :revoked_at

      # The authorization server MAY issue a new refresh token, in which case
      # *the client MUST discard the old refresh token* and replace it with the
      # new refresh token. The authorization server MAY revoke the old
      # refresh token after issuing a new refresh token to the client.
      # @see https://datatracker.ietf.org/doc/html/rfc6749#section-6
      #
      # Doorkeeper implementation: if there is a `previous_refresh_token` column,
      # refresh tokens will be revoked after a related access token is used.
      # If there is no `previous_refresh_token` column, previous tokens are
      # revoked as soon as a new access token is created.
      #
      # Comment out this line if you want refresh tokens to be instantly
      # revoked after use.
      t.string   :previous_refresh_token, null: false, default: ""
    end

    add_index :oauth_access_tokens, :token, unique: true

    # See https://github.com/doorkeeper-gem/doorkeeper/issues/1592
    if ActiveRecord::Base.connection.adapter_name == "SQLServer"
      execute <<~SQL.squish
        CREATE UNIQUE NONCLUSTERED INDEX index_oauth_access_tokens_on_refresh_token ON oauth_access_tokens(refresh_token)
        WHERE refresh_token IS NOT NULL
      SQL
    else
      add_index :oauth_access_tokens, :refresh_token, unique: true
    end

    add_foreign_key(
      :oauth_access_tokens,
      :oauth_applications,
      column: :application_id
    )

    add_foreign_key :oauth_access_grants, :users, column: :resource_owner_id
    add_foreign_key :oauth_access_tokens, :users, column: :resource_owner_id
  end
end
