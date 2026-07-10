// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// webadmin template vendor JS (config/importmap.rb) — side-effect imports, same as the plain
// <script> tags these replaced; both attach globals (window.bootstrap, window.MetisMenu) rather
// than exporting ESM bindings. Loaded once here instead of per-layout javascript_include_tag
// calls, since every page (auth, admin, super_admin) already loads this entry point.
import "bootstrap"
import "metismenujs"
