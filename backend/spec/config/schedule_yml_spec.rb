require "rails_helper"

# Plain config sanity, not a Sidekiq::Cron::Job integration test — this suite runs jobs inline via
# ActiveJob::TestHelper, never against real Sidekiq/Redis (config/environments/test.rb), so this
# doesn't touch Sidekiq::Cron::Job.load_from_hash! at all. Just enough to catch a typo'd class name
# or malformed cron string in config/schedule.yml before it silently no-ops in production.
RSpec.describe "config/schedule.yml" do
  let(:entries) { YAML.load_file(Rails.root.join("config/schedule.yml")) }

  it "is present and non-empty" do
    expect(entries).to be_a(Hash)
    expect(entries).not_to be_empty
  end

  it "points every entry at a real, loadable job class" do
    entries.each_value do |entry|
      expect { entry.fetch("class").constantize }.not_to raise_error
    end
  end

  it "gives every entry a syntactically valid cron expression" do
    entries.each_value do |entry|
      expect(Fugit::Cron.parse(entry.fetch("cron"))).not_to be_nil
    end
  end

  it "schedules exactly the jobs this app currently expects" do
    expect(entries.keys).to contain_exactly("event_scheduler", "invoice_generation")
  end
end
