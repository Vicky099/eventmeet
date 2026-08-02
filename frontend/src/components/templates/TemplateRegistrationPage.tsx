import { RegistrationPage } from "@/components/registration-page";
import { eventShowPath } from "@/lib/event-paths";
import {
  TemplateStylesheets,
  extractSection,
  stripFooterTop,
  substituteTemplateTokens,
  type TemplatePageProps,
} from "./template-shared";

// requirement.md revisit (direct user instruction): "design this professionally (refer
// eventics/contact.html for the form design)" — the info-card + form two-column layout below is
// modeled directly on that file's own "CONTACT SECTION" (bg-etBlue icon-circle info cards on the
// left, a heading + grid-cols-2 form on the right), repurposed for event info (date/location/
// seats) instead of generic contact details, since that's what a registrant actually needs
// alongside the form. Icons are Font Awesome (already loaded via TemplateStylesheets — no new
// asset needed), matching contact.html's own icon usage.
function InfoRow({ icon, label, value }: { icon: string; label: string; value: string }) {
  return (
    <div className="flex flex-wrap items-center gap-[20px] pb-[20px] text-white border-b border-white/30 last:border-0 last:pb-0">
      <span className="icon shrink-0 border border-dashed border-white rounded-full h-[62px] w-[62px] flex items-center justify-center">
        <i className={`fa-solid ${icon} text-[22px]`} aria-hidden="true" />
      </span>
      <div className="txt">
        <span className="font-light block">{label}</span>
        <h4 className="font-semibold text-[20px]">{value}</h4>
      </div>
    </div>
  );
}

function formatDateRange(startsAt: string, endsAt: string): string {
  const starts = new Date(startsAt);
  const ends = new Date(endsAt);
  const dateFmt = new Intl.DateTimeFormat(undefined, { dateStyle: "medium" });
  const timeFmt = new Intl.DateTimeFormat(undefined, { timeStyle: "short" });
  const sameDay = starts.toDateString() === ends.toDateString();
  return sameDay
    ? `${dateFmt.format(starts)}, ${timeFmt.format(starts)} – ${timeFmt.format(ends)}`
    : `${dateFmt.format(starts)} – ${dateFmt.format(ends)}`;
}

// doc/event_page_templates_plan.md revisit (direct user instruction): "Registration should be a
// separate route and form... make sure it should obey template UI format." One generic component
// for all 5 templates (not 5 separate register-page components) — reuses whichever template's own
// footer chrome the event was assigned, instead of the generic centered layout
// `registration-page.tsx` uses on its own for a Custom-HTML or no-template event.
//
// requirement.md revisit (direct user instruction): "remove header and the added image ... instead
// of logo add the back button" — an earlier pass here reused the template's own full nav header
// (logo/menu/hamburger) plus a contact.html-style breadcrumb banner; both are gone now. No
// `js/main.js` load either — that script's only job was the header's own search/sidebar/tab
// interactions, none of which exist on this page anymore.
export function TemplateRegistrationPage({
  rawHtml,
  ...props
}: TemplatePageProps & { rawHtml: string }) {
  const html = substituteTemplateTokens(rawHtml, props);
  // requirement.md revisit (direct user instruction): "remove Find Events, Useful Links & Upcoming
  // Events, social links and logo ... Event Venue, Send Email, Call Emergency blue box ... only
  // keep footer [text]" — all of that lives inside `et-footer-top` (stripFooterTop's own comment);
  // only the trailing `et-footer-bottom` copyright bar survives.
  const rawFooter = extractSection(html, "footer");
  const footer = rawFooter && stripFooterTop(rawFooter);
  const { event } = props;
  const backHref = eventShowPath(props.eventSlug, props.accountSlug);

  return (
    <>
      <TemplateStylesheets />

      {/* requirement.md revisit (direct user instruction): "check on mobile view too" — see
          registration-form.tsx's own STYLES.eventics comment for the full story (unregistered
          `xxs:`/`xs:` variants, and every other prefix copied from contact.html in *descending*
          value order — backwards from this app's real, min-width Tailwind breakpoints). Same fix
          here: mobile-first ascending values on real breakpoints, `!` on every override. */}
      {/* requirement.md revisit (direct user instruction): "footer should be fixed to the
          viewport" — extra bottom padding here (beyond the symmetric top/bottom py- above) so the
          fixed footer below never overlaps the last field/button on a short page or a page
          scrolled to the very bottom. */}
      <main className="pt-[40px] sm:!pt-[60px] lg:!pt-[80px] pb-[120px]">
        <div className="container mx-auto max-w-[1200px] px-[12px]">
          {/* Replaces the removed header's logo — the one way back to the event this page no
              longer has a nav bar to provide. Exact same style as RegistrationForm's own eventics
              success-page/back link (registration-page.tsx) — this is that same link, just moved
              to the top since it's now the only one on the page (registration-page.tsx skips its
              own copy for variant="eventics" to avoid showing it twice). */}
          <a
            href={backHref}
            className="mb-[30px] md:!mb-[40px] inline-flex items-center gap-2 font-lato text-[15px] font-semibold text-etBlue hover:text-etBlack"
          >
            ← Back to event
          </a>

          <div className="grid grid-cols-1 md:!grid-cols-2 gap-[40px] md:!gap-[60px] items-start">
            {/* left side — event info, same card treatment contact.html's own left column uses */}
            <div className="bg-etBlue p-[30px] sm:!p-[40px] space-y-[24px] text-[16px] rounded-[10px]">
              <InfoRow icon="fa-calendar-days" label="When" value={formatDateRange(event.starts_at, event.ends_at)} />
              {event.address && <InfoRow icon="fa-location-dot" label="Where" value={event.address} />}
              {!event.address && event.meeting_link && (
                <InfoRow icon="fa-video" label="Where" value="Online event" />
              )}
              {event.seats_remaining != null && (
                <InfoRow icon="fa-ticket" label="Seats remaining" value={String(event.seats_remaining)} />
              )}
            </div>

            {/* right side — heading + the actual form */}
            <div>
              <RegistrationPage
                slug={props.eventSlug}
                accountSlug={props.accountSlug}
                eventName={event.name}
                ticketCategories={event.registration_schema}
                backHref={backHref}
                variant="eventics"
                heading={
                  <>
                    <h2 className="text-[28px] sm:!text-[30px] md:!text-[35px] lg:!text-[40px] font-medium text-etBlack mb-[7px]">
                      Register for {event.name}
                    </h2>
                    {event.description && (
                      <p className="text-etGray font-light text-[16px] mb-[38px]">
                        {event.description}
                      </p>
                    )}
                  </>
                }
              />
            </div>
          </div>
        </div>
      </main>

      {/* requirement.md revisit (direct user instruction): "footer should be fixed to the
          viewport" — a plain wrapper div carries the fixed positioning (z-40, under the success
          modal's own z-50 were one ever open at the same time) since the footer's own raw markup
          is vendor HTML we don't want to hand-edit. suppressHydrationWarning — see
          template-shared.tsx's own TemplateVendorScripts comment for the live, byte-level
          verification behind this (not blindly silencing a real bug). */}
      {footer && (
        <div
          className="fixed inset-x-0 bottom-0 z-40"
          dangerouslySetInnerHTML={{ __html: footer }}
          suppressHydrationWarning
        />
      )}
    </>
  );
}
