import type { PublicEvent } from "@/lib/server/rails";
import { DefaultEventPage } from "./default-event-page";
import { RegistrationModal } from "./registration-modal";

// The actual page body, shared by both route trees:
//   app/events/[eventSlug]/page.tsx              — a tenant's own verified custom domain
//   app/events/[tenantSlug]/[eventSlug]/page.tsx — the shared default domain
// Rendering is identical either way; only *how the tenant was identified* differs between the two
// callers (Host header vs. URL path segment) — accountSlug is only passed by the path-based
// route, since that's the only one whose own /api/register calls can't rely on Host alone to
// figure out which tenant to hit.
export function PublicEventPage({
  event,
  eventSlug,
  accountSlug,
}: {
  event: PublicEvent;
  eventSlug: string;
  accountSlug?: string;
}) {
  return (
    <main>
      {!event.published ? (
        <DefaultEventPage />
      ) : event.content_html ? (
        // Rendered as-is, no split/sentinel handling — doc's Confirmed decisions #2/#5 dropped
        // the earlier draft's token-substitution design entirely. Sanitization is a deliberate
        // non-goal here (Confirmed decision #2): this event's own admin owns the risk for their
        // own page/visitors, same trust model a website builder's "custom code" feature takes.
        <div dangerouslySetInnerHTML={{ __html: event.content_html }} />
      ) : (
        <DefaultEventPage event={event} />
      )}

      {event.published && (
        <RegistrationModal
          slug={eventSlug}
          accountSlug={accountSlug}
          eventName={event.name}
          ticketCategories={event.registration_schema}
        />
      )}
    </main>
  );
}
