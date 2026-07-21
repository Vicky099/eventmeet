# Sidekiq's own admin UI (queues, retries, dead set, and — via sidekiq-cron's own web extension,
# required second so it can patch Sidekiq::Web's tabs — the cron schedule config/schedule.yml
# loads). Required at the top level, not inside `Rails.application.routes.draw`, matching every
# other Sidekiq app's own convention (`Sidekiq::Web` is a plain Rack app, mounted below).
require "sidekiq/web"
require "sidekiq/cron/web"

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

    # Agency → Tenant account switch (requirement.md revisit): the redeem half of
    # AccountSwitch — reachable while signed out (Admin::AccountSwitchesController skips
    # authenticate_user!, same as Admin::SessionsController), same reason it's a GET, not a POST:
    # a plain redirect_to from AgencyConsole::AccountsController#switch has to work as an ordinary
    # cross-origin browser redirect, the same shape Devise's own password-reset link already uses.
    get "admin/switch", to: "admin/account_switches#redeem", as: :redeem_account_switch

    # Phase 23 — Audit Log & Super Admin Impersonation (doc/implementation_3.md): the redeem half
    # of ImpersonationToken — same "GET, reachable signed out" shape as admin/switch above, minted
    # instead from SuperAdmin::ImpersonationsController#create. #destroy ("Stop Impersonating") is
    # a DELETE since it's a real, deliberate state change (clears the impersonation session flag)
    # triggered from a button_to, not a plain link.
    get "admin/impersonate", to: "admin/impersonations#redeem", as: :redeem_impersonation
    delete "admin/impersonate", to: "admin/impersonations#destroy", as: :stop_impersonation

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
            # Phase 13 — Communications (requirement.md §3.10): "send to all pending batch job."
            post :send_to_pending
          end
          member do
            patch :approve
            # Phase 13 — Communications (requirement.md §3.10): "Resend invitation per
            # participant."
            post :resend
            # Phase 8 — Badge Design & Printing (requirement.md §3.6): "on-demand single-badge
            # download endpoint" — one participant, whichever Badge applies to them
            # (Event#badge_for: their own ticket category's badge, falling back to the event's
            # default). Participant-scoped, not Badge-scoped, since that's the actual unit an
            # admin downloads from the participant list/detail.
            get :badge, defaults: { format: :pdf }
            # Phase 10 — Print Agent (Electron) Integration, revisited (requirement.md §5.5.1):
            # the manual Print button on the participant list/show — dispatches to the event's
            # default print station if one's paired and online, otherwise falls back to the same
            # inline PDF #badge already streams. GET (not a button_to POST), same "GET with a
            # deliberate side effect" precedent #badge already sets, opened target="_blank" the
            # same way #badge's own "Download badge" link already is.
            get :print
            # requirement.md revisit: "a participant show page where we can show the profile of
            # participant" — a plain download link for their own uploaded document, on the show
            # page. Not a raw blob URL (CloudinaryRawFile's own comment: the "raw" resource-type
            # double-extension bug this app already hit twice for xlsx and PDF exports could just
            # as easily hit a non-image document upload — routing through the same fix now avoids
            # a third occurrence rather than waiting to discover it live).
            get :document
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
        # Phase 13 — Communications, revisited (requirement.md §3.10, §5.10): per-tenant ask,
        # confirmed scoped per event — "admin ask to have a customized email template for
        # participant registration," store/replace placeholders at send time. `param: :kind` (not
        # the row's uuid) — one EmailTemplate row per kind per event, so the kind itself is the
        # natural identifier, and it lets edit/update/preview work even before a row exists yet
        # (Admin::EmailTemplatesController#set_email_template's find_or_initialize_by(kind:)), with
        # no separate :new/:create step. No :show — same "edit is the workspace" shape :badges above
        # takes.
        resources :email_templates, controller: "admin/email_templates", param: :kind,
          only: [ :index, :edit, :update, :destroy ] do
          member do
            post :preview
          end
          # "Quick Email Send" (index page button + modal) — a collection route, not nested under
          # one :kind, since the modal's own <select> is what picks which configured template to
          # broadcast; the kind travels as a form param (QuickEmailSendJob), same shape
          # Admin::ParticipantsController's own collection :send_to_pending already takes for its
          # analogous "send to more than one participant at once" action.
          collection do
            post :quick_send
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
        # Phase 10 — Print Agent (Electron) Integration (requirement.md §5.5.1, §8). The
        # admin-facing management surface: create a station, generate/regenerate its pairing
        # code, revoke a paired agent, plus the event-wide auto-print/default-station settings
        # (collection :update_settings, not a separate page — a couple of fields alongside the
        # station list itself).
        resources :print_stations, controller: "admin/print_stations" do
          member do
            post :generate_pairing_code
            post :revoke
          end
          collection do
            patch :update_settings
          end
        end
        # Phase 10 revisit — Bulk Print (requirement.md §3.6/§5.5's baseline "bulk print queue").
        # Only :new/:create/:show — a run is started once and then only ever watched.
        resources :bulk_print_runs, controller: "admin/bulk_print_runs", only: [ :new, :create, :show ]
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

      # requirement.md revisit: the sidebar's own "Profile" entry (AdminHelper#admin_nav_items)
      # used to be a "#" stub — this is current_user's own account, not a per-:id resource, so a
      # singular resource with no :id segment. #password is its own member route (not folded into
      # #update) since it carries different semantics — Devise's own update_with_password requires
      # current_password on every field, which the plain contact-details form has no reason to ask
      # for.
      resource :profile, only: [ :show, :update ], controller: "admin/profiles" do
        patch :password, on: :member
      end
    end

    # Fixed-hierarchy pivot (requirement.md revisit, confirmed with the user): the Agency
    # Console — a third console tier sharing this exact same subdomain constraint and the exact
    # same devise_for :users login above (AgencyConsole::BaseController's own comment has the full
    # "why no separate Devise scope"). #new/#create is the only place a new tenant Account comes
    # into existence now (AgencyConsole::AccountsController, AccountProvisioning's existing
    # agency: kwarg).
    #
    # requirement.md revisit: "show only latest 10 tenants and top right corner of tenant will
    # have view all link and also have a sidebar which will have all the tenants with pagination"
    # — the dashboard's own Tenants card is a preview now, not the full list; #index is that full,
    # paginated list, its own sidebar nav entry (AgencyHelper#agency_nav_items).
    #
    # Controller module is AgencyConsole:: (not Agency::) — Agency is already a top-level model
    # class, and Zeitwerk can't resolve a name as both a class and a controller namespace module.
    # Route path/name (as: "agency", agency_root_path etc.) are independent of the controller
    # module name and stay as they were designed.
    get "agency", to: "agency_console/dashboard#index", as: :agency_root
    scope path: "agency", as: "agency" do
      resources :accounts, controller: "agency_console/accounts", only: [ :index, :new, :create ] do
        # Agency → Tenant account switch (requirement.md revisit): mints a one-time
        # AccountSwitch and redirects straight to that tenant's own admin/switch — the SSO
        # handoff itself lives on the Admin:: side (see the top-level redeem_account_switch
        # route), this is only ever the "start" half.
        #
        # requirement.md revisit: "have a action to suspend and reinstate" on the tenant list —
        # the agency's own oversight of its own tenants, mirrors the Platform Console's identical
        # pair (suspend_platform_account_path/reinstate_platform_account_path) one tier down.
        member do
          post :switch
          patch :suspend
          patch :reinstate
        end
      end
      # Invoices moved to the Agency Console entirely (requirement.md revisit) — every Invoice
      # this agency is responsible for: its own upfront annual-contract Invoice (Agency#invoice)
      # for an `annual` agency, or every per-event Invoice across its own tenants for a
      # `per_event` one (Invoice.for_agency covers both). Plus the "Mark as Paid" flow.
      resources :invoices, controller: "agency_console/invoices", only: [ :index, :show ] do
        member do
          get :download
          post :submit_payment
        end
      end

      # This console's own copy of Admin::DirectUploadsController's route (see that controller's
      # own comment for why the stock ActiveStorage one can't be used as-is) — needed now that the
      # payment-receipt upload (AgencyConsole::InvoicesController#submit_payment) auto-uploads
      # straight to Cloudinary the same way Participant#photo/#document already do, rather than a
      # plain relayed file_field_tag.
      resource :direct_uploads, only: [ :create ], controller: "agency_console/direct_uploads"
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

    # Phase 10 — Print Agent (Electron) Integration (requirement.md §5.5.1, §4.9 item 3). The
    # Electron agent's own two HTTP touchpoints — deliberately outside `scope path: "admin"` and
    # the Admin:: namespace, same "no Devise session here" reasoning the checkin scope above
    # already established, just for a background daemon instead of a browser tab. Still inside
    # the tenant subdomain constraint — the agent hits the same `{tenant_slug}.{platform_domain}.com`
    # host its pairing code was generated on.
    scope path: "print_agent", as: "print_agent" do
      post "pair", to: "print_agent#pair"
      get "print_jobs/:id/badge", to: "print_agent#badge", as: :badge
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

    # Phase 2 — Tenant Provisioning (requirement.md §4.1, §4.3, §4.7), revisited for the
    # fixed-hierarchy pivot: no :new/:create here anymore — AgencyConsole::AccountsController (the
    # agency's own console) is the only place a tenant Account is created now. requirement.md
    # revisit: "this page and sidebar link is not required as we have a agency to handle the
    # tenant accounts" — the standalone index/show/edit pages are gone too; a tenant's own details
    # now render as a modal directly on its owning Agency's own show page
    # (super_admin/agencies/show.html.erb), using data that page already loaded, no separate
    # request. Only #suspend/#reinstate are left as real routes — pure actions, no page of their
    # own, triggered from that same modal.
    scope path: "platform", as: "platform" do
      resources :accounts, controller: "super_admin/accounts", only: [] do
        member do
          patch :suspend
          patch :reinstate
        end
        # Phase 23 — Audit Log & Super Admin Impersonation (doc/implementation_3.md): the mint
        # half of ImpersonationToken, triggered per-user from this account's own roster
        # (super_admin/agencies/_tenant_modal.html.erb) — nested under :accounts, not a flat
        # resource, since impersonation always targets one specific account's user. Only :create —
        # same "pure action, no page of its own" shape #suspend/#reinstate above already take.
        resources :impersonations, controller: "super_admin/impersonations", only: [ :create ]
      end

      # Fixed-hierarchy pivot (requirement.md revisit, confirmed with the user): the agency is now
      # the only place a tenant Account comes from — "Add Tenant" no longer exists on this page at
      # all (AgencyConsole::AccountsController, the agency's own console, is where that happens now).
      # #grant_events tops up a per_event agency's pool (Agency#grant_more!) — additive, not a raw
      # edit, same reasoning as that method's own comment. agency_memberships is the agency's own
      # admin roster — #create/#destroy plus #resend_invite (regenerates a temp password and
      # re-sends the welcome email to a not-yet-onboarded agency_admin).
      resources :agencies, controller: "super_admin/agencies", only: [ :index, :new, :create, :show, :edit, :update ] do
        member do
          patch :suspend
          patch :reinstate
          post :grant_events
        end
        resources :agency_memberships, controller: "super_admin/agency_memberships", only: [ :create, :destroy ] do
          member do
            post :resend_invite
          end
        end
      end

      # Phase 15 — Platform Billing & Invoicing, revisited (requirement.md §4.6, confirmed with the
      # user): invoices are auto-generated the day after an event ends (InvoiceGenerationJob), or
      # (fixed-hierarchy pivot) once, at agency-provisioning time, for an `annual` agency's own
      # upfront contract (AgencyProvisioning). Plain `resources :invoices`, not nested under
      # Event/Agency — #deliver sends a draft to the tenant/agency, #verify/#reject review whatever
      # payment proof they submit (folded directly onto Invoice, no separate PaymentSubmission
      # model in the simplified design). `deliver` (not `send` — Kernel#send collision, see that
      # action's own comment).
      resources :invoices, controller: "super_admin/invoices", only: [ :index, :show ] do
        member do
          get :download
          post :deliver
          post :verify
          post :reject
        end
      end

      # Phase 23 — Audit Log & Super Admin Impersonation (doc/implementation_3.md): read-only
      # viewer over every AuditLogEntry — :index only, same "no #show/edit/destroy, an audit log
      # that can be modified isn't one" reasoning that table's own migration comment states.
      resources :audit_log_entries, controller: "super_admin/audit_log_entries", only: [ :index ]
    end

    # Devise's own routing helper — `authenticated` (not the throwing `authenticate`, real bug
    # caught live: `authenticate` triggers Warden's own failure-app redirect *from inside* the
    # mounted Rack app's dispatch on a genuinely unauthenticated request, which computes the
    # redirect Location relative to Sidekiq::Web's own mount point instead of the app root —
    # `/platform/sidekiq/platform/login`, a route that doesn't exist. `authenticated` is the
    # soft, non-throwing check: a request that isn't :platform_staff (not signed in at all, or
    # signed in as :user — a signed-in tenant admin must not reach this even though both scopes
    # share the same underlying User model) simply never matches this route at all, same plain
    # 404 as hitting any other undefined path, no broken redirect. Sidekiq::Web can list/retry/
    # delete jobs and edit the cron schedule — real, destructive admin surface, not a read-only
    # status page, so this is deliberately gated the same way every other Platform Console
    # controller already is (SuperAdmin::BaseController's own before_action), just via a routing
    # constraint instead since Sidekiq::Web is a plain Rack app, not a Rails controller.
    # SidekiqWebSameOriginShim (app/middleware/) — Sidekiq::Web's own `Sec-Fetch-Site` CSRF check
    # (its own comment has the full "why," including a live repro) needs to sit in front of
    # Sidekiq::Web itself, not inside it — `Sidekiq::Web.use`-registered middleware runs too late,
    # after the check already happened.
    authenticated :platform_staff do
      mount Rack::Builder.new {
        use SidekiqWebSameOriginShim
        run Sidekiq::Web
      } => "/platform/sidekiq"
    end
  end
end
