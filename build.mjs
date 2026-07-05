// Shared SDK bundler — src/plugin.ts (+ deps) → self-contained dist/index.mjs.
import { buildAddon } from "../rewind_addon_sdk/build.mjs";

await buildAddon();
