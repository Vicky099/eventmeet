"use client";

import { useState, type FormEvent } from "react";
import { RegistrationStoreProvider } from "@/store/provider";
import { useRegisterParticipantMutation } from "@/store/registrationApi";
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
};

// The one form component every event uses (doc's own "same form for all the event" requirement) —
// fields are entirely data-driven from that event's own ticket_categories (registration_schema),
// never hardcoded per event. photo/document/file custom fields are intentionally not rendered
// here yet — see lib/server/rails.ts's own comment on why.
function RegistrationForm({
  slug,
  accountSlug,
  eventName,
  ticketCategories,
  onClose,
}: {
  slug: string;
  accountSlug?: string;
  eventName: string;
  ticketCategories: TicketCategorySchema[];
  onClose: () => void;
}) {
  const [categoryId, setCategoryId] = useState(ticketCategories[0]?.id ?? "");
  const [fields, setFields] = useState<Record<string, string>>({});
  const [customFields, setCustomFields] = useState<
    Record<string, string | boolean>
  >({});
  const [register, { isLoading, isError, isSuccess, error }] =
    useRegisterParticipantMutation();

  const category = ticketCategories.find((c) => c.id === categoryId);

  async function handleSubmit(formEvent: FormEvent) {
    formEvent.preventDefault();
    await register({
      slug,
      accountSlug,
      participant: {
        ticket_category_id: categoryId,
        ...fields,
        custom_field_values: customFields,
      },
    });
  }

  if (isSuccess) {
    return (
      <div className="mt-4">
        <p className="text-green-700">
          You&apos;re registered for {eventName}! Check your email for
          confirmation.
        </p>
        <button
          type="button"
          onClick={onClose}
          className="mt-4 w-full rounded bg-slate-100 px-4 py-2 font-semibold text-slate-700 hover:bg-slate-200"
        >
          Close
        </button>
      </div>
    );
  }

  return (
    <form onSubmit={handleSubmit} className="mt-4 space-y-3">
      {ticketCategories.length > 1 && (
        <div>
          <label
            className="block text-sm font-medium text-slate-700"
            htmlFor="ticket_category"
          >
            Ticket type
          </label>
          <select
            id="ticket_category"
            className="mt-1 w-full rounded border border-slate-300 px-3 py-2"
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

      {/* photo/document are catalog fields but are file uploads, not text — rendering them as a
          plain <input type="text"> would submit a string Rails' attach_tenant_scoped can't use
          (lib/server/rails.ts's own comment on why public file uploads aren't wired yet). Skipped
          here the same way file-type custom fields already are below, rather than rendering a
          broken field. */}
      {category?.catalog_fields
        .filter((field) => field !== "photo" && field !== "document")
        .map((field) => (
        <div key={field}>
          <label
            className="block text-sm font-medium text-slate-700"
            htmlFor={field}
          >
            {FIELD_LABELS[field] ?? field}
          </label>
          <input
            id={field}
            type={field === "email" ? "email" : "text"}
            required
            className="mt-1 w-full rounded border border-slate-300 px-3 py-2"
            value={fields[field] ?? ""}
            onChange={(changeEvent) =>
              setFields((prev) => ({
                ...prev,
                [field]: changeEvent.target.value,
              }))
            }
          />
        </div>
      ))}

      {category?.custom_fields
        .filter((field) => field.field_type !== "file")
        .map((field) =>
          field.field_type === "checkbox" ? (
            <label
              key={field.id}
              className="flex items-center gap-2 text-sm text-slate-700"
            >
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
              <label
                className="block text-sm font-medium text-slate-700"
                htmlFor={field.id}
              >
                {field.label}
              </label>
              {field.field_type === "dropdown" ? (
                <select
                  id={field.id}
                  required={field.required}
                  className="mt-1 w-full rounded border border-slate-300 px-3 py-2"
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
                  className="mt-1 w-full rounded border border-slate-300 px-3 py-2"
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

      {isError && (
        <p className="text-sm text-red-600">{formatError(error)}</p>
      )}

      <button
        type="submit"
        disabled={isLoading || !categoryId}
        className="w-full rounded bg-blue-600 px-4 py-2 font-semibold text-white hover:bg-blue-700 disabled:opacity-50"
      >
        {isLoading ? "Submitting…" : "Submit"}
      </button>
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

function RegistrationModalInner({
  slug,
  accountSlug,
  eventName,
  ticketCategories,
}: {
  slug: string;
  accountSlug?: string;
  eventName: string;
  ticketCategories: TicketCategorySchema[];
}) {
  const [open, setOpen] = useState(false);

  if (ticketCategories.length === 0) return null;

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="fixed bottom-6 right-6 z-40 rounded-full bg-blue-600 px-6 py-3 font-semibold text-white shadow-lg hover:bg-blue-700"
      >
        Register
      </button>

      {open && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
          role="dialog"
          aria-modal="true"
          aria-labelledby="registration-modal-title"
        >
          <div className="w-full max-w-md rounded-lg bg-white p-6 shadow-xl">
            <div className="flex items-center justify-between">
              <h2
                id="registration-modal-title"
                className="text-lg font-semibold text-slate-900"
              >
                Register for {eventName}
              </h2>
              <button
                type="button"
                onClick={() => setOpen(false)}
                aria-label="Close"
                className="text-xl leading-none text-slate-500 hover:text-slate-800"
              >
                ×
              </button>
            </div>

            <RegistrationForm
              slug={slug}
              accountSlug={accountSlug}
              eventName={eventName}
              ticketCategories={ticketCategories}
              onClose={() => setOpen(false)}
            />
          </div>
        </div>
      )}
    </>
  );
}

export function RegistrationModal(
  props: Parameters<typeof RegistrationModalInner>[0],
) {
  return (
    <RegistrationStoreProvider>
      <RegistrationModalInner {...props} />
    </RegistrationStoreProvider>
  );
}
