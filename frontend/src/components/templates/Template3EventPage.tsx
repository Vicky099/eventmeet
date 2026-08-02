import { TEMPLATE_3_RAW_HTML } from "./raw/template3.raw";
import {
  BASE_VENDOR_SCRIPTS,
  TemplateStylesheets,
  TemplateVendorScripts,
  substituteTemplateTokens,
  type TemplatePageProps,
} from "./template-shared";

// doc/event_page_templates_plan.md, Stage 5 — "Events Conference" design, eventics' index-5.html.
// requirement.md revisit (direct user instruction, two renumberings): first "keep the template
// number in serial. 1,2,3,4" (this app's own former Template 5 renumbered down to Template 4,
// after Template 4's own original auction/marketplace design was removed as a poor fit), then
// "Remove template 3 completely ... keep the numbering serial again" (the *original* Template 3,
// a nightclub/multi-event-venue demo design, removed as a poor fit too — this renumbered down
// again, from Template 4 to Template 3). The vendor's own source file is unchanged throughout —
// only this app's own numbering shifted. Same shallow-binding scope as Template1EventPage — see
// that file. This template's banner/hero has no CTA of its own (image/vector layout only); the
// register link is on the Countdown section's "Buy Ticket" button instead (raw/template3.raw.ts's
// own comment).
export function Template3EventPage(props: TemplatePageProps) {
  const html = substituteTemplateTokens(TEMPLATE_3_RAW_HTML, props);

  return (
    <>
      <TemplateStylesheets />
      {/* suppressHydrationWarning — see template-shared.tsx's own TemplateVendorScripts comment
          for the live, byte-level verification behind this (not blindly silencing a real bug). */}
      <div dangerouslySetInnerHTML={{ __html: html }} suppressHydrationWarning />
      <TemplateVendorScripts scripts={[...BASE_VENDOR_SCRIPTS, "js/countdown.js", "js/accordion.js"]} />
    </>
  );
}
