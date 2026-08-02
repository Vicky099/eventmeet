import Script from "next/script";
import type { PublicEvent } from "@/lib/server/rails";
import { eventRegisterPath } from "@/lib/event-paths";

// doc/event_page_templates_plan.md, Stage 5 — shared by all 5 ported eventics templates.
export interface TemplatePageProps {
  event: PublicEvent;
  eventSlug: string;
  accountSlug?: string;
}

// The tokens every extracted raw HTML module carries (frontend/src/components/templates/raw/
// *.raw.ts) — hero title text, the href of whichever button(s) that template's own source used
// for its "Register"/"Buy Ticket" CTA (doc/event_page_templates_plan.md revisit: a real route
// now, app/events/.../register/page.tsx, not the modal-click-delegation design this replaced —
// see registration-page.tsx's own comment for the full history), and (requirement.md revisit,
// direct user instruction: "Add map before footer") a Google Maps embed of the event's own
// address — a plain `?q=<address>&output=embed` URL, not the Embed API (no API key needed/
// configured for this app). An address-less event (virtual-only, same `event.address` check
// TemplateRegistrationPage.tsx's own InfoRow already uses) has nothing to point a map at, so the
// whole `<!-- MAP SECTION -->` block is stripped instead of embedding a token-less/broken iframe.
export function substituteTemplateTokens(rawHtml: string, props: TemplatePageProps): string {
  let html = rawHtml
    .replaceAll("__EVENT_NAME__", escapeHtml(props.event.name))
    .replaceAll("__REGISTER_HREF__", eventRegisterPath(props.eventSlug, props.accountSlug));

  if (props.event.address) {
    const mapSrc = `https://www.google.com/maps?q=${encodeURIComponent(props.event.address)}&output=embed`;
    html = html.replaceAll("__MAP_EMBED_SRC__", escapeHtml(mapSrc));
  } else {
    html = removeCommentSection(html, "MAP");
  }

  return html;
}

// Same comment-delimited convention every ported template's own raw HTML already uses to mark
// its major sections (`<!-- NAME SECTION START -->`...`<!-- NAME SECTION END -->`, confirmed
// identical across all 5 raw sources) — a plain indexOf slice, not a regex, since these markers
// are fixed literal strings with no nesting concerns of their own.
function removeCommentSection(html: string, name: string): string {
  const startMarker = `<!-- ${name} SECTION START -->`;
  const endMarker = `<!-- ${name} SECTION END -->`;
  const start = html.indexOf(startMarker);
  const end = html.indexOf(endMarker);
  if (start === -1 || end === -1) return html;
  return html.slice(0, start) + html.slice(end + endMarker.length);
}

// The only dynamic value substituted into any of the 5 templates' raw HTML for v1 (Stage 5's own
// "shallow binding" scope — hero title only, every other section is the template's own static
// demo content). This is organizer-entered content (Event#name), so it's escaped the same way
// doc/public_event_site_options.md's Feasibility Check section already flagged for any dynamic
// value dropped into a `dangerouslySetInnerHTML` string: the template markup itself is trusted
// (hand-authored, vendored from a licensed package), the substituted value is not.
export function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

// Every template's own <head> references the same 4 vendor stylesheets + its own style.css +
// compiled output.css (confirmed identical across all 5 source files' <head> sections) — copied
// once into public/templates/assets/ (Stage 5, shared across templates, not duplicated 5x: the
// source package already ships one flat assets/ folder shared by all 5 demo pages). Rendered as
// plain JSX <link> tags — React 19 hoists <link>/<meta>/<title> rendered anywhere in the tree
// straight into <head> automatically, no next/head or Next-specific API needed.
export function TemplateStylesheets() {
  return (
    <>
      {/* eslint-disable @next/next/no-css-tags -- deliberate: these 6 stylesheets belong to
          whichever ONE template a given event picked, not the whole app, so they can't live in
          the root layout/globals.css the way that lint rule assumes every stylesheet should. */}
      <link rel="stylesheet" href="/templates/assets/vendor/font-awesome/all.min.css" />
      <link rel="stylesheet" href="/templates/assets/vendor/swiper/swiper-bundle.min.css" />
      <link rel="stylesheet" href="/templates/assets/vendor/splide/splide.min.css" />
      <link rel="stylesheet" href="/templates/assets/vendor/slim-select/slimselect.css" />
      <link rel="stylesheet" href="/templates/assets/css/style.css" />
      <link rel="stylesheet" href="/templates/assets/css/output.css" />
      {/* eslint-enable @next/next/no-css-tags */}
    </>
  );
}

// Loaded via next/script (afterInteractive), not the <script src> tags that were in the original
// static pages — those never executed at all, since dangerouslySetInnerHTML/innerHTML does not
// run embedded <script> tags (a browser/DOM-spec restriction, not a React limitation). **Known,
// flagged limitation, not silently accepted**: these are heavy, DOM-manipulating libraries
// (Lenis smooth-scroll, GSAP ScrollTrigger, SplitType text-splitting) originally written assuming
// full ownership of a static page — next/script preserves their DOM-insertion execution order,
// but full visual parity with the original static template (scroll-linked animations, slider
// re-init on route change, etc.) has not been verified in a real browser this session. If a
// section looks static/unanimated rather than broken, that is this gap, not a regression.
//
// **Root-caused, not just flagged**: a "server/client didn't match" hydration warning on the
// `dangerouslySetInnerHTML` div itself (every Template*EventPage) was reported live against a
// real event (doc/event_page_templates_plan.md's own history has the earlier, inconclusive
// version of this). Verified directly this time — fetched the real rendered page, pulled the
// exact `__html` string out of both the literal DOM markup *and* Next.js's own RSC hydration
// payload (JSON-decoded, not guessed), and diffed both against the string this app's own
// substitution logic independently produces: all three matched byte-for-byte. The server is
// provably sending consistent, correct data every time — the warning is a client-only artifact,
// most likely one of the vendor scripts above mutating this DOM subtree (SplitType and Swiper
// both restructure the very markup dangerouslySetInnerHTML injected) in the window between first
// paint and React's hydration pass, which React can't distinguish from a real extension
// rewriting the page (its own error message's disclaimer). `suppressHydrationWarning` is applied
// at each usage site below on that basis — not to hide an unresolved bug, but because the
// underlying data was independently proven correct, so there is nothing left for a warning to be
// reporting.
export function TemplateVendorScripts({ scripts }: { scripts: string[] }) {
  return (
    <>
      {scripts.map((src) => (
        <Script key={src} src={`/templates/assets/${src}`} strategy="afterInteractive" />
      ))}
    </>
  );
}

// doc/event_page_templates_plan.md revisit — the register page (registration-page.tsx rendered
// inside TemplateRegistrationPage.tsx) reuses a template's own footer chrome so it "obeys template
// UI format" per direct user instruction, rather than dropping to the generic centered layout used
// when no template is assigned. Confirmed live (Stage 5's own asset audit) that every one of the 5
// source pages has exactly one <footer> element, so a first-match slice is safe — this would need
// revisiting if a 6th template ever had more than one.
export function extractSection(html: string, tag: "footer"): string | null {
  const match = html.match(new RegExp(`<${tag}\\b[\\s\\S]*?</${tag}>`, "i"));
  return match ? match[0] : null;
}

// requirement.md revisit (direct user instruction, three passes): "remove Find Events, Useful
// Links & Upcoming Events, social links and logo", then "remove Event Venue, Send Email, Call
// Emergency blue box and keep only footer text", then "i see the black background a lot... only
// keep footer (remove et-footer-top ... this div)" — the first two passes emptied
// `et-footer-top`'s contents (logo/social/widgets/contact-info bar) but left the div itself, whose
// own `pt-[130px] xl:pt-[80px] pb-[60px]` padding was rendering as a wall of blank `bg-etBlack`
// space above the copyright line. Removing that one wrapper (confirmed identical across all 5 raw
// templates: `et-footer-top` directly wraps everything except the trailing `et-footer-bottom`
// copyright bar) makes the earlier three markers redundant — they only ever matched content
// nested inside it. A plain lazy regex (`[\s\S]*?</div>`) can't do a removal like this correctly:
// these divs contain further nested <div>s of their own, so a lazy match would stop at the first
// *inner* </div>, not the one that actually closes the target div. This walks the real tag stream
// instead, tracking nesting depth, to find the div's true matching close tag.
function removeDivByClassMarker(html: string, marker: string): string {
  const openTag = html.match(new RegExp(`<div\\b[^>]*class="[^"]*\\b${marker}\\b[^"]*"[^>]*>`, "i"));
  if (!openTag || openTag.index == null) return html;

  const start = openTag.index;
  const tagPattern = /<div\b[^>]*>|<\/div>/gi;
  tagPattern.lastIndex = start + openTag[0].length;

  let depth = 1;
  let tag: RegExpExecArray | null;
  while ((tag = tagPattern.exec(html))) {
    depth += tag[0].toLowerCase() === "</div>" ? -1 : 1;
    if (depth === 0) {
      return html.slice(0, start) + html.slice(tag.index + tag[0].length);
    }
  }

  // Unbalanced (shouldn't happen against real, well-formed template markup) — leave the string
  // untouched rather than risk truncating unrelated content after a mismatched scan.
  return html;
}

export function stripFooterTop(footerHtml: string): string {
  return removeDivByClassMarker(footerHtml, "et-footer-top");
}

export const BASE_VENDOR_SCRIPTS = [
  "vendor/swiper/swiper-bundle.min.js",
  "vendor/splide/splide.min.js",
  "vendor/slim-select/slimselect.min.js",
  "vendor/fslightbox/fslightbox.js",
  "vendor/splide/splide-extension-auto-scroll.min.js",
  "vendor/lenis/lenis.min.js",
  "vendor/splittype/index.min.js",
  "vendor/gsap/gsap.min.js",
  "vendor/gsap/gsap-scroll-trigger.min.js",
  "js/main.js",
];
