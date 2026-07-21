# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"

# webadmin template's vendor JS (requirement.md §5.14/v11) — manually vendored under
# vendor/javascript (not downloaded via `bin/importmap pin --download`, since these come from the
# template package, not npm). Both are classic UMD bundles (attach to window when there's no
# CommonJS/AMD loader present, which there isn't in a browser ESM context) — imported for their
# side effect in app/javascript/application.js, same as loading them as plain global <script> tags
# would, just through the asset pipeline instead of a hand-written <script src>.
pin "bootstrap", to: "bootstrap.min.js" # @5.3.3 — Bootstrap's own JS (dropdowns, etc.)
pin "metismenujs" # @1.4.0 — collapsible sidebar menu; file is already named metismenujs.js
pin "grapesjs" # @0.23.2
pin "grapesjs-preset-webpage" # @1.0.3
pin "grapesjs-blocks-basic" # @1.0.2
pin "@rails/activestorage", to: "@rails--activestorage.js" # @8.1.300
pin "jsqr" # @1.4.0
