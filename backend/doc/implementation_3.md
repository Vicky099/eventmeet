# EventMeet — Implementation Plan, Part 3 (Forward Plan)

**Status:** Draft v1 — Phase 23 (Audit Log & Super Admin Impersonation) is complete; Phases 24–26 are still `[ ]`, not yet started.
**Relationship to `implementation.md`/`implementation_2.md`:** those two files are a record of what's already shipped (`implementation.md` = Phases 0–18 as originally planned; `implementation_2.md` = the Agency pivot and everything else that landed without ever getting written down). This file is the opposite: a forward plan for what's still genuinely missing from `requirement.md`'s scope, re-sequenced and re-scoped against the *current* architecture (Agency layer, no Quotation, no `ScanEvent`/`Attendance` partitioning, xEvent branding) rather than the pre-pivot one those phases were originally written against.
**How to use this document:** same conventions as the other two — one phase = one demo-able, testable slice, check items off in place as they land, copy the cross-tenant leak spec pattern into anything new that's tenant-scoped, flag a deviation rather than silently build around it. When a phase here is done, move its content into a future `implementation_4.md` (or fold it back into `implementation.md`'s own phase list) rather than leaving a completed checklist stranded in a "forward plan" file.

## Why this order

1. **Phase 23 (Audit Log & Impersonation) first.** `implementation_2.md`'s own Cross-cutting checklist flags this as the single largest gap versus `requirement.md`'s intent: every cross-tenant Super Admin action shipped since the Agency pivot (suspend/reinstate, `grant_events`, invoice deliver/verify/reject, agency membership management) has **no audit trail today**. This isn't new work so much as closing an already-open hole under already-shipped features — worth doing before adding more surface area that would also need auditing.
2. **Phase 24 (Sponsors/Exhibitors)** and **Phase 25 (Tenant OAuth2 API)** are independent of each other and of Phase 23 — reorder freely if priorities differ.
3. **Phase 26 (Next.js Public Event Site) last**, unchanged from the original doc's own reasoning: it depends on the OAuth API (Phase 25) genuinely existing to authenticate against, and is the one surface where every other backend capability it needs (registration rules, live counters, agency-gated event creation) already exists and is already tested.

---

## Phase 23 — Audit Log & Super Admin Impersonation

**Goal:** every cross-tenant Super Admin action gets a permanent, queryable record of who did what to whom; a Super Admin can enter a tenant's Admin Console as a specific user to help/debug, with a visible banner and the same audit trail covering every action taken while impersonating.
**Implements:** `requirement.md` §4.7, §4.11 (referenced but never built — see `implementation_2.md`'s Corrections section for how the rest of the original Phase 17 this comes from was actually delivered).
**Depends on:** nothing new — every action this phase instruments already exists (`implementation_2.md` Phase 19).

### 23.1 `AuditLogEntry`
- [x] `AuditLogEntry` model — platform-level (not `TenantScoped`, no `account_id`), `actor` (`belongs_to :user`), `action` (string, dot-namespaced), polymorphic `target`, `metadata` (jsonb), `created_at` only. → `app/models/audit_log_entry.rb`, `db/migrate/20260719080000_create_audit_log_entries.rb`. No `updated_at` column at all — Rails' normal timestamp handling only touches columns that exist, so `created_at` still auto-populates with no model-side override needed.
- [x] `AuditLog.record!(actor:, action:, target:, metadata: {})` — the single entry point. → `app/services/audit_log.rb`.
- [x] Retrofit every existing cross-tenant Super Admin action: `SuperAdmin::AgenciesController#create`/`#update`/`#suspend`/`#reinstate`/`#grant_events`, `SuperAdmin::AccountsController#suspend`/`#reinstate`, `SuperAdmin::AgencyMembershipsController#create`/`#destroy`/`#resend_invite`, `SuperAdmin::InvoicesController#deliver`/`#verify`/`#reject` — each call site's `metadata` captures the actionable detail (`grant_events`: `count`/`events_remaining`; `#reject`: the rejection `reason`; `#update`: `saved_changes` minus `updated_at`).
- [x] Platform Console viewer — `SuperAdmin::AuditLogEntriesController#index` (`app/controllers/super_admin/audit_log_entries_controller.rb`), filterable by actor/action/target type/date range (Pagy-paginated, `items: 25`), its own `super_admin_nav_items` entry ("Audit Log"). Read-only, no `#show`/edit/destroy.

### 23.2 Impersonation
- [x] `ImpersonationToken` — same shape as `AccountSwitch` (short-lived 60s TTL, single-use, `SecureRandom.urlsafe_base64(32)`, `redeemable?`/`#redeem!`), minted by a Super Admin targeting a specific tenant `User`. → `app/models/impersonation_token.rb`, `db/migrate/20260719080100_create_impersonation_tokens.rb`.
- [x] Mint: `SuperAdmin::ImpersonationsController#create`, nested under `platform_account_impersonations_path(account)` (`user_id` param picks which of the account's users) — a per-user "Impersonate" button added to the existing tenant details modal (`super_admin/agencies/_tenant_modal.html.erb`), issues the token, redirects cross-subdomain (`allow_other_host: true`). Logged (`impersonation.start`, target: the `Account`) at mint time, since that's the real Super Admin decision being audited — redemption is just completing it.
- [x] Redeem: `Admin::ImpersonationsController#redeem` (mirrors `Admin::AccountSwitchesController#redeem` almost exactly) signs the target `User` in and additionally stashes `session[:impersonator_platform_staff_id]`, read back by `Admin::BaseController#current_impersonator` on every subsequent request.
- [x] Persistent banner — `shared/_impersonation_banner.html.erb`, passed in as an explicit `impersonator:` local from `layouts/admin.html.erb` (same "layout passes locals into `shared/_console_shell`, not the partial looking things up itself" convention `footer_text`/`back_link` already established), rendered whenever present.
- [x] "Stop Impersonating" — `Admin::ImpersonationsController#destroy` (`DELETE /admin/impersonate`), clears the session key, signs the `:user` scope out, redirects cross-subdomain back to the Platform Console — the original `:platform_staff` session cookie is untouched (separate host-only cookie, Phase 1's isolation model), so no re-login is needed.
- [x] Every state-changing request made while `current_impersonator` is present writes an `AuditLogEntry` — `Admin::BaseController`'s own `after_action :audit_impersonated_action, if: -> { current_impersonator && !request.get? && !request.head? }` (`actor: current_impersonator`, never `current_user`; `action: "impersonation.#{controller_name}##{action_name}"`; `target: current_user`, `metadata` includes the impersonated user's email).
- [x] **Real bug caught live, not by inspection**: the first version of both cross-subdomain buttons (Impersonate, Stop Impersonating) silently failed — Turbo's fetch-based form submission can't follow a cross-origin redirect (`TypeError: Failed to fetch` in the console, an `OPTIONS` preflight 404 server-side, no visible error on the page itself). Fixed with `form: { data: { turbo: false } }` on both `button_to` calls, the exact same fix `agency_console/accounts/index.html.erb`'s own pre-existing "Switch to this tenant" button already needed for the identical reason — confirmed missed only because that precedent wasn't checked before building the new buttons.
- [x] **Second real bug caught live, via user report during manual QA**: the banner initially overlapped the topbar's logo/logout button instead of pushing them down — `#page-topbar`/`.vertical-menu` are `position: fixed` (pinned to the *viewport*, not the document flow), so a plain in-flow/`position: sticky` banner reserves no space for them regardless of DOM order. Fixed via a CSS `transform` on `#layout-wrapper` (making it the containing block for its own `position: fixed` descendants, a standard CSS behavior) plus `margin-top` equal to the banner's height, scoped under `body.impersonating` (`app/assets/stylesheets/application.css`) — set only when `current_impersonator` is present (`layouts/admin.html.erb`'s own `<body class="...">`). Caught a second, more subtle instance of the same class of bug while fixing it: the banner itself must render as a **sibling** of `#layout-wrapper`, not a child — nesting it inside would make the banner itself subject to the same transform/margin shift meant to push the topbar out from under it, landing the banner at the topbar's new position instead of the true viewport top (`shared/_console_shell.html.erb`).

### Definition of Done
- [x] Model spec: `AuditLogEntry` validations + append-only shape; `ImpersonationToken` single-use/expiry, mirroring `spec/models/account_switch_spec.rb`. → `spec/models/audit_log_entry_spec.rb`, `spec/models/impersonation_token_spec.rb`, `spec/services/audit_log_spec.rb`.
- [x] Request spec: every retrofitted Super Admin action produces exactly one correctly-attributed `AuditLogEntry`. → added directly into the existing `spec/requests/super_admin_agencies_spec.rb`, `spec/requests/super_admin_accounts_spec.rb`, `spec/requests/super_admin_invoices_spec.rb` (not a separate file — matches how those actions were already tested).
- [x] Request spec: impersonation mint→redeem lands the Super Admin on the correct tenant's Admin Console signed in as the correct user; the banner renders; "Stop Impersonating" returns to the Platform Console with no re-login required. → `spec/requests/super_admin_impersonations_spec.rb`.
- [x] Request spec: a state-changing action taken *while impersonating* produces an `AuditLogEntry` whose `actor` is the real Super Admin, not the impersonated user. → same file, `"attributes a state-changing action taken while impersonating to the real Super Admin, not the impersonated user"` — plus a companion check that a plain `GET` made while impersonating does *not* get audited.
- [x] Request spec: a second redemption of the same `ImpersonationToken` fails; an expired one fails; redemption is rejected if the target's `AccountMembership` was removed after minting. → same file.
- [x] Manual QA: impersonated a real seeded tenant admin (`xaniel@gmail.com`, under agency "Smart track Zone") from a live dev server — verified the mint→redeem→banner→stop flow end to end in a real browser, confirmed the resulting `AuditLogEntry` rows in the new `/platform/audit_log_entries` viewer, and confirmed the two real bugs above (cross-origin Turbo submission, banner/topbar overlap) both via server logs and visually before/after each fix.
- [x] Full suite green: **903 examples, 0 failures** (876 → 903, +27 new), Rubocop clean, Brakeman: 0 warnings.

---

## Phase 24 — Sponsors/Exhibitors & Branding Cascade

**Goal:** unchanged from the original doc's own Phase 12 — per-event sponsor/co-branding, generalized from the baseline's single `Client` record, plus a real tenant-level branding cascade. Re-scoped here only where the Agency layer changes what "tenant-level" actually means.
**Implements:** §3.9, §4.5, §5.8 (module minus billing, which stays out of scope — no payment gateway anywhere in this app, unchanged decision).
**Depends on:** `implementation.md` Phase 9 (`ScanEvent.scan_type: lead_retrieval` already exists as an enum value, unused until this phase wires a real UI to it).

- [ ] `Sponsor`/`Exhibitor` model (generalized `Client`): `event_id`, logo, custom email body/footer, tier. Tenant-scoped, `TenantScoped` + RLS, same as every other per-event model.
- [ ] Branding cascade, **updated for the Agency layer**: the original plan was Platform → Tenant → Event → Sponsor; with Agency now sitting between Platform and Tenant, decide (and record the decision here, not silently) whether an Agency gets its own optional branding tier (Platform → Agency → Tenant → Event → Sponsor) or whether tenant branding stays independent of its owning Agency as it does today (`Account#logo`, already shipped ahead of this phase, has no Agency-level equivalent or override). Whichever is chosen, apply it to email templates (Phase 13, already live — `participant_mailer/confirmation.html.erb` currently only reads `Account#logo`) and badge rendering (Phase 8, revisit `BadgePdfService` only if a real need surfaces — the original doc's own note that this may not need touching still holds).
- [ ] Booth page stub content fields — data model + admin CRUD only, a full booth-page builder is an explicit fast-follow, not this phase's blocker.
- [ ] Lead-retrieval: exhibitor staff scan attendee badges, `ScanEvent.scan_type: lead_retrieval` (enum value already exists, unused), notes/tags captured on the resulting row, exportable list per sponsor (reuse `ParticipantExportJob`'s existing per-format serializers rather than a new export path).
- [ ] Admin nav: `admin_helper.rb`'s own comment already flags that "Sponsors... lost/never got a nav entry, by deliberate choice... until it gets a real home" — this phase is that real home; add it to `event_nav_items` (event-scoped, matching how Sponsor/Exhibitor is per-event) rather than the account-level nav.

### Definition of Done
- [ ] Model spec: sponsor tier CRUD, whichever branding cascade is chosen renders correctly into both a preview and a real sent email.
- [ ] Request spec: a lead-retrieval scan creates a `ScanEvent` distinct from attendee check-in, doesn't affect `EventLiveStats` occupancy counters (the existing check-in dashboard must not double-count a lead scan as an attendee check-in).
- [ ] Cross-tenant leak spec: `Sponsor`/`Exhibitor`, same pattern as every other new tenant-scoped table since Phase 0.
- [ ] Manual QA: set tenant (and/or agency, per whichever cascade is chosen) branding, confirm it appears on a rendered registration-confirmation email and — only if the cascade decision above concludes badges need it — a rendered badge.

---

## Phase 25 — Tenant OAuth2 API Provider

**Goal:** unchanged from the original doc's own Phase 16 — each tenant's Doorkeeper application (auto-created since `implementation.md` Phase 2, unaffected by the Agency pivot — still one `OAuthApplication` per `Account`, not per `Agency`) becomes a real, working credential against a two-endpoint MVP API surface. Built and tested now via `curl`/request specs since Phase 26 (Next.js) doesn't exist yet.
**Implements:** §4.9 items 2 & 4, §5.1, §8 (`OAuthAccessGrant`/`OAuthAccessToken` — tables already exist from Phase 2's Doorkeeper migration, unused until this phase).
**Depends on:** `implementation.md` Phase 7 (register-participant endpoint reuses its dedupe/validation rules). The original doc listed Phase 5 (event-show only returns approved events) as a dependency too — **that gate no longer exists** (`implementation_2.md` Corrections: the whole approval workflow was removed). The correct current-architecture equivalent is `Event#published?` (`published_at.present?`) — an event is public once published, full stop, no separate approval step in between.

- [ ] `client_credentials` grant flow — already configured (`config/initializers/doorkeeper.rb`'s `grant_flows %w[client_credentials]`, set at Phase 2, unused since). Set an explicit access-token TTL and enable refresh-token rotation (`access_token_expires_in`, `use_refresh_token`, `reuse_access_token: false` for single-use rotation) — currently commented out, running on Doorkeeper's own un-configured defaults.
- [ ] Tenant Admin Console surfaces its own `client_id`/`client_secret` — a read-only Settings screen (no self-service app creation/rotation for MVP, per the original doc's own §10.12 #17 citation). Currently `Account#oauth_application` exists in the DB but is never rendered anywhere in the admin UI at all.
- [ ] **Endpoint 1 — event show (read):** returns event/agenda/speaker/ticket-category data for one event, filtered to `published?` (not the removed `approval_status: approved`) server-side — never trust a client-side check.
- [ ] **Endpoint 2 — register participant (write):** creates a `Participant` scoped to the token's `Account`, reuses Phase 7's dedupe/validation rules, `source: client_api` (confirm this source value still exists on `Participant#source`'s enum — added in Phase 7, unaffected by anything since).
- [ ] `rack-attack` — the gem is already in the `Gemfile` (Phase 0.1) but has **no initializer at all yet**; add one now, default throttle keyed by application + IP (no per-tenant tiering needed for MVP).
- [ ] Both endpoints enforced through the same `Current.account` guard as every other tenant-scoped path — a token minted for Account A can never touch Account B's data. Confirm this composes correctly with `TenantResolvable`'s now-three-way host resolution (`implementation_2.md` Phase 19.3: a request host now resolves to an `Account`, an `Agency`, or neither) — an API request authenticates via Doorkeeper token, not host-based tenant resolution at all, so make sure the two mechanisms don't fight (e.g. an API request arriving on a *tenant* subdomain vs. an API-specific route/subdomain — decide and document which, this phase's own first real decision).

### Definition of Done
- [ ] Request spec: client-credentials grant issues a token; token correctly scoped to its Account on every subsequent call.
- [ ] Request spec: refresh flow rotates the refresh token, old one becomes unusable (replay rejected).
- [ ] Request spec: event-show endpoint 404s/omits an unpublished event even with a valid token.
- [ ] Request spec: register-participant endpoint rejects a request scoped to the wrong Account's event.
- [ ] Cross-tenant leak spec: Account A's token cannot read or write Account B's data under any endpoint — same pattern as every other cross-tenant spec in this app, just via a Bearer token instead of a Devise session.
- [ ] Manual QA: full `curl` walkthrough — obtain token, fetch a published event, register a participant, confirm it shows up in the Phase 7 admin participant list.

---

## Phase 26 — Next.js Public Event Site (final phase)

**Goal:** unchanged from the original doc — the attendee-facing application, deliberately last. A `frontend/` directory already exists as a sibling to this repo but is still the unmodified `create-next-app` scaffold (7 files total, none of them real feature code) — this phase is where it actually becomes the public site.
**Implements:** §4.3 (public routing), §4.8, §4.9 items 2 & 5 (BFF), §5.15 (public live ticker), §6 item 14.
**Depends on:** Phase 25 (OAuth API, this file), `implementation.md` Phases 6, 7, 9 (ticketing, participant rules, live stats — all already live and unaffected by the Agency pivot).

- [ ] Domain-resolution middleware: `events.{platform_domain}.com/{tenant_slug}/{event_slug}` (path-resolved) vs. verified custom domain (`Host`-resolved) — both branches converge on the same data-fetching code, calling Rails' `domain_resolution` endpoint with short-TTL caching. Note: `TenantDomain` (custom-domain model) already exists from Phase 0, scaffolded but never used for real — this phase is its first real consumer.
- [ ] BFF pattern: Next.js server (route handlers) is the only thing calling Rails; browser never calls Rails directly. Client-credentials token obtained/refreshed server-side (Phase 25's flow, consumed for real here for the first time).
- [ ] Event detail page (SSR/ISR): agenda, speakers, ticket categories — sourced from Phase 25's event-show endpoint, 404s cleanly for an unpublished event (not "unapproved" — see Phase 25's own dependency note on why that language changed).
- [ ] Registration form (CSR island): submits to Phase 25's register-participant endpoint, respects Phase 7.5's custom-field builder output and Phase 6's capacity/waitlist rules.
- [ ] Public live "seats remaining" ticker: subscribes directly to a scoped, read-only `PublicEventLiveChannel` (Action Cable, aggregate counts only — never participant-level data) via `@rails/actioncable`.
- [ ] `TenantDomain` custom-domain flow made real end-to-end: verification record generation, DNS polling job, Caddy on-demand TLS integration (infra-level, coordinate with deployment work).
- [ ] Basic accessibility pass (WCAG 2.2 AA) on the registration form and event page, since this is the one truly public-facing surface (§6 item 5).

### Definition of Done
- [ ] E2E spec (Playwright, matching `capybara-playwright-driver` already in the Gemfile, or a Next.js-native e2e runner): visit a published event's public URL on both the shared subdomain and a mock custom domain, confirm both resolve the same content.
- [ ] E2E spec: an unpublished event's public URL 404s regardless of how it's reached.
- [ ] E2E spec: submitting the registration form creates a real `Participant` visible in the admin console, respects a full ticket category (routes to waitlist).
- [ ] E2E/manual: open the event page in one browser, register from another, watch the "seats remaining" ticker update live with no refresh.
- [ ] Manual QA: full attendee journey — land on the public event page, register, receive confirmation email (already live, Phase 13), and (if a station is paired) observe the badge auto-print (already live, Phase 10).

---

## Cross-cutting checklist (unchanged, still applies to every phase above)

- [ ] Every new tenant-scoped table gets the cross-tenant leak spec pattern from Phase 0.
- [ ] Every new Super Admin action that touches tenant data gets an `AuditLogEntry` (Phase 23, this file) — once 23 lands, this stops being aspirational and becomes an actual review checklist item for every PR touching `SuperAdmin::`.
- [ ] Every new background job that touches tenant data explicitly sets `Current.account` at the top.
- [ ] Every new admin screen composes the shared partial library and webadmin template components — check the template first.
- [ ] Brakeman + Rubocop clean on every merged branch.
