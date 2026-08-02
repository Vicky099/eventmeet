"use client";

import { useState, type FormEvent } from "react";
import { useRegisterParticipantMutation } from "@/store/registrationApi";
import { invitationDownloadPath } from "@/lib/event-paths";
import type { TicketCategorySchema } from "@/lib/server/rails";

const FIELD_LABELS: Record<string, string> = {
  title: "Title",
  first_name: "First name",
  last_name: "Last name",
  email: "Email",
  contact_num: "Phone number",
  company: "Company",
  department: "Department",
  position: "Position",
  nationality: "Nationality",
  country: "Country",
  govt_id: "Government ID",
  rf_id: "RFID",
  photo: "Photo",
  document: "Document",
};

// Participant#photo/#document (ActiveStorage attachments) — the only two catalog fields that are
// files, not text. Api::V1::Public::ParticipantsController#apply_uploads already accepts a real
// multipart file for these (attach_tenant_scoped's own non-String branch), so a plain
// `<input type="file">` submitted via FormData is all the backend needs — no separate
// direct-upload/signed_id endpoint required for this flow.
const FILE_CATALOG_FIELDS = new Set(["photo", "document"]);

// Two visual skins for the exact same fields/validation/submit logic — never two different form
// implementations. "generic" is the plain Tailwind look used when no template is assigned
// (registration-page.tsx on its own, no eventics stylesheet loaded to draw from). "eventics" is
// modeled on the vendored template package's own contact.html form (grid-cols-2, its border/
// radius/color choices) so a numbered-template event's register page actually looks designed,
// not bolted on — only usable where TemplateStylesheets is already loaded (the etBlue/etBlack/
// etGray colors and font-lato come from that compiled output.css, not this app's own Tailwind
// build), which is exactly the one place this variant is ever passed.
export type RegistrationFormVariant = "generic" | "eventics";

const STYLES: Record<
  RegistrationFormVariant,
  {
    grid: string;
    field: string;
    label: string;
    input: string;
    fileInput: string;
    checkboxRow: string;
    button: string;
    error: string;
    // requirement.md revisit (direct user instruction): "registration success should follow the
    // template font size and font family" — the success card was hardcoded to generic Tailwind
    // type-scale classes (`text-xl`/`text-sm`, slate colors) regardless of variant, so on a
    // numbered-template event it visibly broke from the surrounding page's own text-[Npx]/etBlack/
    // etGray/font-lato conventions the instant registration succeeded. These four give the success
    // card the same per-variant typography as everything else in this component.
    successContainer: string;
    successHeading: string;
    successDescription: string;
    successPrimaryButton: string;
    successSecondaryButton: string;
  }
> = {
  generic: {
    grid: "mt-4 space-y-3",
    field: "",
    label: "block text-sm font-medium text-slate-700",
    input: "mt-1 w-full rounded border border-slate-300 px-3 py-2",
    // A bordered box matching every other field, not a styled `::file-selector-button` — the
    // native "Choose File" control stays browser-default inside it, same convention Flowbite's
    // own file-input pattern uses.
    fileInput:
      "mt-1 block w-full cursor-pointer rounded border border-slate-300 px-3 py-2 text-sm text-slate-700 focus:border-blue-600 focus:outline-none focus:ring-1 focus:ring-blue-600",
    checkboxRow: "flex items-center gap-2 text-sm text-slate-700",
    button:
      "w-full rounded bg-blue-600 px-4 py-2 font-semibold text-white hover:bg-blue-700 disabled:opacity-50",
    error: "text-sm text-red-600",
    successContainer: "rounded-lg border border-slate-200 bg-white p-8 text-center shadow-sm",
    successHeading: "mt-4 text-xl font-semibold text-slate-900",
    successDescription: "mt-2 text-sm text-slate-600",
    successPrimaryButton:
      "inline-flex w-full items-center justify-center gap-2 rounded bg-blue-600 px-4 py-2 font-semibold text-white hover:bg-blue-700",
    successSecondaryButton:
      "inline-flex w-full items-center justify-center rounded border border-slate-300 px-4 py-2 font-semibold text-slate-700 hover:bg-slate-50",
  },
  // requirement.md revisit (direct user instruction): "check on mobile view too" — this whole
  // eventics variant was written with the vendored template's own class *names* (xxs:/xs:, and
  // sm:/md:/lg:/xl: in *descending* value order — `grid-cols-2 xxs:grid-cols-1`) copied verbatim
  // from contact.html. Two compounding bugs made every one of those silently do nothing:
  // (1) `xxs`/`xs` aren't registered breakpoints in *this app's own* Tailwind theme (only the
  // vendored stylesheet's own separate build defines them as max-width queries) — this app's
  // compiler simply drops any variant it doesn't recognize, so `xxs:grid-cols-1` never became any
  // CSS rule at all, confirmed by inspecting the served stylesheet directly. (2) contact.html's
  // *own* authors used max-width breakpoints (`md:` = "at md and below"), backwards from
  // Tailwind's real default `sm/md/lg/xl` (min-width, "at sm and above") that this app's own build
  // actually uses — so even the classes that *did* compile (`md:col-span-1`) meant the opposite of
  // what copying them here intended, and confirmed live to lose a cascade tie against the vendored
  // stylesheet's own same-named unconditional rule regardless (that stylesheet loads *after* this
  // app's own compiled CSS, so any of its bare, unprefixed classes — `.grid-cols-2` chief among
  // them — always wins a specificity tie against this app's conditional override). Rewritten
  // mobile-first with only real breakpoints (base value = smallest screen, `sm:`/`md:` grow it),
  // `!` (Tailwind's important modifier) on every override as a second, decisive guard against that
  // same cascade-tie issue recurring for some other value this pass didn't happen to trip over.
  eventics: {
    grid: "grid grid-cols-1 sm:!grid-cols-2 gap-[20px] sm:!gap-[30px] text-[16px]",
    // Always full-width (the ticket-type dropdown and the submit button are the only two things
    // wrapped in this, and neither ever shares a row with another field) — no breakpoint needed;
    // `col-span-2` on a single-column mobile grid just clamps to the one column that exists.
    field: "col-span-2",
    label: "font-lato font-semibold text-etBlack block mb-[12px]",
    input:
      "border border-[#ECECEC] h-[55px] px-[15px] sm:!px-[20px] rounded-[4px] w-full focus:outline-none focus:border-etBlue transition",
    // Same bordered/rounded/h-[55px] box every other field uses so it lines up in the grid — the
    // native "Choose File" button stays browser-default inside it (etBlue/etBlack only have real
    // CSS for the *exact* class combinations the vendored eventics stylesheet's own static markup
    // already used; `file:bg-etBlue` was never one of them and silently renders nothing, confirmed
    // live — var(--et-blue) below reads the same underlying token as a real CSS custom property
    // instead, compiled by this app's own arbitrary-value Tailwind build regardless of what the
    // vendored stylesheet happens to contain).
    fileInput:
      "cursor-pointer border border-[#ECECEC] h-[55px] px-[15px] sm:!px-[20px] rounded-[4px] w-full font-lato text-[14px] text-etGray focus:outline-none focus:border-[var(--et-blue)] transition",
    checkboxRow: "col-span-2 flex items-center gap-2 text-[16px] text-etBlack",
    button:
      "col-span-2 bg-etBlue h-[55px] px-[24px] rounded-[10px] text-[16px] font-medium text-white hover:bg-etBlack transition disabled:opacity-50 inline-flex items-center justify-center gap-[10px]",
    error: "col-span-2 text-sm text-red-600",
    successContainer: "rounded-[10px] border border-[#ECECEC] bg-white p-8 text-center",
    // font-medium/text-etBlack matches the "Register for {event}" heading's own weight/color
    // (TemplateRegistrationPage.tsx) — text-[24px] sits deliberately between that big page heading
    // and InfoRow's own text-[20px] value labels, since this is a card-level heading, not a page
    // one.
    successHeading: "mt-4 text-[24px] font-medium text-etBlack",
    // Exactly the "Register for {event}" heading's own description-paragraph styling
    // (TemplateRegistrationPage.tsx) — same font-light/text-etGray/text-[16px] treatment for any
    // secondary line of body copy in this template.
    successDescription: "mt-2 text-[16px] font-light text-etGray",
    // Reuses `button` above verbatim (bg-etBlue/rounded-[10px]/text-[16px] font-medium) so the
    // primary action here looks identical to every other primary button in this form, rather than
    // inventing a second button style.
    successPrimaryButton:
      "w-full bg-etBlue h-[55px] px-[24px] rounded-[10px] text-[16px] font-medium text-white hover:bg-etBlack transition inline-flex items-center justify-center gap-[10px]",
    // Exactly the eventics "← Back to event" link style used elsewhere (TemplateRegistrationPage's
    // own top-of-page back link).
    successSecondaryButton:
      "w-full inline-flex items-center justify-center gap-2 font-lato text-[15px] font-semibold text-etBlue hover:text-etBlack",
  },
};

// The one form component every event uses (doc's own "same form for all the event" requirement) —
// fields are entirely data-driven from that event's own ticket_categories (registration_schema),
// never hardcoded per event. photo/document/file custom fields are intentionally not rendered
// here yet — see lib/server/rails.ts's own comment on why.
//
// doc/event_page_templates_plan.md revisit — registration is a real page now
// (registration-page.tsx), not a modal (registration-modal.tsx, deleted). This component itself
// is unchanged either way; only its container changed, same as the modal→page move before it only
// ever changed the container, never this form's own field logic.
export function RegistrationForm({
  slug,
  accountSlug,
  eventName,
  ticketCategories,
  backHref,
  variant = "generic",
}: {
  slug: string;
  accountSlug?: string;
  eventName: string;
  ticketCategories: TicketCategorySchema[];
  backHref: string;
  variant?: RegistrationFormVariant;
}) {
  const [categoryId, setCategoryId] = useState(ticketCategories[0]?.id ?? "");
  const [fields, setFields] = useState<Record<string, string>>({});
  const [fileFields, setFileFields] = useState<Record<string, File>>({});
  const [customFields, setCustomFields] = useState<
    Record<string, string | boolean>
  >({});
  const [register, { data, isLoading, isError, isSuccess, error }] =
    useRegisterParticipantMutation();

  const category = ticketCategories.find((c) => c.id === categoryId);
  const s = STYLES[variant];

  async function handleSubmit(formEvent: FormEvent) {
    formEvent.preventDefault();
    await register({
      slug,
      accountSlug,
      participant: {
        ticket_category_id: categoryId,
        ...fields,
        ...fileFields,
        custom_field_values: customFields,
      },
    });
  }

  // requirement.md revisit (direct user instruction, superseding the earlier modal design):
  // "instead of modal show the same modal text in the place of form. with the buttons." — same
  // content (checkmark, heading, buttons) as the modal this replaces, just rendered inline exactly
  // where the <form> below would otherwise sit — no fixed overlay, no backdrop, no dialog role.
  if (isSuccess && data) {
    return (
      <div className={s.successContainer}>
        <div className="mx-auto flex h-14 w-14 items-center justify-center rounded-full bg-green-100">
          <svg
            className="h-8 w-8 text-green-600"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
            strokeWidth={2}
            aria-hidden="true"
          >
            <path strokeLinecap="round" strokeLinejoin="round" d="M4.5 12.75l6 6 9-13.5" />
          </svg>
        </div>

        <h2 className={s.successHeading}>You&apos;re registered!</h2>
        <p className={s.successDescription}>
          You&apos;re all set for {eventName}. We&apos;ve also emailed your invitation to you.
        </p>

        <div className="mt-6 flex flex-col gap-3">
          <a
            href={invitationDownloadPath(slug, data.hex_id, accountSlug)}
            className={s.successPrimaryButton}
          >
            Download Invitation
          </a>
          <a href={backHref} className={s.successSecondaryButton}>
            Back to event
          </a>
        </div>
      </div>
    );
  }

  return (
    <form onSubmit={handleSubmit} className={s.grid}>
      {ticketCategories.length > 1 && (
        <div className={s.field}>
          <label className={s.label} htmlFor="ticket_category">
            Ticket type
          </label>
          <select
            id="ticket_category"
            className={s.input}
            value={categoryId}
            onChange={(changeEvent) => setCategoryId(changeEvent.target.value)}
          >
            {ticketCategories.map((c) => {
              const soldOut = !c.unlimited && (c.remain_count ?? 0) <= 0;
              return (
                <option key={c.id} value={c.id} disabled={soldOut}>
                  {c.name}
                  {soldOut ? " (sold out)" : ""}
                </option>
              );
            })}
          </select>
        </div>
      )}

      {category?.catalog_fields.map((field) =>
        FILE_CATALOG_FIELDS.has(field) ? (
          <div key={field}>
            <label className={s.label} htmlFor={field}>
              {FIELD_LABELS[field] ?? field}
            </label>
            <input
              id={field}
              type="file"
              accept={field === "photo" ? "image/*" : undefined}
              required={!fileFields[field]}
              className={s.fileInput}
              onChange={(changeEvent) => {
                const file = changeEvent.target.files?.[0];
                setFileFields((prev) => {
                  if (!file) {
                    const rest = { ...prev };
                    delete rest[field];
                    return rest;
                  }
                  return { ...prev, [field]: file };
                });
              }}
            />
          </div>
        ) : (
          <div key={field}>
            <label className={s.label} htmlFor={field}>
              {FIELD_LABELS[field] ?? field}
            </label>
            <input
              id={field}
              type={field === "email" ? "email" : "text"}
              required
              className={s.input}
              value={fields[field] ?? ""}
              onChange={(changeEvent) =>
                setFields((prev) => ({
                  ...prev,
                  [field]: changeEvent.target.value,
                }))
              }
            />
          </div>
        ),
      )}

      {category?.custom_fields
        .filter((field) => field.field_type !== "file")
        .map((field) =>
          field.field_type === "checkbox" ? (
            <label key={field.id} className={s.checkboxRow}>
              <input
                type="checkbox"
                required={field.required}
                checked={Boolean(customFields[field.id])}
                onChange={(changeEvent) =>
                  setCustomFields((prev) => ({
                    ...prev,
                    [field.id]: changeEvent.target.checked,
                  }))
                }
              />
              {field.label}
            </label>
          ) : (
            <div key={field.id}>
              <label className={s.label} htmlFor={field.id}>
                {field.label}
              </label>
              {field.field_type === "dropdown" ? (
                <select
                  id={field.id}
                  required={field.required}
                  className={s.input}
                  value={(customFields[field.id] as string) ?? ""}
                  onChange={(changeEvent) =>
                    setCustomFields((prev) => ({
                      ...prev,
                      [field.id]: changeEvent.target.value,
                    }))
                  }
                >
                  <option value="" disabled>
                    Select…
                  </option>
                  {field.options.map((option) => (
                    <option key={option} value={option}>
                      {option}
                    </option>
                  ))}
                </select>
              ) : (
                <input
                  id={field.id}
                  required={field.required}
                  className={s.input}
                  value={(customFields[field.id] as string) ?? ""}
                  onChange={(changeEvent) =>
                    setCustomFields((prev) => ({
                      ...prev,
                      [field.id]: changeEvent.target.value,
                    }))
                  }
                />
              )}
            </div>
          ),
        )}

      {isError && <p className={s.error}>{formatError(error)}</p>}

      <div className={s.field}>
        <button type="submit" disabled={isLoading || !categoryId} className={s.button}>
          {isLoading ? "Submitting…" : "Register"}
          {variant === "eventics" && !isLoading && (
            <i className="fa-solid fa-arrow-right-long" aria-hidden="true" />
          )}
        </button>
      </div>
    </form>
  );
}

// RTK Query's own error shape (fetchBaseQuery) is a union of FetchBaseQueryError |
// SerializedError — Rails' own validation_failed/sold_out payloads (Api::V1::Public::
// ParticipantsController's own #create) land in `.data`, surfaced directly rather than a generic
// "something went wrong."
function formatError(error: unknown): string {
  if (
    error &&
    typeof error === "object" &&
    "data" in error &&
    error.data &&
    typeof error.data === "object"
  ) {
    const data = error.data as { message?: string; errors?: Record<string, string[]> };
    if (data.message) return data.message;
    if (data.errors) return Object.values(data.errors).flat().join(", ");
  }
  return "Something went wrong — please try again.";
}
