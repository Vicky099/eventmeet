import { NextResponse } from "next/server";
import {
  resolveDomain,
  resolveDomainForAccountSlug,
  registerParticipant,
} from "@/lib/server/rails";

// RTK Query's own `baseUrl: "/api"` target (store/registrationApi.ts) — a thin proxy, no business
// logic of its own (doc/public_event_site_options.md's own description): holds/refreshes the
// client-credentials token server-side (lib/server/rails.ts, same logic the event-page fetch
// already uses) and forwards straight to Rails' register-participant endpoint.
//
// Two request shapes land here, matching registrationApi.ts's own JSON/FormData branch: a plain
// JSON body when nothing's being uploaded, or multipart/form-data (already keyed
// `participant[field]`/`participant[custom_field_values][id]`, Rack's own nested-param
// convention) whenever photo/document was selected — a File can't survive JSON.stringify. Either
// way `slug`/`accountSlug` travel as their own top-level fields, pulled off here for routing and
// never forwarded themselves; registerParticipant relays whatever's left (JSON object or the
// trimmed FormData) straight through to Rails unchanged.
export async function POST(request: Request) {
  const isMultipart = (request.headers.get("content-type") ?? "").includes("multipart/form-data");

  let slug: string | null;
  let accountSlug: string | undefined;
  let body: unknown;

  if (isMultipart) {
    const formData = await request.formData();
    slug = formData.get("slug") as string | null;
    accountSlug = (formData.get("accountSlug") as string | null) ?? undefined;
    formData.delete("slug");
    formData.delete("accountSlug");
    body = formData;
  } else {
    const json = await request.json();
    slug = json.slug;
    accountSlug = json.accountSlug;
    body = { participant: json.participant };
  }

  if (!slug) {
    return NextResponse.json({ error: "missing_slug" }, { status: 400 });
  }

  // accountSlug is only sent by the shared-default-domain route
  // (app/events/[tenantSlug]/[eventSlug]/page.tsx) — every visitor there shares the same Host, so
  // it can't identify a tenant the way a custom domain can; the tenant travels in the request
  // body instead. Omitted on a tenant's own custom domain (app/events/[eventSlug]/page.tsx),
  // where Host alone already resolves it.
  const resolution = accountSlug
    ? await resolveDomainForAccountSlug(accountSlug)
    : await resolveDomain(request.headers.get("host") ?? "");

  if (!resolution) {
    return NextResponse.json({ error: "unknown_host" }, { status: 404 });
  }

  const result = await registerParticipant(resolution, slug, body);
  return NextResponse.json(result.body, { status: result.status });
}
