import { NextResponse } from "next/server";
import { revalidateTag } from "next/cache";

// Phase 25's own webhook contract (doc/public_event_site_options.md, PublicSiteRevalidator on the
// Rails side) — verifies the shared secret Rails sends (PUBLIC_SITE_REVALIDATE_SECRET, the
// Rails-to-Next.js direction — distinct from PUBLIC_SITE_SHARED_SECRET, which is the
// Next.js-to-Rails direction lib/server/rails.ts uses for domain resolution/credentials), then
// calls revalidateTag(`event:${slug}`) so the next request re-fetches instead of serving the
// stale 300s-cached response.
export async function POST(request: Request) {
  const secret = request.headers.get("x-revalidate-secret");
  if (!secret || secret !== process.env.PUBLIC_SITE_REVALIDATE_SECRET) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const { tag } = await request.json();
  if (!tag) {
    return NextResponse.json({ error: "missing_tag" }, { status: 400 });
  }

  // The installed Next.js version's own type signature requires a second "profile" argument
  // regardless of whether Cache Components is enabled (confirmed against
  // node_modules/next/dist/server/web/spec-extension/revalidate.d.ts — the "Previous Model" doc's
  // one-arg examples don't type-check against this runtime) — "max" is the documented
  // stale-while-revalidate profile, matching this webhook's own "background refresh, slight delay
  // OK" use case.
  revalidateTag(tag, "max");
  return NextResponse.json({ revalidated: true });
}
