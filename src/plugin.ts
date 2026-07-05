/**
 * The Forge — runtime plugin entry (SDK edition).
 *
 * `node build.mjs` bundles this file + all its imports + deps into a single
 * self-contained `dist/index.mjs`; `./publish.sh` commits ONLY that artifact
 * (+ manifest.json) to the dist-only `release` branch operators install from.
 * The server dynamically imports the bundle and calls `register(host)` once.
 *
 * Built with @rewind/addon-sdk `defineAddon`, so the register() result carries
 * both surfaces:
 *   • `api`      — the typed facade rewind_server's stream code calls directly
 *                  (syncNativeStreams / resolveStream, unchanged contract).
 *   • `resources`— the unified protocol handlers (`stream`, `resolve`) served
 *                  at /api/addons/forge/<resource>/<type>/<id>.json.
 */
import { defineAddon, type AddonManifest, type ResourceRequest } from "@sdk";

import { setForgeHost, type ForgeHost } from "@forge/host";
import { syncNativeStreams as pipelineSync, resolveStream } from "@forge/pipeline";
import { parseStreamPrefs } from "@forge/filter";
import { parseFormatterConfig } from "@forge/formatter";
import type { StreamQuery, StreamPreferencesRow } from "@forge/types";

import manifestJson from "../manifest.json";

function buildApi() {
  return {
    syncNativeStreams(opts: {
      itemId: string;
      query: StreamQuery;
      prefsRow: StreamPreferencesRow;
      preferredReleaseGroup?: string | null;
      formatterJson?: string | null;
      episodeName?: string | null;
    }) {
      return pipelineSync({
        itemId: opts.itemId,
        query: opts.query,
        prefs: parseStreamPrefs(opts.prefsRow),
        preferredReleaseGroup: opts.preferredReleaseGroup ?? null,
        formatter: parseFormatterConfig(
          opts.formatterJson ? JSON.parse(opts.formatterJson) : null,
        ),
        episodeName: opts.episodeName ?? null,
      });
    },
    resolveStream,
  };
}
export type ForgeApi = ReturnType<typeof buildApi>;

/** Map a unified stream request onto the pipeline's StreamQuery. The id is an
 *  imdb tt-id or "tmdb:<n>"; season/episode ride in as extra props. */
function queryFromRequest({ type, id, extra }: ResourceRequest): StreamQuery {
  const num = (v: unknown): number | undefined => {
    const n = Number(v);
    return Number.isFinite(n) && n > 0 ? n : undefined;
  };
  return {
    kind: type === "movie" ? "movie" : "series",
    imdbId: /^tt\d+/.test(id) ? id : undefined,
    tmdbId: id.startsWith("tmdb:") ? id.slice(5) : undefined,
    title: typeof extra.title === "string" ? extra.title : undefined,
    year: num(extra.year),
    season: num(extra.season),
    episode: num(extra.episode),
  };
}

export const addon = defineAddon({
  manifest: manifestJson as AddonManifest,
  setup(host: ForgeHost) {
    setForgeHost(host);
    const api = buildApi();
    return {
      api,
      resources: {
        // stream/<movie|series|episode>/<tt…|tmdb:…>.json — search + cache
        // streams for the item. `extra` carries the embedder's prefs row +
        // formatter JSON (the pipeline needs the operator's filter/sort/format
        // settings; they are the embedder's data, not the addon's).
        stream: async (req) => {
          const streams = await api.syncNativeStreams({
            itemId: String(req.extra.itemId ?? req.id),
            query: queryFromRequest(req),
            prefsRow: (req.extra.prefsRow ?? {}) as StreamPreferencesRow,
            preferredReleaseGroup: (req.extra.preferredReleaseGroup as string | null) ?? null,
            formatterJson: (req.extra.formatterJson as string | null) ?? null,
            episodeName: (req.extra.episodeName as string | null) ?? null,
          });
          return { streams };
        },
        // resolve/<type>/<id>.json — turn one chosen candidate into a URL.
        resolve: async ({ extra }) => {
          const url = await api.resolveStream(
            (extra.stream ?? {}) as Parameters<ForgeApi["resolveStream"]>[0],
            extra.hint as { season?: number; episode?: number } | undefined,
          );
          return { url };
        },
      },
    };
  },
});

export const manifest = addon.manifest;
export const register = addon.register;
