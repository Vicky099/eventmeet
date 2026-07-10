require "capybara/rspec"
require "capybara/playwright"

Capybara.default_max_wait_time = 5

RSpec.configure do |config|
  config.before(:each, type: :system) do
    driven_by :playwright, screen_size: [ 1400, 1400 ], options: {
      browser_type: :chromium,
      headless: ENV["PLAYWRIGHT_HEADFUL"].blank?
    }
  end
end
