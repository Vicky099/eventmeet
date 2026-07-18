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
# **Bug fix**: `args:` here previously did nothing — Grover's own JS processor
# (lib/grover/js/processor.cjs) only reads a `launchArgs` option (Ruby's `launch_args:`,
# snake_case auto-converted) for browser *launch* flags; it deletes that key and folds it into
# Puppeteer's `launchParams.args` before calling `puppeteer.launch()`, but a bare `args:` key
# is never consumed at that step — it just falls through toward `page.pdf()`, which has no such
# option and silently ignores it. So `--no-sandbox` was configured but never actually reached the
# browser launch call, anywhere (not CI-specific) — confirmed live: this is exactly why GitHub
# Actions' `ubuntu-24.04` runner (Ubuntu 23.10+'s AppArmor-restricted unprivileged user
# namespaces breaking Chromium's own sandbox) still hit "No usable sandbox!" despite this line
# already existing. `--disable-setuid-sandbox` alongside it matches Grover's own
# `GROVER_NO_SANDBOX` env-var shortcut's pair exactly, rather than only half of it.
#
# Always-on (not just in CI/test) deliberately: every Grover render in this app is this
# platform's own generated HTML (badge/registration/invoice templates), never arbitrary
# user-supplied content, so disabling Chromium's own OS-level sandbox doesn't add attacker
# surface here the way it would for a general-purpose HTML-to-PDF service.
Grover.configure do |config|
  config.options = {
    executable_path: executable_path,
    launch_args: %w[--no-sandbox --disable-setuid-sandbox],
    print_background: true
  }.compact
end
