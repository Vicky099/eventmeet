import { configureStore } from "@reduxjs/toolkit";
import { registrationApi } from "./registrationApi";

// Scoped to the registration island only (doc's own plan) — most of the page is plain
// server-rendered content with nothing to put in a client store, so this is created fresh per
// RegistrationModal mount (store/provider.tsx), not shared app-wide.
export function makeRegistrationStore() {
  return configureStore({
    reducer: { [registrationApi.reducerPath]: registrationApi.reducer },
    middleware: (getDefaultMiddleware) =>
      getDefaultMiddleware().concat(registrationApi.middleware),
  });
}

export type RegistrationStore = ReturnType<typeof makeRegistrationStore>;
