Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Deliberately unconstrained by host — a load balancer/uptime monitor may hit any host and still
  # needs this to work.
  get "up" => "rails/health#show", as: :rails_health_check

  # Phase 9 (requirement.md §5.15). Deliberately unconstrained by host, same reasoning as the
  # health check above — both the tenant Admin Console (on its subdomain) and the Platform
  # Console (on the apex domain) open a cable connection from their own host, and
  # ApplicationCable::Connection itself is what tells the two apart (via Warden scope), not
  # routing.
  mount ActionCable.server => "/cable"

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
    # top of this file), same pattern Phase 2 established for /platform/accounts. :show (Phase
    # 7.5, requirement.md §5.14 v12) is the event-workspace landing page — distinct from the
    # wizard's own `edit` (see Admin::EventsController's class comment).
    scope path: "admin", as: "admin" do
      resources :events, controller: "admin/events", only: [ :index, :new, :create, :show, :edit, :update ] do
        member do
          post :duplicate
          post :publish
          post :submit_for_review
        end

        # Phase 6 — Ticketing (requirement.md §5.3). TicketCategory itself has no routes of its
        # own (only: []) — it's managed as nested attributes on the Event form
        # (Admin::EventsController#update, Event accepts_nested_attributes_for
        # :ticket_categories), not a separate CRUD endpoint; this block exists purely so
        # ticket_reservations can nest under a category for #create. Reservations (group/bulk
        # holds against a category) aren't part of the event-building wizard at all — no view
        # links here yet; Phase 7's registration flow is what's expected to use these.
        resources :ticket_categories, only: [] do
          resources :ticket_reservations, controller: "admin/ticket_reservations", only: [ :create ]
        end
        resources :ticket_reservations, controller: "admin/ticket_reservations", only: [] do
          member do
            patch :cancel
          end
        end

        # Phase 7 — Participant Lifecycle (requirement.md §3.4, §5.4). Nested under Event (every
        # Participant belongs to exactly one) — the sidebar's top-level "Participants" link
        # (AdminHelper#admin_nav_items) resolves to the account's most recent event.
        resources :participants, controller: "admin/participants" do
          collection do
            post :bulk_destroy
            # requirement.md §5.4/§5.14 v12 revisit: "when i select the ticket category then the
            # form fields ... ideally it should check the fields configured and then show the
            # form." Backs ticket_category_fields_controller.js's Turbo Frame src repoint —
            # re-renders admin/participants/_dynamic_fields against the requested category.
            get :dynamic_fields
          end
          member do
            patch :approve
            # Phase 8 — Badge Design & Printing (requirement.md §3.6): "on-demand single-badge
            # download endpoint" — one participant, whichever Badge applies to them
            # (Event#badge_for: their own ticket category's badge, falling back to the event's
            # default). Participant-scoped, not Badge-scoped, since that's the actual unit an
            # admin downloads from the participant list/detail.
            get :badge, defaults: { format: :pdf }
          end
        end
        resources :import_files, controller: "admin/import_files", only: [ :new, :create, :show ] do
          collection do
            get :sample
          end
        end
        # requirement.md revisit: "in upload we should have a separate sample xlsx file to upload
        # the govtID." Same shape as import_files above, its own controller/job/table entirely.
        resources :govt_id_import_files, controller: "admin/govt_id_import_files", only: [ :new, :create, :show ] do
          collection do
            get :sample
          end
        end
        resources :export_files, controller: "admin/export_files", only: [ :new, :create, :show ] do
          member do
            get :download
          end
        end
        # Phase 9 — Check-in, Attendance & Real-Time Live Dashboards (requirement.md §3.7, §5.6),
        # revisited: this is now a read-only real-time dashboard (live stats, session occupancy,
        # ticket-category breakdown, recent scans) plus a "Scan" link out to the standalone kiosk
        # below — the actual scan station moved out of the admin panel/layout entirely (the
        # `scope path: "checkin"` block further down), so #create no longer lives here. No :show/
        # :edit/:update/:destroy — ScanEvent is an append-only log, not something staff browse to
        # a single row and change.
        resources :scan_events, controller: "admin/scan_events", only: [ :index ]
        # Phase 8 — Badge Design & Printing (requirement.md §3.6, §5.5). Per-event badges: at most
        # one default (no ticket_category) plus at most one per TicketCategory (Badge's own
        # uniqueness validation). #index still exists (Admin::BadgesController's own module
        # comment) but the wizard's Badge step is what actually renders this list day to day.
        resources :badges, controller: "admin/badges", except: [ :show ] do
          member do
            # The eye-icon preview modal (admin/badges/_badges_table.html.erb, wherever that table
            # renders — the Badge step, the standalone Badges page, and Review's read-only copy) —
            # a real participant is never available in any of those contexts (Review in particular
            # runs during event *setup*, before anyone has registered — see the "no Participants
            # section" revisit in doc/implementation.md), so this always renders against a synthetic
            # sample participant, never a real one. `:show` above is deliberately still excluded —
            # this isn't a general-purpose read view of a Badge, only ever loaded inside that one
            # iframe/modal.
            get :preview
            # "Copy to..." (admin/badges/_badges_table.html.erb, Admin::BadgesController#copy) —
            # POST since it creates a new Badge row, same verb the framework's own resourceful
            # #create uses for the same reason.
            post :copy
          end
        end
        # Agenda, Speakers & Sessions (requirement.md §3.8, §5.6, §5.7) — each a real wizard step
        # rendering its own management UI directly (app/views/admin/events/edit.html.erb's
        # "sessions"/"speaker"/"event_schedule" cases), not a link out to a separate page. No
        # :show on any of the three — same "edit is the workspace" reasoning as :badges/:events.
        #
        # controller: "admin/event_sessions", not "admin/sessions" — Admin::SessionsController is
        # already taken (Devise's own login controller, config/routes.rb's devise_for :users
        # controllers: { sessions: "admin/sessions" } above). The URL/route-helper name still says
        # "sessions" (admin_event_sessions_path etc.) since that's the `resources` name, not the
        # controller — only the controller class avoids the collision.
        resources :sessions, controller: "admin/event_sessions", except: [ :show ]
        # Event-scoped speaker roster — one per event, not a shared account-wide library
        # (confirmed with user, reversing Phase 11's original design; see Speaker's own model
        # comment). Nested here alongside :sessions/:schedules rather than at the account level.
        resources :speakers, controller: "admin/speakers", except: [ :show ]
        resources :schedules, controller: "admin/schedules", except: [ :show ]
        # Phase 7.5 — Dynamic Registration Form Builder (requirement.md §5.4/§5.14 v12). Standalone,
        # named forms an organizer builds once and assigns to whichever TicketCategory rows should
        # use them — CRUD, not a single-page editor (that was the original shape; revisited once
        # "create a form first, then assign it to a category — including all of them at once" was
        # confirmed as the actual requirement, which needs real records to assign, not a form
        # scoped to one category from the moment it's created). No :show — same "edit is the
        # workspace" shape every other admin resource here already uses. Deliberately NOT part of
        # the Admin::EventsController wizard/STEPS — reached from the event workspace's own
        # "Design Registration Form" nav entry instead (§5.14), never from event creation/editing.
        resources :registration_forms, controller: "admin/registration_forms", except: [ :show ]
      end

      # Phase 8 — Badge Design & Printing (requirement.md §5.5): "badge template library with
      # reusable/sharable templates across events within a tenant" — deliberately account-level,
      # not nested under any one Event, unlike :badges above. No :show — same "edit is the
      # workspace, there's no separate read-only page" reasoning as :badges/:events.
      resources :badge_templates, controller: "admin/badge_templates", except: [ :show ]

      # This app's own authenticated, tenant-scoped replacement for Rails' built-in
      # active_storage_direct_uploads route — see Admin::DirectUploadsController for why the
      # stock one can't be used as-is (it has no way to compute this app's tenant-namespaced blob
      # key). Singular resource, :create only, same shape the framework route itself uses.
      resource :direct_uploads, only: [ :create ], controller: "admin/direct_uploads"
    end

    # Phase 9 revisit — the check-in kiosk, deliberately OUTSIDE `scope path: "admin"` and the
    # Admin:: controller namespace/layout: "the actual event level check-in page should be out of
    # admin panel and admin layout." Still fully authenticated and tenant-scoped (CheckinController
    # includes the same TenantResolvable/authenticate_user! wiring Admin::BaseController's own
    # subclasses get, just without `layout "admin"` or anything Admin::-namespaced) — a
    # checkin_staff/event_manager/owner logs in the same way (the tenant :user Devise scope
    # registered above), then this is just a different URL/layout they can reach, not a different
    # session or auth mechanism. Flat `:event_id` segment (not a nested `resources :events` block)
    # mirrors EventScoped's own `params[:event_id]` lookup directly, same shape
    # Admin::ScanEventsController's nested route already resolves against.
    scope path: "checkin", as: "checkin" do
      get ":event_id", to: "checkin#show", as: :event
      post ":event_id/scan", to: "checkin#scan", as: :scan
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
