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
  participant: Record<string, unknown>;
}

export interface RegisterParticipantResponse {
  id: string;
  status: string;
}

export const registrationApi = createApi({
  reducerPath: "registrationApi",
  baseQuery: fetchBaseQuery({ baseUrl: "/api" }),
  endpoints: (builder) => ({
    registerParticipant: builder.mutation<
      RegisterParticipantResponse,
      RegisterParticipantRequest
    >({
      query: (body) => ({ url: "register", method: "POST", body }),
    }),
  }),
});

export const { useRegisterParticipantMutation } = registrationApi;
