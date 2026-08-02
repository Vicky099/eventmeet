// Shared by the event show page, the ported templates, the register page, and the floating
// register CTA — one place computing the two URL shapes this app already supports (see
// app/events/[slug]/page.tsx and app/events/[slug]/[eventSlug]/page.tsx's own comments):
// `accountSlug` present only on the shared-domain, path-resolved route (Host alone can't
// disambiguate tenants there); absent on a tenant's own subdomain/custom domain, where Host
// already identifies the tenant.
export function eventShowPath(eventSlug: string, accountSlug?: string): string {
  return accountSlug ? `/events/${accountSlug}/${eventSlug}` : `/events/${eventSlug}`;
}

export function eventRegisterPath(eventSlug: string, accountSlug?: string): string {
  return `${eventShowPath(eventSlug, accountSlug)}/register`;
}

// requirement.md revisit: "post registration ... download button ... invitation PDF" — a plain
// query-string GET link (app/api/invitation/route.ts), not a path segment, since this is a
// download URL handed straight to an <a href>, not a Next.js page route of its own.
export function invitationDownloadPath(
  eventSlug: string,
  hexId: string,
  accountSlug?: string,
): string {
  const params = new URLSearchParams({ slug: eventSlug, hexId });
  if (accountSlug) params.set("accountSlug", accountSlug);
  return `/api/invitation?${params.toString()}`;
}
