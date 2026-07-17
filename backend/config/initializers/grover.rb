# Phase 8 — Badge Design & Printing (requirement.md §3.6, §5.5). Grover shells out to Node.js
# (lib/grover/js/processor.cjs, resolved from `puppeteer-core` in this app's own package.json —
# see backend/package.json) to drive a real Chrome/Chromium instance via CDP. Puppeteer-core
# ships with no bundled browser of its own — it needs `executable_path` pointed at one.
#
# In production, set CHROME_EXECUTABLE_PATH to wherever the deploy environment installs
# Chrome/Chromium (e.g. `google-chrome-stable`'s path on the app server/worker image).
#
# In development/test, this repo already depends on Playwright's own browser cache (see
# package.json — capybara-playwright-driver's system specs need it installed regardless of
# Grover), so rather than requiring a second, separate browser download just for badge PDFs, fall
# back to whatever Chrome-for-Testing binary `playwright install` already put there.
module GroverChromeExecutable
  def self.resolve
    ENV["CHROME_EXECUTABLE_PATH"].presence || (Rails.env.local? && detect_playwright_chrome)
  end

  def self.detect_playwright_chrome
    cache_root = ENV["PLAYWRIGHT_BROWSERS_PATH"].presence ||
      File.join(Dir.home, "Library", "Caches", "ms-playwright")
    cache_root = File.join(Dir.home, ".cache", "ms-playwright") unless Dir.exist?(cache_root)

    Dir.glob(File.join(cache_root, "chromium-*", "chrome-*", "**", "{chrome,Google Chrome for Testing,headless_shell}"))
      .find { |path| File.file?(path) && File.executable?(path) }
  end
end

executable_path = GroverChromeExecutable.resolve

# No default `format:` here on purpose — Puppeteer's page.pdf() lets `format` silently win over
# explicit `width`/`height` when both are present, and BadgePdfService always sets width/height
# from the badge's own physical size (requirement.md §3.6: "correct DPI/page size"). A global
# `format: "A4"` default would silently render every badge at A4 regardless of its configured
# size — confirmed live: a 8.5cm x 5.4cm badge without this fix rendered as a full A4 page.
Grover.configure do |config|
  config.options = {
    executable_path: executable_path,
    args: %w[--no-sandbox],
    print_background: true
  }.compact
end
