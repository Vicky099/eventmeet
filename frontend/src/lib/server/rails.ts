// Server-only: talks to Rails using tenant-scoped OAuth credentials looked up per request.
// Never import this from a "use client" file — RAILS_APEX_URL/PUBLIC_SITE_SHARED_SECRET must
// never reach the browser bundle (doc/public_event_site_options.md's own BFF invariant: the
// browser only ever calls this app's own /api/* routes, never Rails directly).
//
// requirement.md §4.9 item 4's "each tenant's own OAuth application" left one real gap the
// backend's own plan doc didn't spell out: this is a single shared Next.js deployment across
// every tenant, so there's no per-tenant client_id/secret hardcoded anywhere — resolveDomain
// below looks one up per request, for whichever tenant the incoming Host resolves to, via a
// second, distinct trust boundary from the base {account_slug, kind} lookup (PUBLIC_SITE_SHARED_SECRET
// proves *this server* is the real Next.js BFF, not a visitor's browser hitting Rails' domain
// resolution endpoint directly and fishing for credentials).

const RAILS_APEX_URL = process.env.RAILS_APEX_URL ?? "http://lvh.me:3000";
const PUBLIC_SITE_SHARED_SECRET = process.env.PUBLIC_SITE_SHARED_SECRET ?? "";

export interface DomainResolution {
  account_slug: string;
  kind: "subdomain" | "custom";
  client_id?: string;
  client_secret?: string;
}

export interface RegistrationCustomField {
  id: string;
  label: string;
  field_type: "text" | "dropdown" | "checkbox" | "file";
  options: string[];
  required: boolean;
}

export interface TicketCategorySchema {
  id: string;
  name: string;
  unlimited: boolean;
  total_count: number | null;
  remain_count: number | null;
  catalog_fields: string[];
  uniqueness_fields: string[];
  custom_fields: RegistrationCustomField[];
}

export interface PublicEvent {
  name: string;
  description: string | null;
  starts_at: string;
  ends_at: string;
  address: string | null;
  meeting_link: string | null;
  published: boolean;
  content_html: string | null;
  seats_remaining: number | null;
  registration_schema: TicketCategorySchema[];
}

// 60s in-memory cache — short enough that a domain re-pointed to a different tenant (or a
// TenantDomain freshly verified) is picked up quickly, long enough that this doesn't add a
// round-trip to every single request (doc's own "short-TTL in-memory/edge cache" plan). In-memory
// only, same "may not persist across requests in serverless" caveat as any other in-process cache
// in this app — a cold instance just re-fetches, this is a latency optimization, not a source of
// truth.
const domainCache = new Map<string, { data: DomainResolution; expiresAt: number }>();

export async function resolveDomain(
  rawHost: string,
): Promise<DomainResolution | null> {
  // The browser's own Host header includes a port on anything but the default 80/443 (real in
  // dev — lvh.me:5173 — and also possible in prod behind a non-standard port) — Rails'
  // Hosting::Resolver expects a bare hostname (confirmed live: a port suffix made
  // `end_with?(".#{platform_domain}")` fail silently, 404ing every request). Stripped here, once,
  // rather than asking every Rails caller to tolerate a port it was never designed to see.
  const host = rawHost.split(":")[0];

  const cached = domainCache.get(host);
  if (cached && cached.expiresAt > Date.now()) return cached.data;

  const url = new URL("/api/v1/public/domain_resolution", RAILS_APEX_URL);
  url.searchParams.set("host", host);

  const response = await fetch(url, {
    headers: { "X-Public-Site-Secret": PUBLIC_SITE_SHARED_SECRET },
    cache: "no-store",
  });
  if (!response.ok) return null;

  const data = (await response.json()) as DomainResolution;
  domainCache.set(host, { data, expiresAt: Date.now() + 60_000 });
  return data;
}

// The shared-default-domain route (app/events/[tenantSlug]/[eventSlug]/page.tsx) already knows
// which tenant it wants — the URL path says so directly — so there's no real Host to resolve
// identity from the way the custom-domain route needs. Rather than a second Rails endpoint, this
// builds the exact same synthetic `{accountSlug}.{platformHostname}` string Hosting::Resolver's
// own subdomain-label parsing already expects, and feeds it to the same resolveDomain above (no
// TenantDomain row will match this synthetic host, so it falls straight through to the plain
// Account#subdomain_slug lookup) — zero Rails-side changes needed for this to work.
export async function resolveDomainForAccountSlug(
  accountSlug: string,
): Promise<DomainResolution | null> {
  const platformHostname = new URL(RAILS_APEX_URL).hostname;
  return resolveDomain(`${accountSlug}.${platformHostname}`);
}

function tenantBaseUrl(accountSlug: string): string {
  const apex = new URL(RAILS_APEX_URL);
  apex.hostname = `${accountSlug}.${apex.hostname}`;
  return apex.toString();
}

// Doorkeeper's own client_credentials grant issues no refresh token in this app's config
// (Doorkeeper.config.refresh_token_enabled? is false) — machine-to-machine credentials don't
// need one: when a cached token expires, this just asks for a brand-new one with the same
// client_id/secret, unlike an authorization_code flow's interactive-consent constraint that
// refresh tokens exist to avoid repeating.
const tokenCache = new Map<string, { token: string; expiresAt: number }>();

async function getAccessToken(
  resolution: DomainResolution,
): Promise<string | null> {
  if (!resolution.client_id || !resolution.client_secret) return null;

  const cached = tokenCache.get(resolution.account_slug);
  if (cached && cached.expiresAt > Date.now()) return cached.token;

  const response = await fetch(
    new URL("/oauth/token", tenantBaseUrl(resolution.account_slug)),
    {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "client_credentials",
        client_id: resolution.client_id,
        client_secret: resolution.client_secret,
      }),
      cache: "no-store",
    },
  );
  if (!response.ok) return null;

  const data = (await response.json()) as {
    access_token: string;
    expires_in: number;
  };
  // 30s safety margin so a cached token doesn't expire mid-flight between the cache check above
  // and the call that actually uses it.
  tokenCache.set(resolution.account_slug, {
    token: data.access_token,
    expiresAt: Date.now() + (data.expires_in - 30) * 1000,
  });
  return data.access_token;
}

// Rails scopes an Event's slug to its own account (`friendly_id :name, use: :scoped, scope:
// :account_id`, confirmed against app/models/event.rb) — the same slug string can exist under two
// different tenants at once, so the cache tag has to carry the account too, or one tenant's
// content change would spuriously invalidate a same-slug event belonging to someone else. Kept as
// its own exported function (not inlined at each of the two call sites below) so the Rails-side
// PublicSiteRevalidator and this side can never drift apart on the exact tag shape.
export function eventCacheTag(accountSlug: string, eventSlug: string): string {
  return `event:${accountSlug}:${eventSlug}`;
}

// The event page's own data source (Server Component fetch, doc's own "Rails-rendered HTML over
// the API" plan) — `next: { tags, revalidate }` is the "Previous Model" caching Next.js uses when
// `cacheComponents` isn't enabled in next.config.ts (confirmed against node_modules/next/dist/docs
// before writing this — Cache Components' `use cache`/`cacheTag` is a different, newer API this
// app isn't opted into). `/api/revalidate`'s own `revalidateTag(eventCacheTag(...))` call is what
// invalidates this on-demand; the 300s revalidate is the time-based fallback.
export async function fetchPublicEvent(
  resolution: DomainResolution,
  slug: string,
): Promise<PublicEvent | null> {
  const token = await getAccessToken(resolution);
  if (!token) return null;

  const response = await fetch(
    new URL(
      `/api/v1/public/events/${slug}`,
      tenantBaseUrl(resolution.account_slug),
    ),
    {
      headers: { Authorization: `Bearer ${token}` },
      next: {
        tags: [eventCacheTag(resolution.account_slug, slug)],
        revalidate: 300,
      },
    },
  );
  if (response.status === 404) return null;
  if (!response.ok)
    throw new Error(`Rails event-show returned ${response.status}`);

  return (await response.json()) as PublicEvent;
}

export interface RegisterParticipantResult {
  ok: boolean;
  status: number;
  body: unknown;
}

// Used by app/api/register/route.ts (the RTK Query mutation's own BFF target) — a thin proxy, no
// business logic of its own (doc's own description of that route handler's job). JSON body only
// for this pass — photo/document/file-type custom fields need a real multipart relay or a public
// direct-upload endpoint, neither built yet (see Api::V1::Public::ParticipantsController's own
// comment on the backend for the same scope note); a required file-type field just surfaces
// Rails' normal "can't be blank" validation error today, not a broken endpoint.
export async function registerParticipant(
  resolution: DomainResolution,
  slug: string,
  body: unknown,
): Promise<RegisterParticipantResult> {
  const token = await getAccessToken(resolution);
  if (!token) {
    return {
      ok: false,
      status: 502,
      body: {
        error: "not_configured",
        message: "Registration is not available right now.",
      },
    };
  }

  const response = await fetch(
    new URL(
      `/api/v1/public/events/${slug}/participants`,
      tenantBaseUrl(resolution.account_slug),
    ),
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
      cache: "no-store",
    },
  );

  return {
    ok: response.ok,
    status: response.status,
    body: await response.json().catch(() => null),
  };
}
