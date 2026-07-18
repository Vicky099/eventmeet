# Contributing to EventMeet

Thanks for working on this. Before touching code, read this file — most of it exists because a
convention here isn't optional (tenant isolation especially) or because it saved someone real
debugging time and is worth not rediscovering.

## Before you start

- [`backend/doc/requirement.md`](backend/doc/requirement.md) is the product spec — the *why*
  behind every module, and the multi-tenancy/domain architecture decisions everything else is
  built on.
- [`backend/doc/implementation.md`](backend/doc/implementation.md) is the phase-by-phase build
  log — what's actually shipped, with real file paths and the reasoning behind non-obvious
  decisions. If you're about to build something, check whether a phase already covers it (and
  whether it's checked off) before assuming it doesn't exist.
- [`backend/doc/print-agent-protocol.md`](backend/doc/print-agent-protocol.md) if you're touching
  the print agent or its Rails-side contract.

If a change is genuinely new scope (not filling in an already-unchecked item), add it to
`implementation.md` under the relevant phase — or a new phase — following the existing style:
short goal statement, checklist items, each checked item followed by `→` and the real files it
landed in. Future contributors (including future you) rely on this being accurate, not
aspirational.

## Repo layout

- `backend/` — Ruby on Rails 8. Admin Console (tenant staff), Platform Console (Super Admin), and
  the API surface. See `backend/README.md` for local setup.
- `frontend/` — Next.js. The public attendee-facing site — currently just the `create-next-app`
  scaffold, not yet built (Phase 18).
- `print-agent/` — Electron. The desktop print agent. See `print-agent/README.md`.

## The one non-negotiable rule: tenant isolation

This is a multi-tenant SaaS with **row-based isolation** — every tenant's data lives in the same
tables, distinguished only by `account_id`. A bug that leaks one tenant's data into another's view
is the single worst class of bug this codebase can have, and it's guarded against at two
independent layers:

1. **`TenantScoped`** (`backend/app/models/concerns/tenant_scoped.rb`) — every tenant-scoped model
   includes this. It default-scopes every query to `Current.account`, and **raises** if a query
   runs with neither `Current.account` nor `Current.platform_request` set, rather than silently
   returning every tenant's rows. If you hit `TenantScoped::MissingTenantContextError`, that's the
   guard doing its job — fix the caller, don't work around the model.
2. **Postgres Row-Level Security**, enabled via `TenantRowLevelSecurity.enable!(self, :table_name)`
   at the end of every migration that creates a tenant-scoped table. Defense-in-depth: even a raw
   SQL query or a bug in `TenantScoped` itself still can't cross tenants, because Postgres refuses
   at the row level. `TenantResolvable` (`backend/app/controllers/concerns/tenant_resolvable.rb`)
   sets the `app.current_account_id` session variable this checks, for the lifetime of a request.

What this means for you, concretely:

- **New tenant-scoped model** → `include TenantScoped`, and the migration ends with
  `TenantRowLevelSecurity.enable!(self, :table_name)`. Copy the shape from a recent migration
  (e.g. `db/migrate/*_create_print_stations.rb`), don't write RLS SQL from scratch.
- **Background jobs, Sidekiq workers, Action Cable channels** run outside the request cycle, so
  nothing sets `Current.account` for you — set it explicitly, first thing, e.g.
  `Current.account = record.account`. `ParticipantExportJob` is the reference example. Action
  Cable channels are worse: `Current` resets on **every single channel action** (each is its own
  executor wrap, not one reset per connection) — see `PrintJobsChannel` for a channel that sets it
  fresh in `subscribed`, `unsubscribed`, and every custom action.
- **Never** reach for `Model.unscoped` to sidestep a "missing tenant context" error. If a query
  genuinely needs to cross tenants (a rake task, a console session, a pairing-code lookup before
  any tenant is known), use `Model.unscoped_across_tenants { ... }` — it's explicit, greppable, and
  narrow, unlike a bare `unscoped` that silently un-guards everything downstream too.
- **Updating a record for a reason unrelated to its own business validations?** Prefer
  `update_columns` over `update!`/`update` — a settings toggle shouldn't fail because of some
  *other* unrelated validation on the same model (this bit a real feature: saving a print-station
  setting 500'd because the event had no `Quotation`, a completely unrelated business rule). See
  `TicketCategory#sync_counts!` or `Admin::PrintStationsController#update_settings` for the
  pattern — and the comment on why, since it's a "confirmed live, not just a style choice" call
  each time.

## Development conventions

- **Comments explain *why*, not *what*.** A hidden constraint, a workaround for a specific bug, a
  decision that would look wrong without context — that's worth a comment. Restating what the next
  line obviously does is not. This codebase's existing comments lean long *when the reasoning is
  genuinely non-obvious* (a real bug that was found and fixed, a design tradeoff that was
  considered and rejected) — match that bar, don't pad.
- **Reuse before you build.** Check for an existing service/concern/pattern before adding a new
  one — this app already has, for example, one canonical debounce window (`ScanService::DEBOUNCE_WINDOW`,
  reused by `PrintTriggerService` rather than reimplemented), one canonical tenant-scoped-blob-key
  helper (`TenantScopedAttachment`), one canonical empty-state partial (`shared/_empty_state`).
- **UUIDv7 primary keys everywhere** — `id: :uuid, default: nil` in the migration,
  `ApplicationRecord` assigns it in Ruby (`before_create`). Don't add a DB-side default.
- **Don't add speculative abstraction.** A bug fix doesn't need a refactor riding along with it; a
  one-off script doesn't need a reusable service class. Three similar lines beat a premature
  shared helper.

## Testing

```sh
cd backend
bundle exec rspec       # full suite must stay green
bin/rubocop              # style — must stay clean
bin/brakeman              # security static analysis — must stay clean
```

All three run in CI (`.github/workflows/ci.yml`) on every PR. A PR that doesn't pass all three
won't merge.

Spec conventions worth knowing before you write new ones:

- Request specs set `Current.account =` before building fixtures, and **again** after any request
  that crosses the HTTP boundary — `ActiveSupport::CurrentAttributes` resets automatically after
  each request completes (and after each Action Cable channel action), so a `post`/`patch`/`get`
  followed by reading a `TenantScoped` record needs `Current.account = account` re-set first. Every
  existing request spec (`spec/requests/checkin_spec.rb` is a good example) does this — copy the
  pattern.
- Don't stub out the thing you're actually testing. A revoke spec that stubbed
  `ActionCable.server.remote_connections.where` hid a real `InvalidIdentifiersError` bug for a full
  release — the stub replaced the exact call whose behavior needed verifying. If you're tempted to
  stub a framework API to make a test pass, ask whether the test should be exercising the real
  thing instead.
- **Verify runtime behavior, not just specs, for anything with a real UI or external process.**
  Green specs don't prove a feature works — several real bugs in this codebase (CSRF blocking a
  non-browser client, Action Cable's own Origin-header allow-list, a corrupt hand-built PNG, Action
  Cable's `identifiers` requirement on `remote_connections.where`) were only caught by actually
  running the app and driving the feature, because none of them are things a request spec's
  test-environment defaults would ever exercise. Before calling a UI-facing or cross-process change
  done, run it.

## Commits & PRs

- Keep commits focused; write commit messages explaining *why*, not a changelog of *what* changed
  (the diff already shows that).
- Don't amend/force-push a commit that's already been reviewed or pushed to a shared branch,
  unless asked to.
- If your change touches `backend/doc/implementation.md`'s checklist, that update belongs in the
  same PR as the code — an unchecked-but-actually-done item (or a checked-but-not-really-done one)
  is worse than no note at all, since the whole point of that file is that it's trustworthy.
