import path from "node:path";
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Pins the workspace root to this directory — otherwise Turbopack walks up looking for the
  // nearest lockfile and can land on an unrelated one outside this repo (e.g. a stray
  // package-lock.json in a parent directory), which silently miscomputes file-watching/aliasing.
  turbopack: {
    root: path.join(__dirname),
  },
};

export default nextConfig;
