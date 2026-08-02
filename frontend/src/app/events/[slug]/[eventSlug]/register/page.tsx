import { notFound, redirect } from "next/navigation";
import type { Metadata } from "next";
import { resolveDomainForAccountSlug, fetchPublicEvent } from "@/lib/server/rails";
import { PublicRegisterPage } from "@/components/public-register-page";

// Sibling to ../page.tsx (the shared-domain event show page) — see that file's own comment for
// why `slug` here means the tenant's account slug, not the event.
type Params = Promise<{ slug: string; eventSlug: string }>;

async function loadEvent(tenantSlug: string, eventSlug: string) {
  const resolution = await resolveDomainForAccountSlug(tenantSlug);
  if (!resolution) return null;

  return (await fetchPublicEvent(resolution, eventSlug)) ?? null;
}

export async function generateMetadata({
  params,
}: {
  params: Params;
}): Promise<Metadata> {
  const { slug, eventSlug } = await params;
  const event = await loadEvent(slug, eventSlug);
  if (!event || !event.published) return {};

  return { title: `Register — ${event.name}` };
}

export default async function TenantPathRegisterPage({
  params,
}: {
  params: Params;
}) {
  const { slug, eventSlug } = await params;
  const event = await loadEvent(slug, eventSlug);
  if (!event) notFound();
  if (!event.published) redirect(`/events/${slug}/${eventSlug}`);

  return (
    <PublicRegisterPage event={event} eventSlug={eventSlug} accountSlug={slug} />
  );
}
