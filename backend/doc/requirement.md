# Multi-Tenant Event Management Platform — Requirements Document

**Status:** Draft v10
**Author:** Architecture (drafted with Claude Code)
**Source baseline:** Feature audit of the existing single-tenant Rails event management application in this repository
**Purpose:** Define the requirements for a new, multi-tenant SaaS event management platform, using the current system's proven feature set as the functional baseline and extending it with the capabilities a modern, competitive product needs.

**v2 decisions (stakeholder-confirmed, supersede the v1 open questions in §10):**
- Tenant isolation: **row-based** (single shared database, `account_id` on every tenant-scoped table).
- Platform billing: three tiers — **Basic** (500 participants, per-participant metered pricing), **Pro** (1,000 participants, plan pricing), **Business** (custom fixed pricing) — see §4.6.
- No existing tenant to migrate — this is a **greenfield** build, no data-migration workstream needed.
- Badge printing must support **Windows, macOS, and Ubuntu**, with **auto-print** (no manual click) — see §5.5.
- **No third-party integrations, no payment gateway, and no payment-related schema in this phase.** DTCM-style government ID integration, Stova-style external sync, client-portal webhooks, and Stripe/any payment gateway are all deferred — see §5.3, §5.12, §9.
- Mobile: **PWA**, not a native app, for this phase.

**v3 decisions (stakeholder-confirmed, extend v2 with the frontend/domain/auth architecture):**
- Admin console login/panel is served per-tenant at `{tenant_slug}.{platform_domain}/login`, with the subdomain chosen/reserved at account registration time — see §4.3.
- Admin console UI is built on a **tenant-provided Tailwind CSS template** (to be supplied) — see §5.14.
- Admin console authentication remains **standard Devise** (session cookie), carried forward from the baseline — see §4.9.
- The public, attendee-facing event website is a **separate Next.js (React + TypeScript) application**, headless, communicating with the Rails backend as an API-only client — see §4.8.
- When a tenant configures a custom domain (`{tenant_domain}.com`), that domain serves the Next.js event site (registration form included) for that tenant — see §4.3.
- A full API authentication strategy connecting Next.js, the print agent, and future integrations to Rails is now defined — see §4.9.

**v4 decisions (stakeholder-confirmed, refine tenant provisioning, finalize domain routing, and add the event-approval workflow):**
- Domain model finalized across three tiers: **Super Admin / Platform Console** at the bare apex domain (`{platform_domain}.com`, no subdomain), **tenant Admin Console** at `{tenant_slug}.{platform_domain}.com`, and the **default public event site** at a single shared `events.{platform_domain}.com` subdomain (path-resolved per tenant/event) — this **supersedes** the v3 recommendation of a per-tenant `{tenant_slug}.events.{platform_domain}` subdomain. See §4.3.
- Tenant accounts and their initial admin users are **provisioned by the Super Admin** via the Platform Console — there is no public self-serve sign-up in this phase. See §4.1, §4.6, §4.7.
- The Super Admin tracks, per tenant and per event, registered-participant volume and the resulting **computed income** under that tenant's plan (Basic/Pro/Business) — a usage/revenue read-model, not a payment-gateway integration; the "no payment schema" decision from v2 still holds. See §4.6, §4.7.
- **New: Event Approval gate.** An organizer-created event is not visible on the public Next.js site, and registration does not open, until the **Super Admin approves it**. See §5.2, §4.9.
- `doc/implementation.md` has been removed. A phase-by-phase build plan will be produced as a separate document once this requirements doc (now v4) is reviewed and approved.

**v5 decisions (stakeholder-confirmed, pulls one item forward into MVP):**
- **The tenant-scoped OAuth2 provider is now in MVP (Phase 1),** not deferred to Phase 2. Each Account can register its own OAuth application (Doorkeeper client) and issue tokens against a public REST API scoped to its own data — see §4.9, §5.1, §5.12. This is narrower than — and distinct from — the still-deferred §5.12 integration framework (DTCM/Stova-style connectors, outbound webhooks, payment gateways): it's the platform *exposing* a secured API for a tenant's own external clients to consume, not the platform *consuming* third-party services.

**v6 decisions (stakeholder-confirmed, narrows MVP login):**
- **SSO/SAML, OIDC, and SCIM are explicitly out of MVP.** Login for every user (tenant admin/staff and Super Admin alike) is **basic Devise email/password** in Phase 1, same as the baseline — see §5.1, §4.9 item 1. Enterprise SSO/SCIM stays a Phase 3 item (§9) to revisit only if a real enterprise tenant needs it.

**v7 decisions (stakeholder-confirmed, decouples the new product's tech/schema from the baseline repo and elevates real-time analytics to a flagship requirement):**
- The baseline Rails repo audited in §3 is a **requirements/feature reference only** — its schema, gem choices, and tooling are **not** a constraint on the new build. Where this doc already locked in a specific technology (Rails admin + Devise + Doorkeeper + Next.js public site — v3/v5), those stand because they were deliberate stakeholder decisions made in this conversation, not baseline carryover. Everything else is now chosen fresh for best fit — see new §4.10.
- **Real-time, no-refresh live dashboards are now a flagship MVP requirement**, not a nice-to-have: live registered-participant counts, live venue check-in/occupancy counts, and related live metrics update in connected dashboards via WebSocket/SSE push the instant the underlying event happens — see new §5.15.
- Schema is to be **optimized for this product, not copied from the baseline**: sortable external IDs (ULID) instead of raw sequential integers, native table partitioning for the highest-write tables, and denormalized live-counter tables purpose-built to serve the real-time dashboards without expensive `COUNT()` queries at scale — see §4.10, §8.
- Workflows are to be **simplified** relative to the baseline's rigid multi-step wizards wherever the rebuild gives an opening to do so — starting with event creation (§5.2).
- Several new USPs added, oriented around the real-time theme — see §6, items 14–18.

**v8 decisions (stakeholder-confirmed, resolves nearly every outstanding open question — billing mechanics, print-agent design, agency SSO, token lifecycle, and the remaining tech-stack picks):**
- **Billing is per event**, not per calendar period. Basic/Pro caps (500/1,000 participants) apply per event. Super Admin can raise an event's cap from the Platform Console; every increase is tracked and billed as overage. After the event completes, one invoice covers the plan/quotation amount plus tracked overage. See §4.6 (rewritten).
- **Business plan is quotation-gated**: Super Admin sends a fixed per-event quotation; the tenant must approve it before the event can even be created. See §4.6.
- **Manual billing workflow fully specified**: post-event invoice → tenant pays via bank transfer (NEFT) → tenant uploads the UTR/receipt and submits for review → Super Admin verifies and marks it paid. Still no payment gateway/PSP — a structured manual-proof workflow, consistent with the v2 decision. See §4.6, §8.
- **Print agent design finalized**: Electron, using Chromium's native silent-print API, packaged per OS with auto-update. See §5.5.1.
- **`govt_id` ships as a plain participant field in Phase 1, with no government-ID-provider API integration** — the confirmed answer to "which integration first" is: none. See §5.4.
- **Payments confirmed fully out of scope for this document** — to be designed fresh in a future round, not extrapolated from anything here.
- **Hosting: self-hosted, single VPS** (Hetzner Cloud a likely, not-yet-final candidate) running Rails, Next.js, and the print-agent's backend broker together — architecture designed around this (Docker Compose + Caddy with on-demand TLS). See §4.10.
- **Cross-tenant SSO designed for agency tenants**: an agency managing several tenant Accounts gets a secure relay-token SSO flow between them, without weakening the host-only-cookie security model, and without granting Platform Console/Super Admin access. See new §4.11.
- **Tenant Server Key retired** — replaced by reusing each tenant's own OAuth application (created by the Super Admin at tenant-provisioning time) with a short-lived access token + refresh token, used by both the Next.js BFF and the tenant's own external tooling. See §4.9 (restructured).
- **MVP public REST API surface confirmed**: exactly two endpoints — event show (read) and register participant (write) — both OAuth-protected. No per-tenant/per-plan rate-limit tiering needed. See §4.9.
- **Remaining tech-stack picks confirmed**: Turbo Streams/Action Cable as the single real-time transport (admin and public site both); UUIDv7 primary keys; monthly range partitioning for `ScanEvent`/`Attendance`; Postgres full-text search; New Relic. See §4.10.
- **Badge design tool recommended**: GrapesJS for the WYSIWYG badge/wristband editor (Grover stays for PDF rendering) — see §4.10, §5.5.
- Hub-listing pages are **not required for MVP** — only direct `/{event_slug}` URLs, per the confirmed URL patterns. See §4.3.

**v9 decisions (stakeholder-confirmed, closes out the remaining v8 open questions):**
- **Gupshup confirmed as the platform's WhatsApp provider — a second, narrow MVP exception to "no third-party integrations."** Ships for Super-Admin-to-tenant operational notifications (event rejection, invoice sent, quotation sent/revised, payment verified) alongside email — not the broader attendee-facing WhatsApp campaign layer, which stays deferred. See §5.2, §5.10, §5.12.
- **Hosting/deployment confirmed: Docker-based deployment provisioned with Terraform** (infrastructure-as-code) — pairs with the Caddy/Docker Compose design from v8 and is provider-agnostic (works whether the final VPS provider is Hetzner or otherwise). See §4.10.
- **Capacity-adjustment overage rate: defaults to the plan's decided rate, with Super Admin override flexibility** per adjustment (e.g. a premium or discounted rate for a specific capacity increase) — see §4.6, §8.
- **Quotation rejection/revision workflow specified:** the tenant (merchant) can reject a quotation with a note explaining why; the Super Admin corrects it and sends a revised quotation — repeatable until approved. See §4.6, §8.
- **Single-VPS resilience trade-off: acknowledged**, no further design change needed for MVP.
- **Cross-tenant agency SSO (§4.11): confirmed for Phase 1/MVP** — not a fast-follow.
- **General scoping principle (v9):** unless a requirement in this document is explicitly marked deferred/Phase 2+/Phase 3, it is **in scope for MVP/Phase 1** — "recorded" means "MVP" by default from this point forward.

**v10 decisions (stakeholder-confirmed, closes out the last open items):**
- **Gupshup account/sender-number/template setup is the stakeholder's own responsibility**, not a platform-engineering task — implementation can assume the credential exists when Phase 1 build reaches the WhatsApp-notification work. See §5.10, §10.16.
- **Phone number for WhatsApp delivery: use the existing `contact_num` field on `User`** — no separate WhatsApp-specific field. See §8.
- **Quotation revision limit: 3 rejections.** After a third rejection, the `Quotation` moves to a **`cancelled`** state (not just staying `rejected`/re-offerable indefinitely) — the Business-tier event request ends there rather than continuing to negotiate. See §4.6, §8.

---

## 1. Executive Summary

The existing application is a single-organization, single-database Rails app that runs on-site/virtual events end-to-end: event setup, ticket categories, registration, payments, badge design & printing, QR/barcode/RFID check-in, session-level attendance, speaker/agenda management, bulk import/export, and integrations with a government ID system (DTCM) and a third-party registration platform (Stova). It is operationally solid (Sidekiq background jobs, Stripe payments, Cloudinary storage, PDF/badge generation) but is architecturally **single-tenant**: one `users` table owns all `events`, there is no organization/account boundary, no per-tenant branding beyond a single `Client` record per event, and integrations are wired via global `ENV` variables (e.g. `STOVA_EVENT_SLUG`, `INTEGRATE_THIRD_PARTY_FOR_EVENT`) rather than per-tenant configuration.

The new product should keep everything that works — the registration → payment → badge → check-in pipeline is genuinely full-featured — but rebuild it on a **multi-tenant foundation** where each customer (organizer company) is an isolated Account/Organization with its own users, branding, billing, integrations, and data, while the platform operator retains cross-tenant administration and observability.

This document is organized as:
1. Baseline capabilities inventoried from the current system (§3)
2. Multi-tenancy architecture requirements (§4)
3. Full functional requirements for the new product, by module (§5)
4. New/"out of the box" capabilities not present today but expected of a modern event platform (§6)
5. Non-functional requirements (§7)
6. High-level data model (§8)
7. Suggested phased roadmap (§9)
8. Open questions & assumptions (§10)

---

## 2. Goals & Non-Goals

**Goals**
- Support many independent organizer accounts (tenants) on one platform, each running many events, with hard data isolation.
- Preserve the depth of the current registration/badge/check-in workflow — this is the product's core differentiator.
- Make integrations (government ID systems, external registration platforms, CRMs, payment gateways) pluggable per tenant instead of hardcoded per deployment.
- Add the collaboration, engagement, and analytics features attendees and organizers expect from a 2026-era platform (sponsors/exhibitors, networking, live engagement, richer reporting).
- Provide a self-serve billing/subscription path so the platform itself is sellable as a SaaS product.

**Non-Goals (for this document)**
- A full field-level ERD/migration listing — §8 is a high-level entity map, not the final schema; that's a follow-up engineering artifact.
- Detailed UI/UX designs — captured separately.
- Migration plan/data backfill from the current system — recommended as a follow-up doc once this is approved.

**Note on technology (updated, v7):** the baseline repo audited in §3 is a *requirements reference only* — its schema and tooling are not a constraint on the new build. Concrete technology choices **are** in scope for this document (see §4.10): Rails (admin/backend), Devise, Doorkeeper, and Next.js are stakeholder-confirmed (v3/v5); everything else is chosen fresh, optimized for a multi-tenant, real-time-analytics-first product rather than inherited from the baseline.

---

## 3. Baseline: What the Current System Already Does

This is the proven functional core to carry forward, grouped by domain. Each item maps to real code in this repo so nothing is lost in translation.

### 3.1 Accounts & Access
- Users with roles: `admin`, `organizer`, `superadmin` (`app/models/user.rb`), plus a granular `permissions` array (currently just one flag: block an organizer's access to the Participants section).
- Forced password reset for newly created organizer accounts (temp password + `restrict_access` enum).
- Devise-based auth (email/password), with async email delivery.
- OAuth provider support via Doorkeeper (`oauth_applications`, `oauth_access_grants/tokens`) for third-party API consumers.

### 3.2 Event Lifecycle
- Event creation wizard with step tracking (`completed_tab`: new → schedule → speakers → visitors → payment → badge → preview) so organizers can save and resume setup.
- Event modes: `on_site` / `virtual` (with meeting link), banner orientation, address/location.
- Status lifecycle: `draft → up_coming → live → completed`, auto-transitioned daily by a scheduler job (`EventSchedularJob`) that also auto-checks-out/marks-absent attendees when an event ends.
- Configurable, per-event **participant field set** (`participant_fields` jsonb) — organizers choose which registration fields are mandatory per event.
- Seat-limited events with capacity validated against the sum of ticket-category allocations.
- Friendly/SEO slugs for public event URLs.

### 3.3 Ticketing ("Visitors" = ticket categories)
- Multiple ticket categories per event, each with its own price (`money-rails`, multi-currency-ready field shape, currently fixed to AED), Stripe product/price sync (`VisitorJob`), inventory (`total/sold/remain_ticket_count`), and document-required flag.
- Automatic ticket count reconciliation (`Event#sync_tickets`) and per-category sellout validation at registration time.

### 3.4 Registration & Participant Management
- Public self-registration form per event + admin-side manual creation.
- Field-level requiredness driven by both event config and badge-mapping config.
- Duplicate protection (unique email/contact/govt ID/RFID per event).
- Multiple identifier types per participant: internal `hex_id`, organizer-supplied `client_participant_id` (auto-generated if missing), government ID (`govt_id`), RFID tag (`rf_id`).
- Photo upload or externally-hosted photo URL fallback.
- Document upload (e.g., passport) when a ticket category requires it.
- Department/company/position/nationality/country metadata, with country/nationality ISO lookups.
- Source tracking: `manual`, `upload` (bulk import), `client_api` (external system).
- Admin search/filter across identifier fields; paginated listing.
- Bulk destroy, per-participant edit/delete.

### 3.5 Payments
- Stripe Checkout integration: customer creation, per-ticket-category product/price, checkout session, success/cancel handling.
- `Order` + `PaymentDetail` with status machine (`not_paid/success/failed/tampered/cancelled`) and raw gateway response storage.
- Cash/offline payment mode with transaction ID/receipt number capture.

### 3.6 Badge Design & Printing
- In-house **badge template designer** storing raw HTML/CSS content plus a field-mapping list (`Badge#content`, `#mapping`) and a background image + logo (Active Storage).
- Token-based badge templating engine (`BadgeReformService`) that substitutes placeholders (`$NAME$`, `$PHOTO$`, `$DTCMQRCODE$`, `$STZBARCODE$`, `$OTHER1..3$`, etc.) with live participant data, QR/barcodes, and images (base64-inlined for PDF rendering).
- Badge vs. wristband output type per event.
- Configurable physical badge size (cm), rendered to PDF via `wicked_pdf` at correct DPI/page size.
- Server-side printing via `lpr` (direct to OS default printer) for front-desk/kiosk stations, plus browser download.
- **Kiosk mode**: documented Chrome kiosk-printing launch flags for unattended self-service check-in/badge stations.
- **Bulk print** workflow: paginated queue of pending/failed prints, batch selection, per-badge failure marking, re-print.
- QR code (`rqrcode`) and Code128 barcode (`barby`) generation, in two independent "slots" (e.g., an internal ID code and a separate government-ID code) so one badge can carry two distinct scannable codes.

### 3.7 Check-in & Attendance
- Public check-in page per event, participant located by scanning **any** of: hex ID, government ID, RFID, or client participant ID.
- Toggle check-in/check-out with a **30-second anti-double-scan debounce**.
- Session-level check-in in addition to event-level, with per-session seat-limit enforcement.
- Attendance direction (`from`: event vs. session) and status (`check_in/check_out/manual_check_out/absent`) tracked historically, not just as current state.
- "Scan → print badge → mark attendance" combined flow for one-tap onsite registration desks.
- Time-spent-in-event / time-spent-in-session computation from paired check-in/check-out events.
- Virtual event redirect-on-check-in (scan badge → auto-mark attendance → redirect to meeting link).

### 3.8 Agenda, Speakers, Sessions
- Speakers with company/bio metadata and photo.
- Schedule items (talks) linked to a speaker, with start/end time and details.
- Sessions (breakout rooms/tracks) with independent seat capacity and their own check-in.

### 3.9 Sponsors/Clients & Branding
- `Client` model: per-event sponsor/co-branding record with logo, custom email body/footer — used to white-label the registration-confirmation email and PDF per event.
- Per-event custom banner/avatar.

### 3.10 Communications
- Registration-confirmation email (customizable body/footer via `Client`), queued via Sidekiq with delivery-state tracking (`state_of_mail: pending/sent/failed`).
- "Resend invitation" per participant and "send to all pending" batch job.
- Welcome email on user (organizer) creation.

### 3.11 Data Import/Export
- XLSX participant bulk import (`roo`) with fuzzy matching against existing records (govt ID → email+name → email → phone) to avoid duplicates, photo resolution from a cloud folder by filename, and downloadable import templates.
- Bulk government-ID (DTCM) code pool import.
- XLSX participant export (`caxlsx`) with attendance/session/time-spent columns, generated async and delivered via a signed cloud URL, with progress polling.

### 3.12 Third-Party / Government Integrations
- Generic authenticated API client base class (`ApiGatewayService::BaseClient`) with token caching in Redis, auto re-auth on 401, retry with backoff — used as the base for:
  - **DTCM integration**: government tourism ID assignment. Two modes: (a) pull a code from a pre-imported pool with row-level locking (`DtcmAssignmentService`), or (b) live-purchase a government ID via API at print time (`DtcmRegistrationJob`).
  - **Stova integration**: scheduled pull-sync of attendee registrations from an external event-registration platform into local `Participant` records, matched by ticket category name and deduplicated by email.
  - **Client Portal / CMF gateway**: push participant create/update/print events out to an external client system (`ApiGatewayJob`), gated by event.
- Public JSON API (`/api/v1`) for participant upsert/lookup and remaining-ticket-count, intended for headless/external registration front-ends.

### 3.13 Misc / Novel Features Worth Preserving
- **RFID/QR-triggered video wall**: scanning a badge/RFID tag at a kiosk can broadcast a specific video to a specific screen in real time via Turbo Streams (`VideosController#scan`) — used for personalized on-site experiences (e.g., welcome videos per sponsor tier).
- Sidekiq Web UI + `sidekiq-status` for operational visibility into async jobs (imports, exports, mailers, integrations).

---

## 4. Multi-Tenancy Architecture Requirements

This is the central architectural change from the current system and should be treated as the foundation everything else is built on, not a bolt-on.

### 4.1 Tenant Model
- Introduce a first-class **Account/Organization** (tenant) entity above `User` and `Event`. Every `Event`, `User`, ticket category, integration config, branding asset, and billing record belongs to exactly one Account.
- A **Platform** layer sits above all tenants for the SaaS operator: cross-tenant search, impersonation-with-audit-trail for support, global usage dashboards, and platform billing.
- Users can belong to more than one Account (e.g., an agency running events for multiple clients) with a distinct role per Account membership — model as a join entity (`AccountMembership`) rather than a single `role` column on `User`.
- **Tenant provisioning (confirmed, v4):** Accounts are **not** self-service. A Super Admin (platform-operator staff) creates the Account and its initial admin `User`(s) from the Platform Console (§4.3, §4.7); the tenant's own admins then invite additional team members within their Account via `AccountMembership`, as described above.
- **Platform staff are a distinct population from tenant users** — modeled as `User` rows with a `platform_staff`/superadmin flag and **no** `AccountMembership` at all (they aren't a member of any tenant's Account). They authenticate at the apex domain, not at any tenant subdomain — see §4.3, §4.7.

### 4.2 Isolation Strategy
- **Decision:** row-level isolation via a mandatory `account_id` on every tenant-scoped table, enforced at the ORM layer (default-scoped, never optional) plus database-level Row Level Security as defense-in-depth. This is cheaper to operate than database-per-tenant at typical event-SaaS scale and still allows a later move to schema/DB-per-tenant for large enterprise customers if needed — that door stays open since nothing here precludes it later.
- Every query path (web, API, background job, console) must be tenant-scoped by construction — a job that forgets to filter by `account_id` is the #1 cause of cross-tenant data leaks in SaaS systems and must be prevented structurally (e.g., current-tenant context required to open a DB session), not just by convention.
- File/object storage (badges, photos, documents, exports) must be namespaced by tenant in the storage path/bucket, independent of the DB isolation choice.

### 4.3 Tenant Identity & Routing

Three host tiers, each serving a distinct application and audience — the domain a request arrives on is the single source of truth for both *who* it's for and *which app* handles it:

| Host | Application | Audience |
|---|---|---|
| `{platform_domain}.com` (apex, no subdomain) | Rails — **Platform Console** | Super Admin (platform-operator staff) |
| `{tenant_slug}.{platform_domain}.com` | Rails — **Admin Console** | Tenant organizer staff |
| `events.{platform_domain}.com` | Next.js — **Public Event Site** (default) | Anonymous attendees, before a tenant has a custom domain |
| `{tenant_domain}.com` (verified custom domain) | Next.js — **Public Event Site** (custom) | Anonymous attendees, once the tenant configures their own domain |

**Platform Console — apex domain (confirmed, v4):**
- The bare platform domain (no subdomain) is reserved exclusively for the Super Admin console: create tenant Accounts, create each tenant's initial admin user(s), review/approve events (§5.2), monitor usage and computed income per tenant/event (§4.6), and the rest of §4.7's cross-tenant administration.
- Served by the same Rails app as the Admin Console but under a distinct routing namespace (e.g. `Platform::`), gated by the `platform_staff`/superadmin flag from §4.1, and — critically — **not tenant-scoped**: requests to the apex domain never set `Current.account`, and every `Platform::` controller is explicitly written to operate across tenants rather than being blocked by the row-level-isolation guard in §4.2.

**Admin Console — tenant subdomain (confirmed):**
- Every Account gets a subdomain slug, chosen by the Super Admin at account-creation time (format: lowercase, alphanumeric + hyphen, 3–63 chars; reserved-word blocklist covering `www`, `api`, `admin`, `app`, `mail`, `events`, `login`, and the apex itself).
- Admin login and the entire admin console live at `{tenant_slug}.{platform_domain}.com` — e.g. `acme.platform.com/login`. This subdomain is served exclusively by Rails.
- Tenant resolution for the admin app is by subdomain only, parsed once from the `Host` header (Rack middleware / `before_action`) and threaded through the whole request — never resolved from a user-editable param.

**Public Event Site — shared default subdomain + optional custom domain (confirmed, v4 — supersedes the v3 per-tenant-subdomain recommendation):**
- All tenants without a configured custom domain share a **single** subdomain, `events.{platform_domain}.com`, served by the Next.js app. Tenant and event are resolved from the **URL path**, not the host, on this domain: `events.{platform_domain}.com/{tenant_slug}/{event_slug}` for a specific event page — resolve tenant by `tenant_slug`.
- A verified custom domain (`{tenant_domain}.com`) serves the **same** Next.js app and the **same** content, but resolves the tenant from the `Host` header instead of a path segment: `{tenant_domain}.com/{event_slug}` for a specific event — resolve tenant by domain.
- **Hub/listing pages not required for MVP (confirmed, v8):** a page listing all of a tenant's events (`events.{platform_domain}.com/{tenant_slug}` alone, or `{tenant_domain}.com/` alone) is out of scope for Phase 1 — only direct `/{event_slug}` event pages are needed. Add a hub listing later if organizers ask for it.
- This means the Next.js domain-resolution middleware has two branches: on `events.{platform_domain}.com`, resolve tenant from the first path segment; on any other verified host, resolve tenant from the host itself. Both branches converge on the same downstream data-fetching code once `{tenant, event_slug}` is known.
- Keeping the admin subdomain (`{tenant_slug}.{platform_domain}.com`) and the public subdomain (`events.{platform_domain}.com`) on clearly distinct hosts still matters for the cookie-isolation reasoning in §4.9 — the admin session cookie must never be reachable from the public site's origin.

**Custom domain onboarding:**
- Tenant (or the Super Admin on their behalf) adds a custom domain from the admin console → platform generates a verification record (DNS TXT or CNAME target) → DNS is updated → a background job polls and confirms ownership → automated TLS provisioning follows. **Confirmed approach (v8, given the self-hosted single-VPS deployment, §4.10): Caddy as the reverse proxy in front of both Rails and Next.js, using its built-in on-demand TLS** — Caddy requests a certificate the first time a verified custom domain is hit, checking back with Rails to confirm the domain is real and verified before issuing it. Purpose-built for exactly this problem (self-hosted, arbitrary customer-owned domains), avoiding hand-rolled ACME scripting → domain marked active and Next.js begins resolving it to that tenant's event site.
- An unverified domain is inert — never resolve or serve tenant data for an unverified `Host` header.

**Domain resolution for Next.js (which has no tenant database of its own):**
- Next.js resolves `{tenant, event}` from the incoming request's `Host` header (and, on the shared `events.` domain, the first path segment) by calling a Rails endpoint (e.g. `GET /api/v1/public/domain_resolution?host=...&path=...`) from middleware, with a short-TTL cache so this doesn't add a round-trip to every request.
- This lookup must never trust a client-supplied tenant ID — `Host` (and, where applicable, the path segment on the shared domain) is the only source of truth for which tenant a request belongs to.
- **Approval gating happens here too**: the resolution/event-detail response only returns a visible event if it has been approved by the Super Admin (§5.2) — an unapproved event resolves as not-found on the public site regardless of how its URL is reached.

### 4.4 Per-Tenant Configuration (replaces today's global ENV vars)
Everything that is currently a global environment variable must become per-tenant, admin-configurable data:
- `STOVA_EVENT_SLUG`, `INTEGRATE_THIRD_PARTY_FOR_EVENT`, `RFID_VIDEO_MAPPING`, `EMAIL_PDF_V1_TEMPLATE_FOR`, `CLOUD_BULK_FOLDER`, `API_EMAIL`/`API_PASSWORD` → all become rows in a per-tenant (and often per-event) **Integration Settings** table, editable from an admin UI, with secrets stored encrypted (e.g., Rails encrypted attributes / a secrets manager), never in code or shared `.env` files.
- Each tenant can enable/disable/configure integrations (DTCM-style government ID systems, Stova-style external registration sync, client-portal webhooks, payment gateways) independently.

### 4.5 Tenant-Level Branding & White-Labeling
- Logo, color palette, custom email sender domain (SPF/DKIM), custom PDF/badge letterhead, and (for higher tiers) fully white-labeled public pages with no platform branding.
- The existing per-event `Client` (sponsor branding) concept is preserved *underneath* tenant branding — i.e., branding is layered: Platform → Tenant (Account) → Event → Ticket-category/Sponsor.

### 4.6 Tenant Lifecycle & Billing **[fully specified, v8]**

**Confirmed plan structure:**

| Plan | Included Participants | Pricing Model | Notes |
|---|---|---|---|
| **Basic** | Up to 500 registered participants **per event** | Metered — amount per registered participant | Entry tier |
| **Pro** | Up to 1,000 registered participants **per event** | Plan amount **per event** | Higher cap |
| **Business** | Custom, per event | Fixed amount, quoted and approved per event (e.g. a flat ~30k-style figure) | Quotation-gated — see below |

- **Billing period (confirmed, v8): billing is per event, not per calendar period.** Every plan's participant cap and pricing apply to a single event, not to the Account as a whole or to a rolling monthly/annual window. An Account running five events on the Basic plan is billed five times, once per event.
- **Provisioning (confirmed, v4):** every tenant is created by the **Super Admin** via the Platform Console (§4.3, §4.7) — no public self-serve sign-up. The plan (and, for Business, the quotation) is really chosen **per event**, not just once per Account.
- **Overage handling (confirmed, v8, rate flexibility added v9):** the Super Admin can **increase a specific event's participant cap** directly from the Platform Console (e.g. a Basic event capped at 500 gets bumped to 650 mid-event). Every increase is logged as a `CapacityAdjustment` (event, previous cap, new cap, increased by, timestamp — §8) and priced as extra participants beyond the plan's originally-included volume — tracked, not charged in real time (still no payment gateway, §5.3/§5.12). **The per-extra-participant rate defaults to the plan's decided rate, but the Super Admin can override it per adjustment** (e.g. a premium rate for a last-minute increase, or a discounted rate for a specific tenant) — the override is optional and recorded alongside the adjustment, not a separate pricing system. This is what makes "500 participants" a *soft* cap in practice: registrations aren't hard-blocked at the limit, the Super Admin can lift it, and the lift is what gets billed.
- **Business plan quotation gate (new, v8, revision flow specified v9):** organizer requests a Business-tier event → Super Admin prepares and sends a **quotation** (a fixed amount for that specific event) → visible to the tenant in their admin panel → **the tenant must approve the quotation before the event can be created at all**. A hard gate: no quotation approval, no event. **If the tenant rejects the quotation, they attach a note explaining why; the Super Admin revises the amount and sends it again.** This can repeat up to **3 rejections** — on the **third rejection, the `Quotation` moves to `cancelled`** and the negotiation ends there (the tenant would need to start a fresh Business-tier request to try again, not resume a cancelled one). See §8 for the `Quotation`/`QuotationRevision` entities that model this negotiation history.
- **Computed income tracking (v4, refined v8):** the Platform Console shows, per tenant and per event, the registered-participant count, any capacity adjustments, and the resulting computed amount owed (base plan/quotation amount + tracked overage) — a read-model, not a transaction, until it becomes the invoice below.
- **Manual billing operations (fully specified, v8)** — entirely without a payment gateway/PSP:
  1. **Event completes** (status transitions to `completed`, §3.2).
  2. **Super Admin raises an `Invoice`** for that event — base plan/quotation amount + tracked `CapacityAdjustment` overage — and sends it to the tenant (visible in their admin panel, plus an email notification).
  3. **Tenant reviews the invoice** and pays **outside the platform** via bank transfer (NEFT).
  4. **Tenant submits payment proof**: uploads the UTR (bank transaction reference) and/or a receipt, creating a `PaymentSubmission` linked to the invoice, status `pending_review`.
  5. **Super Admin verifies** the UTR/receipt and either marks the `PaymentSubmission`/`Invoice` **paid**, or rejects it back to the tenant with a reason (e.g. UTR doesn't match, amount short) for resubmission.
  - This is a **structured manual-proof workflow**, not a payment gateway integration — no card processing, no PSP, no automated charge collection — so it does not conflict with the v2 "no payment gateway/schema" decision. It does need real schema (`Invoice`, `PaymentSubmission`, `CapacityAdjustment`, and for Business plans, `Quotation`) — see §8.
- Platform-level subscription billing is conceptually **separate** from any future per-event attendee ticket payments (§5.3) — "tenant pays platform" and "attendee pays organizer" are two different flows and must not be conflated in the data model even though neither is wired to a gateway.

### 4.7 Cross-Tenant Platform Administration

The Super Admin's Platform Console (§4.3) is where the platform operator does everything that spans or sits above individual tenants:

- **Tenant provisioning (confirmed, v4):** create a new Account (choose/reserve its subdomain slug, assign a plan), and create that tenant's initial admin `User`(s) — see §4.1, §4.6. The tenant's own admins take over day-to-day user management within their Account from there.
- **Event approval (new, v4):** review events submitted by organizers and approve or reject them — an event is not visible on the public Next.js site and does not accept registrations until approved. See §5.2 for the workflow and the approval-state data model.
- **Usage & income tracking (new, v4):** view registered-participant volume and computed income per tenant and per event, against each tenant's plan — see §4.6.
- Tenant search, suspend/reinstate, impersonate-with-audit-log (impersonation must always write an `AuditLogEntry`).
- Global job/queue health, global error/integration-failure dashboards, feature-flag rollout per tenant (for gradual feature releases).

### 4.8 Frontend Architecture: Admin Console vs. Public Event Site

Two separate applications, deliberately:

| | Admin Console | Public Event Site |
|---|---|---|
| **Audience** | Organizer staff (authenticated) | Anonymous attendees, search engines |
| **Framework** | Rails, server-rendered (ERB/Turbo/Stimulus), Devise session auth | Next.js (React + TypeScript), headless, consumes Rails as an API |
| **UI** | Tenant-provided Tailwind CSS admin template (§5.14) | Independent Tailwind-based design system, themed per tenant branding (§4.5) |
| **Rendering** | Server-rendered HTML per request | SSR/ISR for public pages (SEO, fast first paint), CSR for the registration form's interactive bits |
| **Hosting** | Same Rails deployment as the API | Deployed separately (hosting platform TBD — see §10.4) |
| **Auth** | Devise session cookie + CSRF | None for anonymous visitors — see §4.9 for how it talks to Rails |

This split exists because the two apps have fundamentally different requirements: the admin console needs deep, stateful, authenticated CRUD across every module in §5, while the public site needs to be fast, SEO-friendly, cacheable, and safe to expose to the entire internet with zero authenticated surface area. Building both in Rails would force compromises on both; keeping them separate lets each be built for what it actually needs to do.

### 4.9 API Authentication Strategy

This is the connective tissue between the two apps (and, later, the print agent and any external integrations) and the highest-risk area to get wrong in a multi-tenant system, so it's specified explicitly rather than left to be improvised during implementation.

**1. Admin Console → Rails (same app, not really an "API" call):**
- Standard Devise session cookie (`:database_authenticatable, :recoverable, :rememberable, :validatable`, carried forward from the baseline) plus Rails CSRF protection. No token/API-key mechanism needed here — this is a traditional server-rendered app.
- **Cookie scope:** the session cookie is **host-only**, scoped strictly to `{tenant_slug}.{platform_domain}` — *not* a wildcard `.{platform_domain}` cookie. This is deliberate: a wildcard cookie would also be sent to the public-site subdomain, which has no reason to ever see an admin session cookie. The trade-off is that a user belonging to multiple Accounts (§4.1) must re-authenticate when switching tenant subdomains — **solved, not just deferred, as of v8: a relay-token cross-tenant SSO flow is fully designed for exactly this in new §4.11**, preserving this host-only-cookie model rather than weakening it.

**2. Public Event Site (Next.js) → Rails, and any tenant's own external tooling → Rails — unified via the tenant's OAuth application (redesigned, v8):**
- **Pattern: Next.js as a Backend-For-Frontend (BFF).** The attendee's browser only ever talks to the Next.js app (same origin — whichever public domain resolved, default subdomain or custom domain). The browser **never** calls Rails directly. Next.js's own server (route handlers/server actions) is the only thing that calls Rails, server-to-server.
- **Credential — the standalone `Tenant Server Key` is retired (v8), replaced by reusing the tenant's own OAuth application:** at tenant-provisioning time, the Super Admin creates one OAuth application per tenant (item 4 below, §5.1) — that same application is what the Next.js BFF authenticates with, via an OAuth2 **client-credentials grant**: Next.js exchanges the application's `client_id`/`client_secret` (stored only in the Next.js server's environment, never a client bundle) for a **short-lived access token** (recommended TTL: 15–60 minutes) plus a **refresh token**. Every Rails call carries the access token (`Authorization: Bearer ...`); Next.js proactively refreshes before expiry (or reactively on a 401) using the refresh token, which is itself rotated on every use (single-use, via Doorkeeper's refresh-token-rotation support) so a captured refresh token has a narrow window of use. This is more secure than a single long-lived opaque secret sent on every request: the credential that travels with every API call expires quickly, and the long-lived secret is only used for the infrequent refresh step.
- **MVP API surface — confirmed, v8: exactly two endpoints**, both OAuth-protected and scoped to the requesting application's own Account (never cross-tenant, enforced by the same `Current.account` guard as everything else, §4.2): **event show** (read — event/agenda/speaker/ticket-category data for rendering public pages, filtered to `approval_status: approved`, §5.2) and **register participant** (write — registration submission). Everything else (waitlist join, cancellation, richer resources) is a later addition once the MVP surface is proven, not a Phase 1 requirement.
- **Rate limiting:** a single sane default throttle (`rack-attack`, keyed by application + IP) is enough for MVP — **no per-tenant or per-plan-tier rate-limit tiering is required** (confirmed, v8).
- **Approval gating:** the event-show endpoint enforces `approval_status: approved` server-side — Next.js never decides this client-side, and a not-yet-approved event's URLs simply resolve as not-found on the public site (§5.2, §4.3).
- **Attendee self-service (Phase 2+, when built):** no full account/password system for attendees, mirroring the baseline's slug/hex-ID lookup pattern — use signed, single-purpose, short-lived **magic-link tokens** rather than a Devise account per attendee.

**3. Print Agent → Rails (§5.5.1):**
- Station-scoped **JWT** (claims: `account_id`, `event_id`, `station_id`, short expiry), issued when the agent is paired via a one-time pairing code entered into the agent app from the admin console. Delivered over a persistent authenticated channel (Action Cable/WSS, §4.10) so print jobs can be pushed, not polled. Revocable per station at any time from the admin console; the agent can only pull jobs addressed to it and report status back — no broader API surface.

**4. OAuth application provisioning — confirmed for MVP, refined v8:**
- Reuses the baseline's Doorkeeper dependency. **Each tenant's OAuth application is created by the Super Admin at tenant-provisioning time** (v8 — not a tenant self-service "register your own app" screen for MVP, simpler than originally scoped in v5): one application per Account, generated automatically alongside the Account itself in the Platform Console flow (§4.7). The tenant sees their `client_id`/`client_secret` in their own admin panel (to configure their own external tooling if they have any), and it's the same credential the Next.js BFF uses (item 2 above) — one mechanism, two consumers.
- This is distinct from — and not blocked by — the rest of §5.12, which remains deferred: DTCM/Stova-style *inbound* integrations, outbound webhooks, native connectors, and payment gateways are all about the platform consuming or pushing to *other* systems; this item is the platform *exposing* itself as an API provider, which has no payment/third-party dependency and no reason to wait.

**5. Internal/service-to-service (Sidekiq, etc.):**
- In-process, no additional auth required at current scale. Flagged as a future concern (mTLS/signed service tokens) only if the system splits into multiple deployable services later — not a Phase 1 concern.

### 4.10 Technology Stack: Confirmed & Recommended **[updated, v8 — most picks now confirmed]**

The baseline repo (§3) established *what* the product needs to do — it is not a constraint on *how* the new product is built. This section separates what's locked in (deliberate stakeholder decisions) from what's still a working recommendation.

**Locked in (stakeholder-confirmed):**
- Rails for the backend + Admin Console, Devise for admin authentication, Doorkeeper for the tenant OAuth application (now also the Next.js BFF credential, §4.9), row-based Postgres multi-tenancy — v3/v5/v8.
- Next.js (React + TypeScript) for the public event site, Tailwind CSS for the admin console (on a tenant-supplied template, integrated component-by-component as needed — §5.14) — v3.
- **Real-time transport: Turbo Streams over Action Cable, backed by Redis pub/sub — the single unified mechanism for both apps (v8).** The admin console uses it natively (Rails-rendered views, DOM patches with no full reload). The Next.js public site subscribes directly to a scoped, read-only, unauthenticated-safe channel (e.g. `PublicEventLiveChannel`, broadcasting only aggregate counts — never participant-level data) using the `@rails/actioncable` JS client — one real-time mechanism platform-wide instead of a split Action Cable/SSE design. See §5.15.
- **Primary/public keys: UUID, specifically UUIDv7 (v8).** Plain UUIDv4 is fully random and hurts B-tree index locality at scale; UUIDv7 keeps the time-ordered locality property (like ULID) while being a standard, widely-supported UUID variant — gets you "UUIDs" as confirmed, with the performance property preserved.
- **`ScanEvent`/`Attendance` partitioning: monthly range partitioning on the write timestamp (v8)** — the standard approach for time-series/event-log-style tables (this data is fundamentally a log of scans/attendances over time). `account_id` remains a normal indexed column within each partition, not the partition key — cross-tenant isolation is still enforced by the row-level `account_id` scope (§4.2) regardless of partitioning. Monthly partitions also make the GDPR retention job (§7.5) cheap: purging old data becomes a partition drop instead of a slow bulk `DELETE`.
- **Badge/PDF rendering: Grover** (headless Chrome/Puppeteer) — confirmed, replacing `wicked_pdf`/`wkhtmltopdf`.
- **Search: Postgres full-text search** (`tsvector`/`pg_trgm`) — confirmed, no separate search service.
- **Observability: New Relic** — confirmed, kept from the baseline.
- **Background jobs: Sidekiq** — kept, unchanged from the baseline recommendation.

**Badge *design* tool — answering the direct question (v8):** Grover is the PDF *renderer* (HTML/CSS → PDF); it isn't a *design* tool. For the WYSIWYG drag-and-drop badge editor itself (§5.5), **recommend GrapesJS** over building a custom canvas editor from scratch: it's an open-source, actively maintained, framework-agnostic visual HTML/CSS page-builder library — purpose-built for exactly "drag components onto a canvas, get clean HTML/CSS out" — which maps directly onto the existing token-substitution model (`$NAME$`, `$PHOTO$`, `$QRCODE$`, etc. become GrapesJS custom draggable blocks), includes layers/alignment guides/undo-redo/a style panel out of the box, and — since it's vanilla JS, not React-specific — wraps cleanly in a single Stimulus controller inside the Rails-rendered admin console rather than requiring a React island. Building this from scratch (e.g. on a low-level canvas library like Fabric.js/Konva) would mean re-implementing everything GrapesJS already provides for materially more effort, which cuts against "simplify." The GrapesJS canvas output feeds straight into the same token-substitution engine and Grover rendering pipeline already designed.

**Deployment topology — confirmed, v8/v9:** self-hosted on a **single VPS** (Hetzner Cloud a likely candidate; exact provider still open, §10.13), running Rails, Next.js, and the print-agent's backend/broker (the Action Cable print-station channel) together. Confirmed shape:
- **Docker** for the application layer (each of Rails/Sidekiq/Next.js/Postgres/Redis as isolated, independently-restartable containers) and **Terraform for infrastructure-as-code** (v9) — provisioning the VPS itself, networking, and any managed pieces (DNS, storage) declaratively and reproducibly, rather than hand-configuring the box. This pairing is provider-agnostic (Terraform has a first-class Hetzner Cloud provider if that's the final pick, but the same approach ports to another VPS provider without a redesign).
- **Caddy as the reverse proxy in front of everything**, using its built-in **on-demand TLS** — the standard solution to exactly the problem a self-hosted multi-tenant SaaS has (arbitrary customer-owned custom domains needing automatic certificates): Caddy requests a cert the first time a domain is hit, checking back with Rails to confirm it's a real, verified tenant domain before issuing one. Avoids hand-rolling ACME/certbot scripting entirely, and also handles the `Host`-header-based routing to the right backend (Rails for the apex/tenant-subdomains, Next.js for the public site's domains).
- **Single-VPS trade-off: acknowledged (v9).** A single VPS is a single point of failure and a ceiling on horizontal scaling (§7.1) — accepted for MVP/early tenants; revisit (multi-node, managed Postgres, etc.) once real load data exists, not before.

**Explicitly not changed without a reason:** file storage (Active Storage + Cloudinary), QR/barcode generation (`rqrcode`/`barby`-equivalent) — already good fits.

### 4.11 Cross-Tenant SSO for Multi-Account Users (Agencies) **[new, fully designed — v8]**

**Use case (confirmed, v8):** an event agency manages several tenant Accounts on the platform (e.g. one agency runs events for 10 different client organizations, each its own Account). The agency's own staff need to move between those Accounts' admin consoles without re-entering credentials each time — effectively acting with Owner-level control across all the tenants they manage.

**Important boundary:** this is **not** Platform Console/Super Admin access (§4.3, §4.7). An agency user gets full admin control *within the tenant Accounts they're a member of*, via ordinary `AccountMembership` rows (§4.1) — they do not get cross-platform capabilities like creating brand-new tenant Accounts, approving other tenants' events, or seeing platform-wide billing. If an agency needs the Super Admin's own capabilities, that's a separate, explicit decision (making specific agency staff Platform staff, §4.1) — not a side effect of SSO.

**Mechanism — relay-token SSO, preserving the host-only-cookie security model (§4.9 item 1):**
1. An agency user authenticates normally (Devise) on any one of their tenant subdomains — the "source" subdomain. This establishes the usual host-only session cookie there, unchanged from §4.9.
2. The admin console shows an **Account Switcher** (populated from the user's `AccountMembership` rows) whenever a user has more than one.
3. Switching to another Account (the "target" subdomain) triggers the server to mint a **short-lived, single-use, signed relay token** (JWT: `user_id`, `target_account_id`, ~30–60 second expiry, signed with a platform-level secret) and redirect the browser to `{target_tenant_slug}.{platform_domain}.com/sso/consume?token=...`.
4. The target subdomain's Rails process verifies the token — signature valid, not expired, not already consumed (a Redis-backed used-token registry, keyed by the token's `jti`, TTL matching the token's own expiry, rejects replay), and the user genuinely holds an `AccountMembership` on the target Account. If all checks pass, it establishes a **new, ordinary host-only Devise session** on the target subdomain and redirects into the dashboard.
5. **What crosses subdomains is only the ephemeral relay token, never a session cookie** — the wildcard-cookie approach rejected in §4.9 item 1 stays rejected; this gets the SSO *experience* without the cross-subdomain cookie *exposure*.

**Security properties:** relay-issuance itself requires an already-authenticated source session (this can't bootstrap login from nothing), tokens are single-use and short-lived, and they're scoped to exactly one target Account (can't be replayed against a different tenant).

**Data model implication (§8):** no new persistent table required — this reuses `AccountMembership` entirely. The only addition is an ephemeral, Redis-backed used-token registry (not a durable table, matching the token's own short TTL).

This was originally scoped in v3 as a "Phase 2+ enhancement" (§4.9 item 1); the agency use case being confirmed as a near-term need moves it to **planned for Phase 1** (§9) — cheap to build once base multi-tenant auth exists, since it reuses `AccountMembership` rather than introducing new infrastructure.

---

## 5. Functional Requirements by Module (New Product)

Each module below states the requirement; items carried from §3 are marked **[baseline]**, new items are marked **[new]**.

### 5.1 Accounts, Users & Permissions
- **[baseline→extended]** Role-based access, but replace the current flat `admin/organizer/superadmin` enum with **configurable roles and granular permissions** per Account (e.g., Owner, Event Manager, Check-in Staff, Finance/Read-only, Marketing) so tenants can model their own org chart instead of being forced into three fixed roles.
- **[baseline]** Forced password reset on invite, temp-password flow.
- **[new, deferred — confirmed not in MVP, v5]** SSO/SAML and OIDC login for enterprise tenants, SCIM user provisioning — **not built for Phase 1**. MVP login is **basic Devise email/password only** (§4.9 item 1), same as the baseline. Revisit in Phase 3 (§9) if/when an enterprise tenant actually requires it.
- **[new]** Per-event staff assignment (a check-in volunteer only needs access to one event, not the whole Account).
- **[baseline, confirmed for MVP — v5]** OAuth2 provider (Doorkeeper-equivalent), scoped per tenant: each Account can register and manage its own OAuth application(s) from the admin console, for its own external tooling to call the public REST API — see §4.9 item 4 for the full auth design.

### 5.2 Event Management
- **[baseline, simplified — v7]** Event creation is **not** the baseline's rigid linear multi-step wizard (fixed new → schedule → speakers → visitors → payment → badge → preview sequence, §3.2). Instead: a single **tabbed event builder** with autosave per section, freely navigable in any order, each tab showing its own completeness state — same underlying content (basic info, agenda, speakers, ticket categories, badge design, review-and-submit) without forcing a strict sequence. Faster to use, faster to resume, and a more natural fit for the "submit for Super Admin approval" step below than a hard "preview is the last step" gate.
- **[baseline]** Draft/Upcoming/Live/Completed lifecycle, auto-transitioned by schedule.
- **[new — confirmed requirement, v4, detailed v8]** **Super Admin approval gate**: an event has an `approval_status` (`pending` / `approved` / `rejected`) **independent of** its scheduling `status` above. An organizer builds and publishes an event through the tabbed builder above, but publishing only submits it for Super Admin review — the event is **not visible on the public Next.js site and does not accept registrations** until `approval_status` is `approved`. See §4.7 for the Super Admin review UI and §4.3/§4.9 for how this is enforced server-side on every public read/write path (never trusted client-side).
  - **Rejection UX (confirmed, v8, notification channel finalized v9):** rejecting requires a reason; the organizer is notified by **email and WhatsApp (via Gupshup, §5.10, §5.12)**, and the admin console shows the rejection status with the stated reason on the event. The event stays editable and resubmittable.
  - **Approval SLA (confirmed, v8):** target **within 24 hours**. Communicated to organizers in the submitted-for-review state ("typically reviewed within 24 hours"); the Platform Console's review queue should surface events approaching/past that window so the Super Admin doesn't have to track it manually.
  - **Re-approval on edit (confirmed, v8):** once approved, **the organizer can edit anything without reverting to `pending`** — billing is per event (§4.6), not gated on content, so there's no need to re-review every edit. (A manual Super Admin unpublish/revoke action as a safety valve is recommended but not yet confirmed.)
- **[baseline]** On-site / Virtual modes.
- **[new]** **Hybrid** mode (on-site + simultaneous virtual/streaming attendance, both tracked in the same attendance model).
- **[new]** Event **templates/duplication** — clone a past event (structure, ticket categories, badge design, email templates) as the starting point for a new one; this is one of the highest-ROI features for repeat organizers and is conspicuously absent today.
- **[new]** Multi-day / multi-track agenda with parallel sessions and room capacity, building on the existing `Session`/`Schedule` model.
- **[new]** Recurring events / event series (e.g., monthly meetups) sharing an attendee list across occurrences.
- **[baseline]** Configurable required/optional participant fields per event; extend to a **custom-field builder** (organizer-defined fields, not just a fixed catalog) with types (text, select, checkbox, file).

### 5.3 Ticketing

> **Scope note (v2 decision):** No payment gateway integration and no payment-related schema in this phase. All ticket categories in the initial build are **free / RSVP-style with capacity limits only** — there is no price, checkout, or money movement anywhere in Phase 1. The `Order`/`PaymentDetail`-equivalent tables from the baseline system are **not built yet**. Everything below is split into what's in scope now vs. what's deferred until a payment gateway is introduced (see §9 roadmap).

**In scope now (capacity-based, no money involved):**
- **[baseline, adapted]** Multiple ticket categories per event as **capacity buckets** (name, inventory: total/sold/remaining), per-category document requirement — everything from the baseline except price and Stripe sync.
- **[new]** **Group/bulk registration** — one registrant reserves N spots and either fills in attendee details later or forwards individual claim links. No purchase involved, just capacity reservation.
- **[new]** **Waitlists** for full categories with automatic offer-on-release when a spot opens up.

**Deferred until a payment gateway exists (Phase 2+, see §9):**
- Ticket pricing, Stripe (or any) checkout, multi-currency amounts.
- **Discount/promo codes** (meaningless without a price to discount).
- **Tiered/early-bird pricing** with scheduled price changes.
- Invoicing/receipts (PDF) and tax handling (VAT/GST) per tenant jurisdiction.
- Refund/cancellation workflow — the seat-count-restoration logic (`restore_ticket_count`-equivalent) still applies to a plain cancellation even without payment, so **cancellation with seat restoration stays in scope now**; only the *refund* half is deferred.

### 5.4 Registration & Participant Management
- **[baseline, re-platformed]** Public self-registration is delivered by the Next.js public event site (§4.8) via the BFF pattern (§4.9), not server-rendered by Rails as in the baseline — Rails becomes the API/data layer; admin manual entry stays in the Rails admin console. Dedupe validations, multiple identifier types, photo/document upload logic (§3.4) are preserved as backend rules regardless of which app is submitting.
- **[baseline]** Bulk XLSX import with fuzzy dedupe matching; bulk export with attendance/session detail.
- **[new]** **Registration form builder** (drag-and-drop, conditional fields, multi-page forms) instead of a fixed field catalog.
- **[new]** **Approval-based registration** (organizer must approve before ticket/badge is issued) for invite-only or vetted events.
- **[new]** Attendee self-service portal: view/edit own registration, download badge/receipt, cancel/transfer ticket.
- **[new]** **Ticket transfer** (attendee A reassigns their ticket to attendee B).
- **[baseline]** Public JSON API for headless registration and external system upsert.
- **[baseline, confirmed scope — v8]** `govt_id` ships as a **plain, manually-entered participant field** in Phase 1 — carried forward from the baseline identifier set (§3.4), with **no government-ID-provider API integration** (no DTCM-style auto-assignment). This is the confirmed answer to "which integration to build first": none — keep the field, build no integration behind it, revisit only if/when a specific government-ID integration is greenlit (§5.12).

### 5.5 Badge Design & Printing
- **[baseline]** In-house drag-and-drop-capable badge template engine (background image, logo, dynamic tokens), badge vs. wristband types, size-accurate PDF rendering.
- **[baseline]** Kiosk-mode self-service printing, bulk print queue with failure tracking/retry, dual QR/barcode slots.
- **[new, tool confirmed — v8]** Visual (WYSIWYG) badge designer UI, built on **GrapesJS** (§4.10) — a drag-and-drop canvas editor whose custom blocks map to the existing dynamic tokens (`$NAME$`, `$PHOTO$`, `$QRCODE$`, etc.), exporting clean HTML/CSS straight into the same token-substitution engine and Grover rendering pipeline. Chosen over a from-scratch canvas editor because it already provides layers, alignment guides, undo/redo, and a style panel — reinventing those would be pure effort with no product benefit.
- **[new]** Badge template library with reusable/sharable templates across events within a tenant.
- **[new]** Conditional badge layouts by ticket category (VIP vs. Attendee vs. Speaker badge from one event without duplicating templates).

#### 5.5.1 Cross-Platform Print Agent & Auto-Print **[new — confirmed requirement]**

The baseline system's `lpr` call only works because it runs server-side against whatever the *server's* OS default printer is — that doesn't work for a multi-tenant SaaS where badge printers sit at a customer's front desk, not next to the app server. This requires a proper local print agent:

- **Local Print Agent**: a lightweight background service the tenant installs on the front-desk/kiosk machine, distributed for **Windows, macOS, and Ubuntu**. It authenticates to the platform with a station-scoped pairing token (one agent = one tenant + one event/station, never a platform-wide credential) and maintains a persistent connection (WebSocket or long-poll) to receive print jobs pushed from the server.
- **Auto-print**: when a print-triggering action occurs (participant completes check-in, or completes registration at a kiosk — configurable per event, see below), the server renders the badge and pushes the print job straight to the paired agent, which sends it to the assigned printer **with no manual "Print" button click** — this is the core ask, not just "printing is possible" but "printing happens automatically as part of the scan/registration flow."
- **Per-event/per-station configuration**: auto-print on/off toggle per event (some organizers will still want a manual review-then-print step, e.g. for approval-gated registrations), and a printer mapping per station (Station A → Printer 1, Station B → Printer 2) for multi-desk venues.
- **Printer compatibility**: must drive standard OS-registered printers (documents/labels via the native print spooler on each OS) as the baseline; dedicated card/badge printers (Zebra ZPL, Evolis) that need raw driver-level output are a stretch target for the same agent, not a hard Phase 1 requirement — confirm hardware scope before committing (see §10).
- **Implementation approach — confirmed, v8: Electron**, using Chromium's native silent-print API (`webContents.print({ silent: true, deviceName, printBackground: true })` against a hidden window loading the rendered badge PDF). This is the most proven pattern for unattended kiosk-style silent printing across Windows/macOS/Linux from one codebase, and it directly serves the stated priority — **printing must be automatic, full stop** — better than stitching together separate per-OS printing libraries (Windows Print Spooler / CUPS bindings) would. Trade-off: a larger installed footprint (~150–200MB, bundled Chromium+Node) versus a lean Go/Rust binary (~10–20MB); on a semi-permanent front-desk/kiosk machine, that trade is worth it for print reliability. Packaged with `electron-builder` (signed `.exe`/NSIS installer for Windows, notarized `.pkg`/`.dmg` for macOS, `.deb`/AppImage for Ubuntu) and `electron-updater` for auto-updates, so print-reliability fixes reach kiosks without a manual reinstall. A system-tray/menu-bar presence shows agent/printer connection status at a glance.
- **Resilience**: jobs queue locally on the agent if the printer is offline/out of paper, retry automatically, and report failures back to the admin console — this reuses the same print-failure tracking pattern the baseline system already has for its manual bulk-print queue (`mark_print_failed`/failed-print retry), just fed by the agent instead of a browser.
- **Security**: the agent is a persistent local process with network access, so pairing tokens must be scoped (tenant + event + station), short-lived/revocable, and the agent must only be able to *pull* jobs addressed to it and *report status* — never given broader API access.

**Still open:** whether raw ZPL/card-printer (Zebra/Evolis) driver support is required at initial launch, beyond standard OS-registered printers — see §10.13.

### 5.6 Check-in & Attendance
- **[baseline]** Multi-identifier scan lookup (internal ID, govt ID, RFID, client ID), event- and session-level check-in/out, anti-double-scan debounce, seat-limit enforcement, virtual-event redirect-on-scan.
- **[baseline]** Historical attendance log + time-spent computation.
- **[new]** **Offline-capable check-in app** (mobile/PWA) that queues scans locally and syncs when connectivity returns — critical for venues with poor Wi-Fi, and a real gap in the current browser-only flow.
- **[new]** Native mobile check-in app (iOS/Android) with camera-based QR scanning, not just a hardware scanner emitting keystrokes into a web form.
- **[new]** Real-time occupancy dashboard (who's in the building/session right now) for fire-safety/capacity compliance.
- **[new]** Lead-retrieval scanning for exhibitors/sponsors (see §5.8) — a different "who scanned whom" concept from attendee self-check-in.

### 5.7 Agenda, Speakers & Content
- **[baseline]** Speakers, schedules, sessions with capacity.
- **[new]** Public agenda page with per-attendee **personal schedule builder** ("add to my agenda") and calendar export (.ics) / sync to Google/Outlook.
- **[new]** Speaker portal (speakers manage their own bio/photo/slides, no organizer-in-the-loop needed).
- **[new]** Session materials/resources (slide decks, recordings) attached post-session and available on-demand.
- **[new]** Live streaming integration for virtual/hybrid sessions (embed or native player) plus on-demand replay library.

### 5.8 Sponsors & Exhibitors
- **[baseline]** Basic per-event sponsor/`Client` branding record.
- **[new]** Full **exhibitor/sponsor module**: sponsor tiers, virtual/physical booth pages, exhibitor-managed content, lead-retrieval (exhibitor staff scan attendee badges and capture notes/tags), post-event lead export/CRM handoff, sponsor-facing analytics (booth visits, leads captured, session mentions).
- **[new, deferred]** Sponsor billing (sponsorship packages sold as paid line items) — depends on the payment gateway from §5.3/§5.12, so it lands in the same later phase. Sponsor tiers and booth pages themselves don't require payment and can ship earlier.

### 5.9 Attendee Engagement & Networking
*(entirely new — the current system has no attendee-to-attendee or attendee-to-content interaction beyond check-in)*
- **[new]** In-app attendee directory with opt-in visibility and 1:1 messaging/meeting scheduling.
- **[new]** AI- or rule-based **attendee matchmaking** (shared interests/goals) — see §6.
- **[new]** Live polls, Q&A, and session-level live chat.
- **[new]** Gamification: point/badge system for check-ins, booth visits, session attendance, redeemable for leaderboard recognition or prizes.
- **[new]** Push notifications / in-app announcements (session starting, room change, emergency alerts).

### 5.10 Communications
- **[baseline]** Templated, brandable registration-confirmation email with delivery-state tracking and resend.
- **[new, confirmed for MVP — v9]** **WhatsApp via Gupshup** for Super-Admin-to-tenant **operational/transactional notifications**: event rejection (with reason, §5.2), invoice sent, quotation sent/revised (§4.6), payment verified. This is the second narrow exception to the "no third-party integrations" decision (alongside the tenant OAuth2 provider, §5.12) — scoped specifically to platform-operator-to-tenant messages, not attendee-facing messaging. Delivery-state tracking follows the same `pending/sent/failed` pattern already used for email (§3.10).
- **[new]** Full campaign/marketing layer: pre-event drip campaigns, reminder sequences, post-event follow-up/NPS survey, segmentation by ticket category/attendance/engagement.
- **[new, deferred]** **Attendee-facing** SMS and WhatsApp channels (registration confirmations, reminders, marketing) — distinct from the Gupshup operational-notification use above; this broader attendee-facing layer stays deferred to Phase 2 until scoped on its own.
- **[new]** Transactional-email deliverability dashboard (bounce/open/click tracking), not just sent/failed.

### 5.11 Data Import/Export & Reporting
- **[baseline]** XLSX bulk import with dedupe matching, async export with progress polling and templated columns.
- **[new]** Configurable export templates (organizer picks columns/format, including CSV/PDF, not just the fixed XLSX layout used today).
- **[new]** **Analytics & reporting dashboards**: registrations-over-time, revenue, check-in rate, session popularity, engagement funnel, sponsor ROI — currently there is *no* reporting UI at all, only raw XLSX export. This is one of the biggest gaps versus competing platforms and should be a first-class module, not an afterthought.
- **[new]** Scheduled report delivery (emailed weekly/daily summary to organizers).

### 5.12 Integrations & Extensibility

> **Scope note (v2 decision, refined v5/v9): third-party integrations that the platform *consumes* remain deferred**, including no payment gateway. Two narrow, deliberate exceptions are confirmed in MVP: (1) the platform *exposing* a tenant-scoped OAuth2/REST API for a tenant's own external tooling to consume (§4.9 item 4 / §5.1) — a different *direction* of integration, not covered here; and (2) **Gupshup**, for Super-Admin-to-tenant WhatsApp operational notifications only (§5.10) — narrowly scoped to platform-operator messaging, not a general messaging/CRM/marketing integration. Everything below remains deferred, not built, not stubbed, until a later phase. It is documented here so the core data model (events, participants, badges) is designed in a way that doesn't have to be reworked when it's added later (e.g., keep an `external_id`/`source` field on `Participant` as the baseline already does, don't hardcode assumptions that all participants are created locally).

Deferred scope, to be revisited once a first *inbound/consuming* connector is actually greenlit (confirmed, v8: **none for MVP** beyond the two exceptions above — the one other narrow exception is a plain `govt_id` field with no integration behind it, §5.4):
- **[baseline→generalized, deferred]** The baseline system's DTCM (government ID) and Stova (external registration sync) integrations, generalized into pluggable patterns rather than hardcoded vendors: a *Government/Compliance ID Provider* interface, an *External Registration Platform Sync* interface, and an *outbound webhook system* generalizing the baseline's `ApiGatewayJob` client-portal push.
- **[new, deferred]** Native connectors: CRM, calendar sync, marketing tools, Zapier/Make.
- **[new, deferred]** Marketplace/plugin model so integrations can be added without platform-team involvement per tenant request.
- **[new, deferred]** Payment gateway integration (Stripe or otherwise) for paid ticketing — see §5.3 — and, separately, for platform subscription billing — see §4.6.

### 5.13 On-Site Experience Extras
- **[baseline]** RFID/QR-triggered personalized video-wall broadcast via real-time channels — a genuinely distinctive feature; generalize it into a **"triggered on-site content" framework** (scan → play video / show personalized message / unlock content), configurable per tenant/event rather than a single global mapping.
- **[new]** Digital signage feed (session-now/session-next boards) driven off the same session/room data.

### 5.14 Admin Console Design System **[new — confirmed requirement]**
- The admin console UI is built on a **tenant-provided Tailwind CSS template** (to be supplied) rather than a from-scratch design. Implementation must budget for a dedicated template-integration pass: extracting the template's layout/components into the Rails view layer, wiring its interactive elements to Stimulus controllers (the baseline app already uses `stimulus-rails`/Turbo — avoid introducing a second JS framework, e.g. Alpine.js, purely because the supplied template ships with it; port its interactions to Stimulus for consistency unless the team decides otherwise), and establishing a shared component/partial library so new admin screens are built by composing existing pieces rather than re-implementing markup per screen.
- Since the specific template hasn't been delivered yet, this document defines the *integration approach* only — page-by-page specifics, and the rest of the build sequencing, will be defined in a separate implementation plan once this requirements doc is reviewed and the template is in hand.
- **Working process confirmed, v8:** the template will be added directly to the project workspace. Before any UI work on a given screen, check the template first and pick/adapt the relevant existing component rather than designing new markup from scratch — the template is the starting point for every admin screen, not a reference to occasionally consult.

### 5.15 Real-Time Analytics & Live Dashboards **[new — confirmed flagship MVP requirement, v7]**

- **Live registration counter**: the instant a `Participant` is created (from the admin console or the Next.js public site via the BFF), every connected admin dashboard for that event updates its "registered" tile immediately — no polling, no manual refresh.
- **Live check-in/occupancy counter**: the instant a `ScanEvent` (§6.13 unifying abstraction) records a check-in or check-out, the "checked in now"/"current occupancy" tile updates immediately across every connected dashboard, alongside a live registered-vs-checked-in ratio and, for limited-seat events, remaining capacity per ticket category.
- **Mechanism**: every mutation affecting a live metric publishes to a Redis-backed pub/sub channel scoped to the event (`event:{event_id}:live`); Turbo Streams broadcasts the delta to subscribed admin-console connections (Action Cable), patching only the affected DOM nodes — no full-page reload, per the explicit "WebSockets without page refresh" requirement. **Confirmed unified transport (v8):** the public Next.js site (e.g. a "seats remaining" ticker on the registration page) subscribes directly to the same Action Cable layer, via a dedicated, scoped, read-only, unauthenticated-safe channel (`PublicEventLiveChannel`, broadcasting only aggregate counts, never participant-level data) using the `@rails/actioncable` JS client (§4.10) — one real-time mechanism for the whole platform, not a separate SSE path.
- **Session-level live view**: the same mechanism extends to per-session occupancy (room-capacity/fire-safety awareness during a live multi-track event) and to per-ticket-category sell-through.
- **Super Admin cross-tenant pulse**: the Platform Console (§4.7) gets its own live view — aggregate registrations/check-ins across *all* currently-live events platform-wide, and the computed-income view (§4.6) updating live as participants register. Most competing platforms don't give their own operator a real-time cross-tenant view at all — see §6 item 17.
- **Initial load vs. live delta**: a dashboard's first render reads the current value from the `EventLiveStats` counter row (§8) — fast, O(1), no aggregation — then upgrades to live via the Action Cable subscription. The two paths must never disagree: the counter row is the single source of truth for both.
- **Backpressure/fan-out**: many admin users (and, for the Super Admin, all tenants at once) may watch a popular live event simultaneously, so pub/sub fan-out must be load-tested independently of normal web request throughput (§7.1) — a spike in dashboard viewers must never slow down the check-in scanning generating the data they're watching.
- **Historical trend, not just current value**: alongside the live current-value tiles, keep a lightweight time-series (a rolling per-minute bucket derived from `ScanEvent`/`Participant` timestamps) to drive a live sparkline of registration/check-in velocity — cheap to compute incrementally, and far more useful to an organizer mid-event than a single static number.

---

## 6. Out-of-the-Box Additions (Think Beyond the Current Feature Set)

These are not present in the current system at all but are worth designing in from the start because they're expensive to retrofit into a multi-tenant data model later.

1. **AI-assisted organizer tools** — auto-draft event descriptions/emails from a few prompts, AI-suggested badge layouts from a logo + brand colors, auto-generated post-event summary/highlights reel from photos/session data.
2. **AI attendee matchmaking & agenda recommendations** — suggest sessions/people based on stated goals or past behavior; a natural extension of the "personal schedule builder" in §5.7.
3. **No-show / capacity prediction** — use historical check-in rates per ticket category to help organizers overbook responsibly for limited-seat events (the current seat-limit logic is purely deterministic; a predictive layer adds real value).
4. **Conversational check-in support** — a lightweight chatbot for "where's my ticket / I can't check in" self-service, reducing help-desk load at large events.
5. **Accessibility compliance (WCAG 2.2 AA)** as a baseline requirement for all public-facing pages (registration, agenda, badge check-in), not an afterthought — event platforms are frequently subject to accessibility audits.
6. **Sustainability reporting** — estimated carbon footprint from travel distance (derivable from participant country/city data already collected), useful for corporate-event ESG reporting.
7. **Event website/microsite builder** — the current public event page is a single fixed template; a themeable page builder (drag-and-drop sections: agenda, speakers, sponsors, FAQ, venue map) turns the event page into a real marketing asset.
8. **Native calendar & wallet integration** — .ics export (agenda), and Apple Wallet/Google Wallet **digital badge/ticket pass** as an alternative to (or alongside) physical badge printing.
9. **Multi-language / i18n** for both the organizer console and public attendee-facing pages — international events (the DTCM integration already signals a UAE/international customer base) need this from day one, not bolted on later.
10. **Data residency options** per tenant (EU/US/ME region pinning) for regulatory compliance — relevant given the government-ID integration pattern already in the product.
11. **Post-event content hub / on-demand library** with view analytics, monetizable separately from live attendance.
12. **Badge/lead-scan analytics for exhibitors** exposed as a sellable add-on package (ties §5.8 to the billing model in §4.6).
13. **Unified "single scan, many purposes" architecture** — today check-in, badge printing, and the video-wall trigger are three separate scan endpoints keyed off similar-but-slightly-different lookup logic. In the new system, design one **Scan Event** abstraction (who scanned, what was scanned, where, when) that check-in, printing, lead-retrieval, and triggered-content all subscribe to, instead of three parallel implementations.
14. **Live "seats remaining" public ticker** (new, v7) — an embeddable, real-time counter (Action Cable-driven, §5.15) on the public event page and, longer-term, embeddable on the tenant's own marketing site. A proven urgency/social-proof driver used by modern ticketing platforms (Luma, Partiful) that the baseline has no equivalent of.
15. **Live event "pulse"/mission-control view** (new, v7) — a single full-screen dashboard an organizer can put on a lobby TV or laptop during the event: registrations ticking up, check-ins ticking up, a live occupancy gauge, session-by-session live attendance. Built on the same real-time layer as §5.15, not a separate feature.
16. **Instant real-time waitlist promotion** (new, v7) — the moment a spot frees up (a cancellation, a capacity increase), the next waitlisted registrant is notified immediately (push/WebSocket-driven where the attendee has the page open, email/SMS otherwise) instead of waiting on a periodic batch job.
17. **Cross-tenant live platform pulse for the Super Admin** (new, v7) — an aggregate real-time view across every currently-live event platform-wide (§5.15), a genuine differentiator most competing platforms don't offer their own operators.
18. **Predictive final-attendance forecasting** (new, v7) — extends item 3's no-show prediction into a live-updating forecast during the registration window itself ("at this registration velocity, expect ~420 final attendees against your 500 cap"), fed directly by the same live time-series data as §5.15.

---

## 7. Non-Functional Requirements

### 7.1 Scalability
- Must handle spiky load: registration opens and on-site check-in windows (event start) both produce short, extreme traffic bursts for a single tenant/event without degrading other tenants — background job queues and DB connection pools must be tenant-fair (no noisy-neighbor starvation).
- Horizontal scalability for web and worker tiers (the current Puma + Sidekiq + Redis shape is a reasonable starting point).
- **[new, v7]** The real-time layer (§5.15) must scale its fan-out (many dashboard viewers per popular live event, including the Super Admin watching all tenants at once) independently of write throughput — a spike in dashboard viewers must never slow down the check-in scanning generating the data they're watching.

### 7.2 Reliability & Job Processing
- **[baseline]** Async processing for imports, exports, mailers, integrations (Sidekiq today) — preserve this pattern; it correctly keeps slow operations (XLSX generation, external API calls, PDF rendering) off the request cycle.
- Dead-letter/retry visibility per tenant (today's Sidekiq Web UI is a shared, platform-operator-only view — tenants should get a scoped "failed imports/exports" view of their own jobs).
- Idempotency for all external-integration jobs (payment webhooks, government-ID assignment, external-platform sync) — the current DTCM assignment already uses row-level locking (`FOR UPDATE SKIP LOCKED`) for exactly this reason; that pattern should be the template for all shared-resource allocation, not a one-off.

### 7.3 Performance
- Public registration and check-in pages must load and respond in check-in-desk-acceptable time (sub-second) even during a live event's peak scan rate.
- Badge/PDF generation must not block the check-in scan loop — keep it async or pre-warmed where possible.
- **[new, v7]** **Live dashboard update latency**: from the underlying write (registration, check-in scan) to a connected dashboard reflecting it, target **under 1 second** end-to-end — this is the concrete, testable form of the "no page refresh, real-time" requirement (§5.15).

### 7.4 Security
- Strict tenant data isolation (§4.2) is the top security requirement.
- Encryption at rest for PII (government IDs, documents, photos) and in transit everywhere.
- Secrets (integration credentials, payment keys) encrypted per tenant, never in shared config.
- Full audit log of admin actions (who edited/deleted a participant, who issued a refund, who impersonated a tenant) — absent today; required for enterprise customers and support accountability.
- Rate limiting on public endpoints (registration, check-in, API) per tenant to prevent one tenant's traffic (or a scraping/abuse attempt) from affecting others.
- CORS is not the primary defense for the public API surface — the BFF pattern (§4.9) means the browser never calls Rails cross-origin for the main flows. Where CORS is still needed later (e.g. a client-side polling endpoint using a lighter-weight publishable key), origins must be checked dynamically against the tenant's *verified* domains only, never a static wildcard.

### 7.5 Compliance
- GDPR/CCPA-style data subject rights: attendee data export and right-to-erasure, honored per tenant.
- Configurable data retention policy per tenant/event (auto-purge participant PII N days after event completion, if the organizer opts in).
- Government-ID-handling integrations must meet whatever regional compliance applies to that ID system (carry forward the care already evident in the DTCM flow).

### 7.6 Observability
- **[baseline]** APM (New Relic today) — extend with per-tenant usage/error dashboards, not just platform-wide.
- Structured, tenant-tagged logging so a support engineer can filter logs to one tenant without seeing others'.

### 7.7 Extensibility
- Integration and badge-token systems (§5.5, §5.12) should be built as pluggable frameworks from day one, since the current system's history (three separate bespoke integrations: DTCM, Stova, CMF) shows this need recurs constantly per customer.

---

## 8. High-Level Data Model (Additive to Current Schema)

**Phase 1 (this build — no payment, no third-party integration schema):**

`Account (tenant)`, `AccountMembership (user↔account + role)`, `User`, `TenantDomain` *(new: one row per subdomain/custom-domain, verification status, TLS status — §4.3)*, `Event`, `TicketCategory` *(was `Visitor`, capacity only — no price field yet)*, `Participant`, `Badge`, `BadgeTemplate` *(new: reusable library)*, `Attendance`, `ScanEvent` *(new: unifying abstraction, §6.13)*, `Session`, `Schedule`, `Speaker`, `Sponsor/Exhibitor` *(was `Client`, generalized, no billing fields yet)*, `ImportFile`/`ExportFile`, `PrintAgent`/`PrintStation`/`PrintJob` *(new, §5.5.1)*, `Plan`/`Subscription`/`UsageRecord` *(new: platform billing — plan assignment & metering only, no gateway/charge fields yet, §4.6)*, `AuditLogEntry` *(new)*, `OAuthApplication`/`OAuthAccessGrant`/`OAuthAccessToken` *(baseline Doorkeeper tables, now explicitly tenant-scoped and confirmed for Phase 1 — v5, §4.9 item 4, §5.1)*.

**Deferred alongside cross-tenant SSO (§4.9, §10.4):** `SsoRelayToken` — only needed once the multi-account SSO-relay enhancement is built; Phase 1 uses plain per-subdomain Devise sessions.

**Event approval (new, v4):** `Event` gains an `approval_status` (`pending`/`approved`/`rejected`) plus `approved_by` (a Super Admin `User`), `approved_at`, and optionally a `rejection_reason` — orthogonal to the existing scheduling `status` enum (§3.2). Public-site visibility and registration-acceptance checks key off `approval_status`, not `status`, alongside the existing draft/live timing rules.

**Platform staff (new, v4):** `User` gains a `platform_staff`/superadmin flag distinguishing Platform Console operators, who hold no `AccountMembership` row at all (§4.1).

**Real-time & schema optimization (v7, tech confirmed v8):** `EventLiveStats` and `SessionLiveStats` — per-event/per-session denormalized live counters (registered/checked-in/checked-out/occupancy), updated incrementally on every relevant `Participant`/`ScanEvent` write, and the single read source for both a dashboard's initial load and its Action Cable broadcast payload (§5.15, §4.10). Every tenant-facing/externally-exposed record uses a **UUIDv7** primary/public key (§4.10) instead of a raw sequential integer. `ScanEvent` and `Attendance` use **monthly range partitioning** on their write timestamp (confirmed, §4.10) given they are the highest-write, fastest-growing, log-like tables in the system.

**Billing & invoicing (new, v8, entities refined v9 — still no payment gateway):** `Invoice` (event, base amount, overage amount, total, status: `draft`/`sent`/`awaiting_payment`/`under_review`/`paid`), `PaymentSubmission` (invoice, UTR/reference number, uploaded receipt, submitted by, status: `pending_review`/`approved`/`rejected`, reviewed by, reviewed at), `CapacityAdjustment` (event, previous cap, new cap, `override_rate` — nullable, defaults to the plan's standard rate when absent, §4.6 — increased by/Super Admin, timestamp — feeds the overage amount on the eventual invoice), and, for Business-plan events only, `Quotation` (event request, current amount, status: `pending`/`approved`/`rejected`/**`cancelled`** — cancelled automatically on the **3rd rejection**, §4.6/v10, must be `approved` before the `Event` record itself can be created) plus `QuotationRevision` (quotation, amount, rejection note, created by, created at — one row per round of the reject-with-note → Super Admin revises → resend cycle, capped at 3 rounds, so the negotiation history is preserved). None of this is a payment-gateway/PSP integration — it's a structured manual-proof workflow, consistent with the v2 decision.

**WhatsApp notifications (new, v9, field confirmed v10):** no new durable entity beyond extending the existing email delivery-state pattern (§3.10) with a `channel` (`email`/`whatsapp`) on whatever tracks notification delivery — sent via Gupshup, platform-level credential (not per-tenant), to the recipient `User`'s existing **`contact_num`** field (confirmed, v10 — no separate WhatsApp-specific field needed).

**Cross-tenant SSO (new, v8):** no new persistent table — reuses `AccountMembership` entirely, plus an ephemeral Redis-backed used-token registry for relay-token replay prevention (§4.11), not a durable table.

**Explicitly not in the Phase 1 schema** (deferred with their owning feature — do not create these tables yet, add them only when §5.3/§5.12 are actually built): `Order`, `PaymentDetail`, `DiscountCode`, `IntegrationConfig`, `IdentifierPool` *(the DTCM-style external ID pool)*, `Webhook`/`WebhookDelivery`. Keeping them out for now is deliberate — it avoids building payment/integration schema that would sit unused and avoids modeling assumptions (e.g. currency, gateway response shape) before those decisions are made. (Note: this exclusion is about *attendee ticket* payment schema — the platform's own tenant-billing/invoice schema above is a separate, now-in-scope concern.)

Full ERD and field-level schema to be produced as a follow-up engineering design doc once this requirements doc is approved.

---

## 9. Suggested Phased Roadmap

**Phase 1 — Multi-tenant core (payment-free, integration-free MVP)**
Account/tenant model with row-based isolation, the three-tier domain model (Platform Console at the apex domain, tenant Admin Console per subdomain, Next.js public site on the shared default subdomain — §4.3), Super-Admin-provisioned tenant onboarding (§4.6/§4.7, no self-serve sign-up), the event approval gate (§5.2) enforced across the admin and public API surfaces, tenant-scoped auth & RBAC, event/free-capacity-ticketing/registration/badge/check-in pipeline at parity with the current system **minus payments**, per-tenant branding, cross-platform print agent with auto-print (§5.5.1), basic reporting dashboard, **real-time Action Cable-driven live dashboards (live registration and check-in/occupancy counters, §5.15) as a flagship MVP capability** — not just the current system's biggest visible gap closed, but closed with a genuine differentiator, platform billing framework — per-event billing, Super-Admin-adjustable capacity overage tracking, Business-plan quotation approval gate, and the full manual invoice/NEFT/UTR-verification workflow (§4.6) — PWA-based check-in, a **tenant-scoped OAuth application per Account (Super-Admin-provisioned) doubling as the Next.js BFF credential via access+refresh tokens** (§4.9), and **cross-tenant SSO for agency/multi-account users** (§4.11). Two coordinated frontend workstreams: the **Tailwind-template-based admin console** (§5.14) and the **Next.js public event site** (§4.8) with its domain-resolution and BFF API-authentication layer (§4.3, §4.9). **Explicitly excluded from Phase 1:** third-party integrations the platform *consumes* (government-ID/external-registration-sync/webhooks), payment gateway, paid ticketing, `Order`/`PaymentDetail` schema — the OAuth2 provider is exposing an API, not consuming one, which is why it's in scope while the rest of §5.12 isn't. A granular, step-by-step implementation plan will be produced as a separate document once this requirements doc is reviewed.

**Phase 2 — Payments & competitive differentiation**
This is where everything deferred in Phase 1 gets reintroduced, deliberately, once the core product is proven: payment gateway integration + paid ticketing (pricing, checkout, invoicing, refunds, multi-currency, discount codes, tiered pricing), automated platform-subscription billing (connect a gateway so Basic/Pro/Business actually charge automatically), the generalized integration/webhook framework (§5.12) with the first real connector, sponsor & exhibitor module with lead retrieval and sponsor billing, event templates/duplication, visual badge designer, outbound webhooks, event website builder.

**Phase 3 — Engagement & scale**
Networking/matchmaking, live polls/Q&A, gamification, AI-assisted authoring & matchmaking, SSO/SCIM for enterprise tenants, connector marketplace, digital wallet passes, multi-region data residency, native mobile app (if the PWA turns out to be insufficient — see §10).

**Ongoing / cross-cutting**
Accessibility, i18n, security/compliance hardening, observability — start in Phase 1, never "finished."

---

## 10. Decisions Log & Remaining Open Questions

### 10.1 Resolved in v2

| # | Question | Decision |
|---|---|---|
| 1 | Isolation model | Row-based (`account_id` on every tenant-scoped table) — §4.2 |
| 2 | Platform billing model | Three tiers: Basic (500 participants, per-participant metered), Pro (1,000 participants, plan amount), Business (custom fixed amount) — §4.6 |
| 3 | Migration of existing tenant | None — greenfield build, no migration workstream |
| 4 | Print-agent requirement | Confirmed: cross-platform (Windows/macOS/Ubuntu) local print agent with **auto-print** — §5.5.1 |
| 5 | Which integrations first | None — all third-party integrations, including payment gateways, are **deferred** (not built) in this phase — §5.3, §5.12 |
| 6 | Mobile app vs. PWA | PWA for this phase |

### 10.2 New/remaining open questions raised by these decisions

1. **Billing period & cap semantics:** Is the 500/1,000 participant cap per billing period (monthly/annual) or a lifetime/account-wide count? Does it reset, and if so when? This determines the `UsageRecord` design and needs a product decision before Phase 1 billing logic is built.
2. **Overage handling:** What happens when a Basic or Pro tenant exceeds their included participant count — hard-block new registrations, prompt an upgrade, or (for Basic specifically, since it's already metered per-participant) just keep charging per participant with no cap at all? The phrasing "500 participants / amount per participant" for Basic suggests metered-with-a-soft-tier rather than a hard cap, but this needs confirmation.
3. **Business plan mechanics:** Is Business unlimited participants, or a custom negotiated cap? Is it billed as a recurring contract or a one-off engagement? Needed to design the `Plan`/`Subscription` schema flexibly enough to hold a custom tier.
4. **Manual billing operations:** Since no payment gateway is integrated yet, how should the platform admin console support collecting Basic/Pro/Business subscription fees in practice — e.g. a "generate invoice" + "mark invoice paid" workflow for the platform operator? Worth scoping explicitly so Phase 1 doesn't accidentally ship a billing model with no way to actually get paid.
5. **Auto-print trigger definition:** Should auto-print fire on check-in only, on kiosk self-registration completion only, or both — and should it be configurable per event (§5.5.1 assumes yes, per-event toggle)? Confirm before the print-agent protocol is finalized.
6. **Print agent packaging:** Installer/distribution approach per OS (signed `.exe`/`.msi` for Windows, notarized `.pkg` for macOS, `.deb`/AppImage for Ubuntu) and whether the agent needs to self-update. Also confirm whether raw ZPL/dedicated card-printer (Zebra/Evolis) support is required at launch or can follow standard OS-printer support.
7. **First integration to build (Phase 2):** When integrations are reintroduced in Phase 2, DTCM (government ID) and Stova (external registration sync) are UAE/Middle-East-market-specific in the baseline system — confirm target launch markets to prioritize which connector is generalized and built first.
8. **When to revisit payments:** Confirm Phase 2 is genuinely the trigger for payment-gateway work, or whether there's a firmer external deadline (e.g. a paid pilot customer) that would pull it forward.

### 10.3 Resolved in v3

| # | Question | Decision |
|---|---|---|
| 1 | Admin login/panel routing | `{tenant_slug}.{platform_domain}/login`, tenant slug reserved at registration — §4.3 |
| 2 | Public event site framework | Next.js (React + TypeScript), headless, consumes Rails as an API — §4.8 |
| 3 | Public event site custom domain | `{tenant_domain}.com` when the tenant configures/verifies one — §4.3 |
| 4 | Admin panel UI | Built on a tenant-provided Tailwind CSS template (pending delivery) — §5.14 |
| 5 | Admin authentication | Standard Devise (session cookie + CSRF) — §4.9 |
| 6 | API authentication strategy | Defined: BFF pattern + Tenant Server Key for Next.js, host-only session cookie for admin, station-scoped JWT for the print agent, Doorkeeper reserved for the future public API — §4.9 |

### 10.4 Open questions carried from v3 — all resolved by v8

All four items originally listed here (Next.js hosting platform, cross-tenant SSO, Tenant Server Key lifecycle, Tailwind template scope) are now resolved — see §10.12 items 9, 10, 11, 12 respectively. Hosting is the one still carrying a residual "not yet 100% final" note (§10.13 #1); the other three are fully closed.

### 10.5 Resolved in v4

| # | Question | Decision |
|---|---|---|
| 1 | Default public URL scheme (was a v3 open question) | `events.{platform_domain}.com`, a single shared subdomain with tenant/event resolved from the URL path, **not** a per-tenant subdomain — §4.3 |
| 2 | Super Admin's own console location | Bare apex domain `{platform_domain}.com`, distinct from every tenant's admin subdomain — §4.3 |
| 3 | Tenant/admin-user provisioning | Super-Admin-created, not self-serve sign-up, for all three plans — §4.1, §4.6 |
| 4 | Event public visibility & registration opening | Gated on Super Admin approval (`approval_status`), independent of the event's own scheduling status — §5.2 |
| 5 | Platform "income" tracking without payment schema | A computed usage-based read-model (participant count × plan pricing) shown per tenant/event in the Platform Console — not a payment/invoice transaction table — §4.6 |

### 10.6 New open questions raised by v4

1. **Rejection UX:** When the Super Admin rejects an event, does the organizer get a reason/feedback field, and is there a notification (email) back to the organizer, or does this stay purely an in-console status change? Affects the `Event` rejection data model (§8) and §5.10 (communications).
2. **Approval SLA/queue:** Is there an expected turnaround time for approvals that the organizer-facing UI should communicate (e.g. "typically reviewed within 24 hours")? Not a technical blocker, but affects the admin console's event-status messaging (§5.14).
3. **Re-approval on edit:** If an organizer edits an already-approved event (e.g. changes the venue or ticket categories), does it revert to `pending` automatically, or stay `approved` until the Super Admin re-reviews manually? This determines whether edits to a live, public event can go out immediately or need to wait on review again.
4. **Hub page requirement:** Is the tenant hub page (`events.{platform_domain}.com/{tenant_slug}` or `{tenant_domain}.com/`) a hard Phase 1 requirement, or can Phase 1 ship with only direct event-slug URLs and add the hub listing later?

### 10.7 Resolved in v5

| # | Question | Decision |
|---|---|---|
| 1 | Tenant-scoped OAuth2 provider timing | Pulled into MVP/Phase 1 — each Account can register its own OAuth application against a tenant-scoped public REST API; distinct from the still-deferred §5.12 integration framework — §4.9 item 4, §5.1, §8 |

### 10.8 New open questions raised by v5

1. **OAuth application management UI scope for MVP:** Does Phase 1 need a full self-service "create/rotate/revoke OAuth app" screen in the admin console, or is a minimal version (one app per Account, platform-generated) sufficient for launch? Affects §5.14 admin-screen scope.
2. **Public REST API surface for MVP:** Confirm exactly which resources are exposed via the new tenant OAuth API at launch (events, ticket categories, participants — read/write?) versus reserved for later, since "re-scope and re-secure the baseline's `/api/v1`" (§4.9 item 4) needs a concrete endpoint list before implementation.
3. **Per-tenant OAuth rate limits:** What default throttle applies per Account/application, and is it configurable per plan tier (Basic/Pro/Business, §4.6)?

### 10.9 Resolved in v6

| # | Question | Decision |
|---|---|---|
| 1 | SSO/SAML/OIDC/SCIM timing | Explicitly out of MVP — basic Devise email/password login only for Phase 1, for both tenant users and the Super Admin; enterprise SSO/SCIM deferred to Phase 3 — §5.1, §4.9, §9 |

### 10.10 Resolved in v7

| # | Question | Decision |
|---|---|---|
| 1 | Baseline repo's role | Requirements/feature reference only — the new build's schema and tooling are not bound to it. Already-locked decisions (Rails/Devise/Doorkeeper/Next.js/Tailwind) stand because they were separately confirmed in this conversation, not because they're the baseline's — §2, §4.10 |
| 2 | Real-time live dashboards | Confirmed flagship MVP requirement — WebSocket/SSE-driven, no page refresh, starting with live registration and check-in/occupancy counters — §5.15 |
| 3 | Event creation workflow | Simplified from the baseline's rigid linear wizard to a freely-navigable tabbed builder with autosave — §5.2 |

### 10.11 Open questions raised by v7 — all resolved by v8

All six architect recommendations listed here (real-time transport, badge/PDF renderer, ID scheme, partitioning strategy, search approach, observability vendor) are now confirmed — see §10.12 items 20–24 and §4.10 for the final picks.

### 10.12 Resolved in v8

| # | Question (source) | Decision |
|---|---|---|
| 1 | Billing period & cap semantics (§10.2 #1) | Per event, not per calendar period — §4.6 |
| 2 | Overage handling (§10.2 #2) | Soft cap — Super Admin can raise an event's participant cap from the Platform Console; every increase is tracked (`CapacityAdjustment`) and billed as overage on the post-event invoice — §4.6, §8 |
| 3 | Business plan mechanics (§10.2 #3) | Quotation-gated: Super Admin sends a fixed per-event quotation (e.g. a ~30k-style amount); tenant must approve it before the event can be created — §4.6 |
| 4 | Manual billing operations (§10.2 #4) | Fully specified: post-event invoice → tenant pays via NEFT → tenant uploads UTR/receipt → Super Admin verifies and marks paid — §4.6, §8 |
| 5 | Auto-print trigger definition (§10.2 #5) | Per-event toggle — §5.5.1 (already the working design, now confirmed) |
| 6 | Print agent implementation (§10.2 #6, §10.11 partial) | Electron, native silent-print API, `electron-builder` + `electron-updater` — §5.5.1 |
| 7 | First integration to build (§10.2 #7) | None — `govt_id` ships as a plain field with no API integration behind it — §5.4 |
| 8 | When to revisit payments (§10.2 #8) | Confirmed fully out of scope for this document; to be designed fresh in a future round |
| 9 | Next.js hosting platform (§10.4 #1) | Leaning self-hosted single VPS (Hetzner a likely candidate, not yet final) running Rails + Next.js + print-agent broker together, behind Caddy with on-demand TLS — §4.10 |
| 10 | Cross-tenant SSO (§10.4 #2) | Confirmed needed (agency-managing-multiple-tenants use case) and fully designed — new §4.11 |
| 11 | Tenant Server Key lifecycle (§10.4 #3) | Retired — replaced by reusing the tenant's own OAuth application with an access+refresh token flow (Doorkeeper client-credentials) — §4.9 |
| 12 | Tailwind template scope (§10.4 #4) | Process confirmed: template will be added to the workspace; before any UI work, check the template and pick/adapt the relevant component rather than build from scratch — §5.14 |
| 13 | Rejection UX (§10.6 #1) | Reason required, organizer notified by email (WhatsApp deferred), rejection status + reason shown in admin panel — §5.2 |
| 14 | Approval SLA (§10.6 #2) | Within 24 hours, target communicated to organizers, review queue surfaces at-risk items — §5.2 |
| 15 | Re-approval on edit (§10.6 #3) | Confirmed — approved events can be freely edited without reverting to `pending`, since billing is per event, not content-gated — §5.2 |
| 16 | Hub page requirement (§10.6 #4) | Not required for MVP — only direct `/{event_slug}` URLs; tenant resolved by `tenant_slug` on the shared subdomain or by `Host` on a custom domain — §4.3 |
| 17 | OAuth app management UI scope (§10.8 #1) | Super Admin creates the tenant's OAuth application at tenant-provisioning time — no tenant self-service "register an app" screen for MVP — §4.9 item 4 |
| 18 | Public REST API surface for MVP (§10.8 #2) | Exactly two endpoints: event show (read), register participant (write), both OAuth-protected — §4.9 item 2 |
| 19 | Per-tenant OAuth rate limits (§10.8 #3) | Not required — a single default throttle is enough — §4.9 item 2 |
| 20 | Real-time transport split (§10.11 #1) | Unified on Turbo Streams/Action Cable for both apps — no separate SSE — §4.10, §5.15 |
| 21 | ULID vs. UUID (§10.11 #3) | UUID confirmed, specifically **UUIDv7** to keep the index-locality benefit — §4.10 |
| 22 | Partitioning strategy (§10.11 #4) | Monthly range partitioning on write timestamp — standard for event-log-style data — §4.10 |
| 23 | Search approach (§10.11 #5) | Postgres full-text search, confirmed — §4.10 |
| 24 | Observability vendor (§10.11 #6) | New Relic, confirmed — §4.10 |
| 25 | Badge design tool | GrapesJS recommended for the WYSIWYG editor (distinct from Grover, which renders the final PDF) — §4.10, §5.5 |

### 10.13 Open questions raised by v8 — all resolved by v9

All six items originally listed here are now closed — see §10.14.

### 10.14 Resolved in v9

| # | Question (source) | Decision |
|---|---|---|
| 1 | Hosting provider final confirmation (§10.13 #1) | Deployment *approach* confirmed: Docker + Terraform (IaC), provider-agnostic — exact VPS provider (Hetzner candidate) still pending, but no longer blocks design work — §4.10 |
| 2 | WhatsApp rejection notifications (§10.13 #2) | Confirmed for MVP via **Gupshup** — a second narrow exception to "no third-party integrations," scoped to Super-Admin-to-tenant operational notifications only — §5.2, §5.10, §5.12 |
| 3 | Capacity-adjustment pricing rate (§10.13 #3) | Defaults to the plan's decided rate, with Super Admin override flexibility per adjustment — §4.6, §8 |
| 4 | Quotation UI/workflow detail (§10.13 #4) | Tenant can reject with a note; Super Admin revises and resends — repeatable, tracked via `QuotationRevision` — §4.6, §8 |
| 5 | Single-VPS resilience (§10.13 #5) | Acknowledged — accepted trade-off for MVP — §4.10 |
| 6 | Agency SSO scope for Phase 1 (§10.13 #6) | Confirmed in MVP, not a fast-follow — §4.11, §9 |

### 10.15 Open questions raised by v9 — all resolved by v10

### 10.16 Resolved in v10

| # | Question (source) | Decision |
|---|---|---|
| 1 | Gupshup account/number/template setup (§10.15 #1) | Stakeholder's own responsibility, outside platform engineering — assume the credential exists when Phase 1 reaches the WhatsApp work — §5.10 |
| 2 | Phone number collection (§10.15 #2) | Use the existing `contact_num` field on `User` — no separate WhatsApp field — §8 |
| 3 | Quotation revision limit (§10.15 #3) | 3 rejections; on the 3rd, `Quotation` moves to `cancelled` — §4.6, §8 |

No new open questions raised by v10 — every item logged in this decisions log through §10.16 is now resolved.
