import type { PublicEvent } from "@/lib/server/rails";
import { eventRegisterPath } from "@/lib/event-paths";
import { DefaultEventPage } from "./default-event-page";
import { RegisterCta } from "./register-cta";
import { EVENT_PAGE_TEMPLATE_REGISTRY } from "./templates/registry";

function isKnownTemplateKey(
  key: string,
): key is keyof typeof EVENT_PAGE_TEMPLATE_REGISTRY {
  return key in EVENT_PAGE_TEMPLATE_REGISTRY;
}

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
  // doc/event_page_templates_plan.md, Stage 5 — a numbered template always wins over Custom HTML
  // (same priority the backend's own EventPage#clear_html_when_template_selected already
  // enforces server-side, mirrored here rather than trusted blindly), and — same as content_html
  // already worked before this field existed — only once the event is actually published. Each
  // Template*EventPage owns its own full page body (styles, vendor scripts, and its own in-page
  // "Register" links, which point at the real register route below), so it's returned directly
  // rather than composed inside the <main> below.
  if (event.published && event.template_key && isKnownTemplateKey(event.template_key)) {
    const TemplateComponent = EVENT_PAGE_TEMPLATE_REGISTRY[event.template_key];
    return (
      <TemplateComponent event={event} eventSlug={eventSlug} accountSlug={accountSlug} />
    );
  }

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

      {/* doc/event_page_templates_plan.md revisit: registration is a real route
          (app/events/.../register/page.tsx) now, not a modal — this is a plain link, no
          client-side "open" state left to manage. */}
      {event.published && (
        <RegisterCta
          href={eventRegisterPath(eventSlug, accountSlug)}
          ticketCategories={event.registration_schema}
        />
      )}
    </main>
  );
}
