import { configureStore } from "@reduxjs/toolkit";
import { registrationApi } from "./registrationApi";

// Scoped to the registration page only (doc's own plan) — created fresh per RegistrationPage
// mount (store/provider.tsx), not shared app-wide.
export function makeRegistrationStore() {
  return configureStore({
    reducer: { [registrationApi.reducerPath]: registrationApi.reducer },
    middleware: (getDefaultMiddleware) =>
      getDefaultMiddleware().concat(registrationApi.middleware),
  });
}

export type RegistrationStore = ReturnType<typeof makeRegistrationStore>;
