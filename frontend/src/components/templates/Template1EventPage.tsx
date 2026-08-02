import { TEMPLATE_1_RAW_HTML } from "./raw/template1.raw";
import {
  BASE_VENDOR_SCRIPTS,
  TemplateStylesheets,
  TemplateVendorScripts,
  substituteTemplateTokens,
  type TemplatePageProps,
} from "./template-shared";

// doc/event_page_templates_plan.md, Stage 5 — Template 1 ("Business Expo" design, eventics'
// index.html). Hero title (event.name) and the hero's 3 "Register Now" buttons (linked straight
// to the real register route) are the only dynamic bindings for v1; everything else is the
// template's own static demo content.
export function Template1EventPage(props: TemplatePageProps) {
  const html = substituteTemplateTokens(TEMPLATE_1_RAW_HTML, props);

  return (
    <>
      <TemplateStylesheets />
      {/* suppressHydrationWarning — see template-shared.tsx's own TemplateVendorScripts comment
          for the live, byte-level verification behind this (not blindly silencing a real bug). */}
      <div dangerouslySetInnerHTML={{ __html: html }} suppressHydrationWarning />
      <TemplateVendorScripts scripts={[...BASE_VENDOR_SCRIPTS, "js/countdown.js"]} />
    </>
  );
}
