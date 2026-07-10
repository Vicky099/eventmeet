# EventMeet — Backend (Rails)

Multi-tenant Admin Console + Platform (Super Admin) Console. See `doc/requirement.md` for the full
product requirements and `doc/implementation.md` for the phase-by-phase build plan/checklist.

## Local setup

```sh
bin/setup   # bundle install, db:prepare
bin/dev     # web (Puma) + jobs (Sidekiq) + mail (MailCatcher)
```

Requires Postgres and **Redis** running locally (`redis-server` — Redis backs both Sidekiq and
Action Cable's pub/sub, per `doc/requirement.md` §4.10; `bin/dev` does not start Redis itself).

## Email in development

Outgoing mail (Devise's password-reset instructions, later invite/notification emails) is
delivered via SMTP to [MailCatcher](https://mailcatcher.me) instead of actually being sent — view
everything at **http://localhost:1080**. `bin/dev` starts it via `bin/mailcatcher`, or run that
directly on its own. It's deliberately not in the `Gemfile` (pins old `eventmachine`/`thin`
versions that conflict with a modern Rails bundle) — install it as a standalone gem:

```sh
gem install mailcatcher
```

If that fails with a `"rackup" from rack conflicts with installed executable from rackup` error
under this project's Ruby, install it under a different Ruby instead (e.g. via rvm/rbenv) —
`bin/mailcatcher` finds and runs it from there automatically; it doesn't need to share this app's
Ruby or bundle, same as Postgres or Redis.

## Multi-tenant local hosts

Every request is routed by its `Host` header (`doc/requirement.md` §4.3):

| Host (local dev) | App | Audience | Login |
|---|---|---|---|
| `lvh.me:3000` | Platform Console (`SuperAdmin::` namespace) | Super Admin | `/platform/login` |
| `{tenant_slug}.lvh.me:3000` | Admin Console (`Admin::` namespace) | Tenant staff | `/admin/login` |

Every route on both sides carries its console's URL namespace (`/admin/...`, `/platform/...`) —
`config/routes.rb` has the full list.

`*.lvh.me` is public DNS that resolves to `127.0.0.1` — no `/etc/hosts` editing needed. Visit
`acme.lvh.me:3000/admin/login` once you've seeded/created a tenant with `subdomain_slug: "acme"`
(`config/initializers/multi_tenancy.rb` sets `PLATFORM_DOMAIN=lvh.me` by default in development;
override via `ENV["PLATFORM_DOMAIN"]` if needed).

In `RAILS_ENV=production`, `PLATFORM_DOMAIN` must be set explicitly — there's no default.

## Tests

```sh
bundle exec rspec
bin/rubocop
bin/brakeman
```
