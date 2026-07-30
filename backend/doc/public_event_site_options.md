# Public Event Show & Registration Pages — Options

Written in response to a request to think through three asks together:

1. A non-auth public endpoint that shows event details and lets someone register, per event.
2. Support for a tenant's own custom domain on those public pages.
3. An option, at the event/account level, for a tenant to supply their **own custom HTML** for
   the show/registration page, rendered directly on the public pages.

This doc is a set of options and a recommendation, not a plan to execute — nothing here has been
built yet.

## Finding worth flagging first

`doc/requirement.md` (§4.3, §4.8, §4.9) and `doc/implementation_3.md` (Phase 26) already settled
this, months ago, as a deliberate stakeholder decision: the public site is a **separate,
headless Next.js app**, Rails exposes exactly two OAuth-protected endpoints for it (event show,
register participant), and a `frontend/` sibling directory was scaffolded (`create-next-app`,
still unmodified — "final phase, not yet started") to eventually hold it.

**That `frontend/` directory no longer exists.** `git log` shows it was added whole in the first
commit and then deleted whole in the most recent commit, `20c675c "Some fixes around the
event."` — a commit that also carried real, unrelated backend/check-in work (the camera barcode
scanner, a profile controller, etc.). Nothing in that commit's message or the surrounding work
suggests a deliberate "we're abandoning Next.js" call; it reads like collateral damage. Worth
confirming whether that was intentional before treating the Next.js decision as settled — if it
was accidental, `git show 9dc480f -- frontend` has the original scaffold to restore.

Everything below is written assuming that decision is genuinely back open, since the question
was asked again.

## What already exists that any option would reuse

- **Tenant resolution by Host header** — `Hosting::Resolver` + `Hosting::TenantSubdomainConstraint`
  already do exactly this for the Admin Console (`{slug}.{platform_domain}`). The same shape
  extends cleanly to a public namespace.
- **`TenantDomain` model** — `kind: subdomain|custom`, `tls_status`, `verified_at`, `belongs_to
  :account`, deliberately *not* `TenantScoped` so it's findable before any tenant context exists.
  This is exactly "a tenant's own custom domain" — it's modeled, just has zero real consumers
  right now (pure scaffold from Phase 0).
- **Per-account OAuth application** — `Account#oauth_application` (Doorkeeper), auto-provisioned
  already, intended as the credential a BFF-style frontend would use via client-credentials.
- **Row-based multi-tenancy + Postgres RLS** — `Current.account`, `TenantScoped`, session var set
  in `TenantResolvable`. A public controller resolving tenant by Host/slug plugs into the exact
  same mechanism, not a new one.
- **The Badge template/instantiation shape** — directly relevant to ask #3, for its *data model*,
  not its authoring tool. `BadgeTemplate` is a reusable, account-level library; `Badge.
  build_from_template` copies one onto a specific Event, which is then substituted per-participant
  by `BadgeReformService`'s token vocabulary (`$NAME$`, `$QRCODE$`, `$PHOTO$`, etc.) and rendered
  via Grover. The library → per-event-instance → token-substitution *shape* is exactly what the
  event-page template below reuses; GrapesJS (the *authoring* tool badges use to produce that
  HTML) is not part of what's being reused — see below, the HTML here is hand-authored instead.
- **Caddy + on-demand TLS** — already the chosen answer (§4.10) for "arbitrary customer-owned
  domains need certificates automatically," independent of which app ends up serving the content.

## Option A — Rails-rendered public pages (no separate frontend)

A new `public` (or similar) namespace/controller in this same Rails app, unauthenticated, tenant
resolved by Host exactly like `Admin::BaseController` does today, rendering ERB (or ViewComponent)
straight to the browser.

**Pros**
- Ships fastest — one codebase, one deploy, no new runtime, no BFF/OAuth token-refresh machinery
  needed at all (same-process access to `Current.account`, no API hop).
- SEO is fine — it's genuine server-rendered HTML on first byte, same as any Rails app.
- Custom domains: extend the existing `Hosting::Resolver`/constraint pattern to also check
  `TenantDomain` (not just `Account#subdomain_slug`) — a small, well-precedented change, not new
  architecture.
- Real-time "seats remaining" ticker: reuses the exact Turbo Streams/Action Cable + Redis pub/sub
  the admin console already has, no second real-time client library.

**Cons**
- Walks back a decision already made and partially reasoned through (Next.js's SSR/ISR, a richer
  component ecosystem for a marketing-grade public page, future flexibility for a design agency to
  reskin heavily).
- Everything public-facing now shares fate/deploy cadence with the admin console.

## Option B — Separate Next.js app (the original plan, restored)

Rebuild `frontend/` as originally scoped: Next.js, BFF pattern (Next.js server is the only thing
that calls Rails; browser never does), client-credentials OAuth token obtained/refreshed
server-side against each tenant's own `oauth_application`, domain resolution via a Rails
`domain_resolution` endpoint with short-TTL caching.

**Pros**
- Matches the already-written architecture doc and Phase 26 spec exactly — no re-litigating
  §4.3/§4.8/§4.9.
- Best long-term fit if the public site is meant to become a real marketing/SEO surface, or if a
  design/growth team wants to iterate on it independent of backend release cycles.
- Cleanest separation: Rails stays pure API + admin for this surface, matches "exactly two
  endpoints" MVP scope already agreed.

**Cons**
- Real cost to rebuild now: a second codebase, second deploy pipeline, second real-time client
  wiring (`@rails/actioncable` from the browser this time), a real OAuth token-refresh
  implementation server-side — none of that exists yet despite being scoped.
- Tenant-custom-HTML (ask #3) is *harder* here, not easier: a React app doesn't have an obvious
  place to drop a tenant's raw HTML/CSS short of `dangerouslySetInnerHTML` on sanitized markup, or
  building a full block/section renderer. Either way it's more machinery than the Rails
  equivalent, not less.
- Two runtimes to keep in sync on the self-hosted single-VPS topology (`doc/requirement.md`
  §4.10) — more moving parts for the ops side of a fixed-hierarchy, no-dedicated-platform-team
  setup.

## Option C — Ship the API now, decide the renderer per surface (recommended)

Treat "exactly two endpoints, OAuth-protected, tenant-scoped" (already agreed in §4.9) as the
real deliverable and the future-proof boundary — build that now, regardless of what renders it.
Then:

- Ship a **Rails-rendered default public page today** (Option A) that itself simply *consumes*
  those same two endpoints internally (or the underlying service objects directly — no reason to
  force a network hop within one process) — so there's a working, non-auth event show +
  registration page in the very same PR that adds the API.
- Leave `frontend/` (Next.js) restorable/buildable **later**, as a pure swap-in — since it would
  talk to the exact same API surface, adding it later doesn't touch anything that shipped now. No
  work done today is thrown away if/when a Next.js frontend is (re)built.
- Custom domains and tenant-custom-HTML both get solved once, at the Rails layer, and both keep
  working unchanged whichever renderer ends up live.

This sidesteps betting the whole timeline on "rebuild Next.js from scratch right now" while not
foreclosing it either — it was already the agreed direction, this just doesn't make it a
blocker for having *something* live.

## Custom domain handling (applies to any option above)

1. Admin console: tenant enters a domain → creates a `TenantDomain(kind: :custom)` row →
   platform shows a DNS target (CNAME/TXT) to configure.
2. A background job polls DNS, sets `verified_at` once it resolves correctly (already-modeled
   column, no schema change needed).
3. Caddy in front of everything requests a certificate the first time the domain is actually hit,
   confirming with Rails the domain is verified before issuing one (on-demand TLS — the specific
   mechanism `doc/requirement.md` §4.3/§4.10 already picked, still the right tool for
   "arbitrary customer-owned domains, self-hosted, no managed cert automation").
4. Whichever app serves the public page resolves tenant from `Host` when it's a verified
   `TenantDomain`, falling back to the shared default domain + slug otherwise — same dual-branch
   shape §4.3 already specifies for Next.js, equally applicable to a Rails-rendered version.

## Tenant-customizable show/registration HTML (corrected — hand-authored, not GrapesJS)

**Confirmed shape:** the HTML is not tenant self-service and not auto-generated by a visual editor
like the Badge builder. Your own team hand-authors it — plain HTML/CSS files with placeholder
tokens written in by hand (`{{event_name}}`, `{{speaker_list}}`, `{{schedule}}`, etc.) — and a
backend `EventHtmlParser` service (same *role* as `BadgeReformService`: takes a template + real
data, returns a fully-substituted string) fills them in before the result ever reaches Next.js.
This meaningfully narrows the trust/security picture versus a tenant-self-service builder: the
template itself is internally authored, not adversarial input, so the sanitization concern below
is only about the *dynamic values* dropped into it, not the template's own markup.

**Storage shape — shared library, per event/tenant selects one** (confirmed): mirrors
`BadgeTemplate` → `Badge` exactly. An account-level library of hand-authored templates (e.g.
"Conference", "Webinar", "Meetup") that your team maintains; each event (or tenant, at
provisioning time) selects one by reference. Unlike Badge's own `build_from_template` (which
*copies* the template onto the event so it can then be independently tweaked per-event in the
GrapesJS editor), there's no per-event editing UI here — nothing tenant- or event-specific ever
diverges from the library copy — so the simpler, more maintainable default is a **live reference**
(`Event#event_page_template_id` or similar), not a copy. One fix to a library template in your
team's repo/admin then applies to every event using it immediately, no per-event drift to hunt
down later. Worth an explicit call: if you *do* eventually want a specific event to diverge from
its library template (a one-off tweak for a single big event), that's the point where a
copy-on-select becomes worth the added complexity — not needed for the shape as described now.

**`EventHtmlParser`'s token vocabulary** (concrete first pass, name it whatever fits your
conventions) — `{{event_name}}`, `{{event_description}}`, `{{event_banner}}`,
`{{event_starts_at}}`/`{{event_ends_at}}`, `{{event_address}}`/`{{meeting_link}}`,
`{{speaker_list}}`, `{{schedule}}`/`{{agenda}}`, `{{ticket_categories}}`, `{{seats_remaining}}` —
plus one reserved, special-cased token: `{{register_form}}` (see below, it's not replaced with
literal markup).

**The one real technical wrinkle worth solving explicitly now, not discovering mid-build: how does
a live React registration form end up *inside* a big raw HTML string that Next.js injects via
`dangerouslySetInnerHTML`?** Two options:

- **DOM portals** — mount the raw HTML, then `ReactDOM.createPortal` a `<RegistrationForm/>` into
  a node matching a known id/data-attribute found inside it. Works, but is client-side-only (a
  `useEffect` + `querySelector` after mount), so the portal target has a flash-of-missing-form
  moment and doesn't SSR — worse for SEO/first-paint of the one interactive part of the page that
  matters most for conversions.
- **String-split around a sentinel (recommended)** — `EventHtmlParser` leaves `{{register_form}}`
  as a unique, unambiguous sentinel string (not literal HTML) in its output. Next.js's Server
  Component does `content.split(SENTINEL)` and renders three pieces in order: `[dangerouslySetInnerHTML
  first half]`, `<RegistrationForm />` (a real Client Component, fully interactive, still inside
  the normal SSR'd tree), `[dangerouslySetInnerHTML second half]`. No portals, no client-only
  mounting, no hydration-timing fragility — this is the same trick used wherever CMS-authored
  HTML/Markdown needs a live interactive widget dropped mid-content. The same technique generalizes
  to any other live element your team wants embedded inline (e.g. a `{{seats_remaining_ticker}}`
  sentinel for the real-time Action Cable counter), not just the registration form.

**Sanitization, narrowed to what's actually untrusted here:** the hand-authored template markup
itself doesn't need scrubbing (your own team wrote it). What still does: every *dynamic value*
substituted into a placeholder that ultimately traces back to organizer-entered content — event
description, speaker bios, anything from a rich-text field — since those can contain HTML an
organizer pasted in, not just plain text. `EventHtmlParser` should run each such value through
Rails' sanitizer (Loofah, ships with Action View) before substitution, not the template as a
whole.

**No template selected** falls back to the platform's own default page — same "optional override,
sane default" shape `Event#badge_for_category` already uses for badges with no category-specific
override.

## Feasibility check — Rails-rendered HTML over the API, Next.js as a thin cached shell

A specific hybrid shape was proposed and checked for feasibility before committing to Next.js:
Rails fully substitutes tenant/event data into HTML server-side and returns it via the API; Next.js
injects that HTML as-is (not re-templated client-side) and caches it; the registration form itself
stays a real, schema-driven React component, not HTML. Verdict: **feasible, and recommended** —
details below.

**Content (show page).** Same role as `BadgeReformService`, aimed at a webpage string instead of a
PNG/PDF: `EventHtmlParser` substitutes its token vocabulary (`{{event_name}}`,
`{{event_description}}`, `{{speaker_list}}`, `{{agenda}}`, `{{event_banner}}`, ...) into your
team's hand-authored template and returns the finished HTML string, with the `{{register_form}}`
token left as a sentinel rather than substituted (see the split technique above). Next.js does
zero templating — it renders the string in a **Server Component** via `dangerouslySetInnerHTML`
(still fully SSR'd, still crawlable/SEO-fine, no different from any headless-CMS-over-Next
integration), splitting once on the sentinel to interleave the live registration component.

**Registration (interactive part).** Stays a real React **Client Component**, not HTML, rendered
from a structured JSON schema Rails already effectively has via `RegistrationForm`/`CustomField`
(field list, types, required-ness, per-ticket-category assignment) — submitting to the `register
participant` endpoint. It sits beside the static HTML block on the page, not inside it — ordinary
Server + Client Component composition, no conflict with the cached part around it.

**Caching.** Next.js `fetch(url, { next: { tags: ["event:<slug>"], revalidate: 300 } })` as the
safety net, plus on-demand invalidation: Rails calls a small, shared-secret-authenticated `POST
/api/revalidate` on the Next.js server right after an admin saves/publishes an event or its page
template, which calls `revalidateTag`. Standard on-demand-ISR pattern (the same shape
Contentful/Sanity-style webhook integrations use) — nothing novel required.

**The caveat, narrowed now that the template is hand-authored, not tenant-submitted:** the template
markup itself is trusted (your team wrote it), so the XSS surface is only the dynamic values
`EventHtmlParser` substitutes in — event description, speaker bios, any organizer-entered
rich-text field. Because Next.js injects the final string raw (no React escaping), those values
must be sanitized (Loofah, strict allowlist) *before* substitution, every time, not just at input
time — one gap there is still a stored-XSS hole served to every visitor of that page, the
authored-template trust doesn't cover it. One smaller, non-blocking follow-on: `generateMetadata`
needs real event data for OG/social meta tags, not scraped back out of the HTML blob.

**Domain/subdomain resolution.** Also feasible, and no new modeling needed: `TenantDomain#domain`
is matched as a plain exact string against the incoming `Host` header, so a tenant verifying an
apex (`mycompany.com`) versus their own subdomain (`events.mycompany.com`) is the *same* lookup,
same DNS-verification flow, same Caddy on-demand TLS (issued per-hostname regardless of level — no
wildcard cert required). Next.js middleware reads `request.headers.get("host")`, calls Rails'
`domain_resolution` endpoint (already spec'd, §4.3, short-TTL cached): try `TenantDomain` first,
fall back to the shared-subdomain-plus-path-segment scheme otherwise. One resolver, both cases,
built once at the Rails layer regardless of which frontend ends up calling it.

## Recommendation summary

1. Confirm whether the `frontend/` deletion in `20c675c` was intentional — this genuinely changes
   the starting point.
2. Build the public API (event show, register participant) now, per the already-agreed §4.9 spec
   — OAuth-protected, tenant-scoped, reusing `TenantResolvable`'s pattern.
3. Ship a Rails-rendered default public page against that same API/service layer now (Option C),
   rather than waiting on a Next.js rebuild to have anything live.
4. Extend `Hosting::Resolver` to also resolve verified `TenantDomain` rows, wire Caddy on-demand
   TLS in front — same mechanism already chosen in `requirement.md`, now actually consumed.
5. Model page customization as a shared library of hand-authored HTML templates (mirrors
   `BadgeTemplate`'s library shape, not its GrapesJS authoring tool) with an `EventHtmlParser`
   token-substitution service (`BadgeReformService`'s role, new vocabulary) — sanitize the dynamic
   values it substitutes, not the template itself. Keep `{{register_form}}` a sentinel Next.js
   splits on to interleave the real, platform-owned registration component.
6. Treat a (re)built Next.js frontend as a pure, optional swap-in later, consuming the same API —
   never a blocker for shipping the above.

## Open questions for you

- Was the `frontend/` deletion intentional, or should it be restored from `9dc480f`?
- Is a fully custom, agency-designed marketing site (real Next.js/React control) an actual
  near-term ask from a specific tenant, or is "look different per tenant" satisfied by
  colors/logo/layout-order customization within a fixed template? That materially changes whether
  Option B's cost is worth paying soon versus later.
- For custom domains: self-serve DNS verification (as sketched above), or is a Super
  Admin/Agency-assisted manual step acceptable for MVP, given the fixed-hierarchy, no-self-serve-
  signup model the rest of the platform already uses?

---

# Implementation Plan

**Status: reviewed — every open question below is now resolved.** This is the final shape to build
against, pending your go-ahead to start.

**Decision (this revision): Option B confirmed** — separate Next.js app, BFF pattern, per the
"Option B" section above. `frontend/` has already been restored (confirmed present in the repo,
still the untouched `create-next-app` scaffold — Next.js 16, React 19, `@reduxjs/toolkit`/
`react-redux` already in `package.json`, nothing else built yet). This section supersedes the first
draft of the plan that used to live here, written before Option B was picked and before the exact
UX below was described. The Goal/Depends-on/checklist shape still follows
`doc/implementation_3.md`'s own convention for every phase, still refines/extends that file's
existing **Phase 25** (OAuth API) and **Phase 26** (Next.js Public Event Site).

**The actual requirement, as given:** an event-wise public details + registration page. In the
Admin Console, each event's own workspace (the existing per-event sidebar — Analytics, Design
Registration Form, Email Templates, ... — `AdminHelper#event_nav_items`) gains a place to store
that event's own public-page HTML. The public page itself shows that HTML plus a "Register" button;
the button opens a modal containing the registration form — the same form component on every event,
populated with whichever fields that event's own `RegistrationForm`/`CustomField` setup defines.

## What changed vs. the first draft (read this before the phases below)

- **Public page HTML is a per-event, tenant-authored field now, not a shared team-curated
  library.** The first draft's `EventPageTemplate` (an account-level library your own team
  hand-authors, mirroring `BadgeTemplate`) is dropped — replaced by a single `Event#public_page_html`
  field the event's own admin fills in directly, inside that event's own workspace. This is a real
  security-posture shift: the doc's earlier "hand-authored by your team, trusted" framing (the
  "Tenant-customizable show/registration HTML" section above) no longer holds once each tenant can
  paste their own markup — confirmed as a deliberate, no-sanitization trust decision (Confirmed
  decision #2 below), not an oversight.
- **Registration is a modal opened by a button, not inline-embedded via a `{{register_form}}`
  sentinel.** The first draft's entire "one real technical wrinkle" discussion (DOM portals vs.
  string-split-and-interleave) is now moot — the stored HTML renders as-is, nothing is substituted
  or split inside it. A fixed "Register" button, part of the platform's own page chrome (not the
  tenant's stored HTML), opens the modal. This removes the sentinel constant, the token-substitution
  vocabulary (`{{event_name}}`, `{{speaker_list}}`, etc.), and `EventHtmlParser` entirely — the
  stored HTML has no placeholders to fill in at all, it's just rendered.
- **The registration form itself is unchanged** from the first draft: one shared React component,
  fields driven by `registration_schema` (already-built `RegistrationForm`/`CustomField` data, keyed
  by ticket category), RTK Query mutation through a Next.js-hosted `/api/register` route handler.
  Only its container changed (modal instead of inline-interleaved block).
- Custom-domain/`TenantDomain` handling (the "Custom domain handling" section above) is **unchanged**
  by any of this and still applies as written.

## Confirmed decisions (review round complete)

Answers to the six open questions from the previous revision, folded into the phases below:

1. **`frontend/` restoration** — done, already restored in the repo (confirmed above).
2. **Trust extends to the whole document, no sanitization** — any event admin can paste arbitrary
   HTML/CSS/JS for their own event's page, stored and rendered exactly as submitted. Same trust
   model as a website builder's "custom code" feature (Webflow/Squarespace-style): the tenant owns
   the risk for their own page and their own visitors, not a cross-tenant concern. This **removes**
   the first draft's Loofah-sanitization step entirely — `EventHtmlParser`/allowlist/`<script>`
   stripping is dropped from Phase 25.5 below, not just narrowed.
3. **Nav label: "Event Page"** — a new event-scoped sidebar item, alongside "Design Registration
   Form"/"Email Templates" (`AdminHelper#event_nav_items`). Chosen over the literal "Event &
   Registration" phrase since "Design Registration Form" already owns the registration-fields
   concept next to it; "Event Page" names specifically what this new item edits. Flag if you'd
   rather use different wording — trivial to rename before or after building.
4. **No draft/publish workflow for the page content itself** — saving `public_page_html` takes
   effect immediately, live, with no separate publish step and no reverting the *event's* own
   status to draft (does **not** get added to `Event::CONTENT_ATTRIBUTES`). Separately, the
   *event's own* existing draft/published state still gates whether the custom page is shown at
   all: while the event itself is still in draft (`published_at.nil?`, unrelated to page-content
   editing), the public page always shows Next.js's own default page, regardless of what's stored in
   `public_page_html` — see #5, same mechanism handles both "nothing stored" and "event still
   draft."
5. **Fallback page lives in Next.js, not Rails** — no seeded default `EventPageTemplate`/HTML on
   the Rails side. The public API just reports whether an event is published and what
   `content_html` (if any) it has; Next.js owns one built-in default-page component, shown whenever
   either is missing:
   - Event published, `content_html` blank → Next.js default page, **with a working Register
     button** (registration is open, just using the platform's own default look instead of the
     tenant's custom one).
   - Event still draft (not yet published) → Next.js default page, **no Register button** — an
     unpublished event isn't open for registration yet, same as the admin console's own gate
     everywhere else. *(This is a synthesis of your two answers — flag if registration should
     actually stay closed on the default page in the first case too, not just the second.)*
6. **Kept, not deleted** — the "Tenant-customizable show/registration HTML" and "Feasibility check"
   sections above stay in the doc as the reasoning trail for the shared-library/sentinel design that
   got superseded, per your confirmation.

## Phase 25.5 (revision 2) — Per-event public page HTML — **Shipped 2026-07-30**

**Goal:** give an event admin a place, inside that event's own workspace, to store the raw
HTML/CSS for that event's public page.
**Depends on:** nothing new — reuses `Event`, `EventScoped`, `AdminHelper#event_nav_items`,
`EventPolicy#update?`/`#update_reason`.

- [x] `EventPage` model — **not** `Event#public_page_html` as originally planned here; built as a
  dedicated table (`has_one :event_page` on `Event`) instead, per direct correction during
  implementation ("create the separate table for html pages, don't include it in event table") —
  see the memory note this decision is recorded under. `html` column, `TenantScoped` +
  `TenantRowLevelSecurity.enable!` like every other tenant table. Stored and returned exactly as
  submitted — **no sanitization step** (Confirmed decision #2 above).
- [x] New event-scoped admin nav item, **"Event Page"**, in `AdminHelper#event_nav_items`.
- [x] `Admin::EventPagesController` — singular resource (`resource :event_page`, find-or-initialize
  on `#edit`), raw-HTML textarea plus a live preview pane. The preview turned out not to need any
  server round-trip at all (no token substitution to run) — a plain client-side Stimulus controller
  (`event_page_preview_controller.js`) writes the textarea straight into an iframe's `srcdoc`.
- [x] Authorization: `authorize @event, :update?` — the completed-event lock applies for free.
- [x] Saving takes effect immediately — not added to `Event::CONTENT_ATTRIBUTES`.
- [x] No fallback page logic on the Rails side — Next.js owns it (see Phase 26).

### Definition of Done
- [x] Request spec: saves `public_page_html`/`EventPage#html` verbatim, no filtering.
- [x] Request spec: blocked on a completed event, real reason in the flash.
- [x] Request spec: editing on an already-published event leaves `status`/`published_at` untouched.

## Phase 25 (revision 2) — Public API surface — **Shipped 2026-07-30**

- [x] `GET /api/v1/public/events/:slug` (`Api::V1::Public::EventsController#show`) returns
  `content_html`, `published`, `registration_schema`, and structured fields (`name`, `description`,
  `starts_at`/`ends_at`, `address`, `meeting_link`, `seats_remaining`). A draft event still resolves
  (200, `published: false`) rather than 404ing.
- [x] `domain_resolution` endpoint (`Api::V1::Public::DomainResolutionsController#show`) — resolves
  both the shared subdomain shape and a verified `TenantDomain`.
  - **One real gap this doc never spelled out, found and closed during implementation:** Next.js is
    a single shared deployment across every tenant, so it has no per-tenant OAuth `client_id`/
    `client_secret` hardcoded anywhere — it has to look one up per request. Rather than a second
    endpoint, `domain_resolution`'s own response now *also* includes `client_id`/`client_secret`
    when the caller presents a second, distinct shared secret (`PUBLIC_SITE_SHARED_SECRET`, header
    `X-Public-Site-Secret`) proving it's the real Next.js BFF — not the revalidation webhook's own
    secret, a different trust direction.
- [x] **Register-participant endpoint** (`Api::V1::Public::ParticipantsController#create`, `POST
  /api/v1/public/events/:slug/participants`) — not in this doc's original Phase 25 scope at all
  (only sketched as "the other of exactly two endpoints" in the requirement.md quote above) but
  built this session since the registration modal needs somewhere to submit to. Reuses
  `Admin::ParticipantsController`'s own Participant validations unchanged (dedupe, required
  fields, approval-gated status). Adds one new rule neither admin entry nor this doc anticipated: a
  hard per-category capacity check. **Real finding:** `TicketCategory#remain_count`/`sold_count`
  track `TicketReservation` bulk/group holds only (a separate, largely-unused mechanism) — there
  was no existing "how many people already registered" concept for individual participants at all.
  Implemented as a straight count against `total_count`, rejecting with `sold_out` once full — no
  waitlist (`Participant` has no such status; a real FIFO waitlist would need new modeling this
  session didn't do). `source: :client_api` — reused an existing enum value, not a new one.
- [x] Revalidation webhook contract — `PublicSiteRevalidator`/`PublicSiteRevalidationJob`,
  `POST {PUBLIC_SITE_REVALIDATE_URL}` with header `X-Revalidate-Secret`. Fires on `Event`
  (CONTENT_ATTRIBUTES/`published_at` changes) and `EventPage` (any save) via `after_commit` —
  deliberately **not** wired to `RegistrationForm`/`CustomField` changes in this pass (scoped down;
  the 5-minute time-based `revalidate: 300` fallback covers those). No-ops silently when
  `PUBLIC_SITE_REVALIDATE_URL` isn't set — that's the expected default, not a failure.

### Definition of Done (additive)
- [x] Request spec: `content_html` matches `EventPage#html` exactly, verbatim.
- [x] Request spec: `published` reflects `Event#published?` correctly; draft → 200, not 404.
- [x] Request spec: `domain_resolution` resolves a verified custom domain and the shared-subdomain
  case; unverified/unknown hosts resolve to neither (404); credentials only included with the right
  shared secret.
- [x] Request spec: the revalidation webhook rejects a request without the correct shared secret.
- [x] Request spec: register-participant enforces dedupe, capacity, and approval-gated status;
  404s for an unknown ticket category.

## Phase 26 (revision 2) — Next.js Public Event Site — **Shipped 2026-07-30**

> **URL structure, corrected twice, same general area (2026-07-30 then 2026-07-31 — both direct
> user corrections):** three public URL shapes are supported, not one:
> 1. Shared default domain + path (added 2026-07-30): `{platform-public-domain}/events/{tenantSlug}/{eventSlug}`
>    — e.g. `localhost:5173/events/xaniel/aws-summit-2027` locally. Tenant identified by **URL
>    path**, not Host, since every visitor on the shared domain has the same Host.
> 2. Tenant's own subdomain (kept 2026-07-31, after briefly being dropped in favor of (1) — see
>    below): `{tenantSlug}.{platform_domain}/events/{eventSlug}`. Host-based.
> 3. Tenant's own verified custom domain: `{tenant-domain}/events/{eventSlug}` — e.g.
>    `https://xaniel.com/events/aws-summit-2027`. Also Host-based.
>
> (2) and (3) turned out to need **zero code differences between them** — `lib/server/rails.ts#
> resolveDomain` was already generic, it just asks Rails' `domain_resolution`, which tries a
> verified `TenantDomain` first then falls back to `Hosting::Resolver`'s own subdomain-label
> parsing; the route serving both never cared which branch answered. Only the route's own comments
> (previously describing it as custom-domain-only, from the 2026-07-30 pass before (2) was asked
> to come back) needed correcting, not new logic — worth checking whether an existing generic
> resolver already covers a "bring feature X back" ask before adding new routing for it.
>
> Routes ended up as `app/events/[slug]/page.tsx` (shapes (2) and (3), both Host-based) and
> `app/events/[slug]/[eventSlug]/page.tsx` (shape (1) — same outer folder name is a Next.js
> constraint, not a choice: sibling routes at one tree position must share one dynamic-segment
> name; that outer `slug` means the *tenant's* slug on this route, the *event's* slug on the
> other). `lib/server/rails.ts#resolveDomainForAccountSlug` is shape (1)'s own resolver — builds a
> synthetic `{tenantSlug}.{platform_domain}` host and feeds it through the exact same
> `domain_resolution` call shapes (2)/(3) use, zero Rails-side changes needed. `/api/register` and
> the RTK Query mutation both gained an optional `accountSlug` field for the same reason (Host
> alone can't disambiguate a tenant on the shared domain, shape (1) only). One more real bug found
> and fixed during this pass: the revalidation cache tag was just `event:{slug}`, but `Event`'s own
> `friendly_id` is scoped per-account (`use: :scoped, scope: :account_id`), so two tenants sharing
> an event slug could cross-invalidate
> each other's cached page — fixed to `event:{accountSlug}:{eventSlug}` on both sides. Every
> checklist item below still describes what was actually built; only the URL shape it mentions
> (`[slug]`) predates the three-shape structure this note now describes.

- [x] `frontend/` restored (Confirmed decision #1).
- [x] Domain resolution happens inline, server-side, inside the event page's own Server Component
  (`lib/server/rails.ts#resolveDomain`, called from `app/events/[slug]/page.tsx`) — **no
  `proxy.ts`/middleware needed** for this. (Next.js 16 renamed Middleware to Proxy — confirmed
  against `node_modules/next/dist/docs` before writing any of this, per `frontend/AGENTS.md`'s own
  warning that this version has real breaking changes vs. training data. Worth re-reading those
  docs fresh for any *future* Next.js work here too, not just this session's.)
- [x] Client-credentials token fetch — server-only (`lib/server/rails.ts#getAccessToken`), in-memory
  cached per account with a 30s expiry safety margin. **No refresh-token rotation** — this app's
  Doorkeeper config has `refresh_token_enabled? == false`, so a expired token is simply
  re-requested with the same client_id/secret; there's no interactive-consent step client_credentials
  needs a refresh token to avoid repeating.
- [x] Event page (Server Component) — uses the **"Previous Model"** `fetch(url, { next: { tags,
  revalidate: 300 } })` caching API, not the newer Cache Components (`use cache`/`cacheTag`) one —
  confirmed `next.config.ts` doesn't set `cacheComponents: true`, so the installed docs' "Previous
  Model" guide is the one that actually applies here. Branches on `published`/`content_html` exactly
  per Confirmed decision #5. Renders `content_html` via `dangerouslySetInnerHTML` directly, no
  split/sentinel handling — that entire category of complexity the first draft worked through above
  never had to be built.
- [x] Fixed **"Register" button** → `<RegistrationModal />` (Client Component) → `<RegistrationForm
  />`, entirely data-driven from `registration_schema`, RTK Query (`registrationApi.ts`) mutation
  through `/api/register`. Redux store is created per-mount (`store/provider.tsx`, scoped to just
  this component tree), not app-wide.
- [x] `<DefaultEventPage />` — withholds real event details entirely (no `event` prop) when
  unpublished; shows the structured fields when published-but-no-`content_html`.
- [x] `generateMetadata` — sourced from structured fields; also gated on `published` (an
  unpublished event's real name/description don't leak via the browser tab/social preview either —
  a gap the first pass of this build initially missed, caught before shipping).
- [x] `POST /api/register` route handler — thin proxy.
- [x] `POST /api/revalidate` route handler — verifies `PUBLIC_SITE_REVALIDATE_SECRET`, calls
  `revalidateTag(tag, "max")`. **Second argument is required** by this installed Next.js version's
  own type signature even on the "Previous Model" path (the docs' one-arg examples don't type-check
  against this runtime) — `"max"` per the documented stale-while-revalidate profile.
- [ ] **Not built this session:** public live "seats remaining" ticker (Action Cable) — no
  real-time piece was wired up; **not built:** `TenantDomain` custom-domain flow end-to-end (admin
  UI to add a domain, DNS-verification job, Caddy on-demand TLS wiring) — this remains genuinely
  infra-level work, same "can run in parallel, not blocking" scoping this doc always gave it.
- [ ] **Known, flagged gap:** photo/document/file-type custom fields aren't wired for public
  registration — `attach_tenant_scoped`/`attach_custom_field_file` on the Rails side both already
  accept a real multipart file with zero changes needed, so this becomes free once `/api/register`
  relays multipart instead of JSON; not done this session. A required file field today surfaces
  Rails' ordinary "can't be blank" validation error, not a broken endpoint.

### Definition of Done (additive/changed)
- [x] **Manually verified live** (not an automated E2E suite — no Playwright/Cypress is set up in
  `frontend/` at all yet, so none of this doc's original "E2E spec" DoD items below have a real
  automated test backing them, only the live verification described here): created a real event,
  set custom `content_html` including a `<script>` tag, confirmed it executes unmodified in the
  actual rendered response (no-sanitization decision genuinely in effect); confirmed the
  unpublished → `<DefaultEventPage />`-no-button / published-no-html → default-page-with-button /
  published-with-html → custom-page-with-button branching all render correctly; edited
  `EventPage#html` via the admin console and confirmed the Sidekiq-processed webhook actually
  invalidated the Next.js cache (`POST /api/revalidate 200` observed, followed by the updated
  content on next request, all without a redeploy); submitted a real registration through the full
  browser → Next.js `/api/register` → Rails pipeline and confirmed a real `Participant` was created
  (`source: client_api`) with the event's own dedupe rule correctly rejecting a repeat submission
  and the capacity check correctly rejecting once a category filled.
- [ ] Not verified: the subdomain-shaped custom domain path (`TenantDomain` E2E) — no custom domain
  flow exists yet (see above).
- [x] Manual check: confirmed no OAuth token/secret appears anywhere in a browser-facing response —
  every request from the client goes to this app's own `/api/register`, never directly to Rails
  (`lib/server/rails.ts` is a server-only module; `RAILS_APEX_URL`/`PUBLIC_SITE_SHARED_SECRET` are
  never `NEXT_PUBLIC_`-prefixed and are never imported from a `"use client"` file).

**Real bug caught and fixed during live verification, worth flagging for anyone touching this
later:** a browser's `Host` header includes a port on any non-default port (`xaniel.lvh.me:5173`
locally) — Rails' `Hosting::Resolver`/`TenantDomain` lookups assume a bare hostname (`request.host`
strips the port automatically everywhere else in the app; a raw `?host=` query param does not).
This silently 404ed every single request until fixed on both sides: `lib/server/rails.ts#resolveDomain`
strips the port before calling Rails, and `DomainResolutionsController#show` also strips it
independently (defense in depth — any future caller passing a port shouldn't have to know this).

## Suggested build order

**Steps 1–3 shipped 2026-07-30 (see the "Shipped" phase sections above); step 4 remains.**

1. Phase 25.5 (revision 2) — pure Rails: model, admin nav item + editor, authorization. Fully
   testable with no frontend dependency at all.
2. Phase 25 (revision 2) — API surface returning `content_html` + `published` + `registration_schema`.
   Still `curl`-testable.
3. Phase 26 (revision 2) — Next.js: `frontend/` already restored, nothing blocking this now.
   `<DefaultEventPage />`, "Register" button + modal, RTK Query mutation, revalidation webhook.
4. Custom-domain/Caddy wiring — unchanged from the "Custom domain handling" section above, can run
   in parallel with (3) once Phase 25's `domain_resolution` endpoint exists to point it at.

## Note on the sections above

The "Tenant-customizable show/registration HTML" and "Feasibility check" sections earlier in this
doc describe the first draft's shared-library, sentinel-embedded, sanitize-on-substitution design.
They're superseded by the Implementation Plan above for anything actually being built, and kept
in place only as the reasoning trail — the security-model discussion there (what's trusted vs.
not) is still relevant background even though the concrete mechanism changed.
