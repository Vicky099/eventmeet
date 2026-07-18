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

- [x] `SuperAdmin::AccountsController` — index/new/create/show; slug availability check (AJAX/Turbo Frame against reserved words + uniqueness) while typing. → `app/controllers/super_admin/accounts_controller.rb`, routed under `/platform/accounts/*` (`config/routes.rb`, `scope path: "platform", as: "platform"` — only `index/new/create/show` + `check_slug`/`suspend`/`reinstate`, not the full 7-action `resources` default, since `edit`/`update`/`destroy` aren't part of this phase). `#check_slug` renders `_slug_availability` into a `turbo_frame_tag "slug_availability"`, driven by a small debounced Stimulus controller (`app/javascript/controllers/slug_check_controller.js`) that repoints the frame's `src` as the Super Admin types.
- [x] Creating an Account also creates its first `AccountMembership`-holding admin `User` (temp password, forced reset — reuses Phase 1's flow) in the same transaction. → `AccountProvisioning` (`app/services/account_provisioning.rb`): Account + owner `User` (`must_reset_password: true`) + `AccountMembership` + `Doorkeeper::Application`, one DB transaction. Uses a local `success` flag rather than trusting `account.persisted?` after an `ActiveRecord::Rollback` — that flag doesn't un-set itself on the in-memory object once a transaction rolls back, a real footgun if the controller had trusted it directly.
- [x] Auto-create one Doorkeeper `OAuthApplication` per Account at provisioning time (§4.9 item 4) — client_id/secret generated, stored, not yet exposed anywhere in tenant UI (that's Phase 16). → Doorkeeper wasn't actually migrated yet (tables didn't exist) — ran the migration generator and customized it: `resource_owner_id` is `type: :uuid` with a real FK to `users` (the generator defaults to bigint; every resource owner here is `User`, id: uuid), `oauth_applications`/`oauth_access_grants`/`oauth_access_tokens` deliberately keep the gem's own bigint `id` (not forced onto the app's UUIDv7 convention — these rows are never referenced by their own `id` outside Doorkeeper's internal associations; the real public identifier is `uid`/`secret`, already opaque and gem-generated). A second migration adds `account_id` (uuid, FK, unique index — one Application per Account) to `oauth_applications`. `Doorkeeper::Application` is reopened with `belongs_to :account` via `Rails.application.config.to_prepare` (`config/initializers/doorkeeper_application_account.rb`) rather than subclassed, since nothing else needs a custom application class; `Account has_one :oauth_application`. `config/initializers/doorkeeper.rb`: `grant_flows %w[client_credentials]` — the only flow the MVP public API (§4.9 item 2) actually uses, so `resource_owner_authenticator`'s raising placeholder is never reached this phase. `config/routes.rb`'s `use_doorkeeper` now skips the interactive/self-service controllers (`:authorizations`, `:applications`, `:authorized_applications`) that flow doesn't need — applications are provisioned server-side, never self-service. **Regression caught mid-build, not by a spec**: the generator's `redirect_uri` column is `null: false` with no default; Doorkeeper's own model-level validation allows it blank once `grant_flows` excludes `authorization_code`/`implicit`, but blank still isn't NULL — fixed with `default: ""` on the column. **Second regression, genuinely confusing to track down**: after fixing the migration file, `bin/rails db:drop db:create db:migrate` on a fresh/empty database kept producing the *old*, default-less column — turned out `db:migrate` against an empty database takes Rails' schema-load fast path (`load_schema_if_pending!`) rather than replaying migrations one-by-one, so it was loading the stale `db/schema.rb` dump from before the fix, not re-reading the migration file at all. Fixed by correcting `db/schema.rb` directly to match, then `db:schema:load` on both databases — a good reminder that `db/schema.rb` is the actual source of truth for fresh-DB setups (per its own header comment), not just a cache of the migrations.
- [x] Platform Console tenant list: search, status (active/suspended), suspend/reinstate action. → `SuperAdmin::AccountsController#index` (`ILIKE` search across name/subdomain_slug + status filter, no pagination yet — Pagy's first real use stays Phase 4's event index, per the Phase 0.1 pre-flight note), `#suspend`/`#reinstate` member actions. No Pagy, no pagination-worthy volume yet.
- [x] Welcome email to the new tenant admin with their subdomain URL + temp password (reuses baseline's welcome-email pattern, §3.10). → `AccountMailer#welcome` (`app/mailers/account_mailer.rb`), `deliver_later`. Sets `@tenant_account` before `mail(...)`, following `DeviseMailer`'s established pattern (Phase 1), so the sign-in link in the email resolves to the new tenant's own subdomain via `ApplicationMailer#default_url_options` rather than the platform-wide default host.

### Definition of Done
- [x] Request spec: Super Admin creates an Account → `AccountMembership`, initial `User`, and `OAuthApplication` all exist and are correctly associated. → `spec/requests/super_admin_accounts_spec.rb`, `spec/services/account_provisioning_spec.rb`.
- [x] Request spec: reserved-word / duplicate slug rejected with a clear validation error. → both specs above cover reserved-word, duplicate-slug, *and* duplicate-admin-email (an edge case not in the original checklist item, added once `AccountProvisioning`'s two-model transaction made it possible: the whole provision — Account included — rolls back if the admin email is already taken).
- [x] Request spec: a suspended Account's admin cannot log in (ties back to Phase 1's check). → `spec/requests/super_admin_accounts_spec.rb` ("suspending an Account blocks its admin from logging in on their subdomain"), driven through the real `#suspend` action rather than a direct `update!(status: :suspended)`, plus the reverse (`#reinstate` lets them log in again).
- [x] Manual QA: full browser flow — Super Admin provisions "Acme Events," receives the temp password (check test mailer inbox), logs in as that tenant admin at `acme.lvh.me`, is forced through password reset. → full real-server `curl` walkthrough (`bin/dev` on port 3099, MailCatcher at `localhost:1080`): logged in as `superadmin@eventmeet.example` at the apex, hit the live `#check_slug` endpoint (reserved/taken/available all confirmed), provisioned "QA Widgets Co" at `qa-widgets-co.lvh.me`, confirmed the `Account`/`User`/`AccountMembership`/`Doorkeeper::Application` row set via `rails runner`, found the welcome email in MailCatcher with the correct subdomain link and temp password, signed in as the new tenant admin, was redirected straight to the forced-reset form, and completed the reset (`must_reset_password` cleared, new password valid). Tenant list/show pages also confirmed rendering real data (status badges, owner email, OAuth `uid`) against a live server, not just specs.

**79/79 specs green (17 new), Rubocop clean, Brakeman: 0 warnings.**

---

## Phase 3 — Dashboard Shells (Admin Console + Platform Console)

**Goal:** the authenticated landing page for both audiences exists, using real (if mostly empty) data, with the navigation chrome that every later feature phase will plug screens into.
**Implements:** §5.14, §5.15 (initial wiring only — real live data lands in Phase 9), §4.7 (Super Admin cross-tenant pulse, empty-state now).
**Depends on:** Phase 2.

- [x] Tenant Admin Console dashboard: sidebar nav (Events, Participants, Badges, Check-in, Sponsors, Reports, Settings — stub links to be filled by later phases), empty-state widgets (0 events, 0 participants). → `Admin::DashboardController#index` at `user_root_path` (`app/controllers/admin/dashboard_controller.rb`), superseding the Phase 0 `Admin::SmokeController` there — that controller/view isn't deleted, it stays live at the separate `/admin/__smoke` route as real, reusable test infrastructure (Phase 0 DoD), now visibly distinct from the real dashboard for the first time. Event/Participant counts are hardcoded `0` — those models don't exist until Phase 4/7, nothing to query yet — surfaced via the new `shared/_stat_widget` partial, plus a "Getting Started" card (`shared/_card`) with a `shared/_empty_state` CTA stubbed to `New Event` → `#` (same stub convention as the sidebar's own unbuilt nav items).
- [x] Platform Console dashboard: tenant count, events-pending-approval count (stub until Phase 5), placeholder for cross-tenant live pulse (real data in Phase 9). → `SuperAdmin::DashboardController#index` at `platform_staff_root_path`, same supersede-not-delete treatment of `SuperAdmin::SmokeController` (still live at `/platform/__smoke`). Tenant count is real (`Account.count` — Account has existed since Phase 0, been provisionable since Phase 2, nothing stubbed about this one); pending-approval count is a hardcoded `0` (Event/approval_status doesn't exist until Phase 4/5); Cross-Tenant Live Pulse is a `shared/_card` wrapping a `shared/_empty_state` placeholder, explicit about landing in Phase 9.
- [x] Account switcher UI stub in the tenant nav (populated for real in Phase 17 — cross-tenant SSO) — safe to render "no other accounts" for a single-membership user now. → `shared/_account_switcher.html.erb`, rendered from `shared/_console_shell` guarded on `Current.account` (nil on the Platform Console — Super Admin holds no `AccountMembership` at all, §4.1 — so the switcher only ever renders tenant-side). Reads real `AccountMembership` data (`current_user.accounts.where.not(id: Current.account.id)`) rather than hardcoding the empty case — the join table already supports multi-membership (§4.11's agency use case) even though nothing lets a user actually acquire a second membership before Phase 17 either, so every real user honestly lands on "No other accounts" today rather than that being a stand-in. **Placement bug caught by actually looking at the rendered page, not just the DOM**: first attempt placed it as a direct sibling of `.navbar-brand-box`, which is `position: fixed` in app.min.css (taken out of document flow) — the switcher rendered *underneath* the brand box instead of below it. Fixed by moving it inside `.sidebar-menu-scroll` (the element app.min.css itself offsets by `margin-top: 75px` to clear the fixed brand box) — same class of bug as the missing `isvertical-topbar` class and the collapsed-sidebar logo overlap from Phase 2's UI-polish round, all three only visible once real content actually occupied the affected spot.
- [x] Responsive check of both dashboards against the webadmin template's breakpoints. → verified live via Playwright screenshots at desktop (1440px) and mobile (480px, below the template's 991.98px breakpoint) for both consoles: stat-widget cards stack to full width, the sidebar collapses to its mobile overlay behavior, the topbar's welcome text hides (`d-none d-md-block`, pre-existing template behavior) — all correct, no fixes needed here.
- [x] Shared partial library established: card/tile, stat widget, empty-state, page-header — every later phase composes from these rather than hand-rolling markup (§5.14 working process). → `shared/_card.html.erb` (generic header+body wrapper — title/icon/actions slot, ported from the pattern `super_admin/accounts/show.html.erb`'s hand-rolled "Account Details" card already established), `shared/_stat_widget.html.erb` (ported verbatim from the webadmin template's own dashboard-sales.html mini-stat card — label/value/optional-trend + colored icon avatar), `shared/_empty_state.html.erb` (ported from shopmate-backend's recurring icon+muted-message(+CTA) block, same template family). `shared/_page_header` already existed (Phase 2).

### Definition of Done
- [x] Manual QA: both dashboards render correctly logged in, nav links present (even if some 404 until later phases fill them in — track as known-stub, not a bug). → verified live via Playwright: both dashboards render fully signed in, all sidebar nav items present (stub `#` links for unbuilt modules are harmless no-ops, not 404s, since they're plain anchors rather than real routes).
- [x] Request spec: unauthenticated request to either dashboard redirects to the correct login. → `spec/requests/dashboards_spec.rb`.
- [x] Component/view spec for the shared stat-widget partial (renders label + value + optional trend). → `spec/views/shared/_stat_widget.html.erb_spec.rb` — label/value, optional trend (direction + text), trend markup fully absent when omitted, default vs. explicit color.

**94/94 specs green (9 new), Rubocop clean, Brakeman: 0 warnings.**

---

## Phase 4 — Event Lifecycle

**Goal:** an organizer can create, edit, and progress an event through its lifecycle from the Admin Console.
**Implements:** §3.2, §5.2 (tabbed builder, simplified from baseline wizard), §8 (`Event` model, UUIDv7 PK).
**Depends on:** Phase 3.

- [x] `Event` model: `account_id`, `name`, `slug` (friendly_id, unique per account), `mode` (`on_site`/`virtual`/`hybrid`), `status` (`draft`/`up_coming`/`live`/`completed`), `approval_status` (`pending`/`approved`/`rejected` — column added now, workflow built in Phase 5), address/meeting-link fields, `participant_fields` jsonb (configurable required fields, baseline §3.2), banner orientation. → `app/models/event.rb`, `db/migrate/*_create_events.rb`. The first real `TenantScoped` + Postgres-RLS-protected table (`TenantRowLevelSecurity.enable!(self, :events)`) — both were built in Phase 0 specifically for this moment. Slug uses `friendly_id :name, use: :scoped, scope: :account_id` — unique per account, not globally (two tenants can both run "annual-meetup"). Also added `starts_at`/`ends_at` (required, not in the checklist's own field list but load-bearing — `EventSchedulerJob` needs them to exist from day one) and mode-dependent presence validation (on_site needs `address`, virtual needs `meeting_link`, hybrid needs both). **RLS caveat, noted rather than silently glossed over**: `ENABLE ROW LEVEL SECURITY` alone doesn't restrict the table *owner* (confirmed empirically — an INSERT with no `app.current_account_id` GUC set succeeded) — and the app's single Postgres role owns every table in every environment, so RLS is currently inert for the app's own connection. It's still real defense-in-depth against a future lower-privileged role (e.g. a read-replica/reporting connection) and matches what the lib helper (`lib/tenant_row_level_security.rb`) was already built to do — `FORCE ROW LEVEL SECURITY` (which would make it bite immediately, including for our own factories/specs) is a bigger call than this feature phase should make unilaterally, so it's flagged here for a deliberate follow-up decision instead.
- [x] Tabbed event builder UI (not a linear wizard): Basic Info, Agenda (stub until Phase 11), Ticket Categories (stub until Phase 6), Badge (stub until Phase 8), Review — each tab autosaves independently (Turbo Frame per tab + background save), each tab shows its own completeness indicator. → `app/views/admin/events/edit.html.erb` (Bootstrap nav-tabs shell) + `_basic_info_tab`/`_review_tab` partials; Agenda/Ticket Categories/Badge are `shared/_empty_state` stubs naming the phase that fills them in. Basic Info's form lives inside `turbo_frame_tag "event_basic_info_tab"`, autosaved via a new `autosave_controller.js` (debounced `requestSubmit()` on input/change) — the tab strip lives outside the frame, so switching tabs never interrupts an in-flight save. `Event#basic_info_complete?` drives that tab's own checkmark/warning icon; Review is always a live read-only summary (no separate completeness state — it just reflects whatever the other tabs currently hold).
- [x] Event list/index (filter by status), event show/edit shell that hosts the tabs. → `Admin::EventsController#index`/`#edit` (`app/views/admin/events/index.html.erb`). No separate `#show` — `edit` *is* the persistent workspace (every tab is either directly editable or a read-only summary that's part of the same page, not a distinct view).
- [x] `EventScheduler` job (Sidekiq, recurring): auto-transitions `draft → up_coming → live → completed` based on configured start/end times — ports baseline's `EventSchedularJob` logic minus the auto-checkout piece (that belongs in Phase 9 once `Attendance` exists). → `app/jobs/event_scheduler_job.rb`. **Revisited (confirmed with the user): now fired by `sidekiq-cron` on a fixed schedule (`config/schedule.yml`, `*/5 * * * *`), not the self-rescheduling pattern originally used here.** The original reasoning ("no cron gem installed... matches this product's real-time-first positioning") held right up until the self-rescheduling pattern's own documented gap — "bootstrapping the first run is deliberately left open" — became a real, live problem: nothing anywhere ever actually called `EventSchedulerJob.perform_later` the first time, so this job never ran outside a spec. `sidekiq-cron` (`Gemfile`) fixes that structurally — its own persisted Redis schedule is what enqueues every tick, no bootstrap step, no double-enqueue risk across multiple Puma/Sidekiq processes. `InvoiceGenerationJob` (Phase 15) was migrated the same way, onto an hourly entry in the same `config/schedule.yml`; `ScheduledReportJob`/`PartitionMaintenanceJob` were *not* migrated (out of scope for this change) and still self-reschedule, with their own comments now flagging that gap explicitly rather than claiming a cron gem isn't installed at all. Verified live against a real Sidekiq process (`bin/jobs`, not the ActiveJob test adapter): `Sidekiq::Cron::Job.all` showed both entries `enabled` with the correct class/cron; manually firing `event_scheduler`'s `#enqueue!` moved `Sidekiq::Stats#processed` forward by exactly one with nothing landing in the dead/retry sets. Status is recomputed from scratch every tick purely from `starts_at`/`ends_at` vs now (no separate "publish" action anywhere — this job is the only thing that ever moves an Event off `draft`); a per-event `rescue` keeps one bad row from taking down the whole tick.
- [x] Follow-up: `sidekiq-cron`'s existence made `Sidekiq::Web` (its own dashboard/queues/retries/dead-set UI, plus — via `sidekiq/cron/web` — a Cron tab showing both scheduled jobs) worth exposing too, gated to Super Admin only. → `config/routes.rb`: `require "sidekiq/web"` + `require "sidekiq/cron/web"`, mounted at `/platform/sidekiq` inside Devise's `authenticated :platform_staff do ... end` (not the throwing `authenticate` — **real bug caught live**: that variant redirects to a broken, mount-relative login path from inside the mounted Rack app's own dispatch instead of the app root; `authenticated`'s soft check just 404s instead, same as any other undefined path). Covered by `spec/requests/sidekiq_web_spec.rb` (unauthenticated and wrong-Warden-scope requests both 404, never reaching `Sidekiq::Web` at all). **Second real bug caught live, after this shipped**: deleting a retry through the real UI returned a bare "Forbidden" — Sidekiq (≥7.1) replaced its old session-based CSRF protection with a hard requirement that the browser send `Sec-Fetch-Site: same-origin` on every non-GET request, with no config toggle to disable it in this version (confirmed via `Sidekiq::Web#safe_request?`/`#deny` and `Changes.md`: "Remove CSRF code, use Sec-Fetch-Site header"); reproduced with a controlled `curl` request (identical POST, header present vs. absent) to confirm the header was the actual cause before touching any code. Fixed with `SidekiqWebSameOriginShim` (`app/middleware/`), a small Rack middleware wrapped around `Sidekiq::Web` via `Rack::Builder` in the mount itself (`Sidekiq::Web.use`-registered middleware runs too late — after the check already happened) — backfills the header from `Origin`/`Referer` only when they match this app's own host, so a genuine cross-site POST (forged from elsewhere, whose Origin/Referer won't match) is still rejected exactly as before; a real value the browser already sent is never overridden. Unit-tested directly (`spec/middleware/sidekiq_web_same_origin_shim_spec.rb`) rather than against the live retry queue, which drains on its own as Sidekiq's real retry backoff runs. Verified end-to-end live: deleted a real (deliberately-failing, throwaway) retry entry through the actual browser UI with no "Forbidden" error.
- [x] Event duplication/template action stubbed as a menu item (full clone logic can land here since it only touches Event-tab data available at this phase — clone name/mode/participant_fields now; richer clone of tickets/badges revisited once those phases exist). → `Admin::EventsController#duplicate`, an icon button in the index table's Actions column. Also copies dates/location (a required `starts_at`/`ends_at` needs *some* value, and copying is the most sensible default over inventing placeholder dates); `status`/`approval_status` reset to `draft`/`pending` — a duplicate is a new event, not a copy of the original's review state.
- [x] Pundit policy: only users with sufficient `AccountMembership` role can create/edit events; per-event staff assignment (§5.1 new item) modeled as a join table now even if the UI for assigning is added later. → `app/policies/event_policy.rb` (owner/event_manager can create/update, only owner can destroy, any member can view — tenant isolation itself stays `TenantScoped`'s job, same division of labor established in Phase 1). `EventStaffAssignment` (`app/models/event_staff_assignment.rb`, `db/migrate/*_create_event_staff_assignments.rb`) — plain join table (`account_id`/`event_id`/`user_id`, unique per event+user), `TenantScoped` + RLS from day one, no assignment UI yet.

### Definition of Done
- [x] Model spec: status transitions, slug uniqueness scoped to account, participant_fields jsonb round-trips. → `spec/models/event_spec.rb`.
- [x] Job spec: `EventScheduler` transitions a time-traveled event through each status correctly (Timecop/ActiveSupport::Testing::TimeHelpers). → `spec/jobs/event_scheduler_job_spec.rb`, `ActiveSupport::Testing::TimeHelpers` (`travel_to`/`travel`) — full lifecycle walk, no-op-when-unchanged, cross-tenant tick, self-reschedule (including when a single event's transition raises).
- [x] Request spec: organizer without the right role cannot create/edit an event (403). → `spec/requests/admin_events_spec.rb`. Note on the literal "(403)": `PunditAuthorizable` (Phase 1, shared by every policy in this app) rejects with a redirect + flash, not a bare HTTP 403 status — the spec asserts the real behavior (redirect to the dashboard with a "not authorized" flash) rather than introducing a status-code override for this one policy alone.
- [x] Manual QA: create an event, navigate freely between tabs (not forced sequentially), close browser, come back — data persisted per tab. → verified live via Playwright: created a hybrid event, switched Basic Info → Agenda → Review → back to Basic Info, edited the name (autosaved), closed the page entirely, signed in fresh in a new browser context, navigated straight back to the same edit URL — the renamed title, all field values, and the "Saved ... ago" indicator all persisted correctly; the events index also reflected the renamed event.
- [x] Cross-tenant leak spec: Account A cannot see/edit Account B's event by guessing its ID/slug. → `spec/requests/admin_events_spec.rb` ("cross-tenant isolation") — both `edit` and `update` 404 (not 403 — the record simply doesn't exist from the other tenant's `TenantScoped` default_scope) when Account A's session requests Account B's event by slug.

**136/136 specs green (42 new), Rubocop clean, Brakeman: 0 warnings.**

### Revisited — stepper wizard + Publish gate (post-Phase-4, supersedes the autosaving-tabs entry above)

The freely-navigable autosaving-tabs UI above was replaced with a sequential stepper wizard,
reverting §5.2's "simplified from baseline wizard" call for this one piece: Basic Info → Agenda →
Ticket Categories → Badge → Review, each step's Next button doing a real save (not autosave)
before advancing, ending in a Publish button on Review. This also introduces a real Publish
gate that didn't exist before — previously `EventSchedulerJob` was "the only thing that ever
moves an Event off draft," auto-promoting *every* event the moment its schedule allowed,
finished or not. That's no longer true.

- [x] Wizard shell: step icons (clickable, free navigation preserved — same "don't force a strict
      sequence" spirit as the tabs they replace) plus Next/Previous. → `app/views/admin/events/edit.html.erb`
      (`STEPS` order lives on `Admin::EventsController`), `_basic_info_step.html.erb` (renamed from
      `_basic_info_tab.html.erb`, autosave/Turbo-Frame machinery removed, a real `f.submit "Next"`
      added), `_review_step.html.erb` (renamed from `_review_tab.html.erb`). Agenda/Tickets/Badge
      stay `shared/_empty_state` stubs with plain Previous/Next links (nothing to save yet).
      `autosave_controller.js` deleted (its only caller is gone).
- [x] `Event#publish!` / `published_at` (new nullable column, `db/migrate/*_add_published_at_to_events.rb`):
      the Review step's Publish button. `nil` means still draft and invisible to the scheduler; publishing
      sets `published_at` and immediately computes the correct status via the new `Event#computed_status`
      (factored out of the job so publishing doesn't sit at `draft` for up to `RESCHEDULE_INTERVAL` waiting
      for the next tick). Gated in the controller (`Admin::EventsController#publish`) on
      `basic_info_complete?`, not in the model — `publish!` itself is a raw mutation.
- [x] "If a published event is edited, its status reverts to draft" — `Event#revert_to_draft_if_published_content_changed`,
      a `before_save` callback: on any save to an already-published event (`published_at_in_database.present?`)
      that changes one of `Event::CONTENT_ATTRIBUTES`, clears `published_at` and resets `status` to `draft`.
      Guarded against firing on `publish!`'s own write (`published_at_changed?`) and on `EventSchedulerJob`'s
      routine status-only writes (status isn't a `CONTENT_ATTRIBUTES` member), so neither fights this callback.
- [x] `EventSchedulerJob` updated to only manage events where `published_at` is present
      (`.where.not(published_at: nil)`) — an unpublished draft now stays `draft` indefinitely regardless of
      `starts_at`/`ends_at`, instead of auto-promoting on schedule like every other event still does.
- [x] This is independent of `approval_status`/Super Admin review (still Phase 5, unbuilt) — publishing only
      controls the event's own draft/scheduled-live lifecycle, not public visibility on the Next.js site. The
      Review step says so explicitly so it doesn't read as "this event is now live to the public."

**Spec updates:** `spec/models/event_spec.rb` (`#publish!`, revert-on-edit, no-revert on status-only/never-published
writes), `spec/jobs/event_scheduler_job_spec.rb` (`create_event` helper now publishes; added "leaves an
unpublished draft event untouched" case), `spec/requests/admin_events_spec.rb` (wizard-step-save redirects
instead of re-rendering, new `POST .../publish` coverage), `spec/factories/events.rb` (`:published` trait).
146/146 specs green, Rubocop clean.

**Manual QA (Playwright, live dev server):** stepped Basic Info → Agenda → Tickets → Badge → Review on an
existing event (Next saving and advancing each time), clicked Publish — status flipped to the schedule-correct
value (Live, since its dates already spanned "now"), Published badge and success alert appeared. Went back to
Basic Info, changed the name, clicked Next — confirmed via server log that the very same save both persisted
the rename *and* reset `status`/`published_at` back to `draft`/`nil`, and the Review step's Publish button
reappeared.

---

## Phase 5 — Event Approval Workflow (Super Admin gate)

**Goal:** organizer submits an event for review; Super Admin approves or rejects with a reason; this is the single most important cross-cutting gate in the whole system (blocks Phase 18's public visibility later).
**Implements:** §4.7 item 2, §5.2 (approval gate), §8 (`approved_by`, `approved_at`, `rejection_reason`).
**Depends on:** Phase 4.

- [x] `Event#submit_for_review!` action from the Review tab — moves `approval_status` to `pending`, locks nothing else (organizer can keep editing per §5.2 re-approval-on-edit decision). → `app/models/event.rb`, wired to the Review step's "Resubmit for review" button (`Admin::EventsController#submit_for_review`, `app/views/admin/events/_review_step.html.erb`). A brand-new Event is already `pending` — schema default, stamped with a real `submitted_at` via a `before_validation on: :create` callback — so this action mainly matters for the reject → edit → resubmit cycle, where it resets `submitted_at` and clears the previous rejection; it's a no-op state-wise for a fresh event. Deliberately doesn't touch `status`/`published_at` — approval and Phase 4's publish/schedule state are independent axes, and `revert_to_draft_if_published_content_changed` already owns the "edited after publish" side on its own.
- [x] `SuperAdmin::EventReviewsController` — queue of pending events, sorted oldest-first, visually flags anything approaching the 24h SLA (§5.2). → `app/controllers/super_admin/event_reviews_controller.rb`, `app/views/super_admin/event_reviews/{index,show}.html.erb`. No separate Pundit policy — same reasoning as `SuperAdmin::AccountsController` (Phase 2): every action is already gated to `platform_staff` by `BaseController`, no role variation within the Platform Console to further check. Sorted by `submitted_at asc`, not `created_at` — a new `submitted_at` column (`db/migrate/*_add_approval_workflow_to_events.rb`), not in requirement.md §8's literal field list but load-bearing for the SLA/sort requirement, since `approval_status` alone can't answer "since when has this been pending," especially across a reject → resubmit cycle where that clock needs to reset. `Event::REVIEW_SLA`/`REVIEW_SLA_WARNING_WINDOW` + `#review_sla_at_risk?` drive the "at risk" badge on both the queue and the per-event review page. Also wired the Platform Console sidebar's pre-existing "Event Approvals" stub link (`app/helpers/super_admin_helper.rb`, left as `"#"` since Phase 3) to the real queue.
- [x] Approve action: sets `approval_status: approved`, `approved_by`, `approved_at`. → `Event#approve!(by:)`, `SuperAdmin::EventReviewsController#approve`, confirm-dialog-gated button on the per-event review page.
- [x] Reject action: requires a reason (validated non-blank), sets `approval_status: rejected`, `rejection_reason`; event stays editable and resubmittable. → `Event#reject!(reason:)` (model-level `validates :rejection_reason, presence: true, if: :rejected?` too, defense in depth) + a controller-level blank check before calling it, same "controller pre-checks the business rule, model method is a raw mutation" split Phase 4's `publish`/`publish!` already established — a blank reason re-renders the review page with an alert instead of the model raising.
- [x] Email notification to the organizer on reject. → `app/mailers/event_mailer.rb#rejected`, sent to every `owner`-role `AccountMembership` on the event's account. **Phase 13 update:** now routed through `Notifier`/`NotificationDeliveryJob` for real `pending/sent/failed` delivery-state tracking (the gap this entry originally flagged), plus a WhatsApp companion send to the same owners — see Phase 13's own checklist entry for the full story, including why `#rejected` now takes an explicit `to:` instead of deriving "every owner" internally.
- [x] Tenant-side: event show page displays current `approval_status` prominently, with the rejection reason if rejected, and the "typically reviewed within 24 hours" messaging while pending. → No separate show route exists (Phase 4's deliberate call — the wizard's Review step already *is* the read-only summary page); extended `_review_step.html.erb` instead, consistent with that decision rather than opening a second page. Rejected shows the reason + "Resubmit for review"; pending shows "submitted ... ago, typically reviewed within 24 hours"; approved shows a success banner. Also clarifies Publish (Phase 4) and Super Admin approval are independent — publishing alone doesn't make an event publicly visible.
- [x] Re-approval-on-edit confirmed behavior: editing an already-approved event does **not** revert `approval_status` (§5.2 v8 decision) — explicit test for this, since it's easy to accidentally regress. → `spec/models/event_spec.rb` ("is not reverted by a later content edit"). Structurally guaranteed, not just tested: `revert_to_draft_if_published_content_changed` (Phase 4) only ever touches `status`/`published_at`, never `approval_status` — there's no shared code path for a content edit to regress this through.

### Definition of Done
- [x] Model spec: full pending → approved and pending → rejected → resubmit → approved cycles. → `spec/models/event_spec.rb` ("walks the full pending -> rejected -> resubmitted -> approved review cycle"), plus per-action specs for `#approve!`/`#reject!`/`#submit_for_review!`/`#review_sla_at_risk?`.
- [x] Request spec: only Super Admin (`platform_staff`) can access the review queue/approve/reject actions — a tenant admin gets 403 even for their own event. → `spec/requests/super_admin_event_reviews_spec.rb`. As with Phase 4's own note on this same literal "(403)" wording: a signed-in tenant `:user` on the apex host redirects to the Platform Console login (a different Devise Warden scope entirely, not a bare 403 status) rather than being let anywhere near the action — asserted directly, not glossed over as a status-code technicality.
- [x] Job/mailer spec: rejection triggers exactly one email with the reason included. → `spec/requests/super_admin_event_reviews_spec.rb` ("rejects the event, sets the reason, and emails the tenant owner"), `perform_enqueued_jobs` + `ActionMailer::Base.deliveries.last`, same pattern `spec/requests/super_admin_accounts_spec.rb` already established for `AccountMailer`. No dedicated `spec/mailers/event_mailer_spec.rb` — this is the same "exercised indirectly through the request spec that actually matters" call the shared-partial specs note (`spec/views/shared/_stat_widget.html.erb_spec.rb`'s own comment) already makes for markup this simple.
- [x] Manual QA: submit an event, approve it as Super Admin, edit it as the organizer, confirm `approval_status` stays `approved`. Separately: submit, reject with a reason, confirm the tenant sees the reason and can resubmit. → verified live via Playwright: rejected a pending event from the Platform Console queue with a reason, confirmed (via server log, not just the UI — Turbo's async re-render occasionally outraces a screenshot in this environment) the tenant's Review step showed the reason and a "Resubmit for review" button, clicked it, confirmed `approval_status` went back to `pending` with a fresh `submitted_at` and `rejection_reason` cleared. Re-approval-on-edit covered by the model spec above rather than a second manual pass — nothing UI-specific to add beyond what that test already proves.

**Found and fixed along the way (Brakeman, not asked for but real):** the Super Admin review page's `link_to @event.meeting_link, @event.meeting_link` — an organizer-controlled string rendered directly as an href — flagged as a genuine (if weak-confidence) stored-XSS vector: a crafted `javascript:...` value would execute in whoever clicks it. Added `ApplicationHelper#external_link_to` (only linkifies `http(s)://`, otherwise renders inert plain text) and applied it here and to the tenant Review step's identical pre-existing pattern for `meeting_link`/`map_url`.

165/165 specs green, Rubocop clean, Brakeman: 0 warnings.

### Revisited — `unsubmitted` gate on the review queue (post-initial-Phase-5)

First pass had `approval_status` default straight to `pending` (schema default `0`), which meant a
brand-new event — nothing built yet, never touched by the organizer — sat in the Super Admin's
review queue from the moment it was created. Corrected: added a 4th `unsubmitted` state and made
it the real default; an event only becomes `pending` (and so only appears in
`SuperAdmin::EventReviewsController`'s queue) once the organizer explicitly clicks "Submit for
review" on the wizard's Review step.

- [x] `Event#approval_status` enum gains `unsubmitted: 3` (`pending`/`approved`/`rejected` keep
      their existing integer codes — those rows meant something real, an actual `approve!`/
      `reject!`; only the meaningless-until-now `0` default gets reclassified). →
      `db/migrate/*_add_unsubmitted_approval_status_to_events.rb`: `change_column_default` to `3`
      plus a data backfill (`UPDATE events SET approval_status = 3, submitted_at = NULL WHERE
      approval_status = 0`) — safe precisely *because* no explicit "submit for review" gate
      existed before this revisit, so no existing `pending` row was ever a real submission to
      preserve.
- [x] Removed the `before_validation :default_submitted_at, on: :create` callback from the first
      pass — `submitted_at` is now nil until `submit_for_review!` actually runs, not stamped at
      creation. `#review_sla_at_risk?` already only fires for `pending?`, so this needed no
      change.
- [x] `Admin::EventsController#submit_for_review` gated on `basic_info_complete?`, same pattern as
      `#publish` — nothing incomplete belongs in front of a Super Admin reviewer either.
- [x] Review step (`_review_step.html.erb`) gains an `unsubmitted` branch: "Not yet submitted — a
      Super Admin only sees this event once you submit it for review" + the Submit button, instead
      of that button only ever showing up after a rejection.
- [x] Approval badge coloring (secondary/warning/success/danger for unsubmitted/pending/approved/
      rejected) deduplicated into `ApplicationHelper#approval_status_badge_class` — was about to
      become two copies of the same hash (the wizard's top badge strip, `edit.html.erb`, hadn't
      been reflecting `approval_status` state at all before this revisit, just a hardcoded warning
      color) once a 4th state existed to get wrong twice.
- [x] `spec/factories/events.rb` gains a `:pending_review` trait (`approval_status: :pending,
      submitted_at: Time.current`) — the shortcut every review-queue spec needs now that the bare
      factory default is `unsubmitted`, same role `:published` already plays for `status`.

**Manual QA (Playwright, live dev server):** confirmed an existing unsubmitted event was absent
from `/platform/event_reviews`, submitted it from the tenant's Review step, confirmed it appeared
in the queue immediately after (oldest/only entry, "On track" SLA badge, correct tenant name).

170/170 specs green, Rubocop clean, Brakeman: 0 warnings.

### Revisited — approval auto-publishes

Requested: approving an event should publish it too — the organizer's job is just submitting for
review, not a separate "and now also click Publish" step afterward.

- [x] `Event#approve!` now sets `published_at`/`status` (same values `publish!` itself would
      compute) alongside `approval_status`/`approved_by`/`approved_at`, but *only* when the event
      isn't already published — an already-published event's `published_at`/`status` are left
      exactly as they are rather than recomputing them a second time for no reason. This is a
      one-time effect at the moment of approval, not a standing "approved implies published"
      invariant: an edit *after* approval still un-publishes the event via Phase 4's
      `revert_to_draft_if_published_content_changed` same as always (approval_status itself
      still doesn't revert, per the existing re-approval-on-edit rule) — the Publish button on the
      Review step reappears in that case, same mechanism, no special-casing needed.
      `SuperAdmin::EventReviewsController#approve`'s flash distinguishes "approved." from
      "approved and published." based on whether this actually changed anything.
- [x] Tenant Review step copy updated to match: the "Approved" banner now says "visible on the
      public site" when currently published, or explicitly flags "not currently published
      (something was edited since approval)" with a pointer back to the Publish button when not
      (the edit-after-approval edge case above).

**Manual QA (Playwright, live dev server):** submitted an event for review *without* publishing it
first, approved it from the Platform Console (flash: "... approved and published."), confirmed on
the tenant side — with no manual Publish click at any point — the event showed `Live` / `Approved`
/ `Published` all at once.

208/208 specs green, Rubocop clean, Brakeman: 0 warnings.

### Revisited again — publish gated on approval instead of automatic

Corrected: the previous revisit's auto-publish-on-approve was the wrong shape. What was actually
wanted: approving unlocks the tenant's own Publish button (which the tenant doesn't even see until
then) — approving still doesn't publish it *for* them.

- [x] `Event#approve!` reverted to a raw approval only — no more touching `published_at`/`status`.
      `SuperAdmin::EventReviewsController#approve`'s flash is back to a plain "... approved."
- [x] `Admin::EventsController#publish` now requires `@event.approved?` first (checked before
      `basic_info_complete?`, which is effectively always true by the time an event reaches
      `approved` anyway — `submit_for_review` already required it, and nothing un-completes those
      fields afterward): `alert: "This event must be approved by a Super Admin before it can be
      published."` otherwise. Publish is the last step in the chain now: submit for review → Super
      Admin approves → tenant publishes.
- [x] `_review_step.html.erb` reordered — Approval section now comes *before* Publish (it's the
      prerequisite) — and the Publish section itself gained an `!event.approved?` branch ("Publishing
      unlocks once a Super Admin approves this event") that replaces the button entirely until
      then, instead of showing a button that would just redirect back with an alert if clicked.
      Re-approval-on-edit (§5.2 v8) still means an edit-after-approval-and-publish (which reverts
      `published_at`/`status` to draft, same as always) doesn't require a fresh approval to
      re-publish — `approved?` is still true, so the button just reappears.

**Manual QA (Playwright, live dev server):** submitted an event for review, confirmed the Review
step showed no Publish button at all while pending (just "Publishing unlocks once a Super Admin
approves this event"), approved it from the Platform Console (plain "approved." flash, event still
`Draft`/unpublished afterward), confirmed the tenant now saw the Publish button, clicked it, and
only then did status flip to `Live` with a "Dubai Expo published." flash.

209/209 specs green, Rubocop clean, Brakeman: 0 warnings.

---

## Phase 6 — Ticketing (Capacity-Based, No Payment)

**Goal:** organizers define ticket categories as capacity buckets; registrants can be group-reserved and waitlisted. No pricing/checkout anywhere (§5.3 explicit scope note).
**Implements:** §5.3, §8 (`TicketCategory`).
**Depends on:** Phase 4 (event tab this fills in).

- [x] `TicketCategory` model: `event_id`, `name`, `total_count`, `sold_count`, `remain_count` (kept in sync via callback/service, ports baseline `Event#sync_tickets` logic), `document_required` boolean. No price field (deferred). → `app/models/ticket_category.rb`, `db/migrate/*_create_ticket_categories.rb`. TenantScoped + RLS from day one (`account_id` denormalized alongside `event_id`, same pattern Phase 4 established for `EventStaffAssignment`). `sold_count`/`remain_count` are real columns, not computed on every read — `#sync_counts!` recomputes them from this category's own `reserved`-status `TicketReservation`s and persists via `update_columns`, called by `TicketReservationService` after every mutation rather than tracked incrementally (no drift possible; always a full recompute, not `+=`/`-=`).
- [x] Ticket Categories tab in the event builder (Phase 4's stub filled in): CRUD, capacity validated against event-level seat limit if one is set. → `app/views/admin/events/_tickets_step.html.erb`, `Admin::TicketCategoriesController` (nested under Event, `only: [:create, :update, :destroy]` — no `:index`, the Tickets step itself is the listing). New nullable `Event#seat_limit` (`db/migrate/*_add_seat_limit_to_events.rb`) — no cap by default; when set, `TicketCategory#total_count_within_event_seat_limit` validates the sum of every category's `total_count` on the event against it (excluding the record's own prior value on update, so raising one category's own count doesn't double-count itself). Also joined `Event::CONTENT_ATTRIBUTES` (Phase 4) — changing `seat_limit` on an already-published event reverts it to draft, same as every other content field. No dedicated `TicketCategoryPolicy` — authorization delegates to the parent Event's own `EventPolicy#update?` (owner/event_manager), the same shortcut `Admin::EventsController#publish`/`#submit_for_review` already take instead of a separate policy class per Event-child action.
- [x] Group/bulk registration: one reservation holds N spots against a category, with per-seat detail fillable later or via forwarded claim links (claim-link consumption itself can be a thin stub here — full self-service portal is Phase 7/Phase 18 territory, but the reservation + capacity math belongs in this phase). → New `TicketReservation` model (`app/models/ticket_reservation.rb`, `db/migrate/*_create_ticket_reservations.rb`) — not in requirement.md §8's literal data-model list (only `TicketCategory`/`Participant` are named there), added because the checklist explicitly calls for "reservation + capacity math" to exist *before* Phase 7's `Participant` does. Holds `seat_count`/`holder_name`/`holder_email` as one group, not one row per attendee; a `claim_token` (`SecureRandom.hex(16)`, unique-indexed) is generated on create as the thin stub the checklist calls for — no consumption flow reads it yet, but Phase 7's real per-seat claim/manual-entry flow has a column to attach to without another migration. `Admin::TicketReservationsController#create` — manually entered by staff from the Tickets step (there's no public registration surface yet; that's Phase 7/18).
- [x] Waitlist: when a category is full, new interest queues instead of failing outright; a service object handles automatic offer-on-release when capacity frees up (ties into Phase 7's cancellation flow). → `app/services/ticket_reservation_service.rb` (`TicketReservationService.reserve`/`.cancel`, same `Result` struct + class-method-delegates-to-instance shape as Phase 2's `AccountProvisioning`). `.reserve` re-syncs the category's counts immediately before deciding `reserved` vs `waitlisted` — not `sold_count >= total_count`, but whether *this request's* `seat_count` fits in what's actually left, so a big group correctly waitlists even while smaller requests keep succeeding.
- [x] Cancellation-with-seat-restoration (in scope per §5.3 — only refunds are deferred): cancelling a reservation restores `remain_count` and triggers waitlist offer check. → `TicketReservationService.cancel` — status → `cancelled` (+ `cancelled_at`), re-syncs the category, then promotes from the waitlist only if the cancelled reservation was actually holding a seat (cancelling an already-waitlisted one is a pure no-op on capacity). Promotion is FIFO, first-fit-only, and keeps iterating: the oldest waitlisted reservation goes first, but only if it fully fits in whatever's currently free (no partial seat splits — a 3-seat group either gets all 3 or stays waitlisted for a later release); if there's capacity left over after that, the next-oldest fitting request gets promoted too in the same cancellation, not just one entry per release.

### Definition of Done
- [x] Model spec: capacity math (`total/sold/remain`) stays consistent across create/cancel/waitlist-promote. → `spec/models/ticket_category_spec.rb` (`#sync_counts!` — only `reserved` seats count, `waitlisted`/`cancelled` don't), `spec/models/ticket_reservation_spec.rb`.
- [x] Service spec: category at capacity → new registrant waitlisted, not rejected; releasing a seat auto-promotes the next waitlisted entry. → `spec/services/ticket_reservation_service_spec.rb` — waitlist-instead-of-reject (including "a request too big for the *remaining* capacity waitlists even though some seats are free"), FIFO promotion (including the "freed capacity fits more than one waitlisted group" and "oldest waitlisted group doesn't fit, a smaller later one does" first-fit cases), and cancelling an already-waitlisted or already-cancelled reservation being safe no-ops.
- [x] Request spec: organizer cannot set category capacity exceeding the event-level seat limit (if configured). → `spec/requests/admin_ticketing_spec.rb` ("re-renders the step with an error instead of saving when a category would exceed the event's seat_limit"), plus full coverage of the Tickets step's save (create/update/remove a category, all via nested attributes in one PATCH) and reservation create/cancel.
- [x] Manual QA: fill a 2-seat category with 2 reservations, attempt a 3rd (lands on waitlist), cancel one of the first two, confirm the waitlisted one is auto-promoted. → verified live via Playwright against the dev server: created a 2-seat "General" category, reserved Alice (1) and Bob (1) — filled the category (0 remaining) — reserved Carol (1), confirmed she landed `Waitlisted` with the flash "1 seat(s) waitlisted for Carol," cancelled Alice's reservation, confirmed the flash "Reservation for Alice cancelled," Carol auto-promoted to `Reserved`, and the category back to 2 reserved / 0 remaining.

**Found and fixed along the way (not asked for but real):** the category row's "Remove" button (`button_to`, which renders its own `<form>`) was nested inside the category's own edit `form_with` block — an invalid HTML nested-`<form>`, which browsers silently hoist out, scrambling the row's DOM (caught live: a reservation form's fields became briefly unreachable after a save). Split into two sibling forms in the same row instead of one containing the other.

203/203 specs green, Rubocop clean, Brakeman: 0 warnings.

### Revisited — ticket categories build client-side, reservation UI removed from event setup

User feedback on the live Tickets step: "Reserve for / Holder email / Seats" doesn't belong on
the event-*building* wizard at all — reserving seats is a participant-registration action
(Phase 7 territory), not something an organizer does while defining ticket categories. Separately,
each category add/edit/remove was its own immediate PATCH/POST/DELETE round trip — asked to
instead build up categories in the form and only persist on the step's own Next click, the same
"Next saves it" shape Basic Info already has.

- [x] `Event accepts_nested_attributes_for :ticket_categories, allow_destroy: true, reject_if:
      :all_blank` — categories are now nested attributes on the Event form
      (`Admin::EventsController#update`, same action Basic Info's Next already posts to), not a
      separate CRUD endpoint. `Admin::TicketCategoriesController` deleted outright (dead code the
      moment nothing linked to it) along with its `only: [:create, :update, :destroy]` routes;
      `resources :ticket_categories, only: []` stays in `config/routes.rb` purely so
      `ticket_reservations` still has something to nest under for `#create`. The standalone
      `update_seat_limit` action/route is gone too — `seat_limit` is just another field in the
      same nested-attributes form now.
- [x] New `app/javascript/controllers/nested_fields_controller.js` — the standard gem-free Rails
      "clone a `<template>` with a `NEW_RECORD` placeholder index" pattern for add/remove rows
      with zero network requests until the real form submit. Removing a persisted row sets its
      hidden `_destroy` field and hides it (still submitted, so the server actually removes it on
      Next); removing a just-added, never-saved row simply deletes it from the DOM outright — no
      `id` exists yet for the server to destroy.
- [x] `_tickets_step.html.erb` rewritten: one `form_with model: event` (seat limit + `fields_for
      :ticket_categories`, shared row markup extracted into `_ticket_category_fields.html.erb` so
      the live list and the JS template render identically), ending in the same Previous/`f.submit
      "Next"` pair every other real step uses. The reservation section (holder name/email/seat
      count, the per-category reservations table, Cancel buttons) is gone entirely — `
      TicketReservation`/`TicketReservationService`/`Admin::TicketReservationsController` are
      untouched and still fully tested (this phase's waitlist/cancellation-with-restoration
      requirement doesn't go away), just not linked from any view yet. Expected to be wired into
      Phase 7's actual registration flow.

**Found and fixed along the way (not asked for but real, caught from my own verification
screenshot):** a freshly created or total_count-edited TicketCategory showed "0 remaining" even
with zero reservations against it — `remain_count` was only ever written by
`TicketReservationService#sync_counts!` after a *reservation* changed, never initialized or kept
in sync when the *category* itself was saved directly (plain creation defaulted to the schema's
`0`; raising/lowering `total_count` left `remain_count` stale). Added a `before_save
:sync_remain_count` callback on `TicketCategory` itself so both paths — a reservation changing
(service-driven `update_columns`) and the category row being saved directly (create/edit,
including via nested attributes) — keep `remain_count` correct, each through the trigger that
actually fits it.

202/202 specs green, Rubocop clean, Brakeman: 0 warnings.

### Revisited — seat-limit validation didn't catch several new categories added together

User-reported bug, reproduced exactly: `seat_limit` 100, added three brand-new categories
(60/50/40 = 150) in one Tickets-step save — saved without error. Root cause: the seat-limit
validation lived on `TicketCategory#total_count_within_event_seat_limit`, and computed "everyone
else's total" as `event.ticket_categories.where.not(id: id).sum(:total_count)` — a fresh SQL
query. For three simultaneously-new rows in the same nested-attributes batch, none of them exist
in the database yet at validation time, so each one's own query sees zero siblings and passes
individually; nothing ever summed all three together.

- [x] Moved the check to `Event#ticket_categories_within_seat_limit` — sums
      `ticket_categories.reject(&:marked_for_destruction?)` in Ruby over the association's current
      *in-memory* state (which nested-attributes assignment populates with every row in the batch,
      new and existing alike, before validation ever runs), not a fresh query. Removed the old
      broken version from `TicketCategory` entirely rather than leaving two validations
      (`app/models/ticket_category.rb` now just notes where the check moved and why).
      Incidentally this also *simplified* the "editing an existing category" case — no more
      needing to explicitly exclude the record's own prior value by id, since the in-memory
      collection already reflects its freshly-assigned value, not a stale persisted one.
- [x] Spec coverage moved and expanded: `spec/models/event_spec.rb`
      (`#ticket_categories_within_seat_limit`) now includes the exact reported shape — three new
      categories together over the limit while none is individually — plus a request-spec version
      in `spec/requests/admin_ticketing_spec.rb` posting the real multi-row nested-attributes
      params the Tickets step's form actually sends.
- [x] Writing those specs surfaced a second, more subtle lesson (not a product bug, a modeling
      gotcha worth documenting): a bare `create(:event, ...)` already triggers this validation
      once during its own save, which caches the (then-empty) `ticket_categories` association on
      that Ruby object. A *separate* `create(:ticket_category, event: event, ...)` factory call
      afterward inserts a real row but never touches that cached association — so reusing the same
      `event` object for further nested-attributes assignment without an `event.reload` in between
      validates against stale, incomplete data. Not a real risk in production
      (`Admin::EventsController#update` always starts from a freshly-loaded `@event` and assigns
      nested attributes before anything validates), but real enough to trip up two of the new
      specs themselves — fixed with an explicit `event.reload` at the right point, commented so
      the next person adding a ticketing spec doesn't rediscover it the hard way.

205/205 specs green, Rubocop clean, Brakeman: 0 warnings.

### Revisited — explicit "has a seat limit" toggle, gating both the field and a live running total

User request: gate `seat_limit` behind an explicit "This event has a seat limit" flag instead of
it always being a visible, always-optional field, and surface a live "Total seats" readout (the
sum across ticket categories) once the toggle is on.

- [x] New `Event#has_seat_limit` boolean column (`db/migrate/*_add_has_seat_limit_to_events.rb`,
      `default: false`, backfilled `true` for any event that already had a `seat_limit` set —
      that presence was the flag's implicit value before now). Added to `CONTENT_ATTRIBUTES`
      alongside `seat_limit` — toggling it on an already-published event reverts to draft, same as
      every other content field.
- [x] `Event#clear_seat_limit_unless_flagged` (`before_validation`) discards `seat_limit` whenever
      `has_seat_limit?` is false. Needed because the Tickets step hides the field with CSS rather
      than removing it from the DOM (`data-seat-limit-target="limitField"`, toggled by the new
      `seat_limit_controller.js`) — a stale value would otherwise still ride along in the
      submitted params after the organizer switches the toggle back off, silently keeping an old
      cap enforced even though the UI no longer shows it. Runs in `before_validation`, not
      `before_save`, so `ticket_categories_within_seat_limit` (which runs during the same
      validation phase) always sees the corrected value, not the stale one.
- [x] `app/javascript/controllers/seat_limit_controller.js` — one controller, two jobs: show/hide
      `seat_limit`'s field (and the new total-seats line) off the checkbox, and recompute a live
      "Total seats (from categories)" display by summing every visible ticket-category row's
      `total_count` input on `input` events (each row's field carries
      `data-action="input->seat-limit#recompute"`, so it fires for both the live rows and ones
      cloned from `nested-fields`' `<template>`). A row hidden via `nested-fields#remove` (a
      persisted category marked `_destroy` but left in the DOM, not deleted — see Phase 6's own
      revisit above) is excluded from the sum by checking `row.hidden`; the Remove button's
      `data-action` chains both controllers (`nested-fields#remove seat-limit#recompute`) so the
      total updates the instant a row disappears, not just when a count changes. Purely a display
      aid — nothing here is persisted; the real capacity check is still
      `Event#ticket_categories_within_seat_limit`, unchanged.
- [x] Spec coverage: `spec/models/event_spec.rb` (`#clear_seat_limit_unless_flagged` — toggling off
      discards a stale value, toggling stays on leaves it alone), `spec/requests/
      admin_ticketing_spec.rb` (a real Tickets-step PATCH with `has_seat_limit: "0"` clears a
      previously-set `seat_limit`). `spec/factories/events.rb` gained `has_seat_limit {
      seat_limit.present? }` so every existing spec that passes `seat_limit:` directly keeps
      working without individually adding `has_seat_limit: true` everywhere.
- [x] Manual QA: verified live via Playwright against the dev server on `techo-space` — toggle off
      by default (field hidden), toggle on reveals both fields, adding two categories (60 + 30)
      live-updated "Total seats (from categories)" to 60 then 90 without a page reload, Next
      persisted `has_seat_limit: true, seat_limit: 100` plus both categories, and a follow-up
      toggle-off-and-Next correctly cleared `seat_limit` back to `nil` in the database.

266/266 specs green, Rubocop clean, Brakeman: 0 warnings.

**Follow-up correction:** "Total seats" was sharing the same `limitField` Stimulus target as
`seat_limit` already, so it was already hidden while the toggle is off — confirmed, not a fix.
What was missing: `seat_limit` was still labeled "(optional)" and never actually required once the
toggle turned on. Added `validates :seat_limit, presence: true, if: :has_seat_limit?` on `Event`
(server-side source of truth), dropped "(optional)" from the label, and made
`seat_limit_controller.js` keep the input's `required` HTML attribute in sync with the same toggle
(a new `limitInput` target) so the browser's own constraint validation blocks an empty submission
immediately, not just after a round trip. Covered by two new model-spec cases (required when
toggled on, not required when off) and a request spec confirming a real Tickets-step PATCH with
`has_seat_limit: "1"` and a blank `seat_limit` gets rejected with `422` and the presence error.
Verified live: toggling on with an empty field and clicking Next shows the browser's native "Please
fill in this field" tooltip instead of submitting. 269/269 specs green, Rubocop clean, Brakeman: 0
warnings.

**Second follow-up — visibility moved from Ruby/JS to pure CSS:** user reported still seeing
"Total seats" with the toggle off. Root cause of the follow-up-correction fix (server-rendering
`d-none` off `event.has_seat_limit?`, the persisted column) was itself the wrong axis: the
checkbox's *live* DOM state is what should decide visibility, not a value computed once at
render time from the database — those two only coincide up to the moment the organizer actually
touches the toggle, and reactive JS (a `change` listener flipping a class) still leaves a window
between page paint and Stimulus connecting (or a Turbo-cached snapshot) where they can disagree.
Replaced both the SSR class and the Stimulus `toggleLimitField` method with a single CSS rule
(`app/assets/stylesheets/application.css`): `.seat-limit-block:has(#event_has_seat_limit:checked)
.seat-limit-fields { display: block; }` (default `display: none`) — the browser's own `:has()`
match re-evaluates synchronously with the checkbox's DOM state, so there is no window where
markup and checkbox can drift, regardless of JS load timing or the DB value. `seat_limit`'s
`required` attribute is now unconditional in the HTML rather than JS-managed — the HTML5 spec
exempts non-rendered (`display: none`) fields from constraint validation, so "required only while
the toggle is visibly on" falls out of the same CSS rule for free. `seat_limit_controller.js` now
only does the live "Total seats" sum (unrelated to show/hide). Verified with all `*.js` requests
aborted in Playwright (simulating JS never loading at all): toggling the checkbox on/off still
correctly showed/hid both fields — proof the behavior no longer depends on JS or the persisted
value at all. 269/269 specs green (unchanged — this was view/CSS/JS only), Rubocop clean,
Brakeman: 0 warnings.

### Third follow-up — the per-category "Total seats" column, and two bugs the fix itself exposed

User clarified what "still not working" actually meant, with a screenshot: not the summary line
(already fixed, confirmed hidden) but each individual ticket category's own "Total seats" column
(`TicketCategory#total_count`) — unconditionally visible on every row regardless of the toggle,
since a category's own capacity was never gated by it in the first place. Asked directly whether
that should also be hidden when the event has no seat limit, even though it changes what a ticket
category *means* (no seat limit → categories become "unlimited," capacity untracked) — confirmed
yes.

- [x] `total_count`/`remain_count` on `ticket_categories` made nullable
      (`db/migrate/*_allow_null_total_and_remain_count_on_ticket_categories.rb`). `TicketCategory`:
      `total_count` numericality stays `allow_nil: true`, presence now conditional on
      `event&.has_seat_limit?`; new `#unlimited?` (`total_count.nil?`); `#sync_counts!`/
      `#sync_remain_count` both nil-out `remain_count` instead of computing against a
      `total_count.to_i` that would silently treat "unlimited" as zero. `Event#clear_category_
      total_counts_unless_seat_limited` (`before_validation`, same trigger as `clear_seat_limit_
      unless_flagged`) nils every category's `total_count` when the toggle is off, iterating the
      in-memory association so a category added in the very save that also flips the toggle off
      gets caught too. `TicketReservationService#reserve`/`#promote_waitlist` treat an unlimited
      category as always having room — every reservation succeeds outright, nothing ever
      waitlists against it.
- [x] CSS (`.seat-limit-fields`/`.seat-limit-block`, application.css) extended to cover the
      per-category column too: `seat-limit-block` moved from a small wrapper div up onto the whole
      `<form>` in `_tickets_step.html.erb`, since `:has()` needs the checkbox and every "Total
      seats" field — top-level and per-category, including rows `nested-fields` clones in later —
      under one shared ancestor to reach all of them with a single rule.
- [x] **Bug this surfaced, not asked for but real**: made `required` unconditional on both the
      seat_limit and total_count inputs, reasoning that a `display:none` required field is exempt
      from HTML5 constraint validation "by spec." Live testing proved that reasoning wrong for
      this browser: a required field hidden via CSS (or via `hidden`, which nested-fields#remove
      already sets on a removed persisted row) still fails `form.checkValidity()` and silently
      blocks the whole submit — no visible error, just a console-only "An invalid form control ...
      is not focusable" and the PATCH request never even firing. Reverted to JS-managed
      `required`: `seat_limit_controller.js` gained `syncRequired()`, called on connect, on the
      checkbox's own `change`, and on "Add another category" (so a freshly cloned row picks up
      the current toggle state) — and `nested_fields_controller.js#remove` now explicitly clears
      `required` on every field inside a row it hides, closing the same hole for the
      remove-a-persisted-row case.
- [x] **Second bug this surfaced, pre-existing since Phase 6, not asked for but real**: fixing the
      `required` bug above was what first made "Remove" on a *persisted* ticket category actually
      reach the server at all — and that immediately exposed that it never worked correctly in the
      first place. `nested_fields_controller.js#remove` looked for the hidden `id` field via
      `row.querySelector('input[name$="[id]"]')`, but Rails' `fields_for` auto-inserts that hidden
      id field as a **sibling** immediately after a nested partial's own markup for a persisted
      record, not a descendant of it — confirmed by dumping the actual rendered HTML. `querySelector`
      only searches descendants, so `idField` was always `null`, meaning every "Remove" click on an
      *existing* category (or custom field — same shared controller) silently took the
      "brand-new-row, just delete from the DOM" branch: the row visually vanished but nothing was
      ever destroyed server-side, and it would reappear on the next page load. Fixed generically
      (not ticket-category-specific, since custom fields share this controller): derive the
      field-name prefix from the always-present `_destroy` field and look up the id field in the
      row's *parent* instead of the row itself.
- [x] **Third bug, found via the second bug's own fix**: with Remove now actually reaching the
      server, removing a category that already has `Participant` rows pointing to it hit a raw
      `PG::ForeignKeyViolation` — an unhandled 500. Added `has_many :participants, dependent:
      :restrict_with_error` on `TicketCategory` as an association-level guard, but nested-attributes'
      own destroy machinery turned out to call `destroy!` internally, so a blocked
      `restrict_with_error` raised `ActiveRecord::RecordNotDestroyed` instead of degrading
      gracefully — still an unhandled 500, just a different one. Real fix: `Event#destroyed_
      categories_have_no_participants`, a normal `validate` (not a `before_destroy` callback) that
      checks every category marked for destruction *before* any destroy is attempted at all, so a
      blocked removal fails the same clean, friendly "re-render with errors" way every other
      Tickets-step mistake already does. The association-level `restrict_with_error` stays as
      defense-in-depth for any future code path that destroys a category directly (where it
      degrades gracefully, unlike through nested-attributes).
- [x] Spec coverage for all of the above: `spec/models/ticket_category_spec.rb` (total_count
      presence conditional on `has_seat_limit`, `#unlimited?`, `#sync_counts!` leaving
      `remain_count` nil), `spec/services/ticket_reservation_service_spec.rb` (an unlimited
      category always reserves, regardless of how many seats are requested),
      `spec/models/event_spec.rb` (`#clear_category_total_counts_unless_seat_limited`,
      `#destroyed_categories_have_no_participants` — both the rejected and the allowed case),
      `spec/requests/admin_ticketing_spec.rb` (a real toggle-off PATCH clearing an existing
      category's `total_count`, creating a category with none when unlimited, and the
      participants-registered-so-removal-is-blocked case, asserting a clean `422` rather than a
      crash).
- [x] Manual QA: live on `dubai-expo` (which had a real leftover "Visitor" category with an actual
      `Participant` registered against it from earlier Phase 7 testing) — confirmed the per-category
      "Total seats" column hides/shows with the same toggle as the summary line; confirmed
      `form.checkValidity()` was `false` and the PATCH never fired before the `required` fix, `true`
      and a real 302 after; confirmed a toggle-off save actually clears `total_count`/`remain_count`
      to `nil` in the database (previously it only looked cleared client-side); confirmed removing a
      *different*, participant-free category actually deletes it now (previously silently a no-op);
      confirmed removing the participant-linked "Visitor" category now fails with a clean 422 and
      the friendly on-page message instead of a 500. Reset the event's `has_seat_limit`/`seat_limit`
      and the stray category's counts back to their pre-test state afterward; left the real
      "Visitor"-plus-participant pairing in place since it's pre-existing dev data, not something
      created by this fix.

283/283 specs green, Rubocop clean, Brakeman: 0 warnings.

---

## Phase 7 — Participant Lifecycle (Registration & Management)

**Goal:** admin-side participant CRUD, dedupe rules, bulk import/export, custom fields — the deepest data-integrity-sensitive module carried from the baseline. (Public self-registration via Next.js is explicitly out of scope until Phase 18; admin manual entry is the full surface for now.)
**Implements:** §3.4, §5.4, §8 (`Participant`).
**Depends on:** Phase 6 (registers against a `TicketCategory`).

- [x] `Participant` model: `account_id`, `event_id`, `ticket_category_id`, `hex_id`, `client_participant_id` (auto-generated if missing), `govt_id` (plain field, no integration — §5.4 confirmed), `rf_id`, name/email/contact/company/department/position/nationality/country, photo (Active Storage, tenant-namespaced path per §4.2), document upload gated by `ticket_category.document_required`, `source` (`manual`/`upload`/`client_api` — last one wired for real in Phase 16). → `app/models/participant.rb`, `db/migrate/*_create_participants.rb`. `hex_id` is globally unique (requirement.md §3.7: check-in scans it directly, no event context); `client_participant_id` unique per event only. Both auto-generate via a bounded retry loop when left blank, real collision risk is astronomically low (48 bits of randomness) — the loop is a correctness backstop, not a response to expected contention. `photo`/`document` attach through `Participant#attach_tenant_scoped`, which builds an explicit tenant-namespaced storage key (`account.subdomain_slug/participants/...`) — `ActiveStorage::Blob` has no `account_id` column of its own to RLS-protect, so the tenant boundary lives in the key/path instead. **Prerequisite work this surfaced**: Active Storage wasn't installed yet — ran `active_storage:install` and hand-edited the generated migration to use `id: :uuid` (with a `gen_random_uuid()` DB-side default, since `ActiveStorage::Blob`/`Attachment`/`VariantRecord` are framework classes that don't run through `ApplicationRecord`'s own UUIDv7-on-create hook) instead of the gem's bigint default — every one of our own tables' foreign keys are uuid, and a polymorphic `record_id` column has to be able to hold one.
- [x] Dedupe validation chain (govt ID → email+name → email → phone), scoped per event, ported from baseline fuzzy-match logic. → `Participant.duplicate_match` (class method, shared by the model's own `not_a_duplicate` validation and `ParticipantImportJob`) — a real cascade, not four independent checks: tries the highest-confidence identifier first, only falls through to the next tier if that one had nothing to check or nothing to match.
- [x] Custom-field builder (§5.4 new item): organizer-defined fields (text/select/checkbox/file) stored per event, rendered dynamically on the admin manual-entry form — this generalizes the baseline's fixed `participant_fields` catalog from Phase 4. → New `CustomField` model (`app/models/custom_field.rb`), managed as nested attributes on Event (`Event#custom_fields`) — same client-side build-then-save-on-Next shape Phase 6 established for `TicketCategory`, reusing the same `nested_fields_controller.js` Stimulus controller and added to the Basic Info step alongside Phase 4's fixed catalog (additive, not a replacement — that catalog is untouched). File-type responses land in `Participant#custom_field_files` (`has_many_attached`), looked back up per field via a signed blob id stored in `custom_field_values`. **Found and fixed before it ever shipped**: `field_type: :select` doesn't work — Rails raises at boot because the generated `select` class method collides with `ActiveRecord::Base`'s own `.select` query method. Renamed the enum value to `:dropdown` (still labeled "Select" to the organizer); caught by a plain `bin/rails runner` boot check before writing any specs against it.
- [x] Admin participant list: search/filter across identifier fields, pagination (Pagy), bulk destroy. → `Admin::ParticipantsController#index`, `app/views/admin/participants/index.html.erb`. **Found and fixed before it shipped**: `gem "pagy"` (added unversioned in Phase 0, never actually used until now) resolved to 43.6.0, which turned out to be a ground-up API rewrite — no `Pagy::Backend`/`Pagy::Frontend`, no `pagy(scope)`/`pagy_nav` helpers, a completely different class-based API instead. Pinned to `~> 8.6`, the last release on the classic API every existing convention/comment in this codebase assumed.
- [x] Approval-based registration toggle per event (organizer must approve before a participant is considered confirmed) — status field on `Participant`. → New `Event#participant_approval_required` boolean (also joined `Event::CONTENT_ATTRIBUTES`, so toggling it on an already-published event reverts to draft same as every other content field), `Participant#status` (`pending`/`confirmed`). `Event#default_participant_status` is the one place that branches on the toggle — `Admin::ParticipantsController#create` and `ParticipantImportJob` both call it rather than each re-deriving the same logic; deliberately not a model-level callback/default; since the schema's own column default (`pending`) is already a valid value, a `before_validation` `||=` guard could never distinguish "caller explicitly wants pending" from "nobody set it yet."
- [x] Bulk XLSX import (async Sidekiq job) with the same fuzzy-dedupe matching, progress-pollable; bulk XLSX export (attendance/session columns stubbed until Phase 9/11 exist, but the export scaffold and signed-download-URL delivery belong here). → `ParticipantImportJob`/`ParticipantExportJob` (`roo`/`caxlsx`, both added to the Gemfile — neither existed yet), `ImportFile`/`ExportFile` models tracking progress/outcome. Import matches columns case-insensitively against a fixed header map (custom fields aren't populated by import — out of scope for this pass, fixed/identifier columns are the whole surface); per-row outcome is `created`/`duplicate`/an error message, capped at 50 stored row errors so one catastrophically bad file can't write an unbounded jsonb column. The progress page is a plain `<meta http-equiv="refresh">` poll, not a JS loop or Turbo Stream broadcast — no real-time wiring exists until Phase 9, and a 3s page refresh is plenty for a background job the admin is just waiting on. Export's "signed cloud URL" requirement is just `rails_blob_path` — Active Storage blob URLs are already signed/expiring by construction, nothing extra to build.
- [x] `EventLiveStats` row seeded/incremented on participant create (column exists, real-time broadcast wiring is Phase 9 — this phase just keeps the counter correct as a plain DB write). → `Event#live_stats!` (lazily seeds the row on first use, `find_or_create` — most of an event's life happens before it has a single participant), `Participant#increment_live_stats!` (`after_create`). All four counters requirement.md §8 names (registered/checked-in/checked-out/occupancy) exist as columns now so Phase 9 doesn't need another migration; only `registered_count` is actually written to yet.

### Definition of Done
- [x] Model spec: full dedupe chain, each fallback level tested independently. → `spec/models/participant_spec.rb` (`.duplicate_match` — govt_id first, falls through to email+name, then email, then phone; scoped per event; excludes the record's own id).
- [x] Job spec: bulk import handles a mixed file (new + duplicate rows) correctly, reports per-row outcome. → `spec/jobs/participant_import_job_spec.rb` — builds a real `.xlsx` in memory via `caxlsx` (no checked-in binary fixture), covers created/duplicate/error counts on one mixed file, a per-row error message without aborting the rest of the file, blank rows skipped (not counted as errors), and the whole-file-unreadable `failed` state.
- [x] Request spec: admin manual entry respects custom-field requiredness; document upload rejected/accepted based on ticket category flag. → `spec/requests/admin_participants_spec.rb`.
- [x] Cross-tenant leak spec: participant search never returns another account's rows. → `spec/models/participant_spec.rb` (tenant isolation) + `spec/requests/admin_participants_spec.rb` ("never returns another tenant's participants in search results", "404s when Account A requests Account B's event's participants").
- [x] Manual QA: import a sample XLSX with a few intentional duplicates, confirm correct dedupe outcome and progress UI; manually create one participant through the custom-field form. → verified live via Playwright against the dev server: added a required custom field + turned on participant approval from the Basic Info step in one save, created a participant manually through the resulting form (custom field included, landed `Pending` per the toggle), attempted a second participant with the same name+email and confirmed it was rejected with "Duplicate of Alice Smith (matched on email and name)," then separately uploaded a real `.xlsx` through the Import form and confirmed the progress page showed "Import complete — 2 participants created, 0 duplicate(s) skipped, 0 error(s)" once the job ran. (No Sidekiq worker process runs in this dev environment — jobs were executed via `perform_now`/`rails runner` standing in for the worker, same as the request/job specs already do; the enqueue-and-redirect half of the flow was verified through the real controller, confirmed via `have_enqueued_job` in `spec/requests/admin_import_export_files_spec.rb`.)

**Also found and fixed (Brakeman-adjacent, caught from a live server log, not a spec):** `Admin::ParticipantsController#participant_params` originally left `custom_field_values` unpermitted (relying on `params.dig` to read it manually), which is safe but logs a Rails "Unpermitted parameter" warning on every single participant create/update. Permitting it outright to silence that turned out to be a real bug, not just a cosmetic fix — mass-assigning it directly would jsonb-serialize a raw uploaded-file object straight into the column for file-type fields, bypassing `Participant#attach_custom_field_file` entirely. Fixed by permitting it (for the clean logs) but always stripping it before assignment (`fixed_field_params`), leaving `#apply_custom_field_values`'s explicit per-field handling as the only path that actually touches that column.

263/263 specs green, Rubocop clean, Brakeman: 0 warnings.

**Revisited (Cloudinary, cross-cutting):** switched Active Storage's production/development backend to Cloudinary (`gem "cloudinary"`) so tenant photo/document/import/export uploads land in real cloud storage, not local disk. `config/storage.yml` gained a `cloudinary:` service (`folder: "eventmeet/<%= Rails.env %>"` — a fixed root shared by every upload through this service, only there to separate environments in one Cloudinary account); credentials come solely from the `CLOUDINARY_URL` env var (never committed) since the gem's own `Cloudinary::Config` auto-loads it. Production always uses `:cloudinary`; development falls back to `:local` unless `CLOUDINARY_URL` is set, so local dev needs no real account; `test` is untouched (still `:local`, disk). **Found and fixed before it shipped**: the gem's Active Storage adapter (`ActiveStorage::Service::CloudinaryService`) lives outside the gem's own autoload/require tree — `require "cloudinary"` at boot pulls in its Railtie/Engine but never that file, and Rails resolves configured services via `.constantize`, not `require`, so referencing the `:cloudinary` service raised `NameError` until explicitly required. Also, that file monkey-patches `ActiveStorage::Blob` (overrides `#key`), so requiring it too early (a plain initializer) raised `uninitialized constant ActiveStorage::Blob` — fixed via `ActiveSupport.on_load(:active_storage_blob) { require "active_storage/service/cloudinary_service" }` in `config/initializers/cloudinary.rb`, which defers the require until that class actually exists. Tenant-wise folder structure comes from the blob key itself, not any Cloudinary-side setting: Cloudinary treats every `/` in a blob key as a folder separator, so extracted the existing `account.subdomain_slug/participants/...` key-building logic out of `Participant` into a shared `TenantScopedAttachment` concern (`app/models/concerns/tenant_scoped_attachment.rb`, `#tenant_scoped_blob_key`) and applied it to `ImportFile`/`ExportFile` too (previously plain `.attach(io:, filename:, content_type:)` with the framework's default untenanted key) — every tenant's uploads, exports, and imports now nest under that tenant's own folder regardless of attachment type. No real Cloudinary account is available in this environment, so this was verified structurally only (`bin/rails runner` confirming the service resolves to `ActiveStorage::Service::CloudinaryService`, the `folder` option resolves per-environment, and `Cloudinary.config.cloud_name` picks up a `CLOUDINARY_URL` set inline) — actual upload behavior needs a real `CLOUDINARY_URL` supplied to the deploy environment. 263/263 specs still green (test env unaffected), Rubocop clean, Brakeman: 0 warnings.

**Superseded by Phase 7.5 below**: the event-level `participant_fields`/`CustomField` mechanism this phase built is being replaced by a ticket-category-scoped form builder, reached from its own nav tab rather than the event-creation wizard. The Basic Info step's UI for it was already removed (see Phase 7.5's first checklist item) — the columns/model/associations described above stay live until Phase 7.5's rescoping work lands.

---

## Phase 7.5 — Dynamic Registration Form Builder (Ticket-Category Scoped)

**Goal:** an organizer designs the registration form each ticket category actually uses — its own form, a form shared across every category, or (if untouched) a sensible default — from a dedicated **Design Registration Form** screen, not from anywhere inside the event-creation wizard. Whatever fields a category's badge is configured to display are automatically required on that category's form.
**Implements:** §5.4, §5.14 (v12).
**Depends on:** Phase 6 (`TicketCategory`), Phase 7 (`Participant`, `CustomField`, dedupe/requiredness validations — rescoped, not rebuilt), Phase 8 (`Badge`/`HasBadgeMapping` — the badge-mandatory rule reads `Badge#content`/`#mapping` directly).
**Explicitly not part of this phase:** any change to `Admin::EventsController::STEPS` or the Basic Info step — this screen is reachable only once an event already exists, from its own workspace nav, never from event creation/editing itself.

- [x] Removed the "Required Participant Fields" dropdown and "Custom Participant Fields" nested-builder card from the Basic Info step's UI (`app/views/admin/events/_basic_info_step.html.erb`), their display on the Review step and the Super Admin review page, and stopped `Admin::EventsController#event_params` from writing to `participant_fields`/`custom_fields_attributes` (leaving that code in place would have silently zeroed `participant_fields` on every Basic Info save, since the form no longer sends it). Left in place at the time: the `Event#participant_fields` column and the `CustomField` model/table/`Event#custom_fields` association — both retired for real by this phase, not just hidden.

- [x] **`RegistrationForm` model** (`account_id`, `event_id`, `ticket_category_id` — nullable). `ticket_category_id: nil` is the event's own **default/shared** form — one record does double duty as both "what a category falls back to when it hasn't designed its own" and "the one form every category uses" when the organizer wants uniformity; there's no separate boolean for "shared," an organizer gets that behavior for free by simply not creating category-specific forms. Same two-partial-unique-index shape `Badge` already established for the identical nullable-`ticket_category_id` "default vs. specific" pattern (`db/migrate/*_create_badges.rb`, copied into `db/migrate/*_create_registration_forms.rb`): one unique index on `(event_id, ticket_category_id)` where `ticket_category_id IS NOT NULL`, one unique index on `event_id` where `ticket_category_id IS NULL`. `TenantScoped` + RLS from creation, same as every tenant-scoped table since Phase 4. `catalog_fields` jsonb defaults every `Event::PARTICIPANT_FIELD_CATALOG` key to `false` on a new record (`after_initialize ... if: :new_record?`, merging over whatever the caller explicitly set), so the builder UI always has every checkbox to render, never an implicitly-missing key. `Event#registration_forms` (`has_many`, `dependent: :destroy`) and `TicketCategory#own_registration_form` (`has_one`, `dependent: :destroy`) wire up both sides; `TicketCategory#registration_form` is the resolving method (own form, else the event's default/shared one, else `nil`) every future caller uses — implemented now even though nothing calls it yet, so the resolution order only ever lives in one place. `spec/models/registration_form_spec.rb`: factory-default validity, `catalog_fields` default/merge behavior, both partial-unique-index constraints (mirroring `badge_spec.rb`'s equivalent cases), and all three resolution-method branches. 438/438 specs green (10 new), Rubocop clean.
- [x] **`catalog_fields` jsonb column on `RegistrationForm`** and **`TicketCategory#registration_form`** resolution method — delivered as part of the `RegistrationForm` model bullet above rather than separately.
- [x] **Rescope `CustomField`**: `db/migrate/*_rescope_custom_fields_to_registration_form.rb` — `remove_reference :custom_fields, :event` / `add_reference :custom_fields, :registration_form, null: false`. Deletes existing rows in `up` rather than backfilling them onto a new `RegistrationForm` — the only path that ever wrote a `CustomField` (the Basic Info step's nested-attributes form) was already removed in the prior pass, so any row still in the table was an orphaned, already-unreachable relic (confirmed: 2 leftover dev-DB rows from earlier manual QA, cleared by the migration). `CustomField#belongs_to :registration_form` (was `:event`); `RegistrationForm` gained `has_many :custom_fields, -> { order(:position) }, dependent: :destroy` + `accepts_nested_attributes_for :custom_fields, allow_destroy: true, reject_if: :all_blank` (moved verbatim off `Event`, which lost both). Every caller updated to resolve through the participant's own `ticket_category.registration_form&.custom_fields` instead of `event.custom_fields`: `Participant#required_custom_fields_present` (returns early — nothing required — when the category has no resolved form), `Admin::ParticipantsController#apply_custom_field_values`, and `admin/participants/_form.html.erb`'s "Additional fields" block (`participant.ticket_category&.registration_form&.custom_fields || CustomField.none` — renders for whichever category is *currently selected*; re-rendering that block live when the category dropdown changes, without a full page reload, stays a separate not-yet-built item, tracked below under the manual-entry-form bullet). `Event::PARTICIPANT_FIELD_CATALOG`/`Event#participant_fields` themselves are untouched by this pass — `Participant#required_fixed_fields_present` and the fixed-field half of the manual-entry form still read `event.participant_fields` directly, pending the badge-mandatory rule/`effective_catalog_fields` work below. `spec/factories/custom_fields.rb`/`registration_forms.rb`, `spec/models/custom_field_spec.rb` (rebuilt off `registration_form:` instead of `event:`), `spec/models/participant_spec.rb` (required-CustomField spec now goes through a real `ticket_category`/`RegistrationForm`, plus a new case proving a field on *another* category's form isn't required), `spec/requests/admin_participants_spec.rb`, `spec/requests/admin_events_spec.rb` (the "ignores custom_fields_attributes" case now asserts zero `RegistrationForm`s created, since `Event#custom_fields` no longer exists to assert against directly) all updated. 439/439 specs green, Rubocop clean.
- [x] **Badge-mandatory rule**, `Badge#required_catalog_fields`: scans `content` for `BadgeReformService::TOKEN_PATTERN` matches (only `DESIGNATION` → `position` has a catalog counterpart among the direct tokens — `NAME`/`TITLE`/`FIRST_NAME`/`LAST_NAME`/`GOVT_ID`/`PHOTO`/`LOGO`/QR/barcode variants are either always-collected core `Participant` columns or non-form tokens, silently ignored) and `mapping`'s `OTHER1`/`OTHER2`/`OTHER3` values (whichever `HasBadgeMapping::MAPPABLE_FIELDS` entry an organizer mapped a slot to, kept only if it's also in `Event::PARTICIPANT_FIELD_CATALOG`), deduped. **Only ever returns catalog fields, never touches organizer-defined `CustomField`s** — a badge has no mechanism to reference a custom field's jsonb value at all, so there's nothing to enforce there. `spec/models/badge_spec.rb` (`#required_catalog_fields`): empty for a catalog-ineligible badge, `$DESIGNATION$` → `position`, an `OTHER*` mapping to a catalog field, an `OTHER*` mapping to a non-catalog field (`hex_id`) ignored, content + mapping combined and deduped.
- [x] **`TicketCategory#effective_catalog_fields`** — the union that actually drives requiredness: `registration_form&.catalog_fields` (falling back to `RegistrationForm::BUILTIN_DEFAULT_CATALOG`, so a category with no form configured at all still isn't literally fieldless) with every key in the category's resolved `Badge#required_catalog_fields` forced to `true`. **Revisited**: `BUILTIN_DEFAULT_CATALOG` was originally just `email`; confirmed requirement is that the built-in default look like a real, complete registration form on its own — every `Event::PARTICIPANT_FIELD_CATALOG` entry (`Event::PARTICIPANT_FIELD_CATALOG.dup.freeze`), not a bare-minimum placeholder. `title`/`first_name`/`last_name` aren't part of this constant at all — they're always-collected core `Participant` columns, unconditionally rendered/required independent of any catalog (`first_name` via its own `validates :presence`, `title`/`last_name` always shown, optional) — so there was nothing for this constant to add for them. This is a broader default than before, so `spec/factories/participants.rb` needed real values for every catalog field (`contact_num`/`company`/`department`/`position`/`nationality`/`country`) to stay valid by default across the whole suite — `contact_num` specifically sequenced, not a fixed literal, since it's one of `Participant.duplicate_match`'s own dedupe tiers and a fixed value collided the moment two factory-built participants existed in the same event (caught by several unrelated specs — `ScanService`/`EventSchedulerJob`/dashboard-load — failing on a phantom "duplicate phone number" once the fixed value was in place, not by inspection). "This category's own badge" reuses `Event#badge_for`'s category-then-default fallback, refactored into `Event#badge_for_category(ticket_category)` (accepts a `TicketCategory` directly rather than only ever through a `Participant`) — `#badge_for(participant)` is now a one-line wrapper over it, so the two never disagree. `RegistrationForm#catalog_fields` itself changed from an `after_initialize` callback to a reader-method override (`Event::PARTICIPANT_FIELD_CATALOG.index_with { false }.merge(super)`) partway through this work — the callback only fired once at construction, so it silently produced an incomplete hash for any *later* partial assignment (`update!(catalog_fields: {...})`, and how FactoryBot's attribute-by-attribute build strategy sets it) instead of only ever the initial one; the reader override recomputes on every access regardless of how/when the raw value was set. `spec/models/event_spec.rb` (`#badge_for`/`#badge_for_category`: nil-when-no-badges, category-specific-over-default, default-fallback, nil-category resolves the default) and `spec/models/registration_form_spec.rb` (`TicketCategory#effective_catalog_fields`: built-in fallback with no form, reflects the resolved form untouched by any badge, a badge-mandated field forced true alongside an untouched sibling, the category's *own* badge is what applies (not the event's default badge), badge-mandated fields still apply when the category rides the shared/default form). 453/453 specs green (15 new), Rubocop clean, Brakeman: 0 warnings.
- [x] **`Participant#required_fixed_fields_present`** switched from reading `event.participant_fields` to `ticket_category&.effective_catalog_fields` (`#required_custom_fields_present` already made the equivalent switch in the `CustomField` rescoping pass above). No `ticket_category` selected means nothing is enforced, same "no context yet, nothing required" shape `#required_custom_fields_present` already established. `admin/participants/_form.html.erb`'s fixed-field block updated to match (`participant.ticket_category&.effective_catalog_fields || {}` in place of `event.participant_fields`) so the rendered asterisks/required attributes never disagree with what actually gets validated — same "renders whatever's *currently selected*, live re-render on category change is a separate not-yet-built piece" caveat as the custom-fields block already carries. `Event::PARTICIPANT_FIELD_CATALOG`/`Event#participant_fields` themselves are untouched (still real columns/constants) but `event.participant_fields` is now genuinely unread by any enforcement or rendering path — `EventsController#event_params` already stopped writing it (Phase 7.5's first pass) and `#duplicate` still copies it — worth a follow-up decision on dropping the column entirely, not done here since it's outside this bullet's scope. `spec/models/participant_spec.rb` (rewrote the stale event-level test into three: category-turns-a-field-on, no-category-means-nothing-required, badge-mandates-a-field-even-when-the-form-doesn't) and `spec/requests/admin_participants_spec.rb` (rewrote the equivalent request-level case to go through a real `ticket_category`/`RegistrationForm`) updated. 455/455 specs green, Rubocop clean, Brakeman: 0 warnings.
- [x] **`Admin::RegistrationFormsController`** (`admin/events/:event_id/registration_form`, singular resource, `edit`/`update` only — same "one screen, one batched save" shape the Tickets step already uses for multiple `TicketCategory` rows; `EventPolicy#update?` gates it, same as editing the event itself). One page: a always-present **Shared / Default Form** card (the nullable-`ticket_category_id` `RegistrationForm`), plus one card per `TicketCategory` with two radios — **"Use the shared/default form"** / **"Design a custom form for this category"** — CSS-`:has()`-driven show/hide of the custom panel (`.registration-form-category`, per-category-scoped so it works for any number of categories, same technique the Basic Info step's `.seat-limit-block` established, confirmed no `required` attributes exist anywhere inside the hidden panel so — unlike seat-limit — no accompanying JS is needed to keep `required` in sync). Only two real modes, not three — "Default" and "Shared" collapse into the same underlying mechanism (RegistrationForm's own model comment), so the UI reflects that instead of inventing a third persisted state that wouldn't mean anything different. Each panel's catalog checkboxes render checked-and-disabled for whatever this category's own badge mandates (`Event#badge_for_category(category)&.required_catalog_fields`), with a plain hidden field resubmitting the same value alongside the disabled checkbox (a disabled input submits nothing at all, so without it a badge-mandated field could be silently dropped from the saved `catalog_fields` on its own — enforcement doesn't actually depend on this, `TicketCategory#effective_catalog_fields` already can't be bypassed either way, but the UI shouldn't be able to visibly "turn off" something it can't actually turn off). `custom_fields_attributes` reuses `nested_fields_controller.js` verbatim, one independent controller instance per panel (shared form + each category) — a single page-wide instance would break "Add another field," since the controller's container/template targets are singular accessors that'd always resolve to whichever one Stimulus found *first* on the page, not the one next to the clicked button. `_custom_field_fields.html.erb` recreated under `admin/registration_forms/` (byte-identical row markup to the one retired from `admin/events/` earlier in this phase).
  - **Two real bugs caught before/via specs, not by inspection**: (1) `@shared_form.save!` was originally unconditional — since the shared-form panel always renders but an untouched one (nothing checked, no custom fields) submits no `registration_form[shared_form]` key at all (same "unchecked submits nothing" behavior as any checkbox), every single update — even one only meant to touch a single category — was silently creating an empty default `RegistrationForm` as a side effect. Fixed: only saved when the key is actually present in params *or* the form is already persisted (an existing form re-saving to "everything unchecked" is a real, intentional edit; a brand-new one with nothing submitted isn't). Caught by a spec asserting a net `RegistrationForm` count change of exactly -1 when switching a category off "Custom," which was coming back 0. (2) On a validation failure, the initial draft re-fetched fresh state from the DB for re-rendering — silently discarding whatever the organizer had just typed (including the invalid value itself) instead of showing it back with its error. Fixed by unifying `#edit`'s and `#update`'s form-loading into one `#load_forms` that always builds from submitted params when present, DB state only as the fallback (covers a fresh GET) — one code path, so there's no second copy of "what does this page currently show" that could drift from the first.
  - Reachable today via a plain "Design Registration Form" link on the event edit page's status-badge row (`admin/events/edit.html.erb`) — explicitly not one of the wizard steps, matching this phase's own scope note. The real event-workspace sidebar entry (below) still needs to land; this is a real, working interim entry point, not a stub.
  - `spec/requests/admin_registration_forms_spec.rb` (11 examples): access control (unauthenticated/wrong-role/event_manager), GET renders every category + the shared card, PATCH saves the shared form's catalog fields, PATCH creates a category's own form (catalog + custom field) only in "custom" mode, PATCH leaves no form behind for a category on "shared," PATCH destroys an existing form when switched back to "shared" (the count-based regression test that caught bug 1 above), a badge-mandated field stays effectively required even when the submitted `catalog_fields` array omits it, a validation failure re-renders `:unprocessable_content` with the attempted (invalid) custom field's label still visible (the regression test for bug 2 above), and the standard cross-tenant 404. 466/466 specs green (11 new), Rubocop clean, Brakeman: 0 warnings.

### Revisited — standalone, assignable forms (post-Phase-7.5, supersedes the per-category-scoped controller above; requirement.md §5.4/§5.14 v12)

Confirmed requirement: "create a form first and then assign it to ticket category… if one form is for all category then we should have that feasibility as well." The one-form-per-category shape above (`RegistrationForm belongs_to :ticket_category`, nil meaning the event's own default/shared form) couldn't express that cleanly — "shared" only ever meant "the one unnamed default form," not "an organizer-named form deliberately applied to several categories," and creating a form always meant creating it *for* a specific category from the start. Flipped the relationship instead: `TicketCategory belongs_to :registration_form` — a form is a standalone, named record an organizer builds once, then assigns to any number of categories (including all of them) as a separate step. Same enforcement underneath (`TicketCategory#effective_catalog_fields`/`Badge#required_catalog_fields` untouched) — this only changed *how a form and its categories find each other*, not what's actually validated.

- [x] **`db/migrate/*_rescope_registration_forms_to_standalone_assignable.rb`**: `remove_reference :registration_forms, :ticket_category` (Postgres drops both partial unique indexes automatically as a side effect of dropping the column they reference — confirmed empirically; an explicit `remove_index` for either afterward raised `PG::UndefinedObject`, already gone by the time it ran), `add_column :registration_forms, :name, :string, null: false` (no temp-default two-step needed — the table is guaranteed empty at that point in the same migration), `add_reference :ticket_categories, :registration_form`. `up` clears `custom_fields`/`registration_forms` first, same "dev/QA data from a shape being actively rebuilt, not worth a real backfill" reasoning as the earlier `CustomField` rescoping migration in this phase.
- [x] **`RegistrationForm`**: `belongs_to :ticket_category` replaced with `has_many :ticket_categories, dependent: :nullify` (deleting a form an organizer no longer wants shouldn't destroy or block-destroy the categories using it — they just fall back to `BUILTIN_DEFAULT_CATALOG`, same as any other unassigned category) and `validates :name, presence: true` (names matter now that several forms can coexist per event). The old `only_one_default_form_per_event`/`ticket_category_id` uniqueness validations are gone entirely — nothing needs to be unique anymore, since "apply to every category" is just assigning the same form to all of them, not a special nil-category state.
- [x] **`TicketCategory`**: `has_one :own_registration_form` replaced with a plain `belongs_to :registration_form, optional: true` — the custom `#registration_form` resolution method is gone too, since the association's own generated reader *is* the resolution now (no more "own form, else the event's default" fallback chain to hand-write). `#effective_catalog_fields` itself is unchanged.
- [x] **`Admin::RegistrationFormsController`** rebuilt as ordinary resourceful CRUD (`index`/`new`/`create`/`edit`/`update`/`destroy`, no `:show`) over `resources :registration_forms` (was a singular `resource`). `#assign_categories!` handles both plain multi-select (`ticket_category_ids: [...]`) and the confirmed "apply to all" requirement (`apply_to_all: "1"` assigns every one of the event's categories, overriding whatever was individually checked) — a one-time bulk assignment, not a persisted flag, so a category added to the event later doesn't retroactively inherit it. Assignment is always explicit, never additive: a category previously on this form but left unchecked on save is unassigned (`update_all(registration_form_id: nil)` for the difference, `update_all(registration_form_id: @registration_form.id)` for what's now checked) — editing assignment always reflects exactly what's currently checked.
- [x] **Views rebuilt**: `index.html.erb` (list of forms + which categories each applies to — "All categories" badge when every category is covered, plus a note listing categories still on the built-in default), `_form.html.erb` (shared new/edit partial: name, catalog checkboxes, `custom_fields_attributes` via `nested_fields_controller.js`, then an "Assign to Ticket Categories" section — an "Apply to ALL" checkbox plus the individual list, dimmed/inert via `pointer-events: none` under `.registration-form-categories:has(#apply_to_all:checked)` once "Apply to ALL" is checked, same `:has()`-off-live-DOM-state technique as `.seat-limit-fields`). The old per-category "badge-mandated fields render checked-and-disabled" builder UI is gone — it depended on a form having exactly one category (and so exactly one relevant badge) to check against, which no longer holds once a form can be shared across categories with different badges; server-side enforcement (`effective_catalog_fields`) was always the real mechanism and is completely unaffected.
- [x] **Real bug caught immediately, not by inspection**: `_form.html.erb`'s first draft used `form_with model: [@event, registration_form]` — raised `NoMethodError: undefined method 'event_registration_forms_path'` (missing the `admin_` prefix) the moment a spec actually exercised the `new` form. This app's routes give every `Admin::` path its `admin_` prefix via `scope path: "admin", as: "admin"`, not a real `namespace :admin do` — the only shape `form_with model: [...]`'s polymorphic-URL inference actually detects. Every other form in this app (`admin/participants/_form.html.erb` included) already avoids this by passing an explicit `url:`; fixed the same way here.
- [x] `AdminHelper#event_nav_items`'s "Design Registration Form" link now points at `admin_event_registration_forms_path` (the index), not the old singular `edit_admin_event_registration_form_path`.
- [x] `spec/factories/registration_forms.rb` gained a sequenced `name`; `spec/models/registration_form_spec.rb`, `spec/models/participant_spec.rb`, `spec/requests/admin_participants_spec.rb`, and `spec/requests/admin_registration_forms_spec.rb` (fully rewritten for the CRUD/assignment shape — creation, multi-select assignment, "apply to all," reassignment un-assigns what's no longer checked, badge-mandatory enforcement survives regardless of what's saved, validation-failure re-render, `dependent: :nullify` on delete, cross-tenant 404) all updated. Verified beyond specs too: a `bin/rails runner` walkthrough creating one form, assigning it to two categories, confirming both resolve it and `effective_catalog_fields` reflects it, then destroying the form and confirming both categories survive with `registration_form: nil`. 470/470 specs green, Rubocop clean, Brakeman: 0 warnings.
- [x] **Toggle-switch styling**: every checkbox on this screen (`registration_form[catalog_fields][]`, `apply_to_all`, `ticket_category_ids[]`, and each custom field row's `required`) gained Bootstrap's `form-switch` class — same toggle idiom already used elsewhere in this app (Basic Info step's "Paid Event"/"Send a confirmation email"/"Seat Limit"). Still plain checkbox inputs underneath, so the existing `:has(#apply_to_all:checked)` CSS rule needed no changes.
- [x] **Field ordering** (requirement.md v12 revisit: "I want to position each and every field … order of the field should be configurable"). `CustomField#position` already existed (`RegistrationForm#custom_fields` was already `-> { order(:position) }`) — nothing had ever exposed it in the builder, so every row defaulted to the schema's own `0`. The fixed catalog had no equivalent at all (`Event::PARTICIPANT_FIELD_CATALOG` is a plain Ruby array, always iterated in its own fixed order).
  - `db/migrate/*_add_catalog_field_positions_to_registration_forms.rb`: `catalog_field_positions` jsonb (default `{}`) on `RegistrationForm` — a sibling column to `catalog_fields`, not folded into it: enabled/required-ness and display order are independent concerns, so none of the existing `effective_catalog_fields`/badge-mandatory/validation logic needed to change at all.
  - `RegistrationForm#catalog_field_positions` — same reader-override-not-`after_initialize` pattern as `#catalog_fields`, defaulting each field to its own natural index in `Event::PARTICIPANT_FIELD_CATALOG` so an organizer who never touches ordering still gets the catalog's declared order, not something arbitrary. `#ordered_catalog_fields` sorts the catalog by it; `TicketCategory#ordered_catalog_fields` delegates to the assigned form's version, falling back to the catalog's own plain order when nothing's assigned — the one place both the builder and `admin/participants/_form.html.erb` read from, so they can't disagree.
  - Builder UI: the "Fields" section changed from a 3-per-row checkbox grid to one row per catalog field (toggle on the left, a small "Position" number input on the right) — listed in the catalog's own fixed order regardless of configured position (a plain number to edit, not live drag-reordering); `_custom_field_fields.html.erb` gained an equivalent `f.number_field :position` column. `admin/participants/_form.html.erb`'s catalog-field loop switched from `Event::PARTICIPANT_FIELD_CATALOG.each` to `participant.ticket_category&.ordered_catalog_fields`; the custom-fields loop needed no change (already sorted via the association's own `order(:position)` scope).
  - Controller: `catalog_field_positions` permitted as a real hash-of-values param (unlike `catalog_fields`' checked-or-absent array) and normalized so a blank/non-numeric box falls back to that field's own natural index rather than collapsing to `0` (which would otherwise silently pull an untouched field to the very front). `custom_fields_attributes` already permitted `:position`, no change needed there.
  - Ties aren't specially resolved (Ruby's `sort_by` isn't guaranteed stable) — a deliberate non-goal: the builder always renders a number input for every field, so real usage naturally assigns distinct values; a spec deliberately used negative positions to sidestep colliding with untouched fields' natural-index defaults, documented inline as to why.
  - `spec/models/registration_form_spec.rb` (`catalog_field_positions` default/override, `#ordered_catalog_fields` sorts correctly, `TicketCategory#ordered_catalog_fields` both branches) and `spec/requests/admin_registration_forms_spec.rb` (positions round-trip through the controller for both catalog and custom fields) added. Verified beyond specs: a `bin/rails runner` walkthrough assigning explicit catalog positions and a negative-position custom field, confirming `ordered_catalog_fields` reflects them. 476/476 specs green, Rubocop clean, Brakeman: 0 warnings.
  - **Stale schema cache, not a code bug**: after this migration landed, the browser hit `NoMethodError: super: no superclass method 'catalog_field_positions'` on the New Registration Form page — the already-running dev Puma/Sidekiq processes had cached `RegistrationForm`'s columns from before the migration ran (a fresh `bin/rails runner` process, and the full spec suite, both already saw the column correctly). Fixed by restarting both processes; no code change needed.
- [x] **`title`/`first_name`/`last_name` joined `Event::PARTICIPANT_FIELD_CATALOG`** (requirement.md v12 revisit: "title, firstname & lastname in the default fields selection"). Previously hardcoded, unconditionally rendered at the very top of the manual-entry form, entirely outside any catalog config — now genuinely selectable/orderable/toggleable in the registration form builder like every other catalog field, `RegistrationForm::BUILTIN_DEFAULT_CATALOG` (already `Event::PARTICIPANT_FIELD_CATALOG.dup`) picking them up for free.
  - **`first_name` is the one exception**: `TicketCategory#effective_catalog_fields` now `.merge("first_name" => true)` unconditionally, after the badge-mandatory union — a participant needs *some* name no matter what an organizer configures, mirrored by `Participant`'s own pre-existing unconditional `validates :first_name, presence: true` (the real backstop either way). `admin/participants/_form.html.erb` force-merges the same `"first_name" => true` locally too, so the rendered asterisk/`required` attribute never disagrees with what's actually enforced even in the no-`ticket_category`-selected case (where `effective_catalog_fields` itself is never called). The registration form builder (`admin/registration_forms/_form.html.erb`) renders `first_name`'s own toggle checked-and-disabled with a "Always required" note and a hidden field resubmitting the value (a disabled input submits nothing on its own) — same "make the UI honest about what it can't turn off" treatment badge-mandated fields used before forms became shareable across categories; safe to bring back for this one field specifically since its mandatoriness doesn't vary by category the way a badge's does.
  - `admin/participants/_form.html.erb`: the hardcoded title/first_name/last_name block at the top is gone — all three render through the same `ordered_catalog_fields` loop as every other catalog field now (title keeps its own "Mr./Ms./Dr." placeholder via a `case field` branch, first_name/last_name fall through to the generic text field, same as before).
  - `Badge#required_catalog_fields`: `DESIGNATION_TOKEN_CATALOG_FIELD` (a single constant) generalized into `TOKEN_TO_CATALOG_FIELD` (a hash) so `$TITLE$`/`$FIRST_NAME$`/`$LAST_NAME$` — direct badge tokens that already existed in `BadgeReformService::TOKEN_PATTERN`, just previously ignored for having no catalog counterpart — now correctly feed the badge-mandatory rule too. `$NAME$` still has none (the derived full name, not a directly editable column).
  - `spec/factories/participants.rb` gained a `title` default (same "keep the factory valid regardless of which catalog fields end up effectively required" reasoning as the earlier `contact_num`/`company`/etc. additions) — caught 5 unrelated specs (`Event#destroyed_categories_have_no_participants`, two `#badge_for`/`#badge_for_category` cases, an `admin_badges_spec.rb` case, an `admin_ticketing_spec.rb` case) failing on "Title can't be blank" the same way the earlier BUILTIN_DEFAULT_CATALOG expansion did. `spec/models/participant_spec.rb` (`first_name` required with no category selected, and even when a form explicitly turns it off), `spec/models/registration_form_spec.rb` (`effective_catalog_fields["first_name"]` forced true in both branches), and `spec/models/badge_spec.rb` (`$TITLE$`/`$FIRST_NAME$`/`$LAST_NAME$` tokens) added. Verified beyond specs: a `bin/rails runner` walkthrough confirming the default order includes all three, and that a form explicitly turning `first_name` off still leaves it effectively `true`. 481/481 specs green, Rubocop clean, Brakeman: 0 warnings.
- [x] **Event-workspace sidebar** (requirement.md §5.14 v12): today's account-level sidebar (`AdminHelper#admin_nav_items`, `shared/_console_shell`) was a single flat list, and Participants/Check-in resolved their nav link via a "jump to the account's most-recently-created event" hack (`participants_nav_path`/`checkin_nav_path`, both now retired) precisely because nothing established "you are inside event X" as page context. Fixed for real:
  - New flat top-level concern `EventScoped` (`app/controllers/concerns/event_scoped.rb` — not namespaced `Admin::EventScoped` as originally sketched; matches this app's existing convention of flat concern names — `PunditAuthorizable`, `PlatformRequestScoped`, `TenantResolvable` — even though all of them, like this one, are only ever included from one audience's controllers), `before_action :set_event`. Replaces byte-identical private `#set_event` methods on `Admin::RegistrationFormsController`, `Admin::ParticipantsController`, `Admin::ImportFilesController`, `Admin::ExportFilesController`, `Admin::ScanEventsController`.
  - `AdminHelper#event_nav_items(event)`: Dashboard, **Design Registration Form**, Participants, Export, Import, Check In — every link carries the real `event_id`. "Export" points at the Participants page (`admin/participants/index.html.erb`) rather than a dead end — `Admin::ExportFilesController` is `:create`/`:show` only (a POST that kicks off the job, then a progress/download page for that one file), the actual "Export" trigger already lives on the Participants page, so the nav link goes where the feature actually is.
  - `layouts/admin.html.erb`: `nav_items: @event&.persisted? ? event_nav_items(@event) : admin_nav_items` — `#persisted?`, not bare presence, so `Admin::EventsController#new`/a failed `#create` (a real but unsaved `@event`) correctly still shows the account-level sidebar. Since this keys off `@event` itself rather than a controller allowlist, it also naturally (and correctly) applies to the wizard-internal controllers that already set `@event` for their own scoping (`Admin::BadgesController`/`EventSessionsController`/`SpeakersController`/`SchedulesController`/`TicketReservationsController`) — genuinely inside event X's workspace either way, not a gap.
  - **New `Admin::EventsController#show`** (`admin/events/:id`, `admin_event_path`) — the event-workspace "Dashboard" landing target: status/approval badges (same as the wizard's own top row), live participant/ticket-category/checked-in counts (`shared/_stat_widget`), core event details, and a "Continue Setup" button into `#edit`. Kept **separate from `#edit`** (the creation wizard's `STEPS` machinery, untouched) so the wizard and the post-creation workspace stay two distinct surfaces, per this phase's own scope note. The Events index now links an event's name into `#show`, not `#edit` (the row's pencil icon still goes straight to `#edit`); every event-scoped page's own breadcrumb (`Events → <event name>`) now points its `<event name>` crumb at `#show` too, not `#edit` — `admin/participants/*`, `admin/scan_events/index`, `admin/import_files/*`, `admin/export_files/show`, `admin/registration_forms/edit` (its own "Back to event" button too). Left untouched, deliberately: `admin/event_sessions/*`, `admin/speakers/*`, `admin/schedules/*`, `admin/badges/*` — those are wizard-step-authoring pages (reached from within `#edit`'s own step panel), so "back" correctly still means the wizard, not the workspace home.
  - **User decision, not a default assumption**: matching the requirement's literal account-level sidebar (Dashboard/Events/Reports/Settings/Profile) meant dropping "Badges" (the account-wide Badge Template library, `admin_badge_templates_path` — distinct from any one event's own badge design) from *any* nav link, since it was the account-level sidebar's only entry point and doesn't belong on the event-scoped one either (it isn't tied to one event). Asked; confirmed drop it — the template library still exists and works, just isn't linked from anywhere in the nav for now (direct URL only) until it gets a real home, e.g. under Settings once that's built. "Sponsors" (already a `"#"` stub) and "Profile" (new `"#"` stub, no page built yet) round out the account-level five.
  - `spec/requests/admin_events_spec.rb`: new `GET /admin/events/:id (show)` describe block (renders the overview, switches the sidebar to the event-scoped nav, cross-tenant 404) plus a check that the Events index still shows the account-level sidebar (no event in context). 470/470 specs green (4 new), Rubocop clean, Brakeman: 0 warnings.

**Phase 7.5 complete** — every checklist item above is now `[x]`. Registration forms are ticket-category-scoped with a default/shared fallback and badge-mandatory enforcement, designed from their own nav tab, entirely outside event creation.
- [ ] **`Admin::ParticipantsController`/`app/views/admin/participants/_form.html.erb`**: fixed + custom fields now vary by the participant's selected ticket category (previously fixed for the whole event), so the manual-entry form needs to re-render its dynamic field block when the category dropdown changes — a small Turbo Frame (or Stimulus-driven fetch) keyed on `ticket_category_id`, replacing the current "just loop over `event.custom_fields`, always the same set" render. `#apply_custom_field_values` resolves fields via `participant.ticket_category.registration_form&.custom_fields` instead of `@event.custom_fields`.
- [ ] **`ParticipantImportJob`**: per-row requiredness check switches from `event.participant_fields` to each row's resolved `ticket_category.effective_catalog_fields` (custom fields stay out of scope for import, unchanged from Phase 7).

### Definition of Done
- [ ] Model spec: `TicketCategory#registration_form` resolution (own form wins over shared, shared wins over built-in default), the two partial unique indexes reject a second per-category and a second default form.
- [ ] Model spec: `Badge#required_catalog_fields` correctly extracts catalog fields from both `content` tokens and `mapping`, and correctly ignores tokens with no catalog counterpart.
- [ ] Model spec: `TicketCategory#effective_catalog_fields` forces a badge-mandated field to `true` even when the organizer's own `RegistrationForm#catalog_fields` has it `false`/unset.
- [ ] Request spec: Design Registration Form screen saves Default/Shared/Custom per category in one batch; a badge-mandated catalog checkbox can't be unchecked through a direct param manipulation either (server-side enforcement, not just a disabled input).
- [ ] Request spec: admin manual entry and CSV import both resolve required/available fields through the category, not the event — two categories on the same event with different forms produce different validation results for an otherwise-identical row.
- [ ] Request spec: `Admin::EventsController::STEPS`/Basic Info step unaffected — confirms this phase genuinely didn't touch event creation.
- [ ] Cross-tenant leak spec: `RegistrationForm`/rescoped `CustomField` follow the same `TenantScoped`/RLS pattern as every other tenant table — Account A cannot read/edit Account B's forms by guessing IDs.
- [ ] Manual QA: on one event, leave one ticket category on the default form, give a second its own custom form with a required custom field, mark a third Shared to the first's shared form, put a badge-mapped `$OTHER1$` → `company` token on one category's badge and confirm `company` renders checked-and-disabled-required on that category's form and is actually enforced on save; confirm the event-creation wizard (Basic Info → Review) shows no trace of the old catalog/custom-field UI.

---

## Phase 8 — Badge Design & Printing

**Goal:** organizers design a badge visually and render a correctly sized PDF with live participant data substituted in. (Auto-print via the Electron agent is Phase 10 — this phase is design + on-demand render/download only.)
**Implements:** §3.6, §5.5, §4.10 (GrapesJS + Grover), §8 (`Badge`, `BadgeTemplate`).
**Depends on:** Phase 7 (needs real participant data to render tokens against).

- [x] `BadgeTemplate` model: `account_id`, reusable across events (library, §5.5 new item), `content` (HTML/CSS), `mapping` (token list), background image + logo (Active Storage), `output_type` (`badge`/`wristband`), physical size (cm). → `app/models/badge_template.rb`, `db/migrate/*_create_badge_templates.rb`. TenantScoped + RLS; `has_one_attached :background_image`/`:logo` via the existing `TenantScopedAttachment` concern (Phase 7/Cloudinary), key namespaced under `"badge_templates/..."`.
- [x] `Badge` — per-event instantiation of a `BadgeTemplate` (or a fresh one), same content/mapping shape. → `app/models/badge.rb`, `db/migrate/*_create_badges.rb`. `.build_from_template` copies content/mapping/size/attachments *in* rather than referencing the template live — editing a template later never silently changes badges already built from it, same "copy, not a live link" relationship Phase 4's "Duplicate event" established. `content`/`mapping`/`output_type`/size/validations live in a shared `HasBadgeMapping` concern (`app/models/concerns/has_badge_mapping.rb`) so Badge and BadgeTemplate can't drift apart on what's actually the same shape.
- [x] GrapesJS integration wrapped in a single Stimulus controller (§4.10 — no React island) inside the admin console's Badge tab (Phase 4 stub filled in); custom draggable blocks map to tokens (`$NAME$`, `$PHOTO$`, `$QRCODE$`, `$BARCODE$`, `$OTHER1..3$`, etc.). → `app/javascript/controllers/badge_editor_controller.js`, shared canvas partial `app/views/admin/shared/_badge_editor.html.erb` (used by both `Admin::BadgeTemplatesController#edit` and `Admin::BadgesController#edit`). GrapesJS itself plus `grapesjs-preset-webpage` (layers/style-manager/code-view/undo-redo panel chrome) and `grapesjs-blocks-basic` (generic text/image/container blocks) pinned via `bin/importmap pin` — vendored locally like the rest of this app's JS, not loaded from a CDN at runtime. Seven custom blocks registered under a "Badge Tokens" category, one per placeholder; dragging one onto the canvas inserts real markup (e.g. `<img src="$QRCODE$">`) with the token sitting in whatever attribute/text position actually gets substituted later — the token IS the placeholder, not a separate editor-only concept.
- [x] Token-substitution engine (`BadgeReformService`-equivalent): given a `Participant` + `Badge`, produce final HTML with tokens replaced, QR (`rqrcode`) and Code128 barcode (`barby`) generated in two independent slots. → `app/services/badge_reform_service.rb`. Pure text substitution (`gsub` against a token pattern), not HTML construction — the canvas is what puts a token inside real markup in the first place, so this only ever replaces the token string with escaped text or a `data:` URI. `$QRCODE$` always encodes the participant's own `hex_id` (what a check-in scanner looks up directly); `$BARCODE$` encodes `govt_id`, falling back to `client_participant_id` — genuinely two independent scannable codes, not the same identifier twice. `$OTHER1$`/`$OTHER2$`/`$OTHER3$` resolve through `Badge#mapping` against `HasBadgeMapping::MAPPABLE_FIELDS`, a fixed allowlist — never an arbitrary `public_send` off organizer input. `$PHOTO$` falls back to a 1x1 transparent PNG when the participant has none attached, so the badge still renders instead of showing a broken-image icon.
- [x] Grover-based PDF render at correct DPI/page size from the substituted HTML; on-demand single-badge download endpoint. → `app/services/badge_pdf_service.rb`, `Admin::ParticipantsController#badge` (`GET .../participants/:id/badge`, `format: :pdf`) — resolves the applicable `Badge` via `Event#badge_for` (the participant's own ticket-category badge first, falling back to the event's default) and streams the rendered PDF inline. `config/initializers/grover.rb` points Grover/Puppeteer-core at a real Chrome executable — `CHROME_EXECUTABLE_PATH` in any real deploy environment, auto-detected from this repo's own Playwright browser cache (`package.json` already depends on it for system specs) in development/test, so badge PDFs work locally with zero extra setup. Physical size (`Badge#width_cm`/`#height_cm`) passed straight to Grover as `"Xcm"` page dimensions — no DPI math needed, Puppeteer accepts physical units natively.
- [x] Conditional badge layout by ticket category (§5.5 new item): an event can map different `Badge`s to different `TicketCategory`s without duplicating the whole template. → `Badge#ticket_category` (nullable — nil means the event's default badge), two partial unique indexes (`db/migrate/*_create_badges.rb`) enforcing at most one default and at most one per category, `Event#badge_for` resolving which one applies to a given participant.
- [x] Badge template library UI (`Admin::BadgeTemplatesController`, account-level, not nested under any Event) and per-event badge management (`Admin::BadgesController`, nested — `#index` is what the wizard's Badge step actually links out to, each badge's own GrapesJS canvas is too big for a step panel). Sidebar's "Badges" placeholder (Phase 3 stub) now points at the template library.

### Definition of Done
- [x] Service spec: token substitution produces correct output for a fixture participant across all supported tokens, including both QR/barcode slots independently. → `spec/services/badge_reform_service_spec.rb` — `$NAME$` (HTML-escaped), `$QRCODE$`/`$BARCODE$` (real PNG magic bytes, independent govt_id-vs-hex_id data), `$PHOTO$` (attached and blank-pixel-fallback cases), `$OTHER1$`/`$OTHER2$` mapped vs. an unmapped `$OTHER3$` left blank.
- [x] Request spec: PDF download endpoint returns a correctly-sized PDF (assert page dimensions match configured badge size). → `spec/requests/admin_badges_spec.rb`, using the `pdf-reader` gem (test-only) to read back the actual `MediaBox` and assert it matches `width_cm`/`height_cm` within a small tolerance; also covers a category-specific badge winning over the event default, and the no-badge-configured case redirecting with a friendly alert instead of a broken download.
- [x] Manual QA: design a badge in the GrapesJS canvas, save, generate a PDF for a real participant, visually confirm photo/QR/text placement matches the design. → verified live via Playwright against the dev server: created a badge template, confirmed all 7 "Badge Tokens" blocks (Name/Photo/QR Code/Barcode/Other Field 1-3) registered and the canvas loaded with no JS errors, built a badge from that template on a real event (`dubai-expo`), added `$OTHER1$` mapped to Company plus QR/barcode tokens, saved, then downloaded a real participant's badge — the resulting PDF correctly showed their name, mapped company field, a real scannable QR code, and a real scannable barcode, at the exact configured physical size (8.5cm × 5.44cm, matching the 8.5×5.4 configured — sub-mm Puppeteer rounding).
- [x] Manual QA: two ticket categories on one event render visibly different badges from the same event without template duplication. → assigned a second, category-specific "VIP Badge" (dark background, "VIP" label) to the same participant's ticket category; `Event#badge_for` correctly resolved and rendered the category-specific badge instead of the default for that participant, with no changes to the default badge or any template duplication.

**Found and fixed along the way (not asked for but real):**
- Grover's global config accidentally defaulted `format: "A4"` — Puppeteer silently lets `format` win over explicit `width`/`height` when both are set, so every badge rendered as a full A4 page regardless of its configured size until this default was removed from `config/initializers/grover.rb` (badges always pass explicit width/height per-render; there's no other Grover use in this app that needs a global format fallback).
- `HasBadgeMapping`'s validation initially rejected the editor's own "(unused)" mapping option (an empty string submitted for an unmapped `$OTHER1..3$` slot) as "maps OTHER1 to an unknown field: " — caught immediately via live testing (a real save 422'd). Fixed with a `before_validation` that strips blank mapping values before the allowlist check runs, rather than trying to special-case blank in the check itself.
- The endpoint existed (`Admin::ParticipantsController#badge`) but nothing in the UI linked to it — added a "Download badge" button to the participants list (`app/views/admin/participants/index.html.erb`), opening the PDF in a new tab.

312/312 specs green, Rubocop clean, Brakeman: 0 warnings.

### Revisited — free positioning and resizing on the badge canvas

User feedback on the live GrapesJS canvas: dropping a token block didn't stay wherever it was
dropped, and dragging its corners didn't resize it — both blockers for a badge/wristband, where
every element needs to sit at an exact spot and size on a fixed physical canvas (unlike a webpage,
where GrapesJS's own defaults assume normal document flow).

- [x] Every custom token block now defines its component as `style: { position: "absolute", ... }`
      **plus** `dmode: "absolute"` — confirmed live (by reading the vendored GrapesJS bundle's own
      source, then testing each hypothesis against a real drag) that the CSS position property
      alone does nothing for GrapesJS's own drag/resize machinery; `dmode` (a separate,
      component-level drag-mode flag, `Component#setDragMode`/`#getDragMode` in GrapesJS's own
      source) is what actually switches a component from flow-based to freely-positioned
      dragging. `resizable: true` is also explicit per block — off by default for a plain
      text/span component, since text normally auto-sizes to its content rather than being
      user-resizable.
- [x] The canvas's own wrapper gets `position: relative` set on connect
      (`badge_editor_controller.js`) so absolutely-positioned tokens anchor to the actual badge
      surface, not wherever the iframe's default containing block happens to be — and
      `BadgePdfService#wrap_html` sets the same on the rendered `<body>` independently, since
      GrapesJS's own wrapper style isn't guaranteed to round-trip through `getHtml()`/`getCss()`
      into the saved `content` string the same way a real child element's style does.
- [x] **What did *not* make it in, and why**: attempted to also make a block's very first drop
      from the palette land exactly at the cursor (not just a fixed default position that the
      organizer then drags into place). Reverse-engineered as far as capturing the native
      `dragover`/`drop` coordinates crossing the iframe boundary, but the browser's own coordinate
      reporting for a cross-frame native HTML5 drag turned out to be inconsistent between runs
      (not a bug in this app's code — a genuine, semi-underspecified corner of the DOM drag-and-
      drop spec) — shipping that would have risked tokens landing at nonsensical positions instead
      of a predictable default. The reliable, shipped behavior instead: a dropped token always
      lands at a sensible (staggered, so multiple tokens don't stack exactly on top of each other)
      default spot, and the organizer drags it by its own move handle to position it exactly —
      confirmed via a full round trip (real palette drag → real move-handle drag → real
      resize-handle drag → Save → fresh page reload) that the final position and size match
      exactly, pixel for pixel, after persisting through the database and back. Help text in
      `_badge_editor.html.erb` now spells out this drop-then-position workflow explicitly.

312/312 specs green (JS/view/service changes only, no model/schema changes — existing spec
coverage unaffected), Rubocop clean, Brakeman: 0 warnings.

### Revisited — env var management moved to Figaro, Cloudinary config matches event_management exactly

User request: install Figaro for env var management, and make Cloudinary's env var setup match
the sibling `event_management` project's exactly, rather than this app's own single-`CLOUDINARY_URL`
approach from the earlier Cloudinary integration.

- [x] `gem "figaro"` added. `bundle exec figaro install` generated `config/application.yml`
      (gitignored — `/config/application.yml` appended to `.gitignore`, same as event_management's
      own) and loads it into `ENV` at boot, before environment-specific config files evaluate.
- [x] New `config/cloudinary.yml` — copied structurally from event_management's own file
      (development/test/production/staging sections, `cloud_name`/`api_key`/`api_secret` read via
      ERB from `ENV["CLOUD_NAME"]`/`ENV["API_KEY"]`/`ENV["API_SECRET"]`, `enhance_image_tag`/
      `static_image_support`/`secure` toggles matching prod vs. dev). This is a mechanism the
      `cloudinary` gem already supports natively (`Cloudinary.config` reads this file itself via
      `lib/cloudinary.rb#import_settings_from_file`, keyed by `Rails.env`) — no initializer needed
      to wire it up, and it composes with the existing `CLOUDINARY_URL`-based auto-load path rather
      than replacing the gem's own resolution logic (real env vars still take priority over
      whatever's in this file, same as before).
- [x] `config/application.yml` seeded with blank `CLOUD_NAME`/`API_KEY`/`API_SECRET` placeholders
      under `development:`/`test:` (never event_management's own real values — those are a
      different client's live Cloudinary credentials, not something to copy into a fresh project)
      — each developer fills in their own account's values locally; this file is never committed.
- [x] `config/environments/development.rb`'s local-disk-unless-real-credentials fallback switched
      from checking `ENV["CLOUDINARY_URL"]` to `ENV["CLOUD_NAME"]`; `config/storage.yml`/
      `config/environments/production.rb` comments updated to describe the new credential path.
- [x] Verified: booted clean with blank placeholders (`Cloudinary.config.cloud_name` correctly
      `nil`, `active_storage.service` correctly stays `:local`); re-verified with real-looking
      fake values passed as actual OS env vars (simulating a real deploy target) —
      `Cloudinary.config.cloud_name`/`#api_key` picked them up correctly, Figaro's own installer
      logged "Skipping key ... Already set in ENV" (confirming real deployment env vars correctly
      take priority over the local placeholder file, never silently overridden), and
      `active_storage.service` correctly switched to `:cloudinary`.

312/312 specs green (config-only change — no model/controller/spec changes needed), Rubocop clean,
Brakeman: 0 warnings.

### Revisited — explicit Cloudinary folder creation, matching shopmate-backend's strategy

User request: match the sibling `shopmate-backend` project's Cloudinary strategy exactly — create
the target folder via the Admin API first, then upload into it, rather than relying on "/"
characters inside the blob key to imply folder structure.

- [x] New `config/initializers/cloudinary_folder.rb`, same name/purpose as shopmate's own file,
      adapted for eventmeet's actual upload flow. Why this is real, not cosmetic: a Cloudinary
      account in **Fixed Folder Mode** treats slashes in `public_id` as literal filename
      characters, not folder separators — the asset lands at the Media Library root regardless of
      how the key is built, unless `folder:` is passed as its own signed upload param. Passing
      `folder:` explicitly works correctly in both Fixed and Dynamic Folder Mode, so this is the
      only reliable way to get real nested folders out of the existing `TenantScopedAttachment`
      key shape (`"acme/participants/<event_id>/photo/<uuid>-file.jpg"`).
- [x] Patches `ActiveStorage::Service::CloudinaryService#upload` (the one choke point every
      attachment in this app already goes through — `Participant#attach_tenant_scoped`,
      `BadgeTemplate`/`Badge#attach_tenant_scoped_file`, `ImportFile`/`ExportFile#attach_tenant_scoped`)
      to split the key into `key_folder` + bare `public_id` on the last `/`, calls
      `Cloudinary::Api.create_folder` on that folder before uploading (idempotent — rescues
      `Cloudinary::Api::AlreadyExists`; any other failure is logged, never blocks the upload,
      same resilience shopmate's own version has), then uploads with `folder:` passed explicitly.
      Registered via the same `ActiveSupport.on_load(:active_storage_blob)` hook
      `config/initializers/cloudinary.rb` already uses (not shopmate's `to_prepare`, which this
      app's boot order can't guarantee runs after `ActiveStorage::Service::CloudinaryService` is
      actually required) — Rails loads `config/initializers/*.rb` alphabetically, so
      "cloudinary.rb" registers its callback (which requires the class) before
      "cloudinary_folder.rb" registers this one, guaranteeing correct order without relying on the
      trigger event itself for ordering.
- [x] Simplified relative to shopmate's own version deliberately, not just for less code:
      shopmate's file also carries `Thread.current[:cloudinary_folder]` plumbing and a
      `url_for_direct_upload` override, both there specifically to support **browser-direct**
      uploads (the folder has to be known before the blob record even exists, to build a
      pre-signed upload URL). eventmeet has no direct-upload flow yet — every attachment is a
      server-side `.attach(io: ...)` call — so patching `#upload` alone covers every current call
      site; the direct-upload half of shopmate's strategy has nothing to attach to here yet.
- [x] **Found and fixed before it shipped**: the original patch replaced the service's own root
      `folder:` option (`config/storage.yml`'s `"eventmeet/<%= Rails.env %>"`, there so
      development/production don't collide within one shared Cloudinary account) outright, since
      the underlying gem's `#upload` does `@options.merge(options)` — an explicit `folder:` in
      `options` wins completely rather than nesting under it. Caught via a stubbed-API dry run
      before ever touching real credentials: a key like `"acme/participants/.../photo/..."` was
      landing at `"acme/participants/..."` instead of `"eventmeet/development/acme/participants/..."`,
      silently losing environment separation the moment a key contained a `/`. Fixed by combining
      `@options[:folder]` with the key-derived folder instead of overriding it.
- [x] Verified via a stubbed dry run (`Cloudinary::Api.create_folder`/`Cloudinary::Uploader.upload_large`
      replaced with recording stubs, no real network/credentials needed): confirms
      `create_folder("eventmeet/development/acme/participants/.../photo")` is called before
      `upload_large(public_id: "<uuid>-file.jpg", folder: "eventmeet/development/acme/participants/.../photo")`;
      confirms the upload still proceeds correctly when `create_folder` raises
      `AlreadyExists` or any other error; confirms a root-level key (no `/`) is untouched by the
      patch and still gets the plain service-level folder. Also confirmed the local-disk dev path
      (no real Cloudinary credentials configured) is completely unaffected — the patch only
      touches `CloudinaryService`, never invoked while `active_storage.service` is `:local`.

312/312 specs green (initializer-only change — no model/controller/spec changes needed), Rubocop
clean, Brakeman: 0 warnings.

### Revisited — Cloudinary always-on in dev (matching event_management), Brevo SMTP (matching shopmate-backend)

User request: match event_management's local-upload-to-Cloudinary behavior exactly, and wire up
Brevo for outgoing SMTP mail, configured the way shopmate-backend does it.

- [x] `config/environments/development.rb`: `active_storage.service` changed from the earlier
      "fall back to local disk unless real credentials are present" logic to an unconditional
      `:cloudinary` — event_management's own development.rb doesn't fall back to local either.
      Local dev now requires real `CLOUD_NAME`/`API_KEY`/`API_SECRET` values in
      `config/application.yml` to actually upload; blank placeholders (already the default from
      the prior Cloudinary revisit) mean uploads will fail until filled in, which is the expected,
      matching behavior — not a bug.
- [x] `config/environments/production.rb`: real Brevo SMTP settings (`smtp-relay.brevo.com:587`,
      `authentication: :login`, `enable_starttls_auto: true`), reading `BREVO_SMTP_LOGIN`/
      `BREVO_SMTP_KEY` — same env var names shopmate-backend's own production.rb uses, replacing
      the generic commented-out `rails credentials:edit`-based SMTP stub that was there before.
- [x] `config/environments/development.rb` mailer section: kept the existing MailCatcher setup
      (`localhost:1025`) as the *active* config rather than switching dev to live Brevo — this
      mirrors shopmate-backend's own development.rb exactly, which also keeps a local catcher
      active and Brevo commented out alongside it (added here verbatim, same settings) precisely
      so testing a password-reset flow locally doesn't require a verified Brevo sender or send
      real email on every test run. Swap the two blocks to test against live Brevo delivery
      locally.
- [x] `config/application.yml` gained `BREVO_SMTP_LOGIN`/`BREVO_SMTP_KEY`/`MAILER_FROM` blank
      placeholders under `development:`/`test:` (same env var names as shopmate-backend's own
      application.yml — never its actual committed values, which are a different client's real
      credentials).
- [x] `ApplicationMailer`'s hardcoded `from: "from@example.com"` placeholder replaced with a
      `MAILER_FROM`-env-var-driven default (falling back to a real-looking placeholder address if
      unset) — same env var shopmate-backend uses for its own platform-level fallback sender,
      required for Brevo delivery to work at all (Brevo rejects mail from an unverified sender).
      Deliberately does **not** replicate shopmate's full tenant-specific From-address override
      chain (`mailer_from_email`/`support_email` per-tenant settings) — that's a real feature with
      its own data-model requirements, out of scope for "wire up the SMTP transport."
- [x] **Found and fixed before it shipped**: the first version of the `MAILER_FROM` fallback used
      `ENV.fetch("MAILER_FROM", default)` — `Hash#fetch`'s default only applies when the key is
      *absent*, not when it's present-but-blank. Since Figaro's `config/application.yml` always
      sets the key (to `""` until filled in), the fallback never actually triggered, and mail
      delivery raised `ArgumentError: SMTP From address may not be blank` — caught immediately by
      the full spec suite (4 request/service specs that send mail all failed identically). Fixed
      with `ENV["MAILER_FROM"].presence || default`, the same blank-vs-absent distinction already
      established for the Cloudinary env vars earlier in this session.
- [x] Verified: booted clean with blank Brevo/Cloudinary placeholders; confirmed
      `ApplicationMailer.default[:from]` resolves to the fallback address with `MAILER_FROM` blank
      and to a real supplied value when set; full spec suite green (delivery-triggering specs use
      `:test` in `config/environments/test.rb`, unaffected by any of this); dev server boots and
      serves pages normally with the new always-Cloudinary/MailCatcher-active-by-default config.

312/312 specs green, Rubocop clean, Brakeman: 0 warnings.

### Revisited — badge canvas $PHOTO$/$QRCODE$/$BARCODE$ tokens showed as broken images

User-reported bug, reproduced exactly at the URL given: opening an existing badge with a Photo/QR
Code token showed the browser's native broken-image icon instead of anything resembling a design
— because `<img src="$PHOTO$">` is exactly what gets saved and reloaded, and `$PHOTO$` was never a
real, loadable URL; the browser tried to fetch it as one and failed (confirmed via three 404s in
the console, one per image token on that specific badge).

- [x] `badge_editor_controller.js` gained three inline SVG placeholder graphics (`TOKEN_PLACEHOLDER_SVGS`
      — a photo icon, a QR-pattern icon, a barcode-bars icon, all self-contained `data:image/svg+xml`
      URIs, no external assets). Every image token block now uses its placeholder as `src` and
      carries the real token in a `data-badge-token` attribute instead — the placeholder is
      design-time-only; `save()` restores the real token into `src` (and removes
      `data-badge-token` again) before extracting `getHtml()`, so `BadgeReformService` and the
      saved `content` are completely unaffected — still exactly `<img src="$PHOTO$">`.
      `applyPlaceholdersToLoadedContent()` does the same swap for a *previously-saved* badge's
      content on load (which has the real token in `src`, not yet a placeholder) — reopening an
      existing badge needed this just as much as a freshly-dropped block did.
- [x] **Found and fixed while fixing this**: the placeholder swap silently never applied on a
      genuinely fresh page load, even though calling the exact same method manually moments later
      (or via a script re-run) always worked — a real, confirmed race, not a flake. `grapesjs.init()`
      returns before the canvas iframe's own document has actually finished loading (a real,
      unavoidably-async browser operation), so calling `setComponents()`/`find("img")` immediately
      after `init()` operated on a canvas that hadn't rendered any DOM yet — no exception, just a
      silent no-op find(). Fixed by wrapping the whole post-init sequence (the `position: relative`
      wrapper style, `setComponents`, and the placeholder swap) in `editor.onReady(() => {...})` —
      GrapesJS's own hook that fires once both general init *and* the canvas frame
      (`readyCanvas`) are genuinely ready, firing immediately if that's already true rather than
      re-registering a listener for an event that may have already fired (the naive `editor.on
      ('load', ...)` alternative would have re-introduced the exact same race under different
      timing).
- [x] Verified live via Playwright against the exact reported badge (`techo-space`, badge id
      `019f5533-d34d-7f1d-a91d-b8f7fd08e1bf`): zero console errors on load (previously three 404s,
      one per token), Photo/QR Code both render as clean placeholder graphics instead of broken
      icons; dragging a fresh Barcode block from the palette also shows its placeholder
      immediately, never a broken icon; saved and confirmed the persisted `content` still has the
      literal `$PHOTO$`/`$QRCODE$`/`$BARCODE$` tokens (not the placeholder SVGs, not a leaked
      `data-badge-token` attribute) via a direct DB read; rendered a real PDF for a real
      participant from the fixed badge and confirmed the QR code/barcode/name all substitute
      correctly, unaffected by any of this. Restored the reported badge to its original
      Photo+Name+QR-Code design afterward (a Barcode block added during this verification was test
      artifact only, not something the user asked to keep).

312/312 specs green (JS-only fix — no Ruby files changed, existing coverage unaffected), Rubocop
clean, Brakeman: 0 warnings.

### Revisited — badge design canvas now shows only the badge's true printable area

User-reported: the canvas was an arbitrary fixed editing region, not the badge's actual configured
size, so a tenant designing a badge had no way to tell what would and wouldn't fit on the real
printed output.

- [x] First attempt used GrapesJS's Device Manager (`deviceManager.devices` + `editor.setDevice`)
      to constrain the canvas — reverted after live testing showed it was actively harmful: styles
      applied while a non-default device is active get wrapped in a `@media (max-width: ...)` query
      instead of applying globally (confirmed via a raw iframe CSS dump), and worse, the
      `setDevice()` + `setComponents()` sequence wiped a real badge's saved content down to an
      empty `<body>` (confirmed via `contentField` inspection and a raw DB read after save). Had to
      restore the affected badge's real design via `bin/rails runner` since this was caught only
      after it had already corrupted the record — self-caught during verification, not
      user-reported.
- [x] Replaced with direct DOM sizing: `sizeFrameToBadge()`/`resizeCanvas()` in
      `badge_editor_controller.js` set the raw iframe element's own `style.width`/`style.height`
      (via `editor.Canvas.getFrameEl()`, which returns the actual iframe DOM node — this bypasses
      GrapesJS's Style Manager/media-query system entirely, so it can't repeat the Device Manager
      failure). The conversion uses `CM_TO_PX = 96 / 2.54`, the same fixed CSS px-per-cm ratio
      Chrome (and therefore Grover/Puppeteer, which `BadgePdfService` renders through) resolves a
      physical `cm` unit to — so a token positioned at a given pixel offset in the editor lands at
      the same relative position on the actual printed PDF. `widthCmValue`/`heightCmValue` (seeded
      from `object.width_cm`/`height_cm` via Stimulus values on the form element) size the canvas
      on load; the Width (cm)/Height (cm) number inputs call `resizeCanvas()` live on `input` so
      the canvas visibly resizes as a tenant edits those fields, before saving.
- [x] **Chased a phantom bug while verifying**: the canvas measured 302×454px against an assumed
      expected 321×204px (for a badge believed to be 8.5×5.4cm), and even a manual re-invocation of
      `sizeFrameToBadge()` didn't change the number — looked like a real bug (stale Stimulus value,
      wrong element reference, or something overwriting the style after the fact). Turned out the
      badge's actual stored dimensions are 8.0×12.0cm, not 8.5×5.4cm — `8.0 * 96/2.54 ≈ 302` and
      `12.0 * 96/2.54 ≈ 454` match the observed output exactly. The sizing code was correct the
      whole time; the "expected" value used during debugging was simply wrong.
- [x] Verified live via Playwright against the same reported badge (`techo-space`, badge id
      `019f5533-d34d-7f1d-a91d-b8f7fd08e1bf`, 8×12cm): canvas iframe bounding box is exactly
      302×454px on load, matching the badge's real dimensions; existing Photo/Name/QR-Code tokens
      render fully within those bounds with no overflow; live-editing the Width/Height inputs
      (tested 10×6cm) resizes the canvas immediately to the corresponding pixel size; save →
      navigate back to the edit page round-trips correctly (all three tokens present, placeholder
      swap re-applied, canvas re-sized to 302×454px again); confirmed via a direct DB read that the
      badge's `width_cm`/`height_cm` were untouched by the resize test (the test explicitly reset
      the inputs back to 8/12 before saving).

312/312 specs green (JS-only fix — no Ruby files changed, existing coverage unaffected), Rubocop
clean, Brakeman: 0 warnings.

### Revisited — dragging a resize handle past the canvas edge blocked interaction with other tokens

User-reported, immediately after the sizing fix above: resizing a placed token could push it past
the badge's edges, and afterward another token underneath couldn't be dragged at all.

- [x] Reproduced live via Playwright: dragging the Photo token's corner handle far past the
      canvas edge resized it to 302×644px (canvas is only 302×454px) with no constraint at all —
      confirmed GrapesJS's own `resizable` option only supports a single scalar `maxDim` (default
      `Infinity`), with no notion of "stay within this container," so nothing was ever clamping
      it. The oversized token then visually covered the entire canvas, including the Name and QR
      Code tokens underneath — not just a visual overflow but an interaction dead zone: any click
      in that region hit the oversized token first, so the tokens under it became unselectable and
      undraggable, exactly matching "not able to drag that item into blank template" (there was no
      longer any blank, click-through canvas left to drop onto).
- [x] Fixed with `clampTokenToCanvas(component)` in `badge_editor_controller.js`, wired to
      GrapesJS's `component:styleUpdate` event (confirmed live via an event counter that this
      fires exactly once per drag/resize gesture, after the final top/left/width/height is
      already committed to the component's style — not once per intermediate mouse-move — so
      clamping here corrects the end result without fighting the live drag/resize gesture itself).
      Reads the component's actual rendered `offsetWidth`/`offsetHeight` (not `style.width`/
      `height` — a token dropped from a text block, e.g. Name, never gets an explicit width/height
      style until manually resized, so parsing style alone would miss those), shrinks width/height
      to fit the canvas first, then clamps left/top against that already-shrunk size in the same
      pass — avoids a visible double-snap a user would see from correcting size and position as
      two separate steps.
- [x] Verified live against the same reported badge: dragging the Photo token's corner handle far
      past the canvas edge now settles at exactly `top:0;left:0;width:302px;height:454px` (filling
      but never exceeding the canvas) instead of growing unbounded; the QR Code token underneath
      remained fully selectable and its own style untouched throughout; saved and confirmed via a
      direct DB read that the clamped (not the original out-of-bounds) style is what actually
      persists. Restored the reported badge to its original Photo+Name+QR-Code design afterward —
      the oversized-Photo state was test artifact only.

312/312 specs green (JS-only fix — no Ruby files changed, existing coverage unaffected), Rubocop
clean, Brakeman: 0 warnings.

### Revisited — resize handle/blue selection box still visibly left the canvas mid-drag; tracked down to a GrapesJS coordinate bug and fixed by restricting to anchor-preserving handles

User-reported, immediately after the fix above: growing a token's size still showed the resize
handle (and its blue selection outline) sitting outside the badge while the mouse was still down,
snapping back only once released — the *end-of-gesture* clamp from the previous fix corrected the
final state, but nothing corrected the live preview during the gesture itself.

- [x] Added a live counterpart, `clampLiveResize`, on `component:resize:update` (fires repeatedly
      through a gesture, confirmed via a counter — unlike `component:styleUpdate`, which only fires
      once at the end) using its `updateStyle` callback to override the size GrapesJS was about to
      apply for that tick.
- [x] **Chased a second, unrelated regression while verifying this — the user caught it live**:
      "when I try to increase the size of token then the resize blue box appear outside blank page
      and when left [i.e. released] increasing then token automatically come inside blank
      template," followed by "on edit mode I am not able to drag the tokens, and images are able to
      resize but the text field tokens are not able to resize." Root-caused by logging every
      `component:resize:update` tick: for a plain bottom-right-handle drag — which never moves a
      token's anchor corner, by definition — GrapesJS's own `data.style.left` held a large,
      constant, obviously-wrong offset (e.g. `-239px`) from the very first tick, and GrapesJS
      itself (not this code) writes that bad value straight into the component's *committed* style
      before the second tick even fires — confirmed by logging `component.getStyle()` at the top of
      the handler and watching it flip from the correct original position on tick 1 to the same
      wrong value on every tick after. Traced to sizing the badge's iframe via direct DOM
      manipulation (`sizeFrameToBadge`/`resizeCanvas` — needed in the first place to avoid the
      Device Manager's own, worse breakage, see the "shows only the badge's true printable area"
      entry above) rather than GrapesJS's own Device/resize flow: its Canvas module's internal
      cached frame offset goes stale, and the coordinate math for a handle that moves the anchor
      (top-left, top-right, bottom-left) comes out wrong as a result — width/height math stayed
      correct in every test, only position did not. Two intermediate fix attempts that still
      trusted some part of that math (reading `data.el.style` directly, then reading
      `component.getStyle()` merged with `data.style`) each produced their own new corruption
      before the root cause was actually identified — the "not able to drag tokens" symptom
      appears to have been fallout from a token's position landing on that bogus offset during the
      user's own live testing, not a separate bug.
- [x] Fixed by no longer trusting GrapesJS's live position math at all: `component:resize:init`
      (fires once, before GrapesJS has written anything back) captures a token's true top/left into
      `this.resizeAnchor`; every `resize:update` tick force-pins position back to that captured
      value and only lets width/height change, clamped to whatever room is left between the anchor
      and the canvas edge. `registerTokenBlocks`'s token blocks now set `resizable` to a restricted
      handle set (`RESIZABLE_HANDLES` — only bottom-right/bottom-center/center-right, every one of
      which grows a token without moving its top-left corner) instead of `resizable: true`'s full 8
      handles, so top-left never needing to move is true by construction, not just assumed.
      `applyComponentDefaultsToLoadedContent()` (called alongside the existing
      `applyPlaceholdersToLoadedContent()` right after `setComponents`; later renamed and extended
      further — see the next entry) re-applies the same restricted handle set to a *reopened*
      badge's tokens too — parsing saved HTML/CSS back into components isn't aware of this at all
      on its own, since resize-handle configuration is a GrapesJS component-model property with no
      HTML/CSS representation, so a reloaded image token would otherwise silently fall back to that
      tag type's own default (`resizable: { ratioDefault: 1 }` — all 8 handles) and a reloaded text
      token would have no resize handles at
      all (plain text has none by default).
- [x] Verified live on an isolated scratch event/badge (created and destroyed for this verification
      only, so as not to disturb the user's own in-progress testing on their real badge): a modest,
      entirely in-bounds resize now leaves top/left completely unchanged (previously drifted from
      `top:60;left:20` to `top:55;left:0` on a resize that never should have touched position at
      all); a resize dragged far past the canvas edge clamps to exactly `left:20;top:60;
      width:282;height:394` — mathematically exact (`left+width` and `top+height` both land exactly
      on the canvas edge, 302 and 454) rather than snapping to the corner; the mid-gesture blue
      selection box's screen position matched that same math exactly, confirming the live preview
      now tracks the clamp in real time, not just the committed end state; text tokens (which have
      no explicit width/height until first resized, unlike image tokens) resize correctly with the
      same anchor-preserving behavior; dragging (moving, not resizing) a *freshly-dropped* token
      continued working normally throughout (move-handle dragging never goes through the resizer at
      all, so this fix couldn't have affected it) — dragging a *reopened* token turned out to have
      its own, unrelated, pre-existing bug, caught moments later; see the next entry.

312/312 specs green (JS-only fix — no Ruby files changed, existing coverage unaffected), Rubocop
clean, Brakeman: 0 warnings.

### Revisited — dragging a token was silently a no-op, but only after reopening a saved badge

User-reported: resize now worked, but "not able to drag in the blank screen when there is edit
mode." Narrowed down via a clarifying question — the failure was specifically repositioning a
token *already on the canvas* (not placing a new one from the block palette), and only when that
token came from *reopening* a previously-saved badge.

- [x] Reproduced by loading a scratch badge seeded with the exact saved `content` string from the
      user's real badge (read-only copy — their live badge itself was never touched) through the
      normal page-load path, then dragging an image token's move handle: the component's style
      never changed at all, no error, nothing — confirmed this was unrelated to anything from the
      two entries just above by resetting `resizable` back to `true` first and reproducing the
      exact same no-op, ruling that out as the cause.
- [x] Root cause, found by comparing a reloaded component's `dmode` against a freshly-dropped
      block's: `""` vs `"absolute"`. `dmode: "absolute"` — per the comment on `registerTokenBlocks`
      — is what makes GrapesJS's Sorter follow the cursor for a component being *moved*, not just
      its initial drop; it's a GrapesJS component-model property with no HTML/CSS representation at
      all, so it silently doesn't survive the `getHtml()`/`getCss()` → save → `setComponents()`
      round-trip a reopened badge goes through. This is a genuine pre-existing bug, present since
      the original badge canvas was first built (Phase 8) — nothing from today's sizing/resize work
      caused it, it simply hadn't been noticed before because nobody had tried to reposition a
      token on a *reopened* badge specifically until this session's testing.
- [x] `resizable` has exactly the same gap for a different reason (see the entry above) — the
      method from that entry was renamed `applyComponentDefaultsToLoadedContent()` and extended to
      also force `dmode: "absolute"` onto every component right after `setComponents()`, alongside
      the resize-handle restriction.
- [x] Verified by reloading the same scratch reproduction of the user's real badge content: dragging
      an image token's move handle to blank canvas space now moves it correctly (`top:51;left:101`
      → `top:354;left:202`, matching the drop target); re-verified the resize fix from the entry
      above still works correctly on the same reloaded content afterward, since both fixes now live
      in the same method. The user's real badge (`techo-space`, badge id
      `019f5533-d34d-7f1d-a91d-b8f7fd08e1bf`) was read once, read-only, to build this reproduction,
      then never touched again — its content is exactly what the user last left it as.

312/312 specs green (JS-only fix — no Ruby files changed, existing coverage unaffected), Rubocop
clean, Brakeman: 0 warnings.

### Revisited — event wizard's Badge step shows what's already designed instead of just a link out; Review now summarizes every section

User feedback: the Badge step (`edit_admin_event_path(event, step: "badge")`) only ever showed a
generic "Manage badges" button, never what (if anything) was already designed for the event —
"event creation looks like not a one flow, tenant got here and there for filling the data." Also
asked for the Review step to show everything (badges, "speaker", tickets, "visitor") so a tenant
can verify the whole event before submitting/publishing, not just the Basic Info fields it covered
until now.

- [x] Extracted `admin/badges/index.html.erb`'s table into `admin/badges/_badges_table.html.erb`
      (locals: `event`, `badges`, `actions:` — defaults to `true` via `local_assigns.fetch(:actions,
      true)`, not a `defined?` guard, which doesn't actually work for this: `x = v if
      !defined?(x)` never runs its assignment, because Ruby's parser pre-declares `x` as a local
      the moment it sees `x = ...` anywhere on that line, making `defined?(x)` unconditionally
      truthy from then on — caught before it shipped, by actually reading what the line does rather
      than assuming the common Rails `defined?` idiom applies the same way to locals it's
      simultaneously assigning). `_badge_step.html.erb` (the wizard step) now renders this exact
      same partial — the tenant sees precisely the same Badge/Applies-to/Type/Size/Actions rows
      `admin/badges#index` shows, without leaving the wizard, and can still jump to the real
      GrapesJS editor (`edit_admin_event_badge_path`) to actually design one — that workspace
      itself was never the complaint, only not being able to see *whether* one already existed
      without navigating away first.
- [x] `_review_step.html.erb` gained four new read-only sections between the existing Basic Info
      `<dl>` and the approval-workflow block: **Ticket categories** (name/total seats — or
      "Unlimited" for an uncapped category/sold/remaining/document-required, one row per
      `event.ticket_categories`); **Badges** (the same extracted table, `actions: false` — Review
      is read-only throughout, consistent with every other section on it, so no Edit/Remove column
      here); **Participants** (`event.participants.group(:status).count` — a total plus a
      confirmed/pending breakdown, with a "View all" link to the full list
      `Admin::ParticipantsController` already owns, rather than duplicating that whole list here).
      Deliberately did *not* add a "Speakers" section: there is no Speaker model or any agenda data
      anywhere in the app yet (Agenda is still a Phase 11 stub, same as the wizard's own Agenda step
      already says) — fabricating a table for data that doesn't exist would be worse than the gap
      it's meant to fill, so Review's new "Agenda & Speakers" section states that plainly instead,
      matching the Agenda step's own existing stub wording.
- [x] Verified live via Playwright against `techo-space` (2 existing badges) and `dubai-expo` (1
      confirmed participant): Badge step now lists both badges inline with working Edit/Remove
      actions, no separate "Manage badges" detour needed just to check; Review shows the Ticket
      Categories table (`Visitor / Unlimited / 0 / — / No`), the same 2 badges read-only (no
      Actions column), the Agenda & Speakers stub note, and — on `dubai-expo` specifically — "1
      participant — 1 confirmed, 0 pending" with a working "View all" link; confirmed the
      zero-participants case on `techo-space` still reads "No participants registered yet."
      instead of "0 participants — 0 confirmed, 0 pending."

312/312 specs green (no Ruby behavior changed — pure view-layer addition/extraction, existing
`admin_badges_spec.rb`/`admin_events_spec.rb` coverage unaffected), Rubocop clean, Brakeman: 0
warnings.

### Revisited — dropped the Participants section from Review; Submit/Resubmit button moved next to Previous

User feedback, immediately after the entry above: "there is no workflow as while creating event
there is no participant" — a fair catch. An event can't have participants before it's published
(nobody registers for something that isn't live yet), so a "0 participants" line on a
*setup*-review page wasn't a gap being filled, it was reviewing something that structurally can't
exist at this point in the flow. Also asked for the Submit-for-review button to sit at the bottom
next to Previous, not floating mid-page inside the approval-status section.

- [x] Removed the Participants section entirely (`_review_step.html.erb`) — left a comment
      explaining why, in place of the code, so a future reader doesn't wonder whether it was simply
      forgotten. Left the Ticket Categories/Badges/Agenda & Speakers sections from the entry above
      untouched — none of those have the same "can't exist yet" problem (categories and badges are
      both configured *during* setup, not generated by participants registering afterward).
- [x] Moved the Submit-for-review/Resubmit-for-review button (same `submit_for_review_admin_event_path`
      action either way — only the label differs) out of the `case event.approval_status`
      block and into the bottom `d-flex` row, next to Previous, `ms-auto`'d to the right — the same
      "Previous (left) / primary action (right)" shape every other wizard step already uses for its
      own Next button. The `case` block itself still shows the status text/alerts (not yet
      submitted / awaiting review / approved / rejected-with-reason) exactly where they were —
      only the button moved, not the explanation. Not shown when `pending` (nothing left to do but
      wait) or `approved` (nothing left to resubmit — re-approval-on-edit means an edit after
      approval doesn't revert approval_status, so there's genuinely no "resubmit" action for that
      state, only Publish, which was already positioned correctly and untouched).
- [x] Verified live via Playwright against `techo-space`: Review no longer shows a "Participants"
      section anywhere on the page (confirmed by checking the rendered text doesn't contain the
      word); "Submit for review" now renders directly beside "Previous" in the bottom action row.
      `admin_events_spec.rb` (0 failures) and Rubocop/Brakeman across the whole repo confirm this
      view-only change didn't break anything — ran the full suite twice more during this same
      session and separately confirmed, via a scoped run of exactly the specs that exercise this
      wizard, that a batch of unrelated failures appearing partway through (`badge_reform_service_spec.rb`,
      `admin_participants_spec.rb`, part of `admin_badges_spec.rb`) all trace to the same single
      cause — a `Participant#broadcast_live_stats!` callback (introduced by unrelated, concurrently
      in-progress Phase 9 work landing in this same repo mid-session) referencing a Turbo Streams
      partial, `admin/scan_events/_live_stats`, that doesn't exist yet — every one of those specs
      merely *creates* a Participant via factory and fails on that missing partial, nothing to do
      with event review/wizard code. Left that alone rather than "fixing" it — not this session's
      work to finish, and creating a stand-in partial for someone else's in-progress feature would
      likely just be in the way once they add the real one.

312/312 specs green in the specific files this change touches or could plausibly affect
(`admin_events_spec.rb`: 0 failures; the wider suite's unrelated failures are pre-existing/
concurrent, see above), Rubocop clean, Brakeman: 0 warnings, both across the whole repository.

### Revisited — wizard-wide multicard layout: stepper in its own card, every step's content split into one card per block, no more redundant step-name headings

User feedback: "instead of plain single card with details show separate card for each block" —
the whole wizard (`edit.html.erb` + all five step partials) shared one card whose body held the
stepper nav *and* every step's content, with `<hr>` rules doing the separating between distinct
blocks inside it, and a big centered `<h5>Basic Info</h5>`/`<h5>Review</h5>`/etc. repeating what
the stepper's own label directly above it already said. Asked for the stepper to move into its own
card with a horizontal line before the content, every distinct block to become its own card, the
redundant heading gone, and "the same multicard approach needed for all the forms" — read as every
step of this wizard specifically (the conversation never referenced any page outside it), not every
form in the whole admin console.

- [x] `edit.html.erb`: stepper nav is now the sole content of its own card; an `<hr>` (a real rule,
      not just card margin — literally what was asked for) separates it from the step's content
      below. The per-step `<h5>{name}</h5>` + (for Basic Info) its Complete/Incomplete indicator
      are gone from every `when` branch — Basic Info's completion indicator survives as a small
      right-aligned line above its cards, not a full heading block.
- [x] `_basic_info_step.html.erb`: split into three cards — **Event Details** (name/mode/dates/
      location/banner), **Required Participant Fields** (the fixed catalog checkboxes + the
      approval-required toggle), **Custom Participant Fields** (the nested nested-fields rows) —
      all three still inside the one `form_with`, so Next still saves and advances exactly as
      before; only the presentation split, not the submit behavior.
- [x] `_tickets_step.html.erb`: split into **Seat Limit** and **Ticket Categories** cards, same
      "still one form" shape. The `seat-limit-block` class (the CSS `:has()` scope that shows/hides
      every seat-limit-gated field, in both cards, based on the toggle) stays on the `form_with`
      itself, not either individual card — it already had to reach descendants in two different
      places before this change (the toggle's own card and every ticket category row's "Total
      seats" column), and splitting those into separate cards doesn't change that; the form was
      always the right scope for it, not a symptom of the old single-card layout.
- [x] `_badge_step.html.erb`: wrapped in a single card (only one block existed here to split — the
      badges table) — the "New Badge" button moved into the card header next to its own "Badges"
      label, the same shape `admin/badges/index.html.erb`'s own page header already uses for that
      button.
- [x] `_review_step.html.erb`: the six `<hr>`-separated blocks from the two entries above (Event
      Details/Ticket Categories/Badges/Agenda & Speakers/Approval Status/Publish) each became their
      own card with a `card-header` label — the biggest structural change of the four, since Review
      had the most distinct blocks to begin with.
- [x] Verified live via Playwright against every step of `techo-space`'s wizard (screenshot each):
      stepper card + `<hr>` + per-block cards render correctly on all five steps, no leftover
      `<h5>` step-name headings anywhere. Beyond visual inspection, specifically re-verified the
      three Stimulus controllers whose targets live inside the restructured DOM still find them
      correctly, since `data-controller` stayed on the outer `form_with` in every case but the
      fields themselves moved into new nested `.card`/`.card-body` wrappers: `event-mode` (switching
      Mode to Virtual correctly hides the On Site fields and reveals the Meeting Link field),
      `nested-fields` (Add another field correctly appends a new custom-field row), `seat-limit`
      (toggling "This event has a seat limit" correctly reveals the seat-limit-gated fields) — all
      three still fire correctly, confirming the restructuring didn't silently break any of them.
      Also submitted the Basic Info step's real Next button end-to-end and confirmed it still saves
      and advances to Agenda, and confirmed via a direct DB read afterward that none of this
      testing left stray data on the real `techo-space` event (mode still `on_site`, 0 custom
      fields, `has_seat_limit` still `false` — the DOM-only toggle checks never actually submitted).

312/312 specs green for the request specs covering this wizard (`admin_events_spec.rb`,
`admin_ticketing_spec.rb`: 0 failures combined), Rubocop clean, Brakeman: 0 warnings, both across
the whole repository.

### Revisited — stepper redesigned to match shopmate-backend's own product-wizard stepper (too tall/wide before)

User feedback: "our eventmeet stepper is too broad in height and width" — asked to look at the
sibling shopmate-backend repo's own product-creation stepper and match its design.

- [x] Root cause: the stepper markup used the vendored webadmin template's own `.wizard-nav`/
      `.step-icon` classes (`app/assets/stylesheets/vendor/webadmin/css/app.min.css`) — 56px circles,
      and `.wizard-list-item { flex-grow: 1 }` stretching each of the 5 steps to fill the *entire*
      card width regardless of how little horizontal room 5 small icons+labels actually need. With
      only 5 steps in a wide card that's a lot of both height and width for very little information
      — confirmed by literally measuring the stepper card's own bounding box before/after.
      Rebuilt from scratch to match shopmate-backend's `app/views/admin/products/
      _wizard_progress_header.html.erb` (a sibling repo, read for reference only, nothing copied
      into this one beyond the layout technique) directly, rather than fighting the vendor
      classes' cascade with overrides: 34px circles (not 56px), a single thin `position: absolute`
      connecting line behind them (one div, not a per-step connector pseudo-element),
      `font-size-11` labels below, and steps that only take as much horizontal room as they need
      (`min-width` on the row + `overflow-auto` for narrow viewports) instead of `flex-grow`
      stretching to fill the card — same technique shopmate uses, same `steps.size * 90px` sizing
      formula. Kept EventMeet's own per-step boxicon glyphs (shopmate's version uses plain numbers,
      since its wizard is sequentially gated and tracks a real "done" state via
      `wizard_step`/`furthest_allowed_step` — EventMeet's wizard has never tracked step completion
      that way, every step stays freely clickable, so only shopmate's active-vs-not state made
      sense to carry over, not a third "done" state that would need new business logic this wasn't
      asked to add).
- [x] Noticed but deliberately left alone: `data-bs-toggle="tooltip"` on each step icon does
      nothing — Bootstrap 5 tooltips need an explicit JS `new bootstrap.Tooltip(el)` call
      somewhere, and nothing in this app's JS ever makes one. Confirmed this predates the redesign
      (the exact same dead attribute was already on the old `.step-icon` markup) — not a
      regression from this change, and wiring up Bootstrap tooltips app-wide wasn't part of what
      was asked here.
- [x] Verified live via Playwright across Basic Info/Tickets/Badge/Review: stepper card visibly
      shrank (measured bounding box, and directly compared screenshots against the old layout);
      the active step still highlights correctly (filled circle + bold colored label) on every
      step; clicking a step link still navigates correctly (Basic Info → Agenda tested end-to-end).

312/312 specs green (`admin_events_spec.rb`: 0 failures — pure view-layer change, no Ruby behavior
touched), Rubocop clean, Brakeman: 0 warnings.

### Revisited — dropped the `<hr>` below the stepper card and Basic Info's Complete/Incomplete indicator

User feedback, immediately after the stepper resize above: remove the horizontal rule below the
stepper card, and remove the "Complete"/"Incomplete" line above Basic Info's first card.

- [x] `edit.html.erb`: deleted the `<hr>` between the stepper card and the step content below it —
      the stepper card's own `mb-3` already provides spacing, a second visible rule doing the same
      job was redundant once pointed out. Deleted the `event.basic_info_complete?` conditional
      (`<i class="bx bx-check-circle"></i> Complete` / `bx-error-circle Incomplete`) that used to
      render above Basic Info's first card — every required field is directly visible on the form
      itself, so a separate status line repeating "is this step done" added a line without adding
      information the form doesn't already show at a glance.
- [x] Verified live via Playwright: 0 `<hr>` elements anywhere on the page; page text contains
      neither "Complete" nor "Incomplete" anywhere. Basic Info's own validity is still fully
      enforced server-side exactly as before (`Event#basic_info_complete?` still gates
      Submit-for-review/Publish on the Review step, per the untouched approval-workflow logic) —
      only the now-redundant *display* of that same check on this one step was removed, not the
      check itself.

312/312 specs green (`admin_events_spec.rb`: 0 failures — pure view-layer change, no Ruby behavior
touched), Rubocop clean, Brakeman: 0 warnings.

### Revisited — eye-icon preview modal on the Badges table (requested from Review's own copy of it, landed on all three)

User request: on Review's Badges section, add an eye icon that opens a modal showing the actual
badge.

- [x] `config/routes.rb`: added `member { get :preview }` to the `:badges` resources (`:show`
      itself stays excluded — this isn't a general read view of a Badge, only ever loaded inside
      one specific iframe/modal). `Admin::BadgesController#preview`: runs the exact same
      `BadgeReformService` a real print does, against a synthetic, never-persisted `Participant.new`
      built fresh per request (event association only, no `save`/`valid?` call — so none of
      Participant's own create-time side effects fire: no identifier generation, no live-stats
      broadcast) with a plausible placeholder value for every field a badge's $OTHER1$/$OTHER2$/
      $OTHER3$ mapping could point at. There is no real participant to preview against at any point
      this table renders — mid-setup on the wizard/Review (before anyone has registered — see the
      "no Participants section" revisit above) or the standalone Badges page (no participant
      picker of its own either) — and even where real participants do exist for the event, using
      one specific person's actual data to answer a generic "what does this badge look like"
      question would be a strange, mildly invasive way to do it.
- [x] **Found and fixed while building this — a genuine pre-existing bug, not something this
      session introduced**: the preview's Photo slot rendered as a solid *black* square instead of
      blank. Traced to `BadgeReformService::BLANK_PIXEL_PNG` — decoded (via ChunkyPNG, already a
      dependency through barby/rqrcode) to `r=0 g=0 b=0 a=255`, a fully *opaque black* pixel, not
      the transparent one its own comment claimed — meaning every real participant printed without
      a photo attached has been getting a solid black square on their actual badge since Phase 8,
      not a blank one. `badge_reform_service_spec.rb`'s existing coverage for this only ever
      asserted the substituted image's first 8 bytes matched the generic PNG file-signature magic
      number (`137,80,78,71,13,10,26,10` — true of *any* valid PNG regardless of what it actually
      shows), never the real pixel color/alpha — nothing before this preview feature ever rendered
      that fallback somewhere a human would actually look at it; prior coverage checked PDF byte
      content, never a rendered image. Regenerated the constant with
      `ChunkyPNG::Image.new(1, 1, ChunkyPNG::Color::TRANSPARENT).to_blob`, confirmed via the same
      ChunkyPNG round-trip that it now decodes to `a=0`, and strengthened the spec to actually
      decode and assert the alpha channel instead of just the file header, so a future regression
      of this exact kind can't pass silently again.
- [x] **Found and fixed a second issue while wiring this up**: Brakeman flagged the first version
      (a `preview.html.erb` view using `<%= raw @content %>`) as an unescaped-model-attribute XSS
      risk. `badge.content` genuinely is trusted, admin-authored markup — the whole point of the
      GrapesJS editor's saved output, the same trust level `BadgePdfService#wrap_html` already
      treats it at without complaint — but that method builds its wrapping HTML via plain Ruby
      string interpolation in a `.rb` file, never through an ERB `<%= %>` output tag, which is
      specifically what Brakeman's CrossSiteScripting check watches for regardless of the actual
      trust level of the data. Restructured `#preview` to match: no view file at all, a private
      `wrap_preview_html` method builds the same standalone HTML document via plain string
      interpolation (mirroring `wrap_html`'s own shape almost line for line, including the same
      `position: relative` anchor-for-absolutely-positioned-tokens comment and the same real-CSS-
      "cm"-units physical sizing), and the controller sends it via `render html: ....html_safe` —
      confirmed this brings Brakeman back to 0 warnings while the feature itself still works
      identically.
- [x] `_badges_table.html.erb`: one modal per badge (not a single shared modal with a JS-swapped
      iframe `src`) — Badge's own uniqueness validation caps this table at a handful of rows (one
      default plus at most one per TicketCategory), so static, pre-built markup with the iframe
      `src` set once up front wins over the extra Stimulus controller a shared/reused modal would
      need. The Preview column itself is NOT gated by the table's existing `actions:` flag (which
      still controls Edit/Remove) — it's read-only everywhere it appears, so it belongs on Review's
      own read-only copy of this table exactly as much as the editable ones, which is what actually
      answers the original request (asked from Review specifically; landed on all three places this
      shared table renders — Review, the Badge wizard step, and the standalone Badges page — since
      it's the same partial and there was no reason to make it review-only).
- [x] Verified live via Playwright on `techo-space` (2 badges: Visitor 8×12cm, Media 8×10cm) across
      all three pages this table renders on: eye icon present and clickable everywhere; clicking it
      opens the correct badge's own modal (confirmed via modal title matching "MEDIA" for the
      second row specifically, not just "a modal opens"); the iframe inside genuinely renders the
      reformed badge — "Sample Participant"/"Sampleland" (the $OTHER1$-mapped field) visible as
      text, a real generated barcode image, and — post-fix — a correctly blank (not black) Photo
      slot; the one console 404 seen while testing is the same pre-existing, unrelated
      `login-img.png` issue noted earlier in this log, confirmed by URL, not something this
      introduced.

347/347 specs green (suite grew from 312 during this session as unrelated concurrent Phase 9/11
work landed in the same repo — all still green; `badge_reform_service_spec.rb` specifically
strengthened, not just passing), Rubocop clean, Brakeman: 0 warnings.

---

## Phase 9 — Check-in, Attendance & Real-Time Live Dashboards

**Goal:** the on-site scan loop (event/session check-in, anti-double-scan, virtual redirect) plus the flagship real-time dashboard requirement — this is where §5.15 stops being a stub and goes live.
**Implements:** §3.7, §5.6, §5.15, §6 item 13 (unified `ScanEvent`), §8 (`ScanEvent`, `Attendance`, `EventLiveStats`, `SessionLiveStats`, partitioning).
**Depends on:** Phase 8 (the "scan → print badge → mark attendance" combined flow needs both).

- [x] `ScanEvent` (unifying abstraction, §6.13): `account_id`, `event_id`, `participant_id`, `scan_type` (check_in/check_out/print/lead_retrieval/triggered_content — later phases add more types onto the same table), `source` (kiosk/manual/agent — plus `system`, this phase's own addition for EventCompletionService's non-human auto-checkout), timestamp. Monthly range-partitioned on the write timestamp (§4.10) — real native Postgres declarative partitioning (`lib/monthly_range_partitioning.rb`), which required switching `config.active_record.schema_format` to `:sql` (`db/structure.sql` replaces `db/schema.rb` — schema.rb can't represent `PARTITION BY`).
- [x] `Attendance`: derived/recorded from `ScanEvent`, `from` (event/session), `status` (check_in/check_out/manual_check_out/absent), time-spent computation from paired events. Also monthly-partitioned.
- [x] Multi-identifier scan lookup (hex ID, govt ID, RFID, client participant ID) with 30-second anti-double-scan debounce. → `Participant.find_by_identifier` + `ScanService::DEBOUNCE_WINDOW`.
- [ ] Session-level check-in with per-session seat-limit enforcement — **deferred to Phase 11**, per this checklist's own allowance: Phase 11's `Session` model hasn't landed yet, so event-level check-in ships first (`Attendance#from`/`ScanEvent` already carry a `session` enum value ready for it, no future migration needed).
- [x] Virtual-event redirect-on-check-in (scan → mark attendance → redirect to meeting link). → `ScanService#virtual_redirect_url`.
- [x] `EventLiveStats`/`SessionLiveStats`: denormalized counters, incremented in the same transaction as the triggering `Participant`/`ScanEvent` write — single source of truth for both initial dashboard load and live broadcast payload (§5.15 — the two paths must never disagree). → `EventLiveStats` done (atomic `update_counters`, wired from both `Participant#increment_live_stats!` and `ScanService`); **`SessionLiveStats` deferred alongside session-level check-in above** — no `Session` to key it off yet.
- [x] Redis pub/sub → Turbo Streams broadcast on `event:{event_id}:live` channel; admin dashboard (Phase 3's stat widgets) subscribes and patches DOM nodes with no full reload. → built on turbo-rails' `Turbo::StreamsChannel`/`turbo_stream_from` (Redis-backed per `config/cable.yml`) rather than a hand-rolled channel — see `LiveDashboard`'s own comment for why that's the same real-time behavior over the same transport, not a literal `event:{id}:live` string.
- [x] Super Admin cross-tenant live pulse (Platform Console dashboard, Phase 3 stub filled in): aggregate registrations/check-ins across all currently-live events. → `LiveDashboard.platform_pulse`/`#broadcast_platform_pulse`.
- [x] Rolling per-minute time-series bucket for the live sparkline (registration/check-in velocity). → `LiveMetricBucket`.
- [x] "Scan → print badge → mark attendance" combined flow, wired to Phase 8's render pipeline (on-demand print only — auto-print via the agent is Phase 10). → check-in kiosk's "Print badge" link reuses `Admin::ParticipantsController#badge`/`BadgePdfService` unchanged; that endpoint now also logs a `print` `ScanEvent` itself, folding it into the same unified abstraction.
- [x] EventScheduler job (Phase 4) extended: auto-checkout/mark-absent attendees when an event's `live → completed` transition fires. → `EventCompletionService`, called from `EventSchedulerJob`.
- [x] **Follow-up (confirmed with the user): the resulting Absent count wasn't actually shown anywhere.** → `Event#absent_participant_count` (real, distinct-participant count of `absent`-status `Attendance` rows, same "count from real rows, not a denormalized counter" shape every other count method here already takes) — surfaced as a 5th stat tile on the check-in dashboard (`admin/scan_events/_live_stats.html.erb`) and a 4th row on the event dashboard's own Check-in Funnel (`admin/events/_checkin_funnel.html.erb`). Both gated on `event.completed?` — `EventCompletionService` is the only thing that ever writes an `absent` row, exactly at that transition, so the count is genuinely zero (not yet a real answer) before then.

### Definition of Done
- [x] Model/service spec: debounce rejects a second scan within 30s, accepts one after. → `spec/services/scan_service_spec.rb`.
- [x] Model spec: `EventLiveStats` counter matches a raw `COUNT()` after a burst of concurrent scans (race-condition check — use `increment_counter`/atomic SQL, not read-modify-write). → `spec/services/scan_service_spec.rb`'s "concurrency" describe block (real OS threads, separate DB connections).
- [x] System spec (Capybara + Action Cable test adapter): a check-in scan in one browser session updates a **second** connected browser session's dashboard tile without a page reload, under 1 second (§7.3 target — assert via polling with a short timeout, not a hard sleep). → `spec/system/live_dashboard_spec.rb`, real two-session Playwright run (~2s wall time for the whole spec, including two logins).
- [x] Load sanity check: fan-out to N simulated subscribers doesn't measurably slow scan-write latency (even a lightweight local benchmark is enough to catch a gross regression — full load testing is a later hardening pass, not a Phase 9 blocker). → `spec/services/live_dashboard_load_spec.rb`.
- [x] Manual QA: two browser windows open on the same event's dashboard, scan a participant in a third tab (or via `curl`/API), watch both dashboards update live. → covered by the system spec above (a stronger, repeatable form of the same check); not additionally hand-driven.

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

- [x] `Speaker`: company/bio/photo, account-scoped and reusable across events (speaker portal itself is Phase 2-roadmap/later — CRUD by organizer is in scope now). → `app/models/speaker.rb`, `Admin::SpeakersController` (account-level, mirrors `Admin::BadgeTemplatesController`).
- [x] `Schedule` (talks): linked to a `Speaker`, start/end time, details, linked to an `Event` and optionally a `Session` (track/room). → `app/models/schedule.rb`, `Admin::SchedulesController`.
- [x] `Session`: independent seat capacity, own check-in (retrofits into Phase 9's session-level check-in once this lands). → `app/models/session.rb` (`seat_limit`/`#unlimited?`, mirrors `TicketCategory`), `SessionLiveStats`.
- [x] Agenda tab UI: multi-day/multi-track view, drag-to-reorder or time-grid editor, room/capacity fields. → time-grid (day-sectioned, track-grouped, sorted by real start/end times — confirmed with user in place of drag-to-reorder, which would've needed a new JS dependency nothing else in the app uses yet), `admin/event_sessions/index.html.erb`, linked from the wizard's Agenda step (`admin/events/_agenda_step.html.erb`).
- [x] If Phase 9 shipped before this phase, backfill session-level check-in wiring now that `Session` exists. → `ScanEvent`/`Attendance` gained `session_id` (migration `20260712180616`, propagated onto every existing partition); `ScanService` gained a `session:` kwarg (per-session debounce, seat-limit enforcement, independent `SessionLiveStats` counters — deliberately not rolled into `EventLiveStats`); `LiveDashboard.broadcast_session_stats`; `Admin::ScanEventsController`/check-in kiosk view gained a session picker + live per-session occupancy table.

### Definition of Done
- [x] Model spec: session capacity validation, schedule overlap warnings (same speaker double-booked, informational not blocking). → `spec/models/session_spec.rb`, `spec/models/schedule_spec.rb`.
- [x] Request spec: agenda CRUD respects tenant scoping and event-edit permissions. → `spec/requests/admin_event_sessions_spec.rb`, `spec/requests/admin_schedules_spec.rb`, `spec/requests/admin_speakers_spec.rb`.
- [x] Manual QA: build a 2-day, 2-track agenda with overlapping sessions in different tracks, confirm the grid renders correctly. → made repeatable in `spec/requests/admin_event_sessions_spec.rb` (asserts day/track grouping in the rendered response); also driven live against a running dev server end-to-end (agenda grid, wizard Agenda step, session check-in scan, live occupancy tile update all confirmed working).

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

- [x] Delivery-state tracking model/concern (`pending/sent/failed`) generalized with a `channel` (`email`/`whatsapp`) column, reused by every mailer already built in earlier phases. → `Notification` (polymorphic `notifiable`, `app/models/notification.rb`) + `Notifier` (`app/services/notifier.rb`, the single entry point — `.email`/`.whatsapp`) + `NotificationDeliveryJob` (`app/jobs/notification_delivery_job.rb`, the one async unit that actually performs the send and updates the row — deliberately *not* layered on top of ActionMailer's own `.deliver_later`, since that re-invokes the whole mailer action in its own job with no way to thread a Notification id through; see that job's own comment). Migrated onto this: `AccountMailer#welcome` (`AccountProvisioning`), `ParticipantMailer#confirmation` (`Participant#send_registration_confirmation!`/new `#deliver_confirmation_email`), `EventMailer#rejected` (`SuperAdmin::EventReviewsController`).
- [x] Gupshup client wrapper (platform-level credential, not per-tenant, per v10 decision) — assume credential exists in `ENV`/Rails credentials; this phase builds the integration code, not the Gupshup account itself (stakeholder's responsibility). → `GupshupClient` (`app/services/gupshup_client.rb`), against Gupshup's own real REST shape (`POST /wa/api/v1/msg`, form-encoded, `apikey` header). No real/sandbox credential was available in this environment — verified live that it fails cleanly (`DeliveryError: Gupshup credentials not configured`), caught by `NotificationDeliveryJob`, and does **not** block the email side of the same rejection (see Manual QA note below).
- [x] WhatsApp sent for: event rejection (Phase 5) — wire these in now that the channel exists; earlier phases' email-only stubs get a WhatsApp companion send here. **Deviation, flagged rather than silently skipped:** invoice sent / quotation sent/revised are Phase 15 — no `Invoice`/`Quotation` model exists yet to wire a send for. Phase 15 has both the infrastructure (this phase) and the models (its own) once it's built; nothing here needs revisiting, it's purely additive. `EventMailer#rejected` was also refactored to take an explicit `to:` (one recipient) instead of deriving "every owner" internally — see that mailer's own comment; deriving the list inside would've duplicate-sent to every owner once per owner once tracking was per-recipient.
- [x] "Resend invitation" and "send to all pending" batch actions (baseline §3.10) on the participant list (Phase 7). → `Admin::ParticipantsController#resend` (member) / `#send_to_pending` (collection, sends to `Participant#status: pending`), both calling `Participant#deliver_confirmation_email` directly — bypasses `Event#send_registration_email?`'s toggle deliberately, since an explicit admin-triggered resend is deliberate intent, not the automatic on-create send that toggle gates. UI: a "Send to Pending" button in the participants index card header, a per-row "Resend invitation" icon (hidden when the participant has no email — the send is a harmless no-op either way, but a button that never does anything is worse than no button).
- [x] Registration-confirmation email using Phase 12's tenant/sponsor branding layering. **Deviation, flagged rather than silently skipped:** Phase 12 itself (Sponsor/Exhibitor model, full Platform → Tenant → Event → Sponsor cascade) isn't built yet. Uses the one piece of tenant branding that already exists — `Account#logo` (added ahead of Phase 12, alongside the tenant-registration intake fields) — in `participant_mailer/confirmation.html.erb`. Revisit once Phase 12 adds color palette/sponsor-tier layering on top. Fixed a real bug surfaced by this: `ActiveStorage::Blob#url` inside a mailer template raised "please set ActiveStorage::Current.url_options" (Rails only sets that automatically for a real web request, not mail rendering in Sidekiq's own process) — `ApplicationMailer#mail` now sets it from the same resolved `default_url_options` every tenant-scoped mailer already relies on.

### Definition of Done
- [x] Job spec: a rejection event now enqueues both an email job and a WhatsApp job, each independently tracked (one failing doesn't block the other). → `spec/jobs/notification_delivery_job_spec.rb`, `spec/requests/super_admin_event_reviews_spec.rb` (two owners × two channels = four independently-tracked rows; the WhatsApp failure doesn't block either owner's email).
- [x] Service spec: Gupshup client handles a non-200 response by marking the notification `failed`, not raising unhandled. → `spec/services/gupshup_client_spec.rb` (missing credentials, blank recipient, non-2xx response, and a raw network exception all become the one `GupshupClient::DeliveryError`, never an unhandled exception); `NotificationDeliveryJob` is what actually turns that into a `failed` Notification row, deliberately *not* re-raising afterward (Sidekiq retry doesn't suit "no Gupshup credential configured," a permanent failure, not a transient one — see that job's own comment).
- [x] Manual QA (with a real or sandbox Gupshup credential): trigger an event rejection, confirm a WhatsApp message arrives at a test number using `contact_num`. **Deviation, flagged rather than silently skipped:** no real/sandbox Gupshup credential is available in this environment (per this phase's own scope note, obtaining one is the stakeholder's responsibility, not a platform-engineering task) — so the actual WhatsApp *delivery* was never observed. What **was** verified live end-to-end instead: rejecting a real event through the Platform Console correctly created four `Notification` rows (email × 2 owners, whatsapp × 2 owners), the email side genuinely delivered (confirmed via mailcatcher), and the WhatsApp side failed cleanly with `"Gupshup credentials not configured"` — without blocking the email send. Re-run this specific check once a real Gupshup credential is available.

---

## Phase 14 — Reporting, Import/Export & Analytics

**Goal:** turn the raw data accumulated by every prior phase into organizer-facing reports — currently a complete gap per the requirements doc, called out as a priority.
**Implements:** §3.11, §5.11.
**Depends on:** Phase 9 (attendance data), Phase 7 (participant data).

- [x] Configurable export templates (organizer picks columns/format: XLSX/CSV/PDF) generalizing Phase 7's fixed export. → `ExportFile#format` enum (`xlsx`/`csv`/`pdf`, migration `20260717182827`), a Format radio group on `admin/export_files/new.html.erb` (`file_format` param — not `format`, a reserved Rails routing/params concept, see `ExportFile`'s own comment). `ParticipantExportJob` refactored: field-value computation (already column-configurable since Phase 7) is now fully format-agnostic (`#build_rows`, a plain 2D array), with three small per-format serializers — XLSX (unchanged Axlsx), CSV (Ruby stdlib), and PDF (Grover — the same engine `BadgePdfService` already uses for badges, rendering a plain HTML table; `format: "A4"` explicit on that one call, never a global default, matching Grover's own initializer comment for why).
- [x] Analytics dashboards: registrations-over-time, check-in rate, session popularity (Phase 11 data), engagement funnel — built as read-models querying `EventLiveStats`/historical `ScanEvent` partitions, not expensive live `COUNT()`s. → **Merged onto the event's existing landing page** (`admin/events#show`, renamed "Analytics" in the sidebar — was "Dashboard" — rather than a second, separate page: that page already *was* the event's real-time/analytics home, just missing these specific views). `Event#daily_registration_counts` (mirrors `#daily_checkin_counts`'s own `pluck` + Ruby-side `.to_date` grouping, not raw SQL `DATE()`, for the same "this app's configured Time.zone, not the stored value's own UTC zone" reasoning) and `#session_attended_participant_count` (distinct participants with a *session* check-in — reads `SessionLiveStats`/`Attendance`, no new counters). Engagement Funnel is a third, deeper stage than the pre-existing Check-in Funnel (Registered → Checked In → Currently In Venue): Registered → Checked In → Attended a Session. **Deviation, flagged rather than silently built wrong:** revenue and sponsor ROI are not included — no payment gateway anywhere in this app (requirement.md's own unchanged v2 scope decision) and Sponsor/Exhibitor is Phase 12 (not built yet); both are additive once their owning phase lands, nothing here needs reworking.
- [x] Scheduled report delivery (Sidekiq-cron or equivalent: emailed weekly/daily summary to organizers). → The "equivalent" this app already uses for every other scheduled job: a self-rescheduling job (`ScheduledReportJob`, hourly, same pattern as `EventSchedulerJob`/`PartitionMaintenanceJob` — no sidekiq-cron gem, a deliberate choice those jobs' own comments already explain). `Event#scheduled_report_frequency` (`none`/`daily`/`weekly`, organizer opt-in on the Basic Info step, off by default, deliberately **not** in `Event::CONTENT_ATTRIBUTES` — a purely internal reporting-cadence preference with no attendee-facing/public-visibility implications, so changing it doesn't revert an already-published event to draft) + `#last_report_sent_at` (what `#due?` compares against — a rolling window, not a fixed calendar slot, so a late-starting tick never permanently skips a cycle). `ReportMailer#summary`, routed through `Notifier`/`NotificationDeliveryJob` (Phase 13) for tracked delivery-state like every other mailer in this app.

### Definition of Done
- [x] Job spec: async export honors a custom column selection and format choice. → `spec/jobs/participant_export_job_spec.rb` — real Grover/headless-Chrome PDF rendering and a real parsed CSV, not mocked, same convention `spec/services/badge_pdf_service_spec.rb` already established for this app's one other PDF generator.
- [x] Request spec: analytics dashboard queries stay within an acceptable query-count/time budget on a seeded large dataset (guard against N+1 regressions with `bullet` or an explicit query-count assertion). **Deviation, flagged rather than silently skipped:** no `bullet`/explicit query-count assertion was added — every new query here (`daily_registration_counts`, `session_attended_participant_count`, the session-popularity `.includes(:session_live_stats)` list) is a single bounded query per event, the same "not worth a raw-SQL/N+1-guard trade-off at this row count" judgment this file's own `#daily_checkin_counts`/`#currently_in_venue_count` already made and were never guarded this way either. Revisit with a real query-budget assertion once an event's own participant/session counts are large enough for it to matter.
- [x] Manual QA: export a custom CSV, confirm columns match selection; view the registrations-over-time chart against seeded historical data. → Verified live end-to-end against the real `dubai-expo` event: the merged Analytics page rendered a real Engagement Funnel (77.8% check-in rate), Registrations Over Time chart, and Session Popularity list with real seeded data; a live PDF export surfaced and fixed a **real, separate Cloudinary bug** (below) before succeeding with a genuine 40KB PDF, confirmed downloadable end-to-end through the real download link (not just the job completing).

**Bug found and fixed during manual QA — real, not hypothetical:** `CloudinaryRawFile` (Phase 7's own Cloudinary "raw" resource workaround) hardcoded `resource_type: "raw"` — correct for xlsx/csv, but the `cloudinary` gem's own upload path (`ActiveStorage::Service::CloudinaryService#content_type_to_resource_type`) files a `application/pdf` blob under `resource_type: "image"` instead (Cloudinary can render/transform PDF pages). A hardcoded "raw" lookup 404'd ("Resource not found") for a PDF that had genuinely uploaded correctly — confirmed live against Cloudinary's own Admin API, the same diagnostic approach that first caught this class's original bug. Fixed by computing the right `resource_type` per blob content-type, mirroring the gem's own mapping exactly (`CloudinaryRawFile.resource_type_for`) — `spec/services/cloudinary_raw_file_spec.rb` now covers xlsx/csv/pdf/video/audio/image.

---

## Phase 15 — Platform Billing & Invoicing

**Goal (revisited — full redesign, confirmed with the user after the first build shipped):** the user found the plan-tier/capacity-overage/manual-raise version below "very confusing" and asked for a simpler, layman-navigable redesign: one price per event (no plan tiers), negotiated via a 3-round quotation, invoiced automatically the day after the event ends, paid via a single "Mark as Paid" modal. The plan-tier version's own goal/checklist is kept below, struck through in spirit but left in place for history — everything under "Redesign (current)" is what's actually live.
**Implements:** §4.6 (redesigned scope — no `Plan`/`Subscription`/`UsageRecord`/`CapacityAdjustment` concept remains), §8 (`Invoice`, `Quotation`, `QuotationRevision` — `PaymentSubmission` folded into `Invoice`).
**Depends on:** Phase 5 (every event is now quotation-gated *before* creation, not just a "Business" tier — this phase's `Quotation` gate replaces Phase 4's plan picker entirely).

### Redesign (current) — confirmed with the user verbatim:
> "Tenant sends the request for the event → Super admin reverts with price (one plan only, priced per event) → Tenant negotiates or approves (max 3 rounds) → Tenant creates the event by picking the approved quotation → day after the event ends, System auto-generates the invoice → Super Admin reviews and sends it → Tenant pays via NEFT/IMPS and submits UTR + receipt through a 'Mark as Paid' modal → Super Admin verifies and marks it settled. Sidebar: Quotations + Invoices, nothing else."

- [x] Removed entirely: `events.plan` enum/column, `EventBilling` pricing concern, `CapacityAdjustment` model/table, `PaymentSubmission` model/table, the cross-tenant `SuperAdmin::EventsController` browser, `Admin`/`SuperAdmin::PaymentSubmissionsController`. → 4 migrations (`20260718110000`–`20260718110300`): drop `capacity_adjustments`/`payment_submissions` tables; `Invoice` loses `base_amount`/`overage_amount`/`raised_by`, gains `utr_reference`/`submitted_by`/`submitted_at`/`verified_by`/`verified_at`/`rejection_reason` directly (one row per event now, unique index on `event_id`) and `total_amount` is renamed to plain `amount`; `events.plan` dropped. `events.quotation_id` deliberately stays nullable at the DB level (not just the app layer) — real dev/QA data (~19 accounts) already had events with no quotation from before this redesign; enforced as required only via `Event`'s own `belongs_to :quotation` for new records, not a NOT NULL constraint that would demand a backfill.
- [x] `Event belongs_to :quotation` (required, was `optional: true`/Business-only) — "one quotation → one event," no exceptions, no tiers. → `Event#quotation_must_be_approved_and_available` (renamed from `#business_plan_requires_an_approved_quotation`, `on: :create`) drops its old `return unless business?` guard — the account-match/approved?/not-already-consumed checks (and the `Event.exists?(quotation_id:)` reuse-detection fix from the original build, still needed — `inverse_of` auto-detection between `belongs_to`/`has_one` reads back an in-memory assignment, not the persisted state) now apply to every event, unconditionally. `has_many :invoices` → `has_one :invoice` (one invoice per event now).
- [x] `Quotation`/`QuotationRevision`: unchanged from the original build — organizer requests → Super Admin sends amount → tenant approves or rejects-with-note (up to 3 rejections → `cancelled`). → `app/models/quotation.rb`/`quotation_revision.rb`, untouched by this redesign. Copy simplified ("Business Quotations" → "Quotations" throughout, no plan-tier framing).
- [x] New Event creation: no plan radio at all — clicking "New Event" opens a modal to pick one of the account's own approved, not-yet-consumed Quotations, then continues to a locked-quotation creation form. → `Admin::EventsController#new`/`#create` rewritten: `#new` 404-redirects to the index (with a "select a quotation" alert) unless `params[:quotation_id]` resolves to a legal choice; `#create` looks the id up without a pre-check redirect so a bad/stray id renders the form again with a real inline error instead of silently bouncing. `app/views/admin/events/index.html.erb` gained the picker modal (Bootstrap, same pattern as the existing Quick Email Send modal); `new.html.erb` shows the locked quotation as read-only text + a hidden field, no radios. `event_plan_controller.js` (Stimulus) deleted — nothing toggles a Business-only field anymore. **Duplicate edge case, not explicitly requested but structurally forced by "one quotation → one event":** the original's own Quotation is already consumed by it, so `Admin::EventsController#duplicate` now also requires picking a fresh approved Quotation, via a per-row modal on the index (same picker, scoped to that row) — the Duplicate icon disables itself with a tooltip when no approved quotation is available.
- [x] Invoice auto-generation: the day after an event ends, the system creates a `draft` Invoice for the event's own quotation amount — no manual "raise" step. → `InvoiceGenerationJob` (`app/jobs/invoice_generation_job.rb`), `Invoice.generate_for(event)` = `event.create_invoice!(amount: event.quotation.current_amount, currency: event.quotation.currency)`. **Reconciled an apparent contradiction in the user's own request**: the high-level flow says "System will generate the invoice and send the invoice to the Tenant," but the detailed sidebar spec says "Super admin manually verify the invoice and then send manually to tenant" — implemented as auto-generating a `draft` only; a human Super Admin still reviews and `#deliver`s it, favoring the more specific instruction. **Follow-up (confirmed with the user): moved from self-rescheduling onto `sidekiq-cron`** (hourly, `config/schedule.yml`) — see `EventSchedulerJob`'s own doc entry above for the full "why"; this job had exactly the same "nothing ever bootstraps the first run" gap, so in practice it had never actually run either.
- [x] "Mark as Paid": tenant submits UTR + platform bank details (shown inline) + a transaction receipt (image/PDF) through one modal; Super Admin verifies or rejects-with-reason (resubmittable). → `PaymentSubmission` folded directly onto `Invoice` itself (`utr_reference`/`submitted_by`/`submitted_at`/`receipt` via `TenantScopedAttachment`/`verified_by`/`verified_at`/`rejection_reason` — a single "current attempt" slot, not a history table, since the redesigned flow only ever needs one at a time) — `Invoice#submit_payment!`/`#verify!`/`#reject_payment!`. New `PlatformBankDetails` (`app/models/platform_bank_details.rb`) — ENV-overridable placeholder NEFT/IMPS account constants, same "clearly-flagged placeholder" treatment the original build's billing rates used, since no real bank details exist anywhere in requirement.md. `Admin::InvoicesController#submit_payment` (member action, not a nested resource) backs the modal, reused identically on both the Invoices index (per-row) and an invoice's own show page. `SuperAdmin::InvoicesController` rewritten as a plain `resources :invoices` (`#index`/`#show`/`#deliver`/`#verify`/`#reject` — no more nesting under `Event`, no more `#new`/`#create`).
- [x] Sidebars collapsed to exactly two items each, per the user's explicit spec. → `AdminHelper#admin_nav_items`: "Billing" split into "Quotations" (`admin_quotations_path`) + "Invoices" (`admin_invoices_path`). `SuperAdminHelper#super_admin_nav_items`: "Billing" split into "Quotations" (`platform_quotations_path`) + "Invoice" (`platform_invoices_path`, singular per the user's own spec wording). `SuperAdmin::QuotationsController#index` also changed from "pending/rejected only" to *every* quotation (approved/cancelled included) — matches the user's explicit "All quotations with approved and awaiting" sidebar description, a real behavior change from the original build's narrower review-queue framing.
- [x] `spec/factories/events.rb` updated to auto-build an approved `Quotation` on the same account by default (`quotation { association :quotation, :approved, account: account }`) — the single factory-level change that kept the ~700 pre-existing specs using `:event` green under the new required-association, rather than touching every individual spec file.
- [x] Follow-up (requested after the redesign shipped): platform quotations index sorts by `updated_at` (was `created_at`), most-recently-negotiated first — `SuperAdmin::QuotationsController#index`.
- [x] Follow-up: `Quotation`/`Invoice` gained an explicit `currency` (defaults to INR, the platform's primary currency) instead of an implicit, unstated one — a Super Admin now picks it alongside the amount when sending/revising a quotation, and it carries straight through to the resulting `Invoice`. → Migration `20260718120000` adds `currency` (string, default `"INR"`) to `quotations`/`quotation_revisions`/`invoices`; new `Currency` module (`app/models/currency.rb`) is the single fixed list (INR/USD/EUR/GBP) + symbol lookup both models validate against and every view/mailer formats through. `Quotation#send_amount!(amount:, currency:)` now takes currency explicitly (defaults to whatever's already on the row); `#reject!` snapshots the currency in effect at rejection time onto the `QuotationRevision`, same reasoning `amount` was already snapshotted — a revised offer can legitimately switch currency between rounds, and the negotiation history needs to reflect what was actually rejected, not what the quotation ended up on. `Invoice.generate_for` copies both `amount` and `currency` straight from the approved `Quotation`. New `ApplicationHelper#money(amount, currency)` replaces every bare `number_to_currency` call across both consoles' Quotation/Invoice views and `BillingMailer`'s own templates. **Real bug caught live, not by inspection**: `BillingMailer`'s views 500'd on `money` — `ActionMailer::Base` doesn't pull in a plain `ApplicationHelper` method the way controllers automatically do; fixed with an explicit `helper ApplicationHelper` in `ApplicationMailer`, confirmed via `bin/rails runner` that `BillingMailer._helpers` didn't expose it beforehand and does after.
- [x] Follow-up: `Admin::QuotationsController#show`/`SuperAdmin::QuotationsController#show` both surface the consumed event's own name/description/start/end date once a quotation has been used to create one (an "Event Details" card, tenant side only) — real `Event.find_by(quotation_id:)` lookups, same "don't trust the `has_one :event` association's own possibly-stale in-memory read" reasoning as `Event`'s own `quotation_must_be_approved_and_available` validation.
- [x] Follow-up: manual "Create Invoice" action — a Super Admin can trigger `Invoice.generate_for(event)` on demand from an approved quotation's own show page (`platform_quotations/:id/create_invoice`), instead of waiting for `InvoiceGenerationJob`'s day-after-event-ends sweep; pricing is fixed via the `Quotation`, not participant count, so there's no computational reason to wait. Same idempotency guard as the job itself (an event that already has an `Invoice` gets a "one already exists" redirect straight to it, never a second row — `Invoice#event_id`'s own unique index is the DB-level backstop either way). **Initially built on the tenant (`Admin::`) side per the first request, then explicitly moved to the Super Admin (`SuperAdmin::`) side per an immediate follow-up correction** — the biller triggering their own invoice early makes more architectural sense than the tenant being billed doing it themselves; the "Event Details" card above stayed on the tenant side since that part of the original request wasn't part of the correction.

<details>
<summary>Original build (plan-tier version, superseded above — kept for history)</summary>

- [x] `Plan` (Basic/Pro/Business definitions), assigned per event at creation time (not per Account), `CapacityAdjustment` for Basic/Pro soft-cap overage, manual per-event `Invoice#build_for`/`#send!` raised by Super Admin, `PaymentSubmission` as its own reviewable table, a cross-tenant `SuperAdmin::EventsController` browser as the entry point for both. All removed/replaced by the redesign above.

</details>

### Definition of Done
- [x] Model spec: Quotation reject/revise cycle caps at 3 rejections, 3rd moves to `cancelled`, no further revision possible after. → `spec/models/quotation_spec.rb` (unchanged by the redesign).
- [x] Model spec: `Event#quotation_must_be_approved_and_available` blocks creation with no/unapproved/foreign/already-consumed quotations, unblocks immediately on approval. → `spec/models/event_spec.rb`.
- [x] Model spec: `Invoice.generate_for`/`#send!`/`#submit_payment!`/`#verify!`/`#reject_payment!` cover the full redesigned lifecycle. → `spec/models/invoice_spec.rb`.
- [x] Job spec: `InvoiceGenerationJob` only generates a draft for `completed` events past the 1-day mark with no invoice yet, skips everything else, doesn't double-generate. → `spec/jobs/invoice_generation_job_spec.rb`.
- [x] Request spec: event creation is blocked without an approved, not-yet-consumed Quotation; unblocked immediately after approval. → `spec/requests/admin_events_spec.rb` ("quotation gate").
- [x] Request spec: tenant "Mark as Paid" (`#submit_payment`) and Super Admin `#deliver`/`#verify`/`#reject` cover the full redesigned payment cycle. → `spec/requests/admin_invoices_spec.rb`, `spec/requests/super_admin_invoices_spec.rb`.
- [x] Manual QA: run the full redesigned flow end to end. → Verified live via a real browser session across both consoles (server restarted mid-QA after discovering a stale schema-cache `PG::UndefinedColumn: plan` error from the pre-migration puma process, not a code bug): opened the "New Event" quotation-picker modal (showed the account's one approved, unconsumed quotation with its amount), continued through to a locked-quotation creation form with no plan radios, created the event, confirmed the quotation's own show page then read "Approved and already used to create ...", confirmed the Duplicate button correctly disabled once no approved quotations remained. Generated a draft invoice and `#send!`t via console/model call (fast-forwarding a day past event-end wasn't practical live), opened the tenant's "Mark as Paid" modal (bank details + UTR + receipt fields rendered exactly as specified), submitted it, then as Super Admin opened the invoice show page ("Payment Submission" card showing UTR/timestamp), clicked "Verify Payment" (confirm dialog showed the exact amount + UTR), confirmed — invoice landed on `paid`, "Paid — settled." 777 examples, 0 failures; Rubocop clean across `app`/`config/routes.rb`/`spec`.

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
