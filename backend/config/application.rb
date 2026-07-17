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

    # Phase 9 (requirement.md §4.10): ScanEvent/Attendance are natively partitioned Postgres
    # tables (see lib/monthly_range_partitioning.rb) — the Ruby schema.rb dumper can't represent
    # `PARTITION BY`/child partitions at all, so db/schema.rb is replaced by a raw pg_dump
    # (db/structure.sql) as the source of truth for `db:schema:load`/test-DB setup.
    config.active_record.schema_format = :sql
  end
end
