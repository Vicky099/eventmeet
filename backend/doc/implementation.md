# EventMeet — Phase-by-Phase Implementation Plan (Admin + Super Admin First)

**Status:** Draft v1
**Scope:** Rails Admin Console + Platform (Super Admin) Console only. The Next.js public event site is deliberately the **last** phase (§18), per the agreed sequencing — nothing in Phases 0–17 requires it to exist.
**Source of truth:** `backend/doc/requirement.md` (v10). Every phase below cites the requirement section(s) it implements. If the two documents ever disagree, `requirement.md` wins and this file should be corrected.

---

## Pre-flight decisions (resolve before or during Phase 0)

These are gaps between what `requirement.md` locks in and what's actually in the repo today. Flagging them now so they don't get silently decided mid-build.

1. **Job/cable backend mismatch — RESOLVED in Phase 0.** Went with `requirement.md` §4.10's confirmed pick: `sidekiq` + `redis`, standard Action Cable (Redis adapter). Removed `solid_queue`/`solid_cable` from the Gemfile and every reference to them (`config/environments/*.rb`, `config/puma.rb`, `config/database.yml`, `config/recurring.yml` deleted, `bin/jobs` now execs Sidekiq). Kept `solid_cache` for `Rails.cache` — that backend wasn't specified either way, not worth swapping.
2. **`webadmin` template — RESOLVED, and it's Bootstrap 5, not Tailwind.** The template arrived (as a sibling directory, vendored into `backend/vendor/webadmin_template/` for reference + `backend/app/assets/vendor/webadmin/` for the actual served assets — see §5.14/v11 in `requirement.md`) and turned out to be built on Bootstrap 5, not Tailwind as originally assumed before any template existed to check against. `tailwindcss-rails` was removed entirely from the Gemfile/asset pipeline in favor of the template's own vendored Bootstrap/CSS/JS. `requirement.md` has a v11 correction note; every "Tailwind" reference against the admin console elsewhere in that doc should be read as Bootstrap 5 (the public Next.js site's own, unrelated Tailwind choice, §4.8, is unaffected).
3. **Authorization gem — RESOLVED.** Pundit installed (`app/policies/application_policy.rb`), used from Phase 1 onward.
4. **Pagination gem — RESOLVED.** Pagy installed, not yet used (first list view is Phase 4's event index).

---

## How to use this document

- **One phase = one demo-able, testable slice.** Nothing is "done" until its Definition of Done checklist is fully checked — specs green, manual QA against a real browser session, not just "code exists."
- Work each phase on its own branch; merge to `main` only when its Definition of Done is met. Don't start a phase's UI work before its data model is migrated and its backend specs pass.
- Every phase that touches tenant-scoped data must include the **cross-tenant leak test** described in Phase 0 — copy that spec pattern into every new controller/job.
- `[ ]` checkboxes are meant to be checked off in place as work lands — treat this file as a living tracker, not a one-time document.

---

## Phase 0 — Foundations & Multi-Tenant Scaffolding

**Goal:** the tenancy substrate every later phase depends on. Not a user-facing feature yet — tested via model/request specs and `rails console`, not a browser demo.
**Implements:** §4.1, §4.2, §4.3, §4.10, §7.4 (isolation, routing, tech stack).

### 0.1 Tooling & gems
- [x] Resolve pre-flight decision #1 (Sidekiq/Redis vs. Solid stack); update `Gemfile` accordingly. → went with Sidekiq + Redis; removed `solid_queue`/`solid_cable` (kept `solid_cache` — Rails.cache backend wasn't specified either way and wasn't worth swapping).
- [x] Add `devise`, `doorkeeper`, `pundit`, `friendly_id`, `pagy`, `rack-attack`, `image_processing`. → UUIDv7 needs no extra gem: Ruby's native `SecureRandom.uuid_v7` (confirmed available on the installed Ruby 4.0.5) is used instead of the `uuid7` gem.
- [x] Confirm Postgres extension `pgcrypto`/`uuid-ossp` (whichever UUIDv7 generation path is chosen) is enabled in `schema.rb`. → `pgcrypto` enabled via migration; not actually load-bearing for ID generation (that's Ruby-side, see `ApplicationRecord`) but kept as a general-purpose extension.
- [x] `bundle install`, commit `Gemfile.lock`. → installed; **not yet git-committed** (no commits made without an explicit ask — ready whenever you want it committed).

### 0.2 Core tenancy models
- [x] `Account` (tenant) — `id: uuid`, `name`, `subdomain_slug` (unique, indexed, reserved-word validation: `www`, `api`, `admin`, `app`, `mail`, `events`, `login`, `platform`), `status` (active/suspended), `plan` placeholder (fleshed out in Phase 15).
- [x] `User` — `id: uuid`, Devise columns (`:database_authenticatable, :recoverable, :rememberable, :validatable` — no `:registerable`, per the no-self-serve-signup decision), `platform_staff` boolean (default false), `contact_num` (used later for WhatsApp, §8 v10), plus `must_reset_password` (forced-reset flow, wired for real in Phase 1).
- [x] `AccountMembership` — join `User` ↔ `Account`, `role` enum (owner/event_manager/checkin_staff/finance_readonly — §5.1), unique on `(user_id, account_id)`.
- [x] `TenantDomain` — `account_id`, `domain`, `kind` (`subdomain`/`custom`), `verified_at`, `tls_status` — scaffolded now, fully used in Phase 18.
- [x] `Current` (ActiveSupport::CurrentAttributes) — `Current.account`, `Current.user`, plus `Current.platform_request` (needed so Platform:: controllers can explicitly declare "deliberately cross-tenant" rather than silently bypassing the guard).
- [x] `TenantScoped` concern built (`app/models/concerns/tenant_scoped.rb`) — default-scopes to `Current.account`, opens to `all` under `Current.platform_request`, raises `TenantScoped::MissingTenantContextError` otherwise, plus a `.unscoped_across_tenants` escape hatch for rake/console. **Not yet included in any model** — by design, no tenant-scoped feature table exists until Phase 4's `Event`. Note: `AccountMembership` and `TenantDomain` *deliberately don't* use it either, despite having `account_id` — see the code comments on those two models for why (the account-switcher's cross-tenant membership listing, and the domain-resolution lookup that runs *before* tenant context exists, would each conflict with a blanket default_scope).
- [x] Postgres Row Level Security as defense-in-depth (§4.2) — real, not just stubbed: `lib/tenant_row_level_security.rb` provides `TenantRowLevelSecurity.enable!(self, :table_name)` for future migrations to call, and `TenantResolvable` sets/resets the `app.current_account_id` session GUC every policy will check, for the lifetime of each tenant request (verified in `spec/requests/hosting_spec.rb`). No table calls `enable!` yet since none qualify until Phase 4.

### 0.3 Host-based routing
- [x] `before_action`-based resolution (chose controller-level over Rack middleware, for direct access to `head :not_found`/redirect helpers and clean request-spec testability): `Hosting::Resolver` parses `Host` once; `TenantResolvable` (tenant `ApplicationController`) resolves the subdomain to a real `Account` and sets `Current.account`, 404ing if none matches; `PlatformRequestScoped` (`Platform::ApplicationController`) sets `Current.platform_request`. Reserved/unrecognized/nonexistent-tenant hosts all 404.
- [x] Local dev host aliasing documented in `backend/README.md` — `*.lvh.me` (public DNS → 127.0.0.1, no `/etc/hosts` edits) plus the `config.hosts` allowance needed in `development.rb` (Rails' DNS-rebinding guard blocks unrecognized hosts by default — hit this for real during manual QA and fixed it).
- [x] Routing constraint classes (`Hosting::ApexConstraint`, `Hosting::TenantSubdomainConstraint`) with request specs (`spec/requests/hosting_spec.rb`) proving each host resolves to the right namespace and that neither namespace is reachable from the other's host.

### 0.4 Template integration shell
- [x] Add the `webadmin` template to the workspace. → vendored: `backend/vendor/webadmin_template/` (raw HTML mockup pages, reference-only, never served — see its `README.md`) + `backend/app/assets/vendor/webadmin/` (the actual CSS/JS/fonts/images, served through Propshaft — registered as an asset path in `config/initializers/assets.rb`). Turned out to be Bootstrap 5, not Tailwind — see pre-flight decision #2 and `requirement.md` §5.14/v11.
- [x] Extract its base layout (sidebar, topbar, content region) into `app/views/layouts/admin.html.erb` and `app/views/layouts/platform.html.erb`. → ported from `vendor/webadmin_template/pages-starter.html`'s vertical-layout variant (sidebar + topbar + main-content + footer). Deliberately dropped: the template's alternate horizontal-topbar markup and its theme-customizer right sidebar (RTL/dark-mode/layout-switcher demo controls) — this is a product, not a template showcase. Added a third layout, `layouts/auth.html.erb` (centered-card, ported from `auth-login.html`), shared by every unauthenticated screen on both hosts.
- [x] Port one representative interactive template component to a Stimulus controller. → two, in the end: `sidebar_controller.js` (sidebar collapse toggle + MetisMenu init, replacing the template's `app.js` — which hard-assumes demo-only DOM we don't ship, e.g. the theme customizer — rather than loading it wholesale) and `password_toggle_controller.js` (ported from the template's standalone `pass-addon.init.js`, used on the login form). Bootstrap's own bundled JS (`bootstrap.bundle.min.js`) and the small vendor MetisMenu library are kept as plain vendored scripts, not reimplemented — the §5.14 "avoid a second JS framework" guidance is about not pulling in a *competing reactive framework* (its explicit example is Alpine.js), not about banning small single-purpose utility libraries.
- [x] Asset pipeline confirmed working — through Propshaft, not `public/` (per direct instruction mid-build): `app/assets/vendor/webadmin/` registered as an asset load path; Propshaft's CSS `url()` rewriting confirmed correctly fingerprinting the template's internal font/image references (verified by fetching the compiled CSS and checking a rewritten `url()` resolves). Caught and fixed one real bug here: `stylesheet_link_tag :app` is Propshaft's *bulk-include-every-CSS-file-under-app/assets* shorthand, not "application.css" — it was sweeping in every vendored library stylesheet a second time; fixed to `stylesheet_link_tag "application"` (explicit logical path). Three background images referenced by the template's own CSS (`bg-auth.png`, `login-img.png`, `profile-bg.jpg`) are missing from the vendored asset package itself (confirmed: same file count in the original source, not something the copy broke) — cosmetic-only gap, login form renders and functions fine without them.

### Definition of Done
- [x] `bin/rails db:migrate` runs clean from empty DB. → verified via `db:drop db:create db:migrate` end to end.
- [x] Model specs: `Account`, `User`, `AccountMembership` validations + `subdomain_slug` reserved-word rejection. → `spec/models/{account,user,account_membership,tenant_domain}_spec.rb`.
- [x] Request spec: hitting an unrecognized tenant host 404s; a valid tenant subdomain sets `Current.account`. → `spec/requests/hosting_spec.rb`, using the `__smoke` routes instead of a throwaway route (kept as real, reusable smoke-test infrastructure rather than one-off).
- [x] **Cross-tenant leak spec pattern established**: `spec/models/concerns/tenant_scoped_spec.rb` — two `Account`s, two records of an anonymous `TenantScoped`-including test model (riding on the `account_memberships` table), proving no query configuration returns another tenant's rows without an explicit cross-tenant escape hatch. Copy this shape for `Event`/`Participant`/etc. starting Phase 4.
- [x] Both layouts render in a browser using the webadmin template's actual chrome — verified live (not just curl-for-status-code): full-page loads, all CSS/JS/font assets resolving 200, sidebar + MetisMenu + Bootstrap dropdowns functioning, on both `acme.lvh.me:3000` and `lvh.me:3000`.

**57/57 specs green, Rubocop clean, Brakeman: 0 warnings.** Phase 0 is fully complete.

---

## Phase 1 — Authentication & Login (Super Admin + Tenant Admin)

**Goal:** a Super Admin can log in at the apex domain; a tenant admin can log in at their subdomain. Two logins, two cookie scopes, one `User` table.
**Implements:** §4.9 item 1, §5.1, §5.6 (v6 — Devise-only, no SSO), §8 (platform_staff flag).
**Depends on:** Phase 0.

- [x] Devise installed on `User` (`:database_authenticatable, :recoverable, :rememberable, :validatable`), async mailer delivery. → done in Phase 0; `:recoverable` used for real starting this phase.
- [x] Two Devise scopes/controllers, not one branching controller: `devise_for :platform_staff, class_name: "User"` (apex) and `devise_for :users` (tenant) — same `User` model, two independent Warden scopes, giving `current_platform_staff`/`platform_staff_signed_in?` vs `current_user`/`user_signed_in?` for free rather than one controller manually branching on host. Authorization itself lives on the model (`User#active_for_authentication?`/`#inactive_message`), reading `Current.platform_request`/`Current.account` (already set by Phase 0's host resolution) to decide `platform_staff?` vs. `AccountMembership` + `Account.active?` — not in either controller. `Platform::SessionsController` can't literally inherit `Platform::ApplicationController` (must stay a `Devise::SessionsController` subclass for Devise's routing to work) — it `skip_before_action :resolve_tenant!` (inherited via Devise's `parent_controller` default, `ApplicationController`, which is the *tenant* one) and `include PlatformRequestScoped` instead. **Regression caught in manual QA, not a unit test**: `sign_out(resource)` is ambiguous once two scopes share one model via `class_name:` — must be `sign_out(resource_name)`.
- [x] **Host-only session cookie** — verified via response headers in a request spec (no `Domain=` attribute on `Set-Cookie`, both scopes) — `spec/requests/sessions_spec.rb`, `spec/requests/platform_sessions_spec.rb`.
- [x] Login views built from the webadmin template's auth screens (Phase 0.4 layout) — `app/views/sessions/new.html.erb`, `app/views/platform/sessions/new.html.erb`, ported from `auth-login.html`, rendered inside `layouts/auth.html.erb`.
- [x] Forced password reset / temp-password flow on invited users — `User#must_reset_password`. Reuses Devise's own reset-password-token mechanism rather than a bespoke controller: `SessionsController#create` detects it, signs the user back out (see the regression above — required for this to work at all, since `PasswordsController` bounces already-authenticated users), mints a token via the otherwise-protected `set_reset_password_token`, and redirects straight to the edit-password form with no email sent. Deliberately **not** built for the `:platform_staff` scope (routes `skip: [:passwords]` — small/known operator population, real password from day one, no dead-route risk).
- [x] Authorization skeleton: Pundit installed and included in both `ApplicationController`s (`rescue_from Pundit::NotAuthorizedError`); `ApplicationPolicy` provides `platform_staff?`/`owner?`/`account_membership` helpers for every future per-model policy to compose (starting Phase 4) — tenant isolation itself stays `TenantScoped`'s job, not re-derived here. `spec/policies/application_policy_spec.rb`.
- [x] Logout, "remember me," basic account-locked/suspended (`Account.status`) rejection at login — suspension checked in the same `authorized_for_current_host?` model method as the console-scope check, so it's one code path, not two.
- [x] Seed script (`db/seeds.rb`, `Rails.env.local?`-gated) creates one Super Admin (`superadmin@eventmeet.example`) and one demo tenant + owner admin (`admin@acme.example`, Account `acme`) — both `password123!`.

### Definition of Done
- [x] Request spec: Super Admin can log in at apex, cannot log in at any tenant subdomain (wrong scope → rejected), and vice versa for a tenant admin. → `spec/requests/sessions_spec.rb` ("rejects a platform_staff user..."), `spec/requests/platform_sessions_spec.rb` ("rejects a non-platform_staff user...").
- [x] Request spec: a user with `AccountMembership` on Account A gets rejected attempting to authenticate on Account B's subdomain. → `spec/requests/sessions_spec.rb` ("rejects a user who is a member of a DIFFERENT Account..."). (Devise's failure pathway for this class of check is redirect-with-flash, not a bare 302/403 — see the spec comments for why, and the wrong-password case right above it in the same file for the contrasting inline-422 pathway.)
- [x] Cookie assertion spec: `Set-Cookie` carries no `Domain=` attribute on either scope (the actual server-side signal for host-only-ness — see both request spec files' "sets a host-only session cookie" examples; more reliable than simulating cross-host cookie-jar behavior against a test client that doesn't fully model real-browser domain matching).
- [x] Manual QA: full real-server, real-`curl` walkthrough of both logins (`acme.lvh.me:3099/users/sign_in`, `lvh.me:3099/platform_staff/sign_in`) landing on distinct authenticated pages, plus wrong-console rejection, suspended-account rejection, and the full forced-password-reset round trip — this is how the `sign_out` scope-ambiguity regression above was actually caught.
- [x] Suspended `Account`'s users cannot log in (generic rejection message, doesn't confirm suspension to a guesser) — `spec/requests/sessions_spec.rb`.

**Post-review refinements (same phase, driven by interactive QA feedback):**
- [x] Dashboard-area pages now require authentication — `before_action :authenticate_user!`/`:authenticate_platform_staff!` on both `ApplicationController`s (declared *after* `TenantResolvable`, so an unrecognized host still 404s before any auth check runs), skipped on the Devise controllers themselves (which must stay reachable while signed out). `spec/requests/hosting_spec.rb` covers both the "requires authentication" and "404 takes priority over auth" cases.
- [x] Logout now redirects to the login form, not the (now auth-gated) dashboard — `after_sign_out_path_for` overridden in both `SessionsController` and `Platform::SessionsController` (Devise's default is always `root_path` regardless of scope, per its own source — needed a real override, not a route change).
- [x] Fixed a Turbo Drive bug: the profile dropdown didn't open until a hard refresh. Root cause — the login form was Turbo-driven (soft navigation across the sign-in boundary), and Turbo's script re-execution rules for that transition weren't reliably re-running the vendor JS. Fix: `data-turbo="false"` on the login and password-reset forms — the same treatment the logout button already had — so the auth boundary is always a true full-page load. Not asserted in a request spec (Turbo behavior is a browser-JS concern specs can't exercise); verified manually.
- [x] Fixed the profile avatar: `.avatar-title` has no dimensions of its own (fills 100% of a sized parent per the template's own CSS) — a bare `<span class="avatar-title">` collapses to the letter's own size, not a circle. Wrapped in `<div class="avatar-sm">` in both layouts, matching the template's own avatar markup convention.
- [x] Fixed a second, more serious instance of the same `Devise::Mapping.find_scope!` ambiguity as the `sign_out` regression above: the reset-password *mailer* infers scope the same ambiguous way (`edit_password_url(@resource, ...)` → `find_scope!`), and unlike `sign_out`, has no explicit-scope escape hatch to call instead — Devise resolves ties to whichever `devise_for` was **registered first**, which was `:platform_staff` (declared first in `config/routes.rb`), so every tenant forgot-password email crashed with `undefined method 'edit_platform_staff_password_url'` (that scope has no password routes at all — `NoMethodError in Passwords#create`, reported live). Fixed by reordering `config/routes.rb` so `devise_for :users` registers before `devise_for :platform_staff` — heavily commented in place, since it's a real "route order matters" landmine for whoever touches that file next. **Found a second bug while verifying the fix**: the emailed reset link pointed at `localhost` instead of the requesting Account's own subdomain (`config.action_mailer.default_url_options` is a single static host, platform-wide) — fixed via a tenant-aware `ApplicationMailer#default_url_options` override (reads `Current.account`/`Current.platform_request`, safe because Devise's mailer delivers synchronously via `deliver_now`, not `deliver_later` — would need revisiting if that ever changes) and pointing `Devise.parent_mailer` at `ApplicationMailer` instead of the default bare `ActionMailer::Base`. `spec/requests/admin_passwords_spec.rb` covers both: no crash, and the link host matches the tenant.
- [x] **Dev tooling**: added [MailCatcher](https://mailcatcher.me) so the reset-password email above (and every future one — invites, notifications) is actually inspectable in development instead of silently vanishing (`config.action_mailer.delivery_method = :smtp` → `localhost:1025`, web UI at `localhost:1080`; `raise_delivery_errors` flipped to `true` now that there's something real to fail against). Deliberately not in the `Gemfile` — its pinned `eventmachine`/`thin` versions conflict with a modern Rails bundle (confirmed: `gem install mailcatcher` under this project's Ruby fails outright, `"rackup" from rack conflicts with installed executable from rackup`). `bin/mailcatcher` finds and runs it from whichever Ruby it's actually installed under (checks other installed rvm rubies, invokes via `rvm <version> do` — a plain file-path exec isn't enough, rvm's shims resolve gems against the *active* Ruby regardless of which one's bin the path came from), wired into `Procfile.dev`.
- [x] **All mail now delivers via Sidekiq (`deliver_later`), not inline** — a slow/down SMTP connection should never block a request. This immediately broke the tenant-subdomain-in-emails fix directly above: `Current.account`/`Current.platform_request` are request-scoped `CurrentAttributes` that do **not** survive into a Sidekiq job's own separate process, so `ApplicationMailer#default_url_options` would have silently fallen back to the static default host once mail actually rendered inside the job — the exact bug already fixed once, regressing silently rather than crashing. Fixed properly, not papered over: `User#send_devise_notification` now captures `Current.account`/`Current.platform_request` *before* the async boundary (still inside the original request) and threads them through as real job arguments (`DeviseMailer < Devise::Mailer` pulls them back out of Devise's `opts` before it merges the rest into mail headers) — an `Account` inside a Hash job argument round-trips correctly via ActiveJob's GlobalID serialization, which is what actually makes this safe across a genuinely separate process, not a coincidence. `ApplicationMailer#default_url_options` checks explicit `@tenant_account`/`@tenant_platform_request` first, `Current` only as a same-request fallback, documented as the pattern any future mailer needing this should follow. **Also fixed `bin/jobs` while wiring this up**: `-r <path/to/config/environment>` (no directory, no `.rb` extension) silently failed to boot Sidekiq at all — a latent bug from Phase 0 that had never actually been run end-to-end until now; Sidekiq wants `-r <app-root-dir>` (`-r .`), not a specific file. **Verified with the real Sidekiq worker as a genuinely separate OS process** (`bin/jobs`, distinct PID from the Rails server), not just the ActiveJob test adapter: triggered a real password-reset request, watched Sidekiq's log show the `GlobalID`-serialized `User` and `Account` arguments, confirmed the delivered email in MailCatcher still links to the correct tenant subdomain. `spec/requests/admin_passwords_spec.rb` covers both enqueuing and (via `perform_enqueued_jobs`, which genuinely round-trips job arguments through serialization) the correct end-to-end link.

- [x] **Restructured controllers/views into `Admin::`/`SuperAdmin::` namespaces** (renamed from the ad hoc top-level-vs-`Platform::` split), each with its own `BaseController` everything else in that namespace inherits from — `Admin::BaseController`, `SuperAdmin::BaseController` — rather than concrete controllers assembling their own before_action chains individually. This also fixed a real architectural wart from earlier in this phase: `Platform::ApplicationController` couldn't inherit the top-level `ApplicationController` at all, because tenant-resolution logic was baked directly into it — every platform controller had to be a bare `ActionController::Base` subclass instead. Now `ApplicationController` is deliberately neutral (no tenant/auth/Pundit logic of its own), and *both* `Admin::BaseController` and `SuperAdmin::BaseController` cleanly inherit from it, each layering on only what their own audience needs.
  - `app/controllers/{admin,super_admin}/base_controller.rb`, with `sessions_controller.rb`/`passwords_controller.rb`/`smoke_controller.rb` (as applicable) inheriting from the sibling `BaseController` — except the two Devise `SessionsController`s, which structurally can't (Devise::SessionsController's ancestry always runs through the single `config.parent_controller` value, now `"Admin::BaseController"` — `SuperAdmin::SessionsController` skips what it inherits wrongly and re-adds `PlatformRequestScoped` manually; heavily commented in place, same pattern as the pre-existing `sign_out(resource_name)` workaround for the same root cause).
  - Views moved to match: `app/views/admin/{sessions,passwords,smoke}/*`, `app/views/super_admin/{sessions,smoke}/*`. Already-shared views stay shared: `app/views/shared/_head.html.erb`, and the three console layouts (`layouts/admin.html.erb`, `layouts/super_admin.html.erb` — renamed from `platform.html.erb`, `layouts/auth.html.erb`) stay flat in `layouts/` per ordinary Rails convention (layouts aren't resolved through a controller's namespace the way action views are, so nesting them under `admin/`/`super_admin/` would be unidiomatic, not more "separated").
  - `config/routes.rb` / `config/initializers/devise.rb` updated to point at the new controller paths (`controllers: { sessions: "admin/sessions", ... }` etc.) and the new `config.parent_controller`. Route **paths** stay clean (no `/admin` or `/super_admin` URL prefix — the module namespace is an internal code-organization concern, not a public URL structure; the tenant subdomain *is* the admin console, it doesn't need a path prefix saying so).
  - **Admin ↔ SuperAdmin isolation** (explicit requirement) verified at all three independent layers, not just asserted: (1) routing — `Hosting::TenantSubdomainConstraint`/`Hosting::ApexConstraint` only ever dispatch to their own namespace, confirmed a tenant subdomain gets a 404 hitting a `super_admin/*` path and vice versa; (2) the Warden scope — manually forced a signed-in tenant admin's cookie onto a request to the apex domain (something no real browser would even do, host-only cookies aren't sent cross-host) and confirmed the server-side `authenticate_platform_staff!` check still correctly rejects it (redirects to the Super Admin login), and the reverse; (3) `Current.account`/`Current.platform_request` stay mutually exclusive at the model layer as a last resort. `spec/requests/hosting_spec.rb` covers layer 1.
  - No functional/behavioral regressions — this was a pure reorganization. 62/62 specs still green (renamed `platform_sessions_spec.rb` → `super_admin_sessions_spec.rb`, `sessions_spec.rb`/`passwords_spec.rb` → `admin_sessions_spec.rb`/`admin_passwords_spec.rb` to match), Rubocop clean, Brakeman clean, full manual re-verification of both login flows, the dashboard, logout, and the isolation checks above against a live server.
- [x] **DRY pass** on what the `Admin::`/`SuperAdmin::` split above made visible as genuine duplication (not hypothetical — each of these was byte-identical or near-identical in 2–4 places before this):
  - `app/controllers/concerns/pundit_authorizable.rb` — `include Pundit::Authorization` + `rescue_from Pundit::NotAuthorizedError` + `user_not_authorized` were verbatim-identical in both `BaseController`s; now included once by each.
  - `app/views/shared/_password_field.html.erb` — the password-input-plus-eye-toggle block (`data-controller="password-toggle"` wrapper, the two Stimulus targets, the toggle button) was copy-pasted 4 times across the two login forms and the set-new-password form's two fields. One partial, parameterized by `form`/`field`/`placeholder`/`autocomplete`/`autofocus`.
  - `app/views/shared/_user_dropdown.html.erb` + `app/views/shared/_console_shell.html.erb` — the topbar/sidebar/footer/script-includes chrome was ~90% identical between `layouts/admin.html.erb` and `layouts/super_admin.html.erb`, differing only in nav items, page-title default, footer text, and which `current_*`/`*_signed_in?`/`destroy_*_session_path` helpers to use. Extracted into one shell partial rendered via `render layout: "shared/console_shell", locals: { ... } do ... end` — locals carry the per-audience data (`nav_items` from new `AdminHelper#admin_nav_items`/`SuperAdminHelper#super_admin_nav_items`, and a `user_dropdown` locals hash, or `nil` if signed out) rather than the partial needing to know which Devise scope it's in. Each layout file is now ~20 lines of "what differs," not ~90 lines of "mostly the same as the other one."
  - Deliberately **not** touched: `Admin::SessionsController`/`Admin::PasswordsController`/`SuperAdmin::SessionsController`'s one-line `skip_before_action :authenticate_user!` each, and the two controllers' `after_sign_out_path_for` overrides (same shape, genuinely different redirect targets). Extracting either would trade three one-line, self-explanatory statements for a concern file plus three `include` lines — more code, not less, for something that isn't actually repeated *logic*, just a repeated *shape*. (Sandi Metz's "prefer duplication over the wrong abstraction" — noted here so it's a considered omission, not a missed one.)
  - No behavior changes. 62/62 specs still green, Rubocop clean, Brakeman clean, full manual re-verification (both login forms' toggle-eye markup, both dashboards' avatar/nav/dropdown, the password-reset form's two fields, vendor JS still resolving from inside the nested shell partial).
- [x] **Every route now carries its console's URL namespace, not just its controller/module namespace**: `acme.lvh.me:3000/users/sign_in` → `/admin/login`, `lvh.me:3000/platform_staff/sign_in` → `/platform/login`, and the same for logout/password/dashboard/smoke — `/admin/*` for the tenant scope, `/platform/*` for the apex scope. Used Devise's `path:`/`path_names:` `devise_for` options (`path: "admin", path_names: { sign_in: "login", sign_out: "logout" }`) rather than wrapping in a routing `namespace`/`scope` block — this rewrites only the URL segments; the Warden scope name, session key, and every route *helper* (`new_user_session_path`, `destroy_user_session_path`, `edit_user_password_path`, ...) are completely unaffected, so no view/controller that already called those helpers needed to change. The dashboard/smoke routes moved from a bare `root to:` at `/` to `get "admin"/"platform"`, named `user_root`/`platform_staff_root` to match Devise's own `"#{scope}_root_path"` lookup convention exactly (`signed_in_root_path` finds them automatically, no override needed for *that* part).
  - Removing the bare `root_path` (nothing lives at literal `/` anymore on either host) rippled into every place that had been calling it generically: `PunditAuthorizable`'s not-authorized fallback now calls a new `authorization_fallback_path` hook each `BaseController` implements with its own scope's root, rather than the shared concern needing to know or branch on which audience it's mixed into; `shared/_console_shell`'s brand link takes a `home_path` local instead of calling `root_path` itself; `Admin`/`SuperAdminHelper#*_nav_items`'s Dashboard entry points at `user_root_path`/`platform_staff_root_path` directly.
  - **Real bug caught by this change, not just a rename**: `after_sign_in_path_for`/`signed_in_root_path`'s default resolves its scope via the same `Devise::Mapping.find_scope!(resource)` ambiguity behind the earlier `sign_out`/mailer bugs — it always resolves to `:user` (registered first in `config/routes.rb`) regardless of which Warden scope actually signed in. This was silently masked the whole time `user_root_path` and `platform_staff_root_path` both happened to generate the same string (`"/"`) — the moment they became genuinely different paths, a successful Super Admin login started redirecting to `/admin` instead of `/platform`. Fixed by explicitly overriding `after_sign_in_path_for` in **both** `Admin::SessionsController` and `SuperAdmin::SessionsController` (`stored_location_for(resource_or_scope) || own_scope_root_path` — preserves Devise's "return to the page you originally tried to visit" behavior, only pins the *fallback*), so neither controller's correctness depends on `devise_for` registration order anymore. Caught by the full spec suite immediately after the routing change — `spec/requests/super_admin_sessions_spec.rb`'s existing "signs in a platform_staff user" test failed exactly as it should have.
  - 62/62 specs green (updated every hardcoded old-path assertion — `/users/...`, `/__smoke`, `/super_admin/__smoke` — to the new `/admin/...`/`/platform/...` forms; route-helper-based assertions needed no changes at all), Rubocop clean, Brakeman clean, full manual re-verification against a live server: both new login URLs render, both old URLs 404, unauthenticated dashboard access redirects to the new login path, both logins land on their *own* correct root (the bug above, confirmed fixed), logout forms post to the new paths, cross-namespace isolation (`/admin/*` unreachable from the apex and vice versa) still holds.
- [x] **Vendored assets trimmed to only what's used, and moved to conventional Rails locations.** The webadmin template got vendored wholesale earlier in this phase (24MB — every demo library the template ships: chart libraries, rich-text editors, calendars, lightboxes, none of which this app uses). Audited by grepping the 3 CSS files we actually load for every `url()` reference (not guessed): all 28 font files turned out to be genuinely referenced (kept whole), but only 1 of 46 vendored images was (`pattern-bg.jpg` — the other 3 the CSS references, `bg-auth.png`/`login-img.png`/`profile-bg.jpg`, don't exist in the source template at all, a pre-existing gap noted back in Phase 0/1). Everything else — `assets/libs/*` beyond Bootstrap's JS and MetisMenu, the template's own `app.js`/`pages/*.js` (we deliberately don't load these, see `shared/_console_shell`'s own comment), all 45 unused images — deleted. Footprint: 24MB → 9.6MB CSS+fonts+images + 88KB JS.
  - **CSS/fonts/images** → `app/assets/stylesheets/vendor/webadmin/{css,fonts,images}` (was `app/assets/vendor/webadmin/`, a non-standard top-level `vendor` folder directly under `app/assets`). Nested under `stylesheets/` because that's Propshaft's actual asset category for this content; `vendor/webadmin/` marks it as third-party within that category, mirroring how `vendor/javascript` marks vendored JS at the app root. The `css/`+`fonts/`+`images/` sibling relationship is preserved exactly (not flattened) — required for the CSS files' own relative `url(../fonts/...)` references to keep resolving through Propshaft's rewriting, a constraint discovered and documented back when these were first vendored.
  - **JS** (`bootstrap.min.js`, `metismenujs.js`) → `vendor/javascript/`, Rails' actual convention for vendored (non-npm-downloaded) JS packages consumed via importmap — pinned in `config/importmap.rb`, imported once as side effects in `app/javascript/application.js` (`import "bootstrap"` / `import "metismenujs"`) rather than a `javascript_include_tag` call repeated in three different layout files. Both are classic UMD bundles (checked: `typeof exports=="object"&&typeof module!="undefined"?...:typeof define=="function"...:(globalThis).bootstrap=...` — the standard UMD wrapper), so importing them for side effects via ESM attaches the same `window.bootstrap`/`window.MetisMenu` globals a plain `<script>` tag would have — `sidebar_controller.js`'s existing `window.MetisMenu` check needed no changes.
  - `config/initializers/assets.rb` simplified (no longer needs to register a custom asset path — `app/assets/stylesheets` is already a Propshaft default, and `vendor/javascript` is auto-registered by importmap-rails itself). `vendor/webadmin_template/README.md` rewritten to describe what's actually vendored vs. what was deliberately left out and where to find it if a future screen needs it.
  - Verified for real, not just "the file moved": booted the server, confirmed every CSS/JS/font/image URL in the rendered HTML resolves 200 (including the font/image references *inside* the compiled CSS, proving Propshaft's `url()` rewriting still works from the new nested location), ran the full login → dashboard flow and confirmed the dashboard still renders with its avatar/nav-icons/dropdown intact. 62/62 specs, Rubocop, Brakeman all clean — no behavior changes, pure reorganization.

**62/62 specs green, Rubocop clean, Brakeman: 0 warnings.**

---

## Phase 2 — Tenant Provisioning (Platform Console)

**Goal:** Super Admin can create a new Account (tenant) and its initial admin user from the Platform Console — the only way tenants come into existence (§4.1, §4.6 — no self-serve signup).
**Implements:** §4.1, §4.3 (Platform Console), §4.7 item 1, §4.9 item 4 (OAuth app auto-creation), §5.1.
**Depends on:** Phase 1.

- [ ] `SuperAdmin::AccountsController` — index/new/create/show; slug availability check (AJAX/Turbo Frame against reserved words + uniqueness) while typing.
- [ ] Creating an Account also creates its first `AccountMembership`-holding admin `User` (temp password, forced reset — reuses Phase 1's flow) in the same transaction.
- [ ] Auto-create one Doorkeeper `OAuthApplication` per Account at provisioning time (§4.9 item 4) — client_id/secret generated, stored, not yet exposed anywhere in tenant UI (that's Phase 16).
- [ ] Platform Console tenant list: search, status (active/suspended), suspend/reinstate action.
- [ ] Welcome email to the new tenant admin with their subdomain URL + temp password (reuses baseline's welcome-email pattern, §3.10).

### Definition of Done
- [ ] Request spec: Super Admin creates an Account → `AccountMembership`, initial `User`, and `OAuthApplication` all exist and are correctly associated.
- [ ] Request spec: reserved-word / duplicate slug rejected with a clear validation error.
- [ ] Request spec: a suspended Account's admin cannot log in (ties back to Phase 1's check).
- [ ] Manual QA: full browser flow — Super Admin provisions "Acme Events," receives the temp password (check test mailer inbox), logs in as that tenant admin at `acme.lvh.me`, is forced through password reset.

---

## Phase 3 — Dashboard Shells (Admin Console + Platform Console)

**Goal:** the authenticated landing page for both audiences exists, using real (if mostly empty) data, with the navigation chrome that every later feature phase will plug screens into.
**Implements:** §5.14, §5.15 (initial wiring only — real live data lands in Phase 9), §4.7 (Super Admin cross-tenant pulse, empty-state now).
**Depends on:** Phase 2.

- [ ] Tenant Admin Console dashboard: sidebar nav (Events, Participants, Badges, Check-in, Sponsors, Reports, Settings — stub links to be filled by later phases), empty-state widgets (0 events, 0 participants).
- [ ] Platform Console dashboard: tenant count, events-pending-approval count (stub until Phase 5), placeholder for cross-tenant live pulse (real data in Phase 9).
- [ ] Account switcher UI stub in the tenant nav (populated for real in Phase 17 — cross-tenant SSO) — safe to render "no other accounts" for a single-membership user now.
- [ ] Responsive check of both dashboards against the webadmin template's breakpoints.
- [ ] Shared partial library established: card/tile, stat widget, empty-state, page-header — every later phase composes from these rather than hand-rolling markup (§5.14 working process).

### Definition of Done
- [ ] Manual QA: both dashboards render correctly logged in, nav links present (even if some 404 until later phases fill them in — track as known-stub, not a bug).
- [ ] Request spec: unauthenticated request to either dashboard redirects to the correct login.
- [ ] Component/view spec for the shared stat-widget partial (renders label + value + optional trend).

---

## Phase 4 — Event Lifecycle

**Goal:** an organizer can create, edit, and progress an event through its lifecycle from the Admin Console.
**Implements:** §3.2, §5.2 (tabbed builder, simplified from baseline wizard), §8 (`Event` model, UUIDv7 PK).
**Depends on:** Phase 3.

- [ ] `Event` model: `account_id`, `name`, `slug` (friendly_id, unique per account), `mode` (`on_site`/`virtual`/`hybrid`), `status` (`draft`/`up_coming`/`live`/`completed`), `approval_status` (`pending`/`approved`/`rejected` — column added now, workflow built in Phase 5), address/meeting-link fields, `participant_fields` jsonb (configurable required fields, baseline §3.2), banner orientation.
- [ ] Tabbed event builder UI (not a linear wizard): Basic Info, Agenda (stub until Phase 11), Ticket Categories (stub until Phase 6), Badge (stub until Phase 8), Review — each tab autosaves independently (Turbo Frame per tab + background save), each tab shows its own completeness indicator.
- [ ] Event list/index (filter by status), event show/edit shell that hosts the tabs.
- [ ] `EventScheduler` job (Sidekiq, recurring): auto-transitions `draft → up_coming → live → completed` based on configured start/end times — ports baseline's `EventSchedularJob` logic minus the auto-checkout piece (that belongs in Phase 9 once `Attendance` exists).
- [ ] Event duplication/template action stubbed as a menu item (full clone logic can land here since it only touches Event-tab data available at this phase — clone name/mode/participant_fields now; richer clone of tickets/badges revisited once those phases exist).
- [ ] Pundit policy: only users with sufficient `AccountMembership` role can create/edit events; per-event staff assignment (§5.1 new item) modeled as a join table now even if the UI for assigning is added later.

### Definition of Done
- [ ] Model spec: status transitions, slug uniqueness scoped to account, participant_fields jsonb round-trips.
- [ ] Job spec: `EventScheduler` transitions a time-traveled event through each status correctly (Timecop/ActiveSupport::Testing::TimeHelpers).
- [ ] Request spec: organizer without the right role cannot create/edit an event (403).
- [ ] Manual QA: create an event, navigate freely between tabs (not forced sequentially), close browser, come back — data persisted per tab.
- [ ] Cross-tenant leak spec: Account A cannot see/edit Account B's event by guessing its ID/slug.

---

## Phase 5 — Event Approval Workflow (Super Admin gate)

**Goal:** organizer submits an event for review; Super Admin approves or rejects with a reason; this is the single most important cross-cutting gate in the whole system (blocks Phase 18's public visibility later).
**Implements:** §4.7 item 2, §5.2 (approval gate), §8 (`approved_by`, `approved_at`, `rejection_reason`).
**Depends on:** Phase 4.

- [ ] `Event#submit_for_review!` action from the Review tab — moves `approval_status` to `pending`, locks nothing else (organizer can keep editing per §5.2 re-approval-on-edit decision).
- [ ] `SuperAdmin::EventReviewsController` — queue of pending events, sorted oldest-first, visually flags anything approaching the 24h SLA (§5.2).
- [ ] Approve action: sets `approval_status: approved`, `approved_by`, `approved_at`.
- [ ] Reject action: requires a reason (validated non-blank), sets `approval_status: rejected`, `rejection_reason`; event stays editable and resubmittable.
- [ ] Email notification to the organizer on reject (WhatsApp/Gupshup piece deferred to Phase 13, per its own dependency on Gupshup credentials) — delivery-state tracked (`pending/sent/failed`, reuses baseline pattern).
- [ ] Tenant-side: event show page displays current `approval_status` prominently, with the rejection reason if rejected, and the "typically reviewed within 24 hours" messaging while pending.
- [ ] Re-approval-on-edit confirmed behavior: editing an already-approved event does **not** revert `approval_status` (§5.2 v8 decision) — explicit test for this, since it's easy to accidentally regress.

### Definition of Done
- [ ] Model spec: full pending → approved and pending → rejected → resubmit → approved cycles.
- [ ] Request spec: only Super Admin (`platform_staff`) can access the review queue/approve/reject actions — a tenant admin gets 403 even for their own event.
- [ ] Job/mailer spec: rejection triggers exactly one email with the reason included.
- [ ] Manual QA: submit an event, approve it as Super Admin, edit it as the organizer, confirm `approval_status` stays `approved`. Separately: submit, reject with a reason, confirm the tenant sees the reason and can resubmit.

---

## Phase 6 — Ticketing (Capacity-Based, No Payment)

**Goal:** organizers define ticket categories as capacity buckets; registrants can be group-reserved and waitlisted. No pricing/checkout anywhere (§5.3 explicit scope note).
**Implements:** §5.3, §8 (`TicketCategory`).
**Depends on:** Phase 4 (event tab this fills in).

- [ ] `TicketCategory` model: `event_id`, `name`, `total_count`, `sold_count`, `remain_count` (kept in sync via callback/service, ports baseline `Event#sync_tickets` logic), `document_required` boolean. No price field (deferred).
- [ ] Ticket Categories tab in the event builder (Phase 4's stub filled in): CRUD, capacity validated against event-level seat limit if one is set.
- [ ] Group/bulk registration: one reservation holds N spots against a category, with per-seat detail fillable later or via forwarded claim links (claim-link consumption itself can be a thin stub here — full self-service portal is Phase 7/Phase 18 territory, but the reservation + capacity math belongs in this phase).
- [ ] Waitlist: when a category is full, new interest queues instead of failing outright; a service object handles automatic offer-on-release when capacity frees up (ties into Phase 7's cancellation flow).
- [ ] Cancellation-with-seat-restoration (in scope per §5.3 — only refunds are deferred): cancelling a reservation restores `remain_count` and triggers waitlist offer check.

### Definition of Done
- [ ] Model spec: capacity math (`total/sold/remain`) stays consistent across create/cancel/waitlist-promote.
- [ ] Service spec: category at capacity → new registrant waitlisted, not rejected; releasing a seat auto-promotes the next waitlisted entry.
- [ ] Request spec: organizer cannot set category capacity exceeding the event-level seat limit (if configured).
- [ ] Manual QA: fill a 2-seat category with 2 reservations, attempt a 3rd (lands on waitlist), cancel one of the first two, confirm the waitlisted one is auto-promoted.

---

## Phase 7 — Participant Lifecycle (Registration & Management)

**Goal:** admin-side participant CRUD, dedupe rules, bulk import/export, custom fields — the deepest data-integrity-sensitive module carried from the baseline. (Public self-registration via Next.js is explicitly out of scope until Phase 18; admin manual entry is the full surface for now.)
**Implements:** §3.4, §5.4, §8 (`Participant`).
**Depends on:** Phase 6 (registers against a `TicketCategory`).

- [ ] `Participant` model: `account_id`, `event_id`, `ticket_category_id`, `hex_id`, `client_participant_id` (auto-generated if missing), `govt_id` (plain field, no integration — §5.4 confirmed), `rf_id`, name/email/contact/company/department/position/nationality/country, photo (Active Storage, tenant-namespaced path per §4.2), document upload gated by `ticket_category.document_required`, `source` (`manual`/`upload`/`client_api` — last one wired for real in Phase 16).
- [ ] Dedupe validation chain (govt ID → email+name → email → phone), scoped per event, ported from baseline fuzzy-match logic.
- [ ] Custom-field builder (§5.4 new item): organizer-defined fields (text/select/checkbox/file) stored per event, rendered dynamically on the admin manual-entry form — this generalizes the baseline's fixed `participant_fields` catalog from Phase 4.
- [ ] Admin participant list: search/filter across identifier fields, pagination (Pagy), bulk destroy.
- [ ] Approval-based registration toggle per event (organizer must approve before a participant is considered confirmed) — status field on `Participant`.
- [ ] Bulk XLSX import (async Sidekiq job) with the same fuzzy-dedupe matching, progress-pollable; bulk XLSX export (attendance/session columns stubbed until Phase 9/11 exist, but the export scaffold and signed-download-URL delivery belong here).
- [ ] `EventLiveStats` row seeded/incremented on participant create (column exists, real-time broadcast wiring is Phase 9 — this phase just keeps the counter correct as a plain DB write).

### Definition of Done
- [ ] Model spec: full dedupe chain, each fallback level tested independently.
- [ ] Job spec: bulk import handles a mixed file (new + duplicate rows) correctly, reports per-row outcome.
- [ ] Request spec: admin manual entry respects custom-field requiredness; document upload rejected/accepted based on ticket category flag.
- [ ] Cross-tenant leak spec: participant search never returns another account's rows.
- [ ] Manual QA: import a sample XLSX with a few intentional duplicates, confirm correct dedupe outcome and progress UI; manually create one participant through the custom-field form.

---

## Phase 8 — Badge Design & Printing

**Goal:** organizers design a badge visually and render a correctly sized PDF with live participant data substituted in. (Auto-print via the Electron agent is Phase 10 — this phase is design + on-demand render/download only.)
**Implements:** §3.6, §5.5, §4.10 (GrapesJS + Grover), §8 (`Badge`, `BadgeTemplate`).
**Depends on:** Phase 7 (needs real participant data to render tokens against).

- [ ] `BadgeTemplate` model: `account_id`, reusable across events (library, §5.5 new item), `content` (HTML/CSS), `mapping` (token list), background image + logo (Active Storage), `output_type` (`badge`/`wristband`), physical size (cm).
- [ ] `Badge` — per-event instantiation of a `BadgeTemplate` (or a fresh one), same content/mapping shape.
- [ ] GrapesJS integration wrapped in a single Stimulus controller (§4.10 — no React island) inside the admin console's Badge tab (Phase 4 stub filled in); custom draggable blocks map to tokens (`$NAME$`, `$PHOTO$`, `$QRCODE$`, `$BARCODE$`, `$OTHER1..3$`, etc.).
- [ ] Token-substitution engine (`BadgeReformService`-equivalent): given a `Participant` + `Badge`, produce final HTML with tokens replaced, QR (`rqrcode`) and Code128 barcode (`barby`) generated in two independent slots.
- [ ] Grover-based PDF render at correct DPI/page size from the substituted HTML; on-demand single-badge download endpoint.
- [ ] Conditional badge layout by ticket category (§5.5 new item): an event can map different `Badge`s to different `TicketCategory`s without duplicating the whole template.

### Definition of Done
- [ ] Service spec: token substitution produces correct output for a fixture participant across all supported tokens, including both QR/barcode slots independently.
- [ ] Request spec: PDF download endpoint returns a correctly-sized PDF (assert page dimensions match configured badge size).
- [ ] Manual QA: design a badge in the GrapesJS canvas, save, generate a PDF for a real participant, visually confirm photo/QR/text placement matches the design.
- [ ] Manual QA: two ticket categories on one event render visibly different badges from the same event without template duplication.

---

## Phase 9 — Check-in, Attendance & Real-Time Live Dashboards

**Goal:** the on-site scan loop (event/session check-in, anti-double-scan, virtual redirect) plus the flagship real-time dashboard requirement — this is where §5.15 stops being a stub and goes live.
**Implements:** §3.7, §5.6, §5.15, §6 item 13 (unified `ScanEvent`), §8 (`ScanEvent`, `Attendance`, `EventLiveStats`, `SessionLiveStats`, partitioning).
**Depends on:** Phase 8 (the "scan → print badge → mark attendance" combined flow needs both).

- [ ] `ScanEvent` (unifying abstraction, §6.13): `account_id`, `event_id`, `participant_id`, `scan_type` (check_in/check_out/print/lead_retrieval/triggered_content — later phases add more types onto the same table), `source` (kiosk/manual/agent), timestamp. Monthly range-partitioned on the write timestamp (§4.10).
- [ ] `Attendance`: derived/recorded from `ScanEvent`, `from` (event/session), `status` (check_in/check_out/manual_check_out/absent), time-spent computation from paired events. Also monthly-partitioned.
- [ ] Multi-identifier scan lookup (hex ID, govt ID, RFID, client participant ID) with 30-second anti-double-scan debounce.
- [ ] Session-level check-in with per-session seat-limit enforcement (depends on Phase 11's `Session` model — if Phase 11 hasn't landed yet, event-level check-in ships first and session-level is added when Phase 11 completes; sequence flexibly if needed).
- [ ] Virtual-event redirect-on-check-in (scan → mark attendance → redirect to meeting link).
- [ ] `EventLiveStats`/`SessionLiveStats`: denormalized counters, incremented in the same transaction as the triggering `Participant`/`ScanEvent` write — single source of truth for both initial dashboard load and live broadcast payload (§5.15 — the two paths must never disagree).
- [ ] Redis pub/sub → Turbo Streams broadcast on `event:{event_id}:live` channel; admin dashboard (Phase 3's stat widgets) subscribes and patches DOM nodes with no full reload.
- [ ] Super Admin cross-tenant live pulse (Platform Console dashboard, Phase 3 stub filled in): aggregate registrations/check-ins across all currently-live events.
- [ ] Rolling per-minute time-series bucket for the live sparkline (registration/check-in velocity).
- [ ] "Scan → print badge → mark attendance" combined flow, wired to Phase 8's render pipeline (on-demand print only — auto-print via the agent is Phase 10).
- [ ] EventScheduler job (Phase 4) extended: auto-checkout/mark-absent attendees when an event's `live → completed` transition fires.

### Definition of Done
- [ ] Model/service spec: debounce rejects a second scan within 30s, accepts one after.
- [ ] Model spec: `EventLiveStats` counter matches a raw `COUNT()` after a burst of concurrent scans (race-condition check — use `increment_counter`/atomic SQL, not read-modify-write).
- [ ] System spec (Capybara + Action Cable test adapter): a check-in scan in one browser session updates a **second** connected browser session's dashboard tile without a page reload, under 1 second (§7.3 target — assert via polling with a short timeout, not a hard sleep).
- [ ] Load sanity check: fan-out to N simulated subscribers doesn't measurably slow scan-write latency (even a lightweight local benchmark is enough to catch a gross regression — full load testing is a later hardening pass, not a Phase 9 blocker).
- [ ] Manual QA: two browser windows open on the same event's dashboard, scan a participant in a third tab (or via `curl`/API), watch both dashboards update live.

---

## Phase 10 — Print Agent (Electron) Integration

**Goal:** badge printing moves from "download a PDF" to "auto-print at a paired front-desk station" — the backend/pairing half lives here; the Electron app itself is a parallel deliverable track (separate repo/package), but its contract with Rails is defined and tested in this phase.
**Implements:** §5.5.1, §4.9 item 3, §8 (`PrintAgent`/`PrintStation`/`PrintJob`).
**Depends on:** Phase 9 (auto-print triggers off a check-in scan).

- [ ] `PrintStation` model: `account_id`, `event_id`, `name`, printer mapping.
- [ ] `PrintAgent`: one-time pairing code generation from the admin console; once paired, issues a station-scoped JWT (`account_id`, `event_id`, `station_id`, short expiry) delivered over Action Cable.
- [ ] `PrintJob`: queued per station, status tracking (pending/sent/failed/succeeded), reuses the pattern from baseline's bulk-print failure tracking.
- [ ] Admin console: pairing-code generator UI, per-station printer assignment, per-event auto-print on/off toggle, connection-status indicator per paired station (online/offline via Cable presence).
- [ ] Server-side: on a qualifying scan (Phase 9), if auto-print is enabled for the event, render the badge (Phase 8) and push a `PrintJob` to the correct station's channel.
- [ ] Revocation: an admin can revoke a station's pairing at any time, immediately invalidating its JWT.
- [ ] Document the agent-facing contract (channel name, JWT claims, job payload shape, ack/status-report format) in this file or a linked `doc/print-agent-protocol.md` so the Electron build (separate track) has a stable target.

### Definition of Done
- [ ] Request/channel spec: pairing code redemption issues a correctly scoped JWT; an expired/revoked JWT is rejected on the next connection attempt.
- [ ] Channel spec: a simulated agent connection (test WebSocket client, no real Electron needed) receives a `PrintJob` push when a qualifying scan occurs and auto-print is on.
- [ ] Request spec: auto-print off → no job pushed, badge still available via the Phase 8 on-demand download.
- [ ] Manual QA (once even a minimal agent stub exists): pair a station, scan a participant, confirm the job arrives at the agent process (doesn't need a real printer — logging "would print X" is sufficient to validate the contract).

---

## Phase 11 — Agenda, Speakers & Sessions

**Goal:** multi-track agenda content management, feeding both the admin console and (later) the public site.
**Implements:** §3.8, §5.2 (multi-day/multi-track), §5.7, §8 (`Session`, `Schedule`, `Speaker`).
**Depends on:** Phase 4 (fills the Agenda tab stub).

- [ ] `Speaker`: company/bio/photo, account-scoped and reusable across events (speaker portal itself is Phase 2-roadmap/later — CRUD by organizer is in scope now).
- [ ] `Schedule` (talks): linked to a `Speaker`, start/end time, details, linked to an `Event` and optionally a `Session` (track/room).
- [ ] `Session`: independent seat capacity, own check-in (retrofits into Phase 9's session-level check-in once this lands).
- [ ] Agenda tab UI: multi-day/multi-track view, drag-to-reorder or time-grid editor, room/capacity fields.
- [ ] If Phase 9 shipped before this phase, backfill session-level check-in wiring now that `Session` exists.

### Definition of Done
- [ ] Model spec: session capacity validation, schedule overlap warnings (same speaker double-booked, informational not blocking).
- [ ] Request spec: agenda CRUD respects tenant scoping and event-edit permissions.
- [ ] Manual QA: build a 2-day, 2-track agenda with overlapping sessions in different tracks, confirm the grid renders correctly.

---

## Phase 12 — Sponsors/Exhibitors & Branding

**Goal:** per-event sponsor/co-branding, generalized from the baseline's single `Client` record, plus tenant-level branding layering.
**Implements:** §3.9, §4.5, §5.8 (module minus billing/lead-retrieval, which need Phase 9's `ScanEvent` abstraction extended — lead-retrieval scan type can piggyback on Phase 9's `ScanEvent.scan_type` enum here).
**Depends on:** Phase 9 (lead-retrieval reuses `ScanEvent`).

- [ ] `Sponsor`/`Exhibitor` model (generalized `Client`): logo, custom email body/footer, tier.
- [ ] Tenant-level branding: logo, color palette, PDF/badge letterhead — layered Platform → Tenant → Event → Sponsor per §4.5, applied to email templates (Phase 13) and badge rendering (Phase 8, revisit if needed).
- [ ] Booth page stub content fields (full booth-page builder can be a fast-follow if time-boxed — the data model and admin CRUD are this phase's actual requirement).
- [ ] Lead-retrieval: exhibitor staff scan attendee badges, `ScanEvent.scan_type: lead_retrieval`, notes/tags captured, exportable list per sponsor.

### Definition of Done
- [ ] Model spec: sponsor tier CRUD, tenant branding cascades correctly into a rendered email preview.
- [ ] Request spec: lead-retrieval scan creates a `ScanEvent` distinct from attendee check-in, doesn't affect `EventLiveStats` occupancy counters.
- [ ] Manual QA: set tenant branding, confirm it appears on a test registration-confirmation email preview and on a rendered badge.

---

## Phase 13 — Communications (Email + WhatsApp/Gupshup)

**Goal:** the notification layer used by every prior phase (approval rejection, invites, invoices) becomes fully real, plus WhatsApp for Super-Admin-to-tenant operational messages.
**Implements:** §3.10, §5.10, §8 (channel field on delivery tracking).
**Depends on:** Phase 5 (rejection notifications already stubbed with email-only), Phase 2 (welcome email).

- [ ] Delivery-state tracking model/concern (`pending/sent/failed`) generalized with a `channel` (`email`/`whatsapp`) column, reused by every mailer already built in earlier phases.
- [ ] Gupshup client wrapper (platform-level credential, not per-tenant, per v10 decision) — assume credential exists in `ENV`/Rails credentials; this phase builds the integration code, not the Gupshup account itself (stakeholder's responsibility).
- [ ] WhatsApp sent for: event rejection (Phase 5), invoice sent, quotation sent/revised (Phase 15) — wire these in now that the channel exists; earlier phases' email-only stubs get a WhatsApp companion send here.
- [ ] "Resend invitation" and "send to all pending" batch actions (baseline §3.10) on the participant list (Phase 7).
- [ ] Registration-confirmation email using Phase 12's tenant/sponsor branding layering.

### Definition of Done
- [ ] Job spec: a rejection event now enqueues both an email job and a WhatsApp job, each independently tracked (one failing doesn't block the other).
- [ ] Service spec: Gupshup client handles a non-200 response by marking the notification `failed`, not raising unhandled.
- [ ] Manual QA (with a real or sandbox Gupshup credential): trigger an event rejection, confirm a WhatsApp message arrives at a test number using `contact_num`.

---

## Phase 14 — Reporting, Import/Export & Analytics

**Goal:** turn the raw data accumulated by every prior phase into organizer-facing reports — currently a complete gap per the requirements doc, called out as a priority.
**Implements:** §3.11, §5.11.
**Depends on:** Phase 9 (attendance data), Phase 7 (participant data).

- [ ] Configurable export templates (organizer picks columns/format: XLSX/CSV/PDF) generalizing Phase 7's fixed export.
- [ ] Analytics dashboards: registrations-over-time, check-in rate, session popularity (Phase 11 data), engagement funnel — built as read-models querying `EventLiveStats`/historical `ScanEvent` partitions, not expensive live `COUNT()`s.
- [ ] Scheduled report delivery (Sidekiq-cron or equivalent: emailed weekly/daily summary to organizers).

### Definition of Done
- [ ] Job spec: async export honors a custom column selection and format choice.
- [ ] Request spec: analytics dashboard queries stay within an acceptable query-count/time budget on a seeded large dataset (guard against N+1 regressions with `bullet` or an explicit query-count assertion).
- [ ] Manual QA: export a custom CSV, confirm columns match selection; view the registrations-over-time chart against seeded historical data.

---

## Phase 15 — Platform Billing & Invoicing

**Goal:** the full manual billing lifecycle — plan assignment, capacity overage, Business-tier quotation gate, post-event invoice, NEFT/UTR verification — entirely without a payment gateway.
**Implements:** §4.6 (fully), §8 (`Plan`/`Subscription`/`UsageRecord`, `Invoice`, `PaymentSubmission`, `CapacityAdjustment`, `Quotation`, `QuotationRevision`).
**Depends on:** Phase 5 (Business events are quotation-gated *before* creation — this phase's `Quotation` gate technically intercepts Phase 4's event-creation flow for Business-plan requests, so expect to revisit Phase 4's create action here).

- [ ] `Plan` (Basic/Pro/Business definitions), assigned per event at creation time (not per Account).
- [ ] Basic/Pro: cap enforcement is soft — registrations aren't hard-blocked at 500/1,000; Super Admin can raise the cap.
- [ ] `CapacityAdjustment`: event, previous cap, new cap, optional `override_rate`, increased-by, timestamp — Platform Console action.
- [ ] `Quotation`/`QuotationRevision` for Business-tier: organizer requests → Super Admin sends amount → tenant approves (event creation unblocked) or rejects-with-note (Super Admin revises, repeat up to 3 rejections → `cancelled`).
- [ ] Retrofit Phase 4's event-creation flow: if `plan == business`, creation is blocked pending an `approved` `Quotation`.
- [ ] Computed-income read-model: Platform Console shows per-tenant/per-event participant count, capacity adjustments, computed amount owed.
- [ ] Manual billing lifecycle: event completes → Super Admin raises `Invoice` (base + overage) → tenant notified (email + WhatsApp, Phase 13) → tenant uploads UTR/receipt → `PaymentSubmission` (`pending_review`) → Super Admin approves (marks paid) or rejects with a reason for resubmission.

### Definition of Done
- [ ] Model spec: Quotation reject/revise cycle caps at 3 rejections, 3rd moves to `cancelled`, no further revision possible after.
- [ ] Model spec: `CapacityAdjustment` correctly feeds the computed-income overage calculation, with and without an `override_rate`.
- [ ] Request spec: Business-tier event creation is blocked without an `approved` `Quotation`; unblocked immediately after approval.
- [ ] Request spec: `PaymentSubmission` review cycle — reject-with-reason keeps `Invoice` unpaid and resubmittable; approve marks it paid.
- [ ] Manual QA: run the full Business-tier flow end to end — request quotation, reject twice with notes, approve on the 3rd offer, create the event, complete it, raise an invoice, submit a fake UTR, verify it as Super Admin.

---

## Phase 16 — Tenant OAuth2 API Provider

**Goal:** each tenant's Doorkeeper application (auto-created in Phase 2) becomes a real, working credential against the confirmed two-endpoint MVP API surface — this is what the Next.js BFF (Phase 18) will authenticate with, built and tested now via `curl`/request specs since Next.js doesn't exist yet.
**Implements:** §4.9 items 2 & 4, §5.1, §8 (`OAuthAccessGrant`/`OAuthAccessToken`).
**Depends on:** Phase 2 (OAuth app already exists per tenant), Phase 7 (register-participant endpoint), Phase 5 (event-show only returns approved events).

- [ ] Doorkeeper client-credentials grant configured; tenant admin console surfaces its own `client_id`/`client_secret` (Settings screen) — read-only display, no self-service app creation for MVP (§10.12 #17).
- [ ] Access token short TTL (15–60 min) + refresh token with rotation (single-use) — Doorkeeper's built-in support, configured not hand-rolled.
- [ ] **Endpoint 1 — event show (read):** returns event/agenda/speaker/ticket-category data, filtered to `approval_status: approved` server-side (never trust a client-side check).
- [ ] **Endpoint 2 — register participant (write):** creates a `Participant` scoped to the token's Account, reuses Phase 7's dedupe/validation rules, `source: client_api`.
- [ ] `rack-attack` default throttle keyed by application + IP (§4.9 — no per-tenant tiering needed for MVP).
- [ ] Both endpoints enforced through the same `Current.account` guard as every other tenant-scoped path — a token minted for Account A can never touch Account B's data, tested explicitly.

### Definition of Done
- [ ] Request spec: client-credentials grant issues a token; token correctly scoped to its Account on every subsequent call.
- [ ] Request spec: refresh flow rotates the refresh token, old one becomes unusable (replay rejected).
- [ ] Request spec: event-show endpoint 404s/omits a `pending` or `rejected` event even with a valid token.
- [ ] Request spec: register-participant endpoint rejects a request scoped to the wrong Account's event.
- [ ] Cross-tenant leak spec: Account A's token cannot read or write Account B's data under any endpoint.
- [ ] Manual QA: full `curl` walkthrough — obtain token, fetch an approved event, register a participant, confirm it shows up in the Phase 7 admin participant list.

---

## Phase 17 — Cross-Tenant SSO (Agency) & Audit Log / Impersonation

**Goal:** the remaining Platform-level administration surface: agency multi-account SSO (relay token) and Super Admin impersonation-with-audit-trail.
**Implements:** §4.11, §4.7 (impersonation, audit log), §7.4, §8 (`AuditLogEntry`, ephemeral relay-token registry).
**Depends on:** Phase 3 (account switcher stub), Phase 1 (host-only cookie model it must preserve).

- [ ] `AuditLogEntry`: actor, action, target, metadata, timestamp — every Super Admin cross-tenant action (impersonation, approval, quotation decision, account suspend) writes one. Retrofit earlier phases' Super Admin actions to log here if they don't already.
- [ ] Account Switcher (Phase 3 stub) populated from real `AccountMembership` rows for multi-account users.
- [ ] Relay-token SSO: short-lived signed JWT (~30–60s, single-use via Redis `jti` registry) minted on switch, consumed at `{target}/sso/consume`, establishes an ordinary new host-only session — never a shared cookie.
- [ ] Super Admin impersonation: enter a tenant's admin console as a specific user, banner indicating impersonation is active, every action during impersonation logged with the real actor identity in `AuditLogEntry`.

### Definition of Done
- [ ] Request spec: relay token is single-use — a second consumption attempt with the same token fails.
- [ ] Request spec: relay token expires after its TTL; expired token rejected.
- [ ] Request spec: relay-issuance requires an already-authenticated source session (can't bootstrap login from nothing).
- [ ] Request spec: every impersonation action produces an `AuditLogEntry` with the correct real-actor/target pair.
- [ ] Manual QA: a seeded agency user with memberships on two Accounts switches between them via the account switcher with no re-login prompt; confirm no session cookie is shared between the two subdomains (repeat Phase 1's cookie-isolation check).

---

## Phase 18 — Next.js Public Event Site (final phase)

**Goal:** the attendee-facing application — deliberately last, since every backend capability it depends on (approval gating, OAuth API, live counters, registration rules) already exists and is already tested by this point.
**Implements:** §4.3 (public routing), §4.8, §4.9 items 2 & 5 (BFF), §5.15 (public live ticker), §6 item 14.
**Depends on:** Phases 5, 6, 7, 9, 16 (approval gate, ticketing, participant rules, live stats, OAuth API — all must already exist).

- [ ] Domain-resolution middleware: `events.{platform_domain}.com/{tenant_slug}/{event_slug}` (path-resolved) vs. verified custom domain (`Host`-resolved) — both branches converge on the same data-fetching code, calling Rails' `domain_resolution` endpoint with short-TTL caching.
- [ ] BFF pattern: Next.js server (route handlers) is the only thing calling Rails; browser never calls Rails directly. Client-credentials token obtained/refreshed server-side (Phase 16's flow, consumed for real here).
- [ ] Event detail page (SSR/ISR): agenda, speakers, ticket categories — sourced from Phase 16's event-show endpoint, 404s cleanly for unapproved events.
- [ ] Registration form (CSR island): submits to Phase 16's register-participant endpoint, respects Phase 7's custom-field builder output and Phase 6's capacity/waitlist rules.
- [ ] Public live "seats remaining" ticker: subscribes directly to a scoped, read-only `PublicEventLiveChannel` (Action Cable, aggregate counts only — never participant-level data) via `@rails/actioncable`.
- [ ] TenantDomain custom-domain flow made real end-to-end: verification record generation, DNS polling job, Caddy on-demand TLS integration (infra-level, coordinate with deployment work).
- [ ] Basic accessibility pass (WCAG 2.2 AA) on the registration form and event page, since this is the one truly public-facing surface (§6 item 5).

### Definition of Done
- [ ] E2E spec (Playwright, matching `capybara-playwright-driver` already in the Gemfile, or a Next.js-native e2e runner): visit an approved event's public URL on both the shared subdomain and a mock custom domain, confirm both resolve the same content.
- [ ] E2E spec: an unapproved/rejected event's public URL 404s regardless of how it's reached.
- [ ] E2E spec: submitting the registration form creates a real `Participant` visible in the admin console (Phase 7), respects a full ticket category (routes to waitlist, Phase 6).
- [ ] E2E/manual: open the event page in one browser, register from another, watch the "seats remaining" ticker update live with no refresh.
- [ ] Manual QA: full attendee journey — land on the public event page, register, receive confirmation email (Phase 13), and (if a station is paired, Phase 10) observe the badge auto-print.

---

## Cross-cutting checklist (apply throughout, not a separate phase)

- [ ] Every new tenant-scoped table gets the cross-tenant leak spec pattern from Phase 0.
- [ ] Every new Super Admin (`SuperAdmin::`) action that touches tenant data gets an `AuditLogEntry` once Phase 17 exists (retrofit earlier ones then).
- [ ] Every background job that touches tenant data explicitly sets `Current.account` at the top — a job that forgets this is called out in §4.2 as the #1 cause of cross-tenant leaks.
- [ ] Every new admin screen is built by composing Phase 0/3's shared partial library and webadmin template components — check the template first, per §5.14's working process, before writing new markup.
- [ ] Brakeman + Rubocop clean on every merged branch (already in the Gemfile's dev/test group).
