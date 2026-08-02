import { TEMPLATE_2_RAW_HTML } from "./raw/template2.raw";
import {
  BASE_VENDOR_SCRIPTS,
  TemplateStylesheets,
  TemplateVendorScripts,
  substituteTemplateTokens,
  type TemplatePageProps,
} from "./template-shared";

// doc/event_page_templates_plan.md, Stage 5 — Template 2 ("Corporate Mega Conference" design,
// eventics' index-2.html). Same shallow-binding scope as Template1EventPage — see that file.
export function Template2EventPage(props: TemplatePageProps) {
  const html = substituteTemplateTokens(TEMPLATE_2_RAW_HTML, props);

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
