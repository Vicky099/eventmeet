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
export async function POST(request: Request) {
  const { slug, accountSlug, participant } = await request.json();
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

  const result = await registerParticipant(resolution, slug, { participant });
  return NextResponse.json(result.body, { status: result.status });
}
