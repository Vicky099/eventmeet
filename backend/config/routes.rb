Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Deliberately unconstrained by host — a load balancer/uptime monitor may hit any host and still
  # needs this to work.
  get "up" => "rails/health#show", as: :rails_health_check

  # requirement.md §4.3: the Host header is the single source of truth for which app/audience a
  # request belongs to. SuperAdmin:: routes only ever match the bare apex domain; Admin:: routes
  # only ever match a real tenant subdomain. Neither namespace is reachable from the other's host,
  # enforced at the routing layer, not just by convention — see Admin::BaseController/
  # SuperAdmin::BaseController for the other two enforcement layers.
  #
  # Every route on both sides carries its console's URL namespace (/admin/..., /platform/...) —
  # not just the controller/module namespace — so the two are visually distinguishable in a
  # browser bar, a log line, or a bug report, not just in the codebase.
  #
  # ORDER MATTERS HERE: the tenant :users scope must be declared before the apex :platform_staff
  # scope. Both devise_for calls map to the same User class (class_name:, §4.9 item 1), and
  # Devise::Mapping.find_scope! — used internally by every Devise helper that infers a scope from
  # a bare resource instance rather than being told explicitly (the reset-password mailer's
  # edit_password_url, signed_in_root_path, etc.) — resolves ambiguous cases to whichever
  # devise_for was *registered first*, full stop, no smarter disambiguation. Registering :users
  # first makes that default land on the tenant scope, which is what actually needs it: every one
  # of those ambiguous call sites that gets exercised in this app belongs to :user's much richer
  # feature set (passwords, forced-reset); :platform_staff is deliberately narrow (sessions only,
  # §9/v6) and structurally can't trigger the ones it doesn't have routes for. (sign_out is the
  # one call site Devise lets you disambiguate explicitly — sign_out(resource_name), not
  # sign_out(resource) — see Admin::SessionsController#create; this ordering is what covers every
  # other call site that doesn't offer that option.)
  constraints(Hosting::TenantSubdomainConstraint.new) do
    # Tenant Admin Console login (requirement.md §4.9 item 1). No :registerable (§6/v6 — no
    # self-serve sign-up, accounts/users are provisioned, not registered) but :recoverable stays
    # so invited staff can reset a forgotten password.
    #
    # path: "admin" + path_names: rewrites the URL segments only (/admin/login, /admin/logout,
    # /admin/password/...) — the :user scope name, Warden session key, and every route *helper*
    # (new_user_session_path, destroy_user_session_path, edit_user_password_path, ...) are
    # completely unaffected, so nothing that already calls those helpers needed to change.
    devise_for :users,
      path: "admin",
      path_names: { sign_in: "login", sign_out: "logout" },
      controllers: { sessions: "admin/sessions", passwords: "admin/passwords" },
      skip: [ :registrations ]
    # requirement.md §4.9 item 2: MVP only uses the client-credentials token endpoint (the
    # Next.js BFF's own credential exchange, config/initializers/doorkeeper.rb's grant_flows) —
    # no interactive resource-owner flow, and applications are provisioned server-side by the
    # Super Admin (Phase 2), never self-service — so the interactive/self-service controllers
    # that flow needs are skipped rather than left reachable with nothing behind them.
    use_doorkeeper do
      skip_controllers :authorizations, :applications, :authorized_applications
    end

    # Named user_root (not admin_root) deliberately: Devise's signed_in_root_path/
    # after_sign_in_path_for looks for "#{scope}_root_path" — for the :user scope that's
    # user_root_path — before ever falling back to the plain root_path (which doesn't exist at
    # all here — see the module comment above on why every route carries the /admin namespace).
    # Naming it to match is what makes Devise find it automatically, no override needed.
    get "admin", to: "admin/dashboard#index", as: :user_root # Phase 3 — real dashboard.
    # Kept as real, reusable smoke-test infrastructure (Phase 0 DoD), not a one-off — still
    # exercised by spec/requests/hosting_spec.rb — distinct from user_root above since Phase 3.
    get "admin/__smoke", to: "admin/smoke#show"

    # Phase 4 — Event Lifecycle (requirement.md §3.2, §5.2). scope path/as: "admin" so these carry
    # the same /admin/... URL namespace as every other Admin Console route (module comment at the
    # top of this file), same pattern Phase 2 established for /platform/accounts. No :show — the
    # wizard's `edit` action is the only workspace page (see Admin::EventsController).
    scope path: "admin", as: "admin" do
      resources :events, controller: "admin/events", only: [ :index, :new, :create, :edit, :update ] do
        member do
          post :duplicate
          post :publish
          post :submit_for_review
        end
      end
    end
  end

  constraints(Hosting::ApexConstraint.new) do
    # Super Admin login (requirement.md §4.9 item 1). A distinct Warden scope (:platform_staff)
    # from the tenant :user scope above — same User model (class_name:), but this keeps
    # current_platform_staff/platform_staff_signed_in? cleanly separate from current_user/
    # user_signed_in?, since a request is never simultaneously both. Sessions only: platform
    # staff don't need self-service registration or password reset in MVP (§9/v6 — basic Devise
    # email/password, small/known population of operators).
    devise_for :platform_staff, class_name: "User",
      path: "platform",
      path_names: { sign_in: "login", sign_out: "logout" },
      controllers: { sessions: "super_admin/sessions" },
      skip: [ :registrations, :passwords ]

    # See the user_root comment above — same reasoning, this scope's name is platform_staff so
    # Devise looks for platform_staff_root_path specifically.
    get "platform", to: "super_admin/dashboard#index", as: :platform_staff_root # Phase 3 — real dashboard.
    # Kept as real, reusable smoke-test infrastructure (Phase 0 DoD), not a one-off — still
    # exercised by spec/requests/hosting_spec.rb — distinct from platform_staff_root above since Phase 3.
    get "platform/__smoke", to: "super_admin/smoke#show"

    # Phase 2 — Tenant Provisioning (requirement.md §4.1, §4.3, §4.7). scope path/as: "platform"
    # (not a bare `resources :accounts`) so these carry the same /platform/... URL namespace as
    # every other Platform Console route (module comment at the top of this file) and get
    # platform_accounts_path/platform_account_path/etc. route helpers, distinct from Devise's own
    # platform_staff_* helpers above.
    scope path: "platform", as: "platform" do
      resources :accounts, controller: "super_admin/accounts", only: [ :index, :new, :create, :show, :edit, :update ] do
        member do
          patch :suspend
          patch :reinstate
        end
        collection do
          get :check_slug
        end
      end

      # Phase 5 — Event Approval Workflow (requirement.md §4.7 item 2, §5.2). No :new/:create/
      # :edit/:update/:destroy — Super Admin reviews events, it doesn't build or own them.
      resources :event_reviews, controller: "super_admin/event_reviews", only: [ :index, :show ] do
        member do
          post :approve
          post :reject
        end
      end
    end
  end
end
