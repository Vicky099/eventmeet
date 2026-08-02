# Event Page Templates — Agency-Level Assignment (Plan)

**Status: all 7 stages shipped and verified** (full RSpec suite — 973 examples — Rubocop, and
Brakeman all clean; the whole feature confirmed live end-to-end across the real Rails + Next.js
stack — see Stage 7's own notes for the walkthrough and the two real bugs it caught).

Written in response to two asks together:

1. A new set of 5 hand-designed landing-page templates (vendored at
   `/Users/vikrampanmand/Documents/workspace/eventics/index.html` … `index-5.html`) need to become
   selectable public event-page designs, rendered by the Next.js public site.
2. The existing per-event "Event Page" editor
   (`admin/events/:event_id/event_page/edit`, [[Admin::EventPagesController]]) lives on the
   **tenant** Admin Console today. That's being moved to the **Agency** Console — a tenant's own
   event_admin should no longer be able to touch this at all, only the agency that owns the tenant.

This doc follows this repo's own planning convention (`doc/public_event_site_options.md`,
`doc/implementation_3.md`): Confirmed decisions, phased checklist, Definition of Done, then
remaining open questions. Nothing here has been built yet.

## Confirmed decisions

1. **Control moves from tenant Admin Console to Agency Console, full stop.** The nav item, the
   controller, and the underlying edit permission all move — an event's own tenant admin loses
   the ability to touch this page entirely. This is the direct fix for "having this at tenant
   level might mess up by mistake."
2. **Six choices, not five** — Template 1 through Template 5 (the eventics designs), plus a
   6th **"Custom HTML"** option that is the *existing* raw-HTML-paste editor
   (`EventPage#html`, [[Admin::EventPagesController]]'s current `edit`/`update` behavior),
   carried over unchanged in behavior — just relocated to the Agency Console and now editable only
   by an agency admin, not a tenant's event_admin. Nothing about the no-sanitization trust
   decision changes (`doc/public_event_site_options.md` Confirmed decision #2) — it now just
   applies to a smaller, more trusted set of editors.
3. **v1 data binding is intentionally shallow.** As originally scoped, Templates 1–5 were meant to
   bind name/title, description, start/end date-time, address/meeting link, banner image, and the
   Register button. **As actually shipped (Stage 5), only the hero title and the Register link are
   bound** — see Stage 5's own "Scope actually shipped" note for why the rest narrowed further
   during implementation, not silently. The Register control itself also changed from the
   original plan: it links to a real, separate register route/page (`app/events/.../register/
   page.tsx`), not a modal — a direct user correction mid-build, see the "Mid-stage architecture
   change" note under Stage 5. Every other section a template ships with today — speakers,
   schedule/agenda, sponsors, gallery, FAQ, pricing/ticket cards, testimonials, blog/news —
   renders with that template's own built-in demo content unchanged, for v1. Richer binding (real
   `Speaker`/`Schedule`/`TicketCategory` data, both already modeled — see "Deferred / fast-follow"
   below) is an explicit later phase, not
   silently dropped.
4. **Live reference, not a copy** — same shape `doc/public_event_site_options.md` already
   recommended for a template-library design: an event stores *which* template it's assigned
   (`template_key`), not a cloned copy of that template's markup. A future edit to how "Template 3"
   renders (a shared Next.js component) applies to every event using it immediately.
5. **No draft/publish workflow for the assignment itself** (mirrors the existing EventPage
   decision) — changing an event's template takes effect immediately, doesn't touch the event's
   own `published_at`/`CONTENT_ATTRIBUTES`. The event's own draft/published gate (`Event#published?`)
   still decides whether *any* custom page shows at all — an unpublished event always shows
   Next.js's own default page regardless of template assignment, unchanged from today.
6. **Eventics license confirmed clear to use** — no attribution/legal follow-up blocking the port
   work below.
7. **Thumbnails are real screenshots**, not a plain text list — one per template, captured once
   during Phase B build and shipped as static images the Agency Console dropdown renders next to
   each option.
8. **Both phases ship together, in one release** — the sequence below is a single build, not a
   staged rollout; "Phase A"/"Phase B" labels from the first draft of this doc are dropped in favor
   of one ordered implementation sequence (below).

## Current state (what exists today)

- `EventPage` — `has_one` off `Event`, one `html` column, `TenantScoped`. Edited at
  `admin/events/:event_id/event_page/edit` ([[Admin::EventPagesController]]), an event-workspace
  nav item ("Event Page", `admin_helper.rb#event_nav_items`) any tenant event_admin can reach.
- `Api::V1::Public::EventsController#show` returns `content_html: event.event_page&.html` among
  other fields; Next.js's `PublicEventPage` (`frontend/src/components/public-event-page.tsx`)
  renders it verbatim via `dangerouslySetInnerHTML` when present, else falls back to
  `DefaultEventPage`.
- Agency Console (`AgencyConsole::*`, `agency/*` routes) today only has: Dashboard, a paginated
  Tenants list (`accounts#index`, no `#show`), New Tenant, Invoices. It has **no existing way to
  drill into one tenant's events at all** — an agency admin who needs to touch a specific event
  today uses `accounts#switch` to SSO into that tenant's own Admin Console subdomain instead.
  This plan has to add that drill-down, since the Event Page screen can't move to Agency Console
  without somewhere to reach a specific event from.
- The eventics package: 5 full landing pages (`index.html`…`index-5.html`, ~2,000-2,600 lines
  each — HTTrack-mirrored static HTML/Tailwind/jQuery, not componentized), each with its own hero,
  about, countdown, features, schedule, speakers, pricing, sponsors, gallery, FAQ, and footer
  sections, sharing one `assets/` tree (css/js/img/vendor) plus a compiled `src/output.css`.
- `Speaker` and `Schedule` (belongs_to `:event`, `:speaker`, optional `:session`) are already real,
  already-populated Rails models — not built by this plan, just available for the fast-follow
  richer-binding phase.

## Target end state

- Agency Console gains: a way to open a specific tenant's specific event, and on it, one "Event
  Page" screen with a template dropdown (Template 1–5, Custom HTML) — Custom HTML reveals the
  existing raw-HTML textarea/preview; picking a numbered template shows a lightweight preview
  (static screenshot or iframe) instead.
- Tenant Admin Console's event-workspace nav loses the "Event Page" item and route entirely — a
  tenant admin has no path to this screen anymore, by URL or by nav.
- `EventPage` gains a `template_key` column (nullable integer-backed enum: `template_1` … `template_5`,
  or `nil` meaning "Custom HTML" / whatever `html` holds — see Data model below for the exact
  nil-handling rule).
- Next.js ships 5 new template components under `frontend/src/components/templates/`, a small
  registry mapping `template_key → Component`, and `PublicEventPage` picks: assigned template
  component (if `template_key` set) → raw `content_html` (if `html` set, i.e. "Custom HTML") →
  `DefaultEventPage` (neither set) — in that priority order.
- Public API (`Api::V1::Public::EventsController#show`) returns `template_key` alongside the
  existing `content_html`, so Next.js knows which branch to take without guessing from
  `content_html`'s presence alone.

## Data model

`EventPage` (existing table) gets one new column — **done, see Stage 1 below**:

```
add_column :event_pages, :template_key, :integer
```

- `template_key` — one of `template_1`..`template_5`, or `nil`. Modeled as a plain Rails `enum`
  on the model, integer-backed (matches how `Agency#billing_cycle`/`Account#status`/`Event#mode`
  are already done in this codebase — confirmed by checking, not assumed) so the dropdown and any
  future template addition (`template_6`) is a one-line change, not a migration.
- **Resolution rule, since both `template_key` and `html` can theoretically be present at once**:
  `template_key` wins whenever it's set. **Decided and built in Stage 3**: setting a numbered
  template from the dropdown clears `html` server-side (`EventPage#clear_html_when_template_selected`,
  a `before_validation` callback, not controller-level) — one-directional only, so switching back
  to "Custom HTML" afterward starts from a blank textarea rather than reviving whatever was cleared.
  Never store both as simultaneously "active" — the UI's own dropdown already prevents the user
  from thinking otherwise, this is just codifying it server-side too so the API payload can't be
  ambiguous.
- No new table — this is exactly the "per-event, rarely-queried-with-parent, one row" shape
  `EventPage` already exists for ([[feedback-dedicated-tables-for-blobs]]), a new column on it is
  consistent with that, not a violation of it (the violation that memory warns about is adding
  this kind of field onto `Event`/`Account` directly, not onto `EventPage` itself).
- Existing `EventPage` rows with `html` present and no migration needed for them — they're already
  correctly modeled as `template_key: nil` (Custom HTML), no backfill required.

## Backend changes

### Routes

- **Remove**: `resource :event_page, controller: "admin/event_pages", only: [:edit, :update]`
  from the tenant `admin/events/:id` nested block (`config/routes.rb`).
- **Add**, inside the existing `scope path: "agency", as: "agency"` block:
  ```ruby
  resources :accounts, controller: "agency_console/accounts", only: [:index, :new, :create] do
    member { post :switch; patch :suspend; patch :reinstate }
    # New: an agency's own read-only drill-down into one tenant's events, existing only to reach
    # the Event Page screen below — not a general tenant event-management surface (event
    # creation/editing/participants/etc. all stay on the tenant's own Admin Console, reached via
    # the existing #switch SSO handoff).
    resources :events, controller: "agency_console/events", only: [:index] do
      resource :event_page, controller: "agency_console/event_pages", only: [:edit, :update]
    end
  end
  ```

### Controllers

- **Delete** `Admin::EventPagesController` and its view (`app/views/admin/event_pages/edit.html.erb`).
- **New** `AgencyConsole::EventsController#index` — same "one tenant's events" read-only list
  `AgencyConsole::AccountsController#index` already builds counts for
  (`Event.unscoped_across_tenants { Current.agency.accounts.find(...).events... }` — the
  authorization boundary is `Current.agency.accounts.find(params[:account_id])`, identical pattern
  to `AccountsController#switch`/`#suspend`). Each row links to that event's Event Page screen.
- **New** `AgencyConsole::EventPagesController#edit`/`#update` — near-identical body to the
  deleted `Admin::EventPagesController` (find-or-initialize on `#edit`, permit `:html` and
  `:template_key` on `#update`), just resolving the event through
  `Current.agency.accounts.find(params[:account_id]).events.friendly.find(params[:event_id])`
  instead of `EventScoped`'s tenant-session-based lookup (agency console has no `Current.account`
  at all — `AgencyConsole::BaseController#require_agency_context!` guarantees that).
- `EventPage#update` keeps its existing `after_commit :notify_public_site_change` — unchanged,
  still fires the Next.js revalidation webhook regardless of which console saved it.

### Nav

- `admin_helper.rb#event_nav_items` — remove the "Event Page" entry (line ~44).
- `agency_helper.rb#agency_nav_items` — no direct top-level entry (there's no single "the event"
  at the agency's dashboard level); the path is Tenants → (a tenant row, new) → Events → Event
  Page, mirroring how `#switch` already works today, not a new sidebar item.

### Public API

- `Api::V1::Public::EventsController#event_show_json` — add `template_key:
  event.event_page&.template_key`.

## Next.js changes

- `frontend/src/components/templates/` — one component per template
  (`Template1EventPage.tsx` … `Template5EventPage.tsx`), each accepting the same
  `{ event, eventSlug, accountSlug }` props `PublicEventPage` already threads through today.
  **As shipped (Stage 5, narrower than planned here — see that stage's own notes)**: hero title
  bound to `event.name`; the template's own "Register Now"/"Buy Ticket" buttons link directly to
  a real register route (`app/events/.../register/page.tsx`, itself reusing that same template's
  header/footer — a mid-build correction, registration is a page now, not a modal); every other
  section (description/dates/address/banner/speakers/schedule/pricing/sponsors/gallery/FAQ) left
  as the template's own static demo
  markup for v1, per Confirmed decision #3.
- `frontend/src/components/templates/registry.ts` — `{ template_1: Template1EventPage, ...,
  template_5: Template5EventPage }` lookup.
- `frontend/src/components/public-event-page.tsx` — branch order becomes: `event.template_key`
  present → registry component; else `event.content_html` present → existing
  `dangerouslySetInnerHTML` path (Custom HTML); else `DefaultEventPage`.
- Static assets (`assets/css/js/img/vendor`, `src/output.css`) copied into
  `frontend/public/templates/{1..5}/` (namespaced per template — the 5 source pages share one
  flat `assets/` folder today, but each template's CSS/JS needs to load independently once they're
  separate routes/components, so this is a real "copy and namespace," not a straight file move)
  and referenced with root-relative paths from each template component; `<script>`-driven
  behavior (countdown timers, slick-style sliders, mobile menu toggle) ported to `useEffect`
  hooks or left as vendored scripts loaded via `next/script`, whichever a given section's vendor
  library tolerates — decided per-section during implementation, not a single blanket approach.
- `lib/server/rails.ts`'s `PublicEvent` type gains `template_key: string | null`.

## Migration / backfill

- Every existing `EventPage` row keeps working with zero data migration — `template_key` defaults
  `nil`, which is exactly "Custom HTML," exactly today's current behavior for every event that
  already has one.
- No tenant admin currently has any in-progress edit to lose — this is a permissions/location
  move, not a data change, so there's no cutover window to coordinate beyond a normal deploy.

## Implementation steps (single sequence, both phases ship together)

Ordered so each step only depends on steps already checked off above it. Grouped into stages for
readability only — this is one release, not a staged rollout (Confirmed decision #8).

### Stage 1 — Data model ✅ done
- [x] Migration: `add_column :event_pages, :template_key, :integer` (nullable, no default —
      `nil` means "Custom HTML," matches every existing row unchanged). →
      `db/migrate/20260802120000_add_template_key_to_event_pages.rb`, applied to both `development`
      and `test` databases, `db/structure.sql` regenerated.
- [x] `EventPage` model: `enum :template_key, { template_1: 0, ..., template_5: 4 }` — an
      **integer**-backed enum, not a string one, matching every other enum in this codebase
      (`Agency#billing_cycle`, `Account#status`, `Event#mode`, etc. are all integer-backed; the
      first draft of this plan considered a string column, revised once the actual codebase idiom
      was checked). `nil` stays legal (no `validates :template_key, presence: true`) — that's the
      whole point, it's what every pre-existing row already has. → `app/models/event_page.rb`.
      `event_page_params` wiring deferred to Stage 3 deliberately — `Admin::EventPagesController`
      (today's only controller touching this) gets deleted in that same stage, so updating its
      params now would be immediately-discarded work.
- [x] Model spec: `template_key` defaults to `nil`, accepts each of the 5 enum values, raises on an
      unknown value (standard Rails enum behavior — confirms the enum is wired, not just the
      column). Mutual-exclusivity-with-`html` enforcement intentionally **not** tested at this
      layer — that rule belongs to the controller (Stage 3), not the model, per the plan's own
      resolution-rule note. → `spec/models/event_page_spec.rb`. **6 examples, 0 failures**;
      Rubocop clean on all 3 touched files.

### Stage 2 — Agency Console: reach a tenant's event ✅ done
- [x] Routes (`config/routes.rb`, inside `scope path: "agency", as: "agency"`): nested
      `resources :events, controller: "agency_console/events", only: [:index] do resource
      :event_page, controller: "agency_console/event_pages", only: [:edit, :update] end` under the
      existing `accounts` resources block. The `:event_page` route is live now even though
      `AgencyConsole::EventPagesController` doesn't exist until Stage 3 — Rails routes don't
      require the controller constant to exist at boot, only at request-dispatch time (confirmed
      via `bin/rails routes -g agency_console`, which lists it correctly).
- [x] `AgencyConsole::EventsController#index` — `Current.agency.accounts.find(params[:account_id])`
      for the authorization boundary (same pattern as `AccountsController#switch`), then
      `Event.unscoped_across_tenants { @account.events.order(starts_at: :desc).includes(:event_page).to_a }`.
      **Correction found while building this** (not in the original plan text): `EventPage` is its
      own `TenantScoped` model, so reading `event.event_page` in the view would raise
      `TenantScoped::MissingTenantContextError` on its own — *except* `unscoped_across_tenants`
      sets `Current.platform_request` for its **entire block**, not just for the model it was
      called on, so any other `TenantScoped` query executed inside that same block (here, the
      `.includes(:event_page)` preload) is already covered without a second explicit
      `EventPage.unscoped_across_tenants` call. `.to_a` still has to run *inside* the block —
      returning a bare relation/`CollectionProxy` for the view to enumerate later would re-raise,
      per `AgencyConsole::DashboardController#index`'s own pre-existing comment on this exact
      trap. → `app/controllers/agency_console/events_controller.rb`.
- [x] View: `app/views/agency_console/events/index.html.erb` — table (name, dates, current
      template/Custom-HTML/"Not set" badge, "Event Page" link), `shared/_page_header` +
      `shared/_empty_state` partials. One build hiccup: `render layout: "shared/page_header",
      locals: {...}` **requires a block** even with nothing in it (confirmed by grepping every
      other caller in the codebase — none omit the `do...end`, and omitting it raises
      `ArgumentError` at render time, not a silent no-op).
- [x] `AgencyConsole::AccountsController`'s `index` view — added an "Events" button per tenant row
      linking to `agency_account_events_path(account)` (the actual generated route helper name,
      nested under `accounts` — not the flat `agency_events_path` the first draft of this plan
      guessed before the routes existed to check against).
- [x] Request spec: `spec/requests/agency_console_events_spec.rb` — signed-out redirect, empty
      state, per-event badge state (none/custom/template, isolated per event), and a 404 for an
      account belonging to a different agency. **11 examples, 0 failures** (this file + the
      pre-existing tenant-list spec, re-run together to confirm no regression). Full
      `spec/requests/agency*` + `spec/requests/admin_events*` suite: **80 examples, 0 failures**.
      Rubocop clean on the 2 new `.rb` files (views are ERB, not linted by Rubocop in this repo —
      confirmed by checking `.rubocop.yml` and every existing `.html.erb` file's own lint history).
      Brakeman: 0 warnings.

### Stage 3 — Agency Console: the Event Page screen itself ✅ done
- [x] `AgencyConsole::EventPagesController#edit`/`#update` — whole action bodies wrapped in
      `Event.unscoped_across_tenants { ... }` (not just the find), since `EventPage#update` itself
      runs a query too (`validates :event_id, uniqueness: true`) that would otherwise also raise.
      `#update` permits `:html, :template_key`. **Second correction found while building this, not
      in the original plan text**: `event.build_event_page` alone left `account_id` nil and failed
      `belongs_to :account`'s presence validation — the tenant-session flow this replaces got
      `account_id` prefilled for free (ActiveRecord derives a new record's default attributes from
      an active `where(account_id: Current.account.id)` default_scope), but that trick only fires
      on `TenantScoped`'s `Current.account` branch; this controller runs on the
      `Current.platform_request` branch (`unscoped_across_tenants`, no `where` clause to borrow a
      default from). Fixed with an explicit `event.build_event_page(account: @account)`. →
      `app/controllers/agency_console/event_pages_controller.rb`.
- [x] Mutual-exclusivity rule implemented as an `EventPage` model callback
      (`before_validation :clear_html_when_template_selected` — blanks `html` whenever
      `template_key` is present), not in the controller — one-directional only, per the plan's own
      note: selecting "Custom HTML" (`template_key` back to `nil`) does *not* try to resurrect
      previously-cleared `html`, it just starts blank. Confirmed the enum's blank-string handling
      needed no extra controller-side normalization: `EventPage#template_key = ""` (what the
      dropdown's blank option submits) casts to `nil` automatically; an unrecognized value still
      raises `ArgumentError`, both confirmed live via `bin/rails runner` before writing the
      controller. → `app/models/event_page.rb`.
- [x] View: `app/views/agency_console/event_pages/edit.html.erb` — a `<select>` for Template 1–5 +
      Custom HTML (literal dropdown, matching the original ask's own wording), the existing
      raw-HTML textarea + live Stimulus preview (`event_page_preview_controller.js` — reused
      as-is, unmodified; it's a generic file-based Stimulus controller already registered
      app-wide, not Admin-console-specific, confirmed by checking `shared/_head.html.erb` loads
      one shared `application.js` importmap for every console), shown only when "Custom HTML" (the
      select's blank option) is chosen. CSS `:has()`-driven show/hide
      (`app/assets/stylesheets/application.css`), same technique
      `admin/events/_basic_info_step`'s seat-limit block already uses — **with one placement
      correction**: the `.event-page-template-block` class had to go on the whole row, not just
      the `<form>`, since the Preview column sits as a *sibling* of the form (outside it), and
      `:has()` can only reach descendants of the element carrying the class.
- [x] Template thumbnails: same `:has()` technique, one rule per template value, each showing a
      `.template-thumbnail[data-template="template_n"]` only when that option is selected. Real
      screenshots are Stage 6's job, but the `image_tag` calls needed *some* file to resolve during
      Stage 3 — Propshaft raises `MissingAssetError` for a referenced-but-absent asset (confirmed
      live; it does not degrade to a broken `<img>` tag) — so 5 placeholder 1×1 PNGs were added now
      at the exact path Stage 6 already plans to overwrite:
      `app/assets/images/event_page_templates/template_{1..5}.png`.
- [x] Deleted `Admin::EventPagesController`, `app/views/admin/event_pages/edit.html.erb`, the
      `resource :event_page` route under tenant `admin/events`, and the "Event Page" entry in
      `admin_helper.rb#event_nav_items`. Also updated: `Event#event_page`'s own association
      comment (referenced the deleted controller by name), and
      `spec/requests/admin_events_spec.rb`'s event-workspace-nav spec (asserted the now-removed nav
      entry/route existed — replaced with an assertion that neither is present anymore, checking
      the route helper itself raises `NoMethodError`).
- [x] Request specs: `spec/requests/agency_console_event_pages_spec.rb` (new, replaces the deleted
      `spec/requests/admin_event_pages_spec.rb`, porting its create/update/verbatim-storage/
      no-draft-workflow coverage plus new cases: assigning a template clears prior Custom HTML,
      selecting Custom HTML clears a prior template assignment, cross-agency 404 on both actions,
      and the literal old tenant URL — `GET /admin/events/:id/event_page/edit` — 404ing directly,
      not just its route-helper method disappearing). **64 examples, 0 failures** across this file
      + Stage 2's spec + the updated `admin_events_spec.rb` + `event_page_spec.rb`. Full
      `spec/requests` + `spec/models` suite: **727 examples, 0 failures**. Rubocop clean on all 7
      touched/added `.rb` files. Brakeman: 0 warnings.
- [ ] Manual QA (deferred, not yet performed): every existing event with a Custom-HTML page still
      renders unchanged on the public site immediately after this stage. Not done live in a
      browser this session — the request specs above cover the same ground at the HTTP-response
      level (verbatim `html` storage, unchanged `published_at`/status, correct redirect), but a
      real Next.js-rendered page wasn't opened to confirm visually. Flagging rather than claiming
      done.

### Stage 4 — Public API ✅ done
- [x] `Api::V1::Public::EventsController#event_show_json` — added `template_key:
      event.event_page&.template_key`, one of `"template_1"`..`"template_5"` or `nil` (Custom
      HTML — Next.js falls back to `content_html`, unchanged priority). →
      `app/controllers/api/v1/public/events_controller.rb`.
- [x] Confirmed live, not just assumed: no new draft-state branching was needed. The controller
      already reported `content_html` verbatim regardless of `published` (Next.js's own
      `DefaultEventPage` gate is what actually withholds it, keyed off the `published` field
      alone) — `template_key` follows the exact same shape, added a request spec proving a
      still-draft event's real `template_key` comes through unchanged (`published: false,
      template_key: "template_1"` in the same response), matching how `content_html` already
      behaved before this field existed.
- [x] Request specs added to `spec/requests/api_v1_public_events_spec.rb`: a numbered-template
      event reports that key and empty `content_html` (proving `EventPage#clear_html_when_template_selected`'s
      effect is visible over the public API too, not just in the admin/agency UI); a Custom-HTML
      event reports `template_key: nil`; a draft event with no `EventPage` row reports both fields
      nil; a draft event *with* a template assigned still reports it. **8 examples, 0 failures**
      (this file alone). Full `spec/requests` + `spec/models` suite: **729 examples, 0 failures**.
      Rubocop clean on both touched files. Brakeman: 0 warnings.

### Stage 5 — Next.js: port the 5 templates ✅ done (scope narrowed from the original text below — see notes)

**Scope actually shipped, and why it's narrower than first drafted:** the original bullet list
below committed to binding hero/description/dates/address/banner/Register across all 5 templates.
Once the actual 5 source files were inspected in detail (not just skimmed), that turned out to be
materially more per-template bespoke work than a first pass justified — each of the 5 is a
genuinely different hand-built layout (not 5 skins of one shared structure), so "bind the address"
would have meant 5 separate investigations into 5 different, non-uniform places an address even
*could* go, several of which don't have an obvious one at all. **Actually bound, verified across
all 5**: hero title (`event.name`) and the Register CTA link. Everything else — description,
dates, address/meeting_link, banner image, speakers/schedule/pricing/sponsors/gallery/FAQ — stays
each template's own static demo content, unchanged, exactly as Confirmed decision #3 already
allowed ("decorative sections static... richer binding... an explicit later phase, not silently
dropped"). This is that later phase not yet started, tracked in "Deferred / fast-follow" below.

- [x] Copied `assets/{css,js,img,vendor}` + `src/output.css` from
      `/Users/vikrampanmand/Documents/workspace/eventics/` into
      `frontend/public/templates/assets/...` — **one shared copy, not 5 namespaced ones**: the
      first draft assumed each template had its own asset folder; checking the actual source
      package found all 5 demo pages share one flat 17MB/281-file `assets/` tree, so 5 copies
      would have meant ~85MB for near-total duplication. `src/output.css` (pre-compiled Tailwind
      output) copied alongside as `assets/css/output.css`.
- [x] `frontend/src/lib/server/rails.ts` — `template_key: string | null` added to `PublicEvent`.
- [x] Built via a Node extraction script (`extract_template.js` + one small per-template driver
      script each, not committed to the repo — regenerate from
      `/Users/vikrampanmand/Documents/workspace/eventics/index*.html` if the source package ever
      changes), not by hand-converting ~11,000 lines of legacy HTML to JSX: each source page's
      `<body>` is extracted verbatim, asset paths rewritten to `/templates/assets/...`, the hero
      `<h1>`'s inner content replaced with an `__EVENT_NAME__` token, and its own Register-style
      CTA's `href` replaced with an `__REGISTER_HREF__` token — then stored as a plain
      `JSON.stringify`'d string constant (`frontend/src/components/templates/raw/template{1..5}.raw.ts`).
      `Template1EventPage.tsx`..`Template5EventPage.tsx` each substitute both tokens at render time
      (`substituteTemplateTokens`, `template-shared.tsx`) and render the result via
      `dangerouslySetInnerHTML`, plus that template's own 6 stylesheets and vendor scripts
      (`next/script`, `afterInteractive`).
  - **CTA locations genuinely differ per template** (confirmed by inspection, not assumed
    uniform): templates 1/2/4 have 3 identical hero-slide CTAs (bulk string replace, exact class
    match verified unique via `grep -c` before touching anything); template 3 reuses its own
    `et-3-btn` class 24× elsewhere on the page for unrelated links, so only the one instance
    immediately following the (unique) hero `<h1>` text got rewired, located by string position,
    not a blind class match; template 5's banner/hero has no CTA of its own at all (image/vector
    layout only) — its register link sits on the Countdown section's "Buy Ticket" button instead.
  - **Real bug found and fixed**: source files are CRLF throughout; embedding that verbatim
    produced a genuine SSR/hydration mismatch (`dangerouslySetInnerHTML`'s server string carried
    `\r\n`, the client-side comparison saw `\n` — confirmed live in a browser, not theoretical).
    Fixed by normalizing to `\n` at extraction time (`extractBody`).
  - **Tailwind v4's own content scanner picked up the raw HTML string files as class-candidate
    source**, generating broken `url(../assets/img/...)` rules into the app's own `globals.css`
    and failing the production build — confirmed live. Fixed with `@source not
    "../components/templates/raw/**/*.ts";` in `globals.css`. Same root cause required excluding
    `src/components/templates/raw/**` and the newly-vendored `public/templates/**` (minified
    third-party JS) from ESLint's scope too (`eslint.config.mjs`) — both produced hundreds of
    spurious errors/warnings trying to lint generated data/vendored libraries as if they were
    hand-written app source.
- [x] `frontend/src/components/templates/registry.ts` — `EVENT_PAGE_TEMPLATE_REGISTRY` (component
      map) and `EVENT_PAGE_TEMPLATE_RAW_HTML` (raw-string map, added for the register-page pivot
      below).
- [x] `frontend/src/components/public-event-page.tsx` — branch order implemented exactly as
      planned: `event.template_key` set → registry component; else `event.content_html` set →
      existing `dangerouslySetInnerHTML` path; else `DefaultEventPage`.
- [x] `next build`/`tsc --noEmit`/`eslint` all clean. Manual browser verification done via a
      temporary, session-only preview route (rendered each `Template*EventPage` against a fake
      `PublicEvent`, no Rails/OAuth stack needed to check the port itself — deleted before this
      stage was marked done, not part of the shipped feature): Template 1 and Template 3 both
      confirmed live — correct hero text substitution, correct fonts/colors/layout from the
      vendored CSS, working header nav, and (after the registration pivot below) a working
      register link navigating to the real route. Templates 2/4/5 share the exact same
      substitution mechanism already proven live twice (bulk-replace path via Template 1, special-
      cased single-anchor path via Template 3) and were verified only via the extraction script's
      own occurrence-count assertions (Stage 5's own build output), **not individually
      click-tested in a browser this session** — flagged, not hidden.
  - **Known, deliberately unverified risk carried forward**: `TemplateVendorScripts` loads Lenis/
    GSAP/ScrollTrigger/SplitType/Swiper/Splide via `next/script`, but full visual parity with the
    original static template (scroll-linked animations, slider re-init) was not verified in a
    browser. One hydration-mismatch dev-overlay warning was observed on Template 1/3's preview
    (on the `<html>` element's font className, not on the templates' own content) that could not
    be conclusively isolated in this session's time — the console error's own stack trace
    originates from the sandboxed browser's React DevTools extension script, and the app's
    homepage (same root layout) showed no such warning, so it is most likely extension noise, not
    application code; recorded here rather than either dismissed or claimed fixed.

**Mid-stage architecture change (direct user instruction, supersedes the original design):**
"Registration should be a separate route and form, not in modal... obey template UI format."
- `registration-modal.tsx` **deleted** — the floating-button-opens-a-modal design (and the
  `data-register-trigger` + `document`-level click-delegation mechanism originally built to let a
  template's native CTA open that modal) is gone entirely, not layered alongside the new design.
- `RegistrationForm` extracted into its own file (`registration-form.tsx`), unchanged internally —
  only its container changed, same "the form itself never changes, only what wraps it" pattern
  this doc's own history already established once before (public_event_site_options.md's
  modal-vs-sentinel-interleave discussion, and again here).
- New real routes: `app/events/[slug]/register/page.tsx` and
  `app/events/[slug]/[eventSlug]/register/page.tsx`, mirroring the existing show-page route pair
  exactly (same domain-resolution/fetch pattern, same `notFound()`/`redirect()`-to-show-page gate
  for an unpublished event). `frontend/src/lib/event-paths.ts` (`eventShowPath`/
  `eventRegisterPath`) centralizes the URL-shape formula so the show page, the templates, the
  register routes, and the floating CTA can't drift apart on it.
- **"Obey template UI format"**: a numbered-template event's register page
  (`TemplateRegistrationPage.tsx`) reuses that *same* template's own `<header>`/`<footer>` —
  sliced out of the already-extracted raw HTML at render time (`extractSection`, confirmed live
  that every one of the 5 source pages has exactly one of each) — with the real
  `RegistrationForm` sandwiched between them, rather than dropping to the generic centered layout.
  A Custom-HTML or no-template event still gets that generic layout (`registration-page.tsx`
  directly), since there's no template chrome to borrow.
- `__REGISTER_HREF__` (all 5 raw HTML modules, re-extracted with the updated build scripts) now
  substitutes a real URL (`eventRegisterPath`) instead of `#register` — the template's own native
  CTA is a plain link now, needing zero client-side JS of its own to work.
- `register-cta.tsx` (new, replaces the modal's floating button) — a plain server-renderable link
  to the register route, used by the default/Custom-HTML show-page path only (the 5 templates
  already have their own native CTA, no floating one layered on top).
- Verified live (same temporary preview route, extended with a `/register` variant): Template 1's
  register page renders that template's own logo/header/footer with the real form fields in
  between; Template 3's hero CTA correctly navigates to the real register URL. "Back to event"
  link and form submission wiring visually confirmed; a real end-to-end submission against a
  running Rails backend was **not** performed this session (no backend running during this
  browser check) — the request-level contract (`useRegisterParticipantMutation`,
  `/api/register`) is unchanged from before this pivot and was already covered by the pre-existing
  backend request specs.

### Stage 6 — Thumbnails for the Agency Console dropdown ✅ done
- [x] Captured one real screenshot per template — the actual Next.js `Template*EventPage`
      component rendered against a fake `PublicEvent` (name "Acme Product Summit 2026"), via a
      temporary session-only preview route (same pattern Stage 5 used, deleted before this stage
      was marked done). Not the original static eventics demo page — every thumbnail shows the
      real hero-title binding, not placeholder text.
  - **Real, time-consuming complication, not anticipated in the plan**: each template's hero
    title uses GSAP + SplitType for a per-character "fade/slide in" reveal animation
    (`main.js#textAnimate`), which starts every character at `opacity: 0` and animates in via an
    `IntersectionObserver` — meaning a screenshot taken immediately on page load captures the
    text mid-animation or fully invisible, not a rendering bug. Confirmed live: waiting long
    enough (empirically 10–20s depending on the template — longer for Template 3, which animates
    two separate headings) lets it finish naturally. An attempted shortcut
    (`gsap.killTweensOf`/`gsap.set` to force-complete the tween instantly) proved **unreliable** —
    racy against the tween's own per-frame updates, sometimes appearing to work and sometimes
    silently getting overwritten a frame later — so the final approach was patient waiting only,
    no forcing. This is a real, user-facing characteristic of the ported templates worth knowing
    about (a real visitor also waits through this animation on first load), not just a
    screenshot-capture inconvenience.
  - Next.js's own dev-mode indicator (`nextjs-portal`, bottom-left corner) and, once, this
    session's own "Claude is active in this tab group" browser-automation banner both had to be
    hidden/dismissed before capturing — neither is part of the real app, both would have otherwise
    been baked permanently into a shipped thumbnail image.
- [x] Saved as `app/assets/images/event_page_templates/template_{1..5}.png` (480×219, replacing
      Stage 3's placeholder 1×1 PNGs) via `sips` (no ImageMagick/PIL available in this
      environment).
- [x] **Real bug found and fixed, only visible with live Cloudinary credentials configured, which
      is why it slipped past every request spec**: Stage 3's view used `image_tag` for the
      thumbnails, but this app's `config/cloudinary.yml` sets `enhance_image_tag: true` in every
      environment, and the Cloudinary gem's `image_tag` override mangles *any* string passed to it
      — including a local Propshaft asset path — into a Cloudinary-style URL
      (`eventmeet/development/event_page_templates/template_1.png`) that 404s
      (`Propshaft::MissingAssetError`), confirmed live in a real browser against a real seeded
      event. This exact trap is already documented elsewhere in this codebase
      (`admin/events/_review_step.html.erb`'s own comment, `admin/speakers/index.html.erb`'s own
      comment) with the established fix: `tag.img` (a bare `<img>` helper, not `image_tag`) +
      `asset_path`, which sidesteps Cloudinary's monkey-patch entirely. Applied the same fix here.
      **Why the request specs never caught this**: they run in `RAILS_ENV=test`, which on this
      machine has no real `CLOUD_NAME`/`API_KEY`/`API_SECRET` configured, so the Cloudinary gem
      silently no-ops instead of mangling the path — this bug is invisible to the existing test
      suite by construction, not a gap in test *coverage* of this feature specifically. Confirmed
      this was the real explanation (not guessed) by reproducing the failure live in a `development`
      server that does have real credentials configured, then confirming the fix resolves it there.
- [x] **Second real bug found, unrelated to this feature**: hit
      `RuntimeError: Undeclared attribute type for enum 'template_key' in EventPage` when first
      loading the Agency Console live — turned out to be a **stale `bin/rails server` process left
      running from earlier in this same session**, from before Stage 1's migration/enum existed in
      that process's loaded code. Not a real defect (confirmed: the column exists correctly in the
      live `development` database, `\d event_pages` via `psql`), purely an artifact of reusing a
      long-lived local dev session — killing the stale process and starting a fresh one resolved it
      immediately. Flagged here only so a future reader doesn't mistake this for a real schema
      issue if they see it mentioned.
- [x] **Manual QA, verified live end-to-end** (not just via request specs): seeded a real
      Agency/Account/Event via `bin/rails runner`, signed into the Agency Console as that agency's
      admin in a real browser, opened Tenants → Events → Event Page, confirmed the dropdown shows
      all 6 options, selected "Template 3" and confirmed its real thumbnail rendered (with the
      CSS `:has()` show/hide correctly hiding the Custom HTML textarea/preview and every other
      template's thumbnail), saved, got the "Event page saved." flash, confirmed via
      `bin/rails runner` that `EventPage#template_key` persisted as `"template_3"` and `html` was
      correctly blanked, and confirmed the Tenants → Events list's own badge updated from
      "Not set" to "Template 3" — the exact chain of UI this stage's own checklist asked for.
      (Verifying the *public* Next.js page also renders that template for this same event would
      additionally require live OAuth/domain-resolution wiring between the two apps — out of
      scope for this stage's own QA note, already covered at the unit level by Stage 4/5's own
      specs and manual template-preview checks.)

### Stage 7 — Full-suite regression pass ✅ done
- [x] **Full** RSpec suite (not just `spec/requests`/`spec/models` as in earlier stages' own
      quicker checks) — **973 examples, 0 failures**. Rubocop across the whole app — **415 files,
      no offenses**. Brakeman — **0 security warnings**.
- [x] Re-ran the specific cross-tenant/cross-agency leak specs by name (Stages 1–4's own): tenant
      list ("404s for an account belonging to a different agency"), events list ("404s for an
      event belonging to a different agency's tenant"), event pages ("404s trying to update an
      event belonging to a different agency's tenant"), account switch ("rejects switching into a
      tenant that belongs to a different agency"), suspend ("404s trying to suspend another
      agency's own tenant"), public API ("404s for an unknown slug") — **37 examples, 0 failures**.
- [x] **Full end-to-end manual walkthrough, genuinely live** (the actual acceptance criterion for
      the whole feature) — ran the real three-process local stack for the first time this session
      (`bin/rails server` + `bin/jobs` Sidekiq + `next dev`, all three with matching
      `PUBLIC_SITE_SHARED_SECRET`/`PUBLIC_SITE_REVALIDATE_SECRET`/`PUBLIC_SITE_REVALIDATE_URL`, per
      the project's own documented local-dev requirement), seeded a real published event with a
      real ticket category and a real Doorkeeper OAuth application, then — as an agency admin,
      driving the actual public Next.js URL (`http://{tenant}.lvh.me:5173/events/{slug}`) — assigned
      **all 6 options in turn** (Template 1 through 5, then Custom HTML) and confirmed each one
      rendered correctly on the real public page, with the real event name ("QA Demo Event") bound
      into each template's hero, and confirmed the floating Register CTA/native template buttons
      both correctly reach the real register page for a real event (not the fake preview data
      Stages 5/6 used).
  - **Real bug found and fixed**: the vendored `output.css` (compiled Tailwind CSS, copied from
      the eventics package's own `src/output.css`) contains 39 hardcoded `url(../assets/img/...)`
      background-image references that were only ever correct relative to that file's *original*
      location (`{package root}/src/output.css`) — copying it into
      `frontend/public/templates/assets/css/output.css` (Stage 5) put it one directory level
      different from where those relative paths assumed, producing a doubled path
      (`/templates/assets/assets/img/...`, confirmed live via a real 404 in the Next.js dev log
      while checking Template 3/5's own background sections) for every one of those 39
      references. `style.css` (the *other* vendored stylesheet) uses a different, already-correct
      relative shape (`../img/...`) and needed no fix — only `output.css` was affected. Fixed by
      rewriting all 39 to absolute `/templates/assets/img/...` paths directly in the copied file.
      This was invisible to Stage 5/6's own manual checks because none of the specific sections
      using these particular background images happened to be on-screen in those checks; Stage
      7's own broader walkthrough (viewing full pages for all 5 templates, not just their hero
      sections) is what surfaced it.
  - **Real bug found and fixed, unrelated to the feature's own logic**: mid-walkthrough, a
      `PublicSiteRevalidationJob` triggered by an `EventPage` save didn't visibly take effect on
      the next page load — turned out to be the **browser's own HTTP cache** serving a stale
      full-page response across what looked like fresh checks (a brand-new tab still shares the
      same browser profile's disk cache as prior tabs for an identical URL; a `?query=param`
      cache-buster did not reliably defeat it either in this session). Confirmed definitively via
      `curl` (a cache-less client) at each step that the *server* was correctly and immediately
      serving the newly-assigned template every time — the revalidation pipeline itself was never
      broken. A genuine hard reload (Cmd+Shift+R, bypassing the disk cache) resolved it in the
      browser too. Recorded here so a future reader who sees "the page didn't update" doesn't
      chase the wrong layer first.
  - Both Rails-side background processes (`bin/jobs` Sidekiq, plus the Rails server itself) needed
      the three `PUBLIC_SITE_*` env vars passed explicitly on their own command lines — exporting
      them in one shell does not propagate to a background process started from a *different*
      shell invocation in this workflow; confirmed live once vs. deduced.
  - QA fixture data (Agency/Account/Event/User/OAuth application) cleaned up afterward via
      `bin/rails runner`, using targeted `Model.delete(id)` calls rather than `#destroy` for the
      `Account` row specifically — a pre-existing, unrelated bug in this codebase
      (`Account#quotations` references a `Quotation` model that no longer exists, confirmed by the
      resulting `NameError` when `#destroy`'s cascade tried to load it) blocks a normal
      `account.destroy` today. Not this feature's bug to fix, flagged here only so a future
      cleanup attempt doesn't lose time rediscovering it.

## Deferred / fast-follow (explicitly not this plan)

- **Description/dates/address/meeting_link/banner-image binding** — narrowed out of Stage 5 during
  implementation (see that stage's own "Scope actually shipped" note) once the 5 templates turned
  out to be genuinely bespoke layouts, not 5 skins of one shared structure. Only hero title and the
  Register CTA are bound today; a future pass would need a real per-template investigation (not a
  blanket approach) for each of the remaining fields, since where they'd even go differs template
  to template.
- Richer per-template binding: real `Speaker`/`Schedule` records into each template's speaker/
  agenda sections, real `TicketCategory` data into its pricing cards. Both models already exist
  today — this is additive work on top of Stage 5's components, not a rebuild.
- Sponsors/gallery/FAQ sections staying static is itself downstream of Sponsors/Exhibitors not
  existing yet at all (`doc/implementation_3.md` Phase 24, still unchecked) — once that phase
  ships, a template's sponsor section becomes a real binding candidate too.
- Full vendor-JS visual-fidelity verification (Lenis smooth-scroll, GSAP ScrollTrigger animations,
  slider re-init) — loaded via `next/script` and confirmed not to break the page, but not checked
  section-by-section against the original static template's own behavior.
- A live in-admin preview (iframe rendering the actual Next.js template with this event's real
  data) instead of a static thumbnail.
- Per-event color/logo overrides layered on top of a fixed template (raised as an open question in
  `doc/public_event_site_options.md`, never resolved) — still out of scope here; v1 is "pick one of
  6 fixed looks," nothing themeable within a template yet.
