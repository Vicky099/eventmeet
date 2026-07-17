class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Installed since Phase 0 but unused until Phase 7's participant list — the Phase 0 pre-flight
  # note flagged the event index as pagy's first real use, but that list stayed small enough not
  # to need it; participants are the first genuinely pagination-worthy volume. Included here
  # (not per-controller) so any future list — across either console — can just call `pagy(scope)`.
  include Pagy::Backend

  # Any view under either console (or the standalone check-in kiosk) that renders an
  # ActiveStorage-attached photo directly — `tag.img src: attachment.url` — needs
  # ActiveStorage::Current.url_options set first; ActiveStorage::Blob#url raises without it under
  # the Disk service (this app's own :test/:local services, config/storage.yml) — confirmed live,
  # the gap CheckinController's own check-in result banner first surfaced. Cloudinary's #url
  # doesn't strictly need it (it builds an external cloudinary.com URL, host-independent), so this
  # sat unnoticed in the Admin/SuperAdmin consoles until a spec actually exercised a real attached
  # photo. Not audience-specific (Rails/ActiveStorage plumbing, same as Pagy::Backend above), so it
  # lives here once rather than duplicated into every BaseController/standalone controller that
  # might render one — ActiveStorage::SetCurrent isn't auto-included by the engine itself; see its
  # own doc comment.
  include ActiveStorage::SetCurrent

  # Deliberately neutral — no tenant resolution, no auth, no Pundit. Admin::BaseController and
  # SuperAdmin::BaseController each add what their own audience needs; keeping this bare is what
  # lets SuperAdmin::BaseController inherit from here cleanly instead of needing its own
  # ActionController::Base root (requirement.md §4.3 — the two consoles are different audiences
  # on different hosts, sharing only Rails/Devise plumbing, not tenant-scoping behavior).
end
