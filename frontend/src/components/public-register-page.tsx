import type { PublicEvent } from "@/lib/server/rails";
import { TemplateRegistrationPage } from "./templates/TemplateRegistrationPage";
import { EVENT_PAGE_TEMPLATE_RAW_HTML } from "./templates/registry";

function isKnownTemplateKey(
  key: string,
): key is keyof typeof EVENT_PAGE_TEMPLATE_RAW_HTML {
  return key in EVENT_PAGE_TEMPLATE_RAW_HTML;
}

// requirement.md revisit (direct user instruction): "for custom HTML template, keep the same
// register page UI which we have used for templates" — a Custom HTML event (template_key nil)
// has no raw vendor template of its own to slice a footer from, so it borrows template_1's just
// for that shared chrome (TemplateStylesheets/the footer are identical vendor assets across all 3
// templates — nothing about this page's own layout depends on which one is picked).
const DEFAULT_RAW_HTML = EVENT_PAGE_TEMPLATE_RAW_HTML.template_1;

// doc/event_page_templates_plan.md revisit (direct user instruction): registration is a real
// route now, mirroring public-event-page.tsx's own shared-by-both-route-trees shape exactly (same
// two callers: app/events/[slug]/register/page.tsx and
// app/events/[slug]/[eventSlug]/register/page.tsx).
export function PublicRegisterPage({
  event,
  eventSlug,
  accountSlug,
}: {
  event: PublicEvent;
  eventSlug: string;
  accountSlug?: string;
}) {
  // "Obey template UI format" (direct user instruction) — every event's register page gets the
  // same info-card + form chrome, whether it's assigned one of the numbered templates (using that
  // template's own raw HTML) or Custom HTML (falling back to DEFAULT_RAW_HTML above) — no more
  // generic centered layout for the Custom HTML case.
  const rawHtml =
    event.template_key && isKnownTemplateKey(event.template_key)
      ? EVENT_PAGE_TEMPLATE_RAW_HTML[event.template_key]
      : DEFAULT_RAW_HTML;

  return (
    <TemplateRegistrationPage
      rawHtml={rawHtml}
      event={event}
      eventSlug={eventSlug}
      accountSlug={accountSlug}
    />
  );
}
