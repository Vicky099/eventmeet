require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Eventmeet
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    config.generators do |g|
      g.test_framework :rspec,
        fixtures: true,
        view_specs: false,
        helper_specs: false,
        routing_specs: false,
        request_specs: true
    end

    # Background jobs run through Sidekiq everywhere except test (see config/environments/test.rb),
    # per requirement.md §4.10 — replaces the Rails 8 default Solid Queue.
    config.active_job.queue_adapter = :sidekiq

    # requirement.md §4.2: every tenant-scoped table gets a Postgres Row Level Security policy
    # (lib/tenant_row_level_security.rb) — the Ruby schema.rb dumper can't represent
    # `ENABLE ROW LEVEL SECURITY`/`CREATE POLICY` at all, so db/schema.rb is replaced by a raw
    # pg_dump (db/structure.sql) as the source of truth for `db:schema:load`/test-DB setup.
    config.active_record.schema_format = :sql

    # requirement.md §4.2: every tenant-scoped model (Participant, Badge/BadgeTemplate, Speaker —
    # anything with an attached photo/logo) raises TenantScoped::MissingTenantContextError if
    # queried with no Current.account set, by design (the whole point of that guard). Rails'
    # default `belongs_to :record, touch: true` on ActiveStorage::Attachment (on since Rails
    # 7.1, config.active_storage.touch_attachment_records — HTTP freshness-caching support this
    # app doesn't use anywhere, confirmed: no fresh_when/stale? calls in app/) does exactly that:
    # ActiveStorage::AnalyzeJob (Rails' own background job, enqueued automatically whenever an
    # image/video is attached, with no way for this app's own "jobs must set Current.account
    # explicitly" convention to reach it) touches the blob's owning record after analyzing it —
    # loading that record, unscoped, is what raised live. This app has no use for the caching
    # feature this touch exists to support, so the correct fix is turning it off, not threading
    # tenant context through a framework-internal job this app doesn't control.
    config.active_storage.touch_attachment_records = false
  end
end
