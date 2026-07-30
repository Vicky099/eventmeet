import { headers } from "next/headers";
import { notFound } from "next/navigation";
import type { Metadata } from "next";
import { resolveDomain, fetchPublicEvent } from "@/lib/server/rails";
import { PublicEventPage } from "@/components/public-event-page";

// Named `slug` (not `eventSlug`) — Next.js requires sibling routes at the same tree position to
// share one dynamic segment name, and this folder is also the *parent* of
// app/events/[slug]/[eventSlug]/page.tsx (confirmed live: naming them differently fails to boot
// with "You cannot use different slug names for the same dynamic path"). Here, at this route,
// `slug` is the event's own slug — see that sibling route for the other meaning this same segment
// name takes one level up from there.
type Params = Promise<{ slug: string }>;

// Reached by any URL where the incoming Host header alone already identifies the tenant — a
// tenant's own verified custom domain (xaniel.com/events/aws-summit-2027) *or* the legacy/kept
// subdomain shape (xaniel.{platform_domain}/events/aws-summit-2027, confirmed still wanted
// alongside the shared-domain path below, not replaced by it). Both resolve identically here:
// resolveDomain doesn't care *which* kind of host it was handed, it just asks Rails'
// domain_resolution, which tries a verified TenantDomain first, then falls back to
// Hosting::Resolver's own subdomain-label parsing — this route is oblivious to which branch
// answered. A visitor on the shared *default* domain (no subdomain, no custom domain of their
// own) instead hits app/events/[slug]/[eventSlug]/page.tsx, where Host can't disambiguate
// tenants at all (everyone shares the exact same host there) and the tenant comes from the URL
// path instead.
//
// fetch() is automatically memoized per-request (confirmed against node_modules/next/dist/docs
// before writing this) — generateMetadata and the page component below both call this with
// identical arguments, so Next.js dedupes them into a single underlying request, not two.
async function loadEvent(eventSlug: string) {
  const host = (await headers()).get("host") ?? "";
  const resolution = await resolveDomain(host);
  if (!resolution) return null;

  const event = await fetchPublicEvent(resolution, eventSlug);
  return event ?? null;
}

export async function generateMetadata({
  params,
}: {
  params: Params;
}): Promise<Metadata> {
  const { slug } = await params;
  const event = await loadEvent(slug);

  // Same gating as PublicEventPage's own body (DefaultEventPage with no `event` prop) — an
  // unpublished event's real name/description shouldn't leak via the browser tab or a social
  // share preview either, just because generateMetadata runs independently of what renders.
  if (!event || !event.published) return {};

  return {
    title: event.name,
    description: event.description ?? undefined,
  };
}

export default async function HostResolvedEventPage({
  params,
}: {
  params: Params;
}) {
  const { slug } = await params;
  const event = await loadEvent(slug);
  if (!event) notFound();

  return <PublicEventPage event={event} eventSlug={slug} />;
}
