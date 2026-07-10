# Mail now delivers via deliver_later (Sidekiq in real life, the :test ActiveJob adapter per
# config/environments/test.rb) — request specs asserting on ActionMailer::Base.deliveries need to
# actually run the enqueued job first, via perform_enqueued_jobs.
RSpec.configure do |config|
  config.include ActiveJob::TestHelper, type: :request
end
