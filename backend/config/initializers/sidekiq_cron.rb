# Loads config/schedule.yml into Redis once, on the Sidekiq server process's own boot — not the
# Rails web server's (`config.on(:startup)` only fires for `bin/jobs`/`sidekiq`, never `puma`),
# and not per-request. `load_from_hash!` (the bang variant) also deletes any cron job that's been
# removed from the YAML but is still sitting in Redis from a previous deploy — the file is the
# single source of truth for what should be scheduled, not an initial seed that then drifts.
Sidekiq.configure_server do |config|
  config.on(:startup) do
    schedule_file = Rails.root.join("config/schedule.yml")
    Sidekiq::Cron::Job.load_from_hash!(YAML.load_file(schedule_file)) if File.exist?(schedule_file)
  end
end
