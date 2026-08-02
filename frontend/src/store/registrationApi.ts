import { createApi, fetchBaseQuery } from "@reduxjs/toolkit/query/react";

// doc/public_event_site_options.md's own RTK Query plan: baseUrl points at a Next.js-hosted route
// handler (/api/register), never at Rails' OAuth-protected endpoint directly — the browser must
// keep going through the BFF exactly as everywhere else in this design.
export interface RegisterParticipantRequest {
  slug: string;
  // Only set by the shared-default-domain route (app/events/[tenantSlug]/[eventSlug]/page.tsx) —
  // /api/register's own Host header can't identify a tenant there (every visitor shares the same
  // host), so the tenant travels in the request body instead. Omitted on a tenant's own custom
  // domain, where Host alone is already enough.
  accountSlug?: string;
  // photo/document (registration-form.tsx's own FILE_CATALOG_FIELDS) may be real File objects —
  // the query fn below switches to a multipart FormData body whenever one is present, since a
  // File can't survive JSON.stringify.
  participant: Record<string, unknown>;
}

// True once any value here (top-level or nested under custom_field_values) is a File — the one
// signal that decides JSON vs. multipart below, since a plain object literal can't otherwise tell
// the difference between "this registration has an upload" and "it doesn't."
function hasFileValue(participant: Record<string, unknown>): boolean {
  const customFieldValues = participant.custom_field_values;
  const nested =
    customFieldValues && typeof customFieldValues === "object"
      ? Object.values(customFieldValues as Record<string, unknown>)
      : [];
  return [...Object.values(participant), ...nested].some((value) => value instanceof File);
}

// Rack/Rails' own nested-param convention (`participant[first_name]`, `participant[custom_field_
// values][<field_id>]`) — the one shape Api::V1::Public::ParticipantsController's strong params
// already expects, multipart or not, so the Next.js route handler (app/api/register/route.ts)
// can relay this FormData straight through without knowing anything about participant fields
// itself.
function toFormData(request: RegisterParticipantRequest): FormData {
  const formData = new FormData();
  formData.set("slug", request.slug);
  if (request.accountSlug) formData.set("accountSlug", request.accountSlug);

  for (const [key, value] of Object.entries(request.participant)) {
    if (key === "custom_field_values" && value && typeof value === "object") {
      for (const [fieldId, fieldValue] of Object.entries(value as Record<string, unknown>)) {
        if (fieldValue == null) continue;
        formData.append(
          `participant[custom_field_values][${fieldId}]`,
          fieldValue instanceof File ? fieldValue : String(fieldValue),
        );
      }
      continue;
    }
    if (value == null) continue;
    formData.append(`participant[${key}]`, value instanceof File ? value : String(value));
  }

  return formData;
}

export interface RegisterParticipantResponse {
  id: string;
  status: string;
  // requirement.md revisit: "post registration ... download button ... invitation PDF" — the
  // globally-unique, already-public-facing token (Participant#hex_id) needed to build the
  // download link (/api/invitation) immediately, with no extra lookup round-trip.
  hex_id: string;
}

export const registrationApi = createApi({
  reducerPath: "registrationApi",
  baseQuery: fetchBaseQuery({ baseUrl: "/api" }),
  endpoints: (builder) => ({
    registerParticipant: builder.mutation<
      RegisterParticipantResponse,
      RegisterParticipantRequest
    >({
      query: (request) => ({
        url: "register",
        method: "POST",
        body: hasFileValue(request.participant) ? toFormData(request) : request,
      }),
    }),
  }),
});

export const { useRegisterParticipantMutation } = registrationApi;
