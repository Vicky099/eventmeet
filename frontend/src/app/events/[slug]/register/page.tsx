import { headers } from "next/headers";
import { notFound, redirect } from "next/navigation";
import type { Metadata } from "next";
import { resolveDomain, fetchPublicEvent } from "@/lib/server/rails";
import { PublicRegisterPage } from "@/components/public-register-page";

// Sibling to ../page.tsx (the event show page) — see that file's own comment for why this segment
// is named `slug` (a Next.js dynamic-segment-naming constraint, not a real ambiguity here: this
// route only ever means "event slug," the shared-domain variant's own `register/page.tsx`
// disambiguates the tenant-slug meaning the same way its own parent already does).
type Params = Promise<{ slug: string }>;

async function loadEvent(eventSlug: string) {
  const host = (await headers()).get("host") ?? "";
  const resolution = await resolveDomain(host);
  if (!resolution) return null;

  return (await fetchPublicEvent(resolution, eventSlug)) ?? null;
}

export async function generateMetadata({
  params,
}: {
  params: Params;
}): Promise<Metadata> {
  const { slug } = await params;
  const event = await loadEvent(slug);
  if (!event || !event.published) return {};

  return { title: `Register — ${event.name}` };
}

export default async function HostResolvedRegisterPage({
  params,
}: {
  params: Params;
}) {
  const { slug } = await params;
  const event = await loadEvent(slug);
  if (!event) notFound();
  // Nothing to register for on an unpublished event — same gate the show page's own Register CTA
  // is already conditioned on (public-event-page.tsx), enforced here too since this route is
  // directly reachable on its own, not only by following that CTA.
  if (!event.published) redirect(`/events/${slug}`);

  return <PublicRegisterPage event={event} eventSlug={slug} />;
}
