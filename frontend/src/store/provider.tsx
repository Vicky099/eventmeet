"use client";

import { useState } from "react";
import { Provider } from "react-redux";
import { makeRegistrationStore } from "./index";

// One store per mount (useState initializer, not a module-level singleton) — the standard
// Redux+Next.js SSR-safe pattern, even though this Provider only ever actually runs client-side
// ("use client") since RegistrationModal itself is a Client Component.
export function RegistrationStoreProvider({
  children,
}: {
  children: React.ReactNode;
}) {
  const [store] = useState(() => makeRegistrationStore());

  return <Provider store={store}>{children}</Provider>;
}
