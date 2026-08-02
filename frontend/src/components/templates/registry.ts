import { Template1EventPage } from "./Template1EventPage";
import { Template2EventPage } from "./Template2EventPage";
import { Template3EventPage } from "./Template3EventPage";
import { TEMPLATE_1_RAW_HTML } from "./raw/template1.raw";
import { TEMPLATE_2_RAW_HTML } from "./raw/template2.raw";
import { TEMPLATE_3_RAW_HTML } from "./raw/template3.raw";

// doc/event_page_templates_plan.md revisit — the register route (TemplateRegistrationPage.tsx)
// needs the same raw HTML the show page renders, to slice its header/footer out of, so the
// register page "obeys template UI format" instead of falling back to the generic layout. Keyed
// identically to EVENT_PAGE_TEMPLATE_REGISTRY below, on purpose — every future template addition
// touches both maps together, never just one.
//
// requirement.md revisit (direct user instruction, two removal+renumber passes): "Remove template
// 4 completely ... as it is not fit with event" then "keep the template number in serial.
// 1,2,3,4" (the old Template 4's own auction/marketplace design, unused by any event, was removed
// outright; this app's own former Template 5 renumbered down to Template 4 to close the gap), then
// "Remove template 3 completely ... keep the numbering serial again" (the *original* Template 3's
// own nightclub/multi-event-venue design removed the same way — this time an event genuinely used
// it, so the former Template 4 renumbered down to Template 3 to close *that* gap, on top of
// reassigning the affected event). See EventPage#template_key (backend) for the matching enum
// rename + migration.
export const EVENT_PAGE_TEMPLATE_RAW_HTML = {
  template_1: TEMPLATE_1_RAW_HTML,
  template_2: TEMPLATE_2_RAW_HTML,
  template_3: TEMPLATE_3_RAW_HTML,
} as const;

// doc/event_page_templates_plan.md, Stage 5 — keyed by the exact strings
// Api::V1::Public::EventsController#event_show_json reports for EventPage#template_key (Rails
// enum keys). public-event-page.tsx looks this up directly; an unrecognized/future key falls
// through to undefined, which that file treats the same as "no template assigned" — never a crash.
export const EVENT_PAGE_TEMPLATE_REGISTRY = {
  template_1: Template1EventPage,
  template_2: Template2EventPage,
  template_3: Template3EventPage,
} as const;

export type EventPageTemplateKey = keyof typeof EVENT_PAGE_TEMPLATE_REGISTRY;
