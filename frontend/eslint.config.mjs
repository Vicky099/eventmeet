import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";

const eslintConfig = defineConfig([
  ...nextVitals,
  ...nextTs,
  // Override default ignores of eslint-config-next.
  globalIgnores([
    // Default ignores of eslint-config-next:
    ".next/**",
    "out/**",
    "build/**",
    "next-env.d.ts",
    // doc/event_page_templates_plan.md, Stage 5 — auto-generated data files (a vendored
    // template's raw HTML body, extracted verbatim as a single JSON.stringify'd string constant),
    // not hand-written source. Linting them is both pointless (there's no real code to review,
    // just a giant string literal) and actively slow/noisy — ESLint's TypeScript parser produces
    // hundreds of spurious warnings/errors trying to analyze a ~200KB single-line string as if it
    // were normal source. Regenerate via the extraction script if these ever need to change,
    // rather than hand-editing them.
    "src/components/templates/raw/**",
    // Same Stage 5 — third-party vendored/minified JS (Swiper, GSAP, Lenis, ...) served as static
    // assets for the ported templates, not app source. `public/` had no JS files in this project
    // before this stage, so eslint-config-next's default scope never had reason to exclude it;
    // this is that exclusion, now that it does.
    "public/templates/**",
  ]),
]);

export default eslintConfig;
