# EventMeet — Phase-by-Phase Implementation Plan (Admin + Super Admin First)

**Status:** Draft v1
**Scope:** Rails Admin Console + Platform (Super Admin) Console only. The Next.js public event site is deliberately the **last** phase (§18), per the agreed sequencing — nothing in Phases 0–17 requires it to exist.
**Source of truth:** `backend/doc/requirement.md` (v10). Every phase below cites the requirement section(s) it implements. If the two documents ever disagree, `requirement.md` wins and this file should be corrected.

---

## Pre-flight decisions (resolve before or during Phase 0)

These are gaps between what `requirement.md` locks in and what's actually in the repo today. Flagging them now so they don't get silently decided mid-build.

1. **Job/cable backend mismatch.** `requirement.md` §4.10 confirms **Sidekiq** for background jobs and **Action Cable over Redis pub/sub** for real-time. The Rails 8 app as generated ships with `solid_queue`/`solid_cache`/`solid_cable` (DB-backed) instead. Recommendation: swap to `sidekiq` + `redis` + standard Action Cable (Redis adapter) in Phase 0, since real-time fan-out (§5.15, Phase 9) needs genuine pub/sub, not DB polling. Flag if you'd rather keep the Solid stack for MVP simplicity and revisit.
2. **`webadmin` template not yet in the workspace.** §5.14 says the template will be dropped directly into the project before UI work starts. Phase 0 has a checklist item to add it under `backend/app/assets` / `backend/vendor` (or wherever it's supplied) and inventory its components — every subsequent Admin/Platform UI phase assumes it's already there. If it isn't in hand yet, Phase 0's UI-shell items block until it is; backend/model work in Phase 0 doesn't.
3. **Authorization gem.** `requirement.md` asks for configurable roles + granular permissions (§5.1) but doesn't name a library. Recommend **Pundit** (policy-per-model, plays cleanly with `Current.account`/`AccountMembership` scoping) over CanCanCan. Called out in Phase 0.
4. **Pagination gem.** Not specified in requirements. Recommend **Pagy** (lighter/faster than Kaminari) for the participant/event lists that will get large.

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
- [ ] Resolve pre-flight decision #1 (Sidekiq/Redis vs. Solid stack); update `Gemfile` accordingly.
- [ ] Add `devise`, `doorkeeper`, `pundit`, `friendly_id`, `pagy`, `rack-attack`, `uuid7` (or Rails 8's native UUIDv7 PK support if available), `image_processing`.
- [ ] Confirm Postgres extension `pgcrypto`/`uuid-ossp` (whichever UUIDv7 generation path is chosen) is enabled in `schema.rb`.
- [ ] `bundle install`, commit `Gemfile.lock`.

### 0.2 Core tenancy models
- [ ] `Account` (tenant) — `id: uuid`, `name`, `subdomain_slug` (unique, indexed, reserved-word validation: `www`, `api`, `admin`, `app`, `mail`, `events`, `login`, apex), `status` (active/suspended), `plan` placeholder (fleshed out in Phase 15).
- [ ] `User` — `id: uuid`, Devise columns, `platform_staff` boolean (default false), `contact_num` (used later for WhatsApp, §8 v10).
- [ ] `AccountMembership` — join `User` ↔ `Account`, `role` (enum or string: Owner/Event Manager/Check-in Staff/Finance-readonly — §5.1), unique on `(user_id, account_id)`.
- [ ] `TenantDomain` — `account_id`, `domain`, `kind` (`subdomain`/`custom`), `verified_at`, `tls_status` — scaffolded now, fully used in Phase 18.
- [ ] `Current` (ActiveSupport::CurrentAttributes) — `Current.account`, `Current.user` — the single source of truth threaded through every request/job.
- [ ] Default-scope every future tenant-scoped model on `account_id` via a shared concern (`TenantScoped`) that raises if `Current.account` is nil when a scoped query runs outside an explicit platform-context override.
- [ ] Postgres Row Level Security policy on tenant-scoped tables as defense-in-depth (§4.2) — at minimum stubbed as a migration pattern to copy for every new tenant table from here on.

### 0.3 Host-based routing
- [ ] Rack middleware / `before_action` that parses `Host` once per request and resolves: apex domain → `Platform::` namespace (no `Current.account`), `{slug}.{platform_domain}` → tenant Admin Console (`Current.account` set), unrecognized/unverified host → 404.
- [ ] Local dev host aliasing (`lvh.me` or `/etc/hosts` entries: `acme.lvh.me`, `platform.lvh.me`) documented in `README.md` so every engineer can hit both tiers locally.
- [ ] Routing constraint classes (`ApexConstraint`, `TenantSubdomainConstraint`) with request specs proving each host resolves to the right namespace and that a subdomain request never leaks into `Platform::`.

### 0.4 Template integration shell
- [ ] Add the `webadmin` Tailwind template to the workspace (resolve pre-flight decision #2).
- [ ] Extract its base layout (sidebar, topbar, content region) into `app/views/layouts/admin.html.erb` and `app/views/layouts/platform.html.erb` — two layouts sharing partials, not a duplicated copy.
- [ ] Port one representative interactive template component (e.g. dropdown or mobile nav toggle) from its native JS to a Stimulus controller, establishing the porting pattern the rest of the build follows (§5.14 — no Alpine.js).
- [ ] `tailwindcss-rails` build pipeline confirmed working against the template's utility classes (no purge/missing-class regressions).

### Definition of Done
- [ ] `bin/rails db:migrate` runs clean from empty DB.
- [ ] Model specs: `Account`, `User`, `AccountMembership` validations + `subdomain_slug` reserved-word rejection.
- [ ] Request spec: hitting `acme.lvh.me/anything` with no matching `Account` returns 404; hitting a valid tenant subdomain sets `Current.account` (assert via a throwaway test route).
- [ ] **Cross-tenant leak spec pattern established**: two `Account`s, two records of some scoped test model, prove `Account.first`'s query never returns `Account.second`'s rows even when queried without an explicit filter.
- [ ] Both empty layouts render in a browser (`/up`-style smoke route) using the webadmin template's chrome.

---

## Phase 1 — Authentication & Login (Super Admin + Tenant Admin)

**Goal:** a Super Admin can log in at the apex domain; a tenant admin can log in at their subdomain. Two logins, two cookie scopes, one `User` table.
**Implements:** §4.9 item 1, §5.1, §5.6 (v6 — Devise-only, no SSO), §8 (platform_staff flag).
**Depends on:** Phase 0.

- [ ] Devise installed on `User` (`:database_authenticatable, :recoverable, :rememberable, :validatable`), async mailer delivery.
- [ ] Two Devise scopes/controllers or one controller branching on host: `Platform::SessionsController` (apex, only allows `platform_staff: true` users) and tenant `SessionsController` (subdomain, only allows users with an `AccountMembership` on `Current.account`).
- [ ] **Host-only session cookie** — explicitly not a wildcard `.{platform_domain}` cookie (§4.9 item 1). Verify via response headers in a request spec.
- [ ] Login views built from the webadmin template's auth screens (Phase 0.4 layout).
- [ ] Forced password reset / temp-password flow on invited users (`restrict_access`-equivalent enum, carried from baseline §3.1).
- [ ] Authorization skeleton: Pundit installed, `ApplicationPolicy` base class scoping every query through `Current.account`; a Super-Admin-only policy bypass for `Platform::` controllers.
- [ ] Logout, "remember me," basic account-locked/suspended (`Account.status`) rejection at login.
- [ ] Seed script / rake task to create one Super Admin user and one demo tenant + admin user for local dev and specs.

### Definition of Done
- [ ] Request spec: Super Admin can log in at apex, cannot log in at any tenant subdomain (wrong scope → rejected), and vice versa for a tenant admin.
- [ ] Request spec: a user with `AccountMembership` on Account A gets a 302/403 attempting to authenticate on Account B's subdomain.
- [ ] Cookie assertion spec: cookie set on `acme.lvh.me` is absent when a request is made to `beta.lvh.me` in the same test session.
- [ ] Manual QA: log in as Super Admin at `platform.lvh.me/login`, log in as tenant admin at `acme.lvh.me/login`, confirm both land on distinct (even if empty) authenticated pages.
- [ ] Suspended `Account`'s users cannot log in (redirect with a clear message).

---

## Phase 2 — Tenant Provisioning (Platform Console)

**Goal:** Super Admin can create a new Account (tenant) and its initial admin user from the Platform Console — the only way tenants come into existence (§4.1, §4.6 — no self-serve signup).
**Implements:** §4.1, §4.3 (Platform Console), §4.7 item 1, §4.9 item 4 (OAuth app auto-creation), §5.1.
**Depends on:** Phase 1.

- [ ] `Platform::AccountsController` — index/new/create/show; slug availability check (AJAX/Turbo Frame against reserved words + uniqueness) while typing.
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
- [ ] `Platform::EventReviewsController` — queue of pending events, sorted oldest-first, visually flags anything approaching the 24h SLA (§5.2).
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
- [ ] Every new Super Admin (`Platform::`) action that touches tenant data gets an `AuditLogEntry` once Phase 17 exists (retrofit earlier ones then).
- [ ] Every background job that touches tenant data explicitly sets `Current.account` at the top — a job that forgets this is called out in §4.2 as the #1 cause of cross-tenant leaks.
- [ ] Every new admin screen is built by composing Phase 0/3's shared partial library and webadmin template components — check the template first, per §5.14's working process, before writing new markup.
- [ ] Brakeman + Rubocop clean on every merged branch (already in the Gemfile's dev/test group).
