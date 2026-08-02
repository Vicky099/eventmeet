import path from "node:path";
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Pins the workspace root to this directory — otherwise Turbopack walks up looking for the
  // nearest lockfile and can land on an unrelated one outside this repo (e.g. a stray
  // package-lock.json in a parent directory), which silently miscomputes file-watching/aliasing.
  turbopack: {
    root: path.join(__dirname),
  },
  // This app is only ever reached in local dev via a tenant/agency subdomain of lvh.me
  // (xaniel.lvh.me, qa-tenant.lvh.me, ...), never bare "localhost" — Next.js's own dev-server
  // origin check (blocks cross-origin HMR/asset requests by default) doesn't know that in
  // advance, so every subdomain otherwise trips its "Blocked cross-origin request" warning and
  // breaks Fast Refresh. Dev-only concern (this option has no effect in production).
  allowedDevOrigins: ["lvh.me", "*.lvh.me"],
};

export default nextConfig;
