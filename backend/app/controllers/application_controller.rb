class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Deliberately neutral — no tenant resolution, no auth, no Pundit. Admin::BaseController and
  # SuperAdmin::BaseController each add what their own audience needs; keeping this bare is what
  # lets SuperAdmin::BaseController inherit from here cleanly instead of needing its own
  # ActionController::Base root (requirement.md §4.3 — the two consoles are different audiences
  # on different hosts, sharing only Rails/Devise plumbing, not tenant-scoping behavior).
end
