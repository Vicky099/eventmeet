"use client";

import type { ReactNode } from "react";
import { RegistrationStoreProvider } from "@/store/provider";
import { RegistrationForm, type RegistrationFormVariant } from "./registration-form";
import type { TicketCategorySchema } from "@/lib/server/rails";

// doc/event_page_templates_plan.md revisit (direct user correction, superseding the earlier
// modal design): "Registration should be a separate route and form, not in modal" — this is that
// route's page body. Used two ways:
//   - directly, wrapped in a plain centered layout, for the default/Custom-HTML event pages
//     (app/events/.../register/page.tsx when the event has no template assigned).
//   - inside a template's own header/footer chrome (templates/TemplateRegistrationPage.tsx), so a
//     numbered-template event's registration page still "obeys template UI format" rather than
//     dropping back to this generic look — that caller passes variant="eventics".
// Same RegistrationForm component either way (doc's own "one shared form" requirement, unchanged
// by the modal→page move) — only the chrome and visual variant differ.
export function RegistrationPage({
  slug,
  accountSlug,
  eventName,
  ticketCategories,
  backHref,
  variant = "generic",
  heading,
}: {
  slug: string;
  accountSlug?: string;
  eventName: string;
  ticketCategories: TicketCategorySchema[];
  backHref: string;
  variant?: RegistrationFormVariant;
  // Overridable so TemplateRegistrationPage can render the exact contact.html-style heading/
  // subtitle block instead of this generic one, without a second copy of the "no tickets" branch
  // below.
  heading?: ReactNode;
}) {
  return (
    <RegistrationStoreProvider>
      {heading ?? (
        <h1 className="text-2xl font-semibold text-slate-900">
          Register for {eventName}
        </h1>
      )}

      {ticketCategories.length === 0 ? (
        <p className="mt-4 text-slate-600">
          Registration isn&apos;t open for this event yet.
        </p>
      ) : (
        <RegistrationForm
          slug={slug}
          accountSlug={accountSlug}
          eventName={eventName}
          ticketCategories={ticketCategories}
          backHref={backHref}
          variant={variant}
        />
      )}

      {/* requirement.md revisit (direct user instruction): "header back button should look the
          same [as this], remove the back button which is below" — TemplateRegistrationPage now
          renders its own top back link (this exact style) in place of the removed template
          header's logo, so the eventics variant would otherwise show the same link twice. The
          generic variant has no such header, so this stays its only way back. */}
      {variant !== "eventics" && (
        <a href={backHref} className="mt-6 inline-block text-sm text-blue-600 underline">
          ← Back to event
        </a>
      )}
    </RegistrationStoreProvider>
  );
}
