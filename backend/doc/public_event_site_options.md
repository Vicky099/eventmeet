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

Concrete, ordered, in the same Goal/Implements/Depends-on/checklist shape `doc/implementation_3.md`
already uses for every other phase — this refines and extends that file's existing **Phase 25**
(OAuth API) and **Phase 26** (Next.js Public Event Site) with everything settled in this doc
(`EventHtmlParser` + template library instead of a generic content model, the sentinel-split
registration technique, real `TenantDomain` wiring including subdomain-shaped custom domains). It
does not replace those phases' own checklists — treat this as the detailed version of Phase 26
plus one new phase (25.5) that has to land first.

## Phase 25.5 — Event page template library + `EventHtmlParser`

**Goal:** give Phase 25's event-show endpoint something real to return — a fully-substituted HTML
string, not just raw JSON fields — before Phase 26 has anything to render.
**Depends on:** `implementation.md` Phase 8 (`BadgeTemplate`/`Badge`'s library → per-record shape,
reused structurally here), Phase 7.5 (`RegistrationForm`/`CustomField`, for the registration
schema half of the payload).

- [ ] `EventPageTemplate` model — account-scoped (`TenantScoped`, like `BadgeTemplate`), holds the
  hand-authored HTML/CSS your team writes (a `content` text column is enough; a file-upload path
  is an alternative if your team prefers editing `.html` files locally and pushing them in over a
  form field — either way, plain storage, no GrapesJS/canvas JSON to parse back out).
- [ ] `Event#event_page_template` — `belongs_to :event_page_template, optional: true`, a **live
  reference** (not a copy — see this doc's own reasoning above: nothing diverges per-event, so a
  library fix should apply everywhere immediately without hunting down per-event drift).
- [ ] `EventHtmlParser` service (`app/services/event_html_parser.rb`, sibling to
  `BadgeReformService`) — `#call(template:, event:)` substituting the token vocabulary from this
  doc's "Tenant-customizable show/registration HTML" section (`{{event_name}}`,
  `{{event_description}}`, `{{speaker_list}}`, `{{agenda}}`, `{{event_banner}}`,
  `{{ticket_categories}}`, `{{seats_remaining}}`, ...) and leaving `{{register_form}}` as a literal,
  unambiguous sentinel constant (export it — Next.js needs the exact same string to split on).
- [ ] Sanitize only the *substituted values* that trace back to organizer-entered rich text (event
  description, speaker bios) at substitution time, via Rails' built-in Loofah-based sanitizer — not
  the template itself (trusted, hand-authored by your team).
- [ ] No template selected → fall back to one shipped default `EventPageTemplate` (seeded, not
  tenant-owned) — same "sane default, optional override" shape as `Event#badge_for_category`.
- [ ] Admin console: a plain read-only (for now — no self-service authoring) picker on the event's
  Basic Info or Review step to select which library template the event uses.

### Definition of Done
- [ ] Model spec: `EventHtmlParser` substitutes every token correctly; a missing/blank value
  degrades gracefully (blank string, not a raw `nil`/token literal leaking into output).
- [ ] Model spec: an organizer-entered `<script>` in the event description never survives into the
  parsed output.
- [ ] Model spec: changing a shared `EventPageTemplate`'s content is immediately reflected for
  every `Event` referencing it (confirms the live-reference, not copy, decision).
- [ ] Request/integration spec: the fallback default template renders correctly for an event with
  no `event_page_template` set.

## Phase 25 (revision) — Public API surface

Builds on the existing Phase 25 checklist in `implementation_3.md` — same OAuth
client-credentials/`rack-attack`/`Current.account` guard work, unchanged. What this doc adds:

- [ ] **One single public read endpoint, not two** (confirmed): earlier drafts of this doc talked
  about "the event-show endpoint" and "the HTML" as if separate concerns — they're the same call.
  `GET /api/v1/public/events/:slug` returns `content_html` (Phase 25.5's `EventHtmlParser` output,
  sentinel intact), `registration_schema` (catalog + custom fields from the event's applicable
  `RegistrationForm`(s), keyed by ticket category), and the handful of plain structured fields
  (name, dates, `seats_remaining`) `generateMetadata` needs for OG/social tags — all in one
  response. There is no second, JSON-only "event show" endpoint behind this one; the requirement.md
  §4.9 "two endpoints" MVP surface stays exactly two (this one, read; register-participant, write)
  — it was never meant to imply a *third* concept sitting between them.
- [ ] **Revalidation webhook contract**: `POST /api/revalidate` on the Next.js side (built in Phase
  26 below), called by Rails — a small shared-secret header (or reuse a signed request, HMAC over
  the body) — every time an `Event`, its `EventPageTemplate`, or its `RegistrationForm` changes in
  a way that affects the public page. Wire this as an `after_commit` on the relevant models (or a
  single service both the wizard's `update`/`publish!` actions and the template picker call into),
  not scattered ad hoc calls.
- [ ] **`domain_resolution` endpoint** (§4.3, referenced but not yet built): `GET
  /api/v1/public/domain_resolution?host=...&path=...` — looks up `TenantDomain.find_by(domain:
  host, verified_at: not nil)` first (this covers an apex *and* a subdomain-shaped custom domain
  identically, since it's a plain exact-string match — no special-casing needed for
  `events.tenant.com` vs `tenant.com`), falling back to `Hosting::Resolver`'s existing
  subdomain-label parsing + a `tenant_slug` path segment on the shared default domain otherwise.
  Response: `{ account_slug, kind }` or 404. Short-TTL-cacheable by the caller (no per-request
  Rails round-trip needed on every Next.js request).

### Definition of Done (additive to existing Phase 25 DoD)
- [ ] Request spec: event-show response includes `content_html` with the sentinel still present,
  unsubstituted.
- [ ] Request spec: `domain_resolution` resolves a verified apex custom domain, a verified
  subdomain-shaped custom domain, and the shared-domain-plus-path-segment case, each to the correct
  `Account`; an unverified or unknown host resolves to neither (404).
- [ ] Request spec: the revalidation webhook rejects a request without the correct shared secret.

## Phase 26 (revision) — Next.js Public Event Site

Builds on the existing Phase 26 checklist in `implementation_3.md`. What this doc adds/changes:

- [ ] Restore or recreate `frontend/` — confirm with the user first whether `20c675c`'s deletion
  was intentional (this doc's own earlier flag); if not, `git show 9dc480f -- frontend` has the
  original scaffold.
- [ ] Domain-resolution middleware calls Phase 25's `domain_resolution` endpoint (not a
  reimplementation of `Hosting::Resolver`'s logic in TypeScript) — short-TTL in-memory/edge cache
  (e.g. 60s) so this doesn't add a round-trip per request.
- [ ] Client-credentials token fetch/refresh — server-only (route handlers/server actions), per
  this doc's BFF description; never shipped to the browser bundle.
- [ ] Event page: `fetch(eventShowUrl, { next: { tags: [`event:${slug}`], revalidate: 300 } })`,
  rendered in a **Server Component**. Split `content_html` on the `{{register_form}}` sentinel
  constant (shared/duplicated from Phase 25.5's Ruby constant — keep the two in sync, e.g. via a
  small generated/shared constants file or just a code comment cross-referencing both sides) and
  render three pieces in order: first HTML half (`dangerouslySetInnerHTML`), `<RegistrationForm />`
  (Client Component), second HTML half.
- [ ] `<RegistrationForm />`: renders from the event-show response's `registration_schema` (passed
  down as a prop from the Server Component that already fetched it — no second fetch of the same
  data just to hand it to the form). Respects existing dedupe/uniqueness rules
  (`RegistrationForm::UNIQUENESS_FIELDS`) and capacity/waitlist behavior — no new rules invented
  client-side, this component is a renderer for rules Rails already enforces server-side.
  Basic accessibility pass here specifically (existing Phase 26 DoD item).
- [ ] **RTK Query for the registration form's data layer** (confirmed): a small Redux store scoped
  to the registration island only (not the whole app — most of the page is plain server-rendered
  content with nothing to put in a client store), created via `createApi`/`fetchBaseQuery`, one
  `registerParticipant` mutation endpoint. Two things this must get right:
  - **`baseUrl` points at a Next.js-hosted route handler** (e.g. `/api/register`), never at Rails'
    OAuth-protected endpoint directly — the browser must keep going through the BFF exactly as
    everywhere else in this design; that Next.js route handler is what actually holds the
    client-credentials token server-side and forwards the call to Rails' register-participant
    endpoint. Pointing RTK Query straight at Rails from the browser would both break the BFF
    invariant and require shipping a bearer token into client JS — don't do that.
  - **Scope it to the mutation, not the initial page data** — `content_html` and
    `registration_schema` stay on the Server Component's plain `fetch` + Next cache-tag path
    already described above; don't also wire an RTK Query `useQuery` to refetch the same payload
    client-side; that's a second, competing cache for data the page already has server-rendered.
  - RTK Query's built-in `isLoading`/`isError`/`isSuccess` states drive the form's submit button
    and surface Rails' own validation errors (duplicate registration, sold-out category → waitlist
    routing) directly from the mutation's error payload — no separate hand-rolled fetch/state
    juggling.
  - `invalidatesTags`/manual re-fetch on a successful submit can drive an optimistic client-side
    bump to a displayed seat count as an immediate-feedback nicety; the real-time ticker below
    stays the authoritative live number via Action Cable regardless, RTK Query isn't a
    replacement for that push channel, only for the request/response mutation lifecycle.
- [ ] `generateMetadata`: sourced from the event-show response's plain structured fields (name,
  description, banner), not parsed out of `content_html`.
- [ ] `POST /api/register` route handler: RTK Query's `baseUrl` target — holds/refreshes the
  client-credentials token server-side (same token logic the event-page fetch already uses),
  forwards the request body to Rails' register-participant endpoint, passes its response/status
  straight back. Thin proxy, no business logic of its own.
- [ ] `POST /api/revalidate` route handler: verifies Phase 25's shared secret, calls
  `revalidateTag(`event:${slug}`)`.
- [ ] Public live "seats remaining" ticker: `@rails/actioncable` subscription to
  `PublicEventLiveChannel`, same sentinel-split technique if your team wants it embedded inline in
  the custom template rather than in a fixed page slot.
- [ ] `TenantDomain` custom-domain flow made real end-to-end: admin console form to add a domain →
  `TenantDomain(kind: :custom)` row + DNS target shown → background job polls DNS → `verified_at`
  set → Caddy on-demand TLS asks Rails to confirm verification before issuing a cert (both apex and
  subdomain-shaped domains handled identically, per Phase 25's `domain_resolution` above).

### Definition of Done (additive to existing Phase 26 DoD)
- [ ] E2E spec: a template-driven event page renders the hand-authored HTML correctly with the
  registration form appearing exactly where the sentinel was placed in the source template.
- [ ] E2E spec: editing a shared `EventPageTemplate` and hitting the revalidation webhook updates
  the live public page within the test's own polling window, without a full redeploy.
- [ ] E2E spec: the same event resolves identically on the shared subdomain+slug path and on a
  mock **subdomain-shaped** custom domain (e.g. `events.mock-tenant.test`), not just an apex one.
- [ ] Security spec/manual check: an organizer-entered `<script>` in the event description (Phase
  25.5's own sanitization) never executes when the page is loaded in a real browser — the one test
  that actually proves the `dangerouslySetInnerHTML` boundary holds, not just that the Ruby-side
  sanitizer runs.
- [ ] E2E spec: submitting via the RTK Query mutation creates a real `Participant`, visible in the
  admin console — same assertion the existing Phase 26 DoD already has, now specifically exercising
  the RTK Query path rather than a generic form submit.
- [ ] E2E spec: a duplicate/sold-out registration attempt surfaces Rails' actual validation error
  in the UI via the mutation's error state, not a generic/swallowed failure.
- [ ] Manual check: confirm no OAuth token or secret is ever visible in the browser's network tab
  — every request the browser makes goes to `/api/register` (this app's own origin), never
  directly to Rails.

## Suggested build order

1. Phase 25.5 (template library + `EventHtmlParser`) — pure Rails, testable via request specs with
   no frontend dependency at all, same reasoning the existing Phase 25 doc already gives for why
   Phase 25 comes before Phase 26.
2. Phase 25 revision (API surface + `domain_resolution` + revalidation contract) — still pure
   Rails/`curl`-testable.
3. Decide the `frontend/` restoration question (this doc's open question #1) — blocks Phase 26
   specifically, nothing before it.
4. Phase 26 revision (Next.js) — the only phase that needs a second runtime at all.
5. Caddy/infra wiring for custom domains — can happen in parallel with (4) once Phase 25's
   `domain_resolution` endpoint exists to point it at.
