import { notFound } from "next/navigation";
import type { Metadata } from "next";
import { resolveDomainForAccountSlug, fetchPublicEvent } from "@/lib/server/rails";
import { PublicEventPage } from "@/components/public-event-page";

// `slug` here is the *tenant's* account slug, not an event slug — see the parent route
// (app/events/[slug]/page.tsx) for why this segment is named `slug` either way: Next.js requires
// the same dynamic-segment name at a shared tree position, and that parent folder doubles as this
// route's own first segment.
type Params = Promise<{ slug: string; eventSlug: string }>;

// Reached via the shared *default* public domain only — locally, http://localhost:5173/events/{tenant}/{event};
// in production, the platform's own default public host the same way. Every visitor on that
// shared domain has the exact same Host header, so it can't identify a tenant the way a
// subdomain or a custom domain can — the tenant slug travels in the URL path instead, resolved
// via resolveDomainForAccountSlug (a synthetic `{tenantSlug}.{platform_domain}` host fed through
// the exact same Rails domain_resolution call, no backend changes needed). Both a tenant's own
// subdomain (xaniel.{platform_domain}) *and* their own verified custom domain use the parent
// one-segment route instead (app/events/[slug]/page.tsx) — Host alone is already enough for
// either of those.
async function loadEvent(tenantSlug: string, eventSlug: string) {
  const resolution = await resolveDomainForAccountSlug(tenantSlug);
  if (!resolution) return null;

  const event = await fetchPublicEvent(resolution, eventSlug);
  return event ?? null;
}

export async function generateMetadata({
  params,
}: {
  params: Params;
}): Promise<Metadata> {
  const { slug, eventSlug } = await params;
  const event = await loadEvent(slug, eventSlug);

  // Same gating as PublicEventPage's own body — an unpublished event's real name/description
  // shouldn't leak via the browser tab/social preview either.
  if (!event || !event.published) return {};

  return {
    title: event.name,
    description: event.description ?? undefined,
  };
}

export default async function TenantPathEventPage({
  params,
}: {
  params: Params;
}) {
  const { slug, eventSlug } = await params;
  const event = await loadEvent(slug, eventSlug);
  if (!event) notFound();

  return (
    <PublicEventPage event={event} eventSlug={eventSlug} accountSlug={slug} />
  );
}
