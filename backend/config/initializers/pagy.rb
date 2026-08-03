# Pagy's plain `pagy_nav` helper renders bare `<span>`/`<a class="page">` markup with no
# Bootstrap-compatible classes — every list page in this app (admin/participants, agency_console/
# accounts, super_admin/audit_log_entries, ...) already loads Bootstrap 5 (vendor/webadmin's own
# app.min.css skins `.pagination`/`.page-item`/`.page-link` to match this app's theme already), so
# the bootstrap extra's `pagy_bootstrap_nav` — real `<ul class="pagination"><li class="page-item">`
# markup — gets a themed pager for free with no custom CSS of our own to write or maintain.
require "pagy/extras/bootstrap"
