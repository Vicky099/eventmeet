require "rails_helper"

RSpec.describe "Health check", type: :system do
  it "boots the app in a real browser via Playwright" do
    visit "/up"

    expect(page.status_code).to eq(200)
  end
end
