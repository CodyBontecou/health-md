import type { ExtensionAPI, ExtensionCommandContext, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { StringEnum } from "@earendil-works/pi-ai";
import { Type } from "typebox";
import { configuredCacheDirectory, forgetCacheDirectory, loadCachedEvidence, persistFetchedEvidence, rememberCacheDirectory, type PersistedCacheReceipt } from "./cache.js";
import { FullDashboardComponent } from "./dashboard.js";
import { boundedJson, truncateUtf8, utf8ByteLength } from "./json.js";
import { canonicalRoot, loadHealthData, loadHealthDataText, requireApprovedPath, storeSummary, type InMemoryJsonInput } from "./loader.js";
import type { HealthStore, QueryOptions, ViewState } from "./model.js";
import { initialView } from "./model.js";
import { formatEvidence, queryStore } from "./query.js";
import { renderDashboard } from "./render.js";
import { fetchHealthMd, HEALTHMD_READ_OPERATIONS, type HealthMdFetchOptions, type HealthMdReadOperation, type HealthMdSourceConfig } from "./source.js";
import { updateView, type ViewAction } from "./view.js";

const WIDGET_KEY = "healthmd-dashboard";
const MAX_TOOL_BYTES = 45_000;
const GUIDELINES = [
  "Tool evidence enters model context and may be retained in Pi session/JSON output; load or fetch only data the user intends to disclose to the model.",
  "healthmd_fetch may contact a paired foreground iPhone through the configured Health.md CLI or read-only MCP stdio server; use explicit bounded dates and metrics whenever possible.",
  "Never invent equivalence between platform/provider facts; preserve semantic ID, statistic, unit, platform, provider, provenance, capture status, and coverage.",
  "WHOOP HRV RMSSD remains provider data and must never be merged into HealthKit SDNN or Health Connect RMSSD metrics.",
  "Do not make medical diagnoses. Describe only bounded evidence loaded from approved roots or explicitly fetched through the configured read-only Health.md source.",
  "healthmd.health_data v9 unified-cross-platform-v1 is proposed/experimental reader support, not evidence of a shipped writer.",
];

export interface DashboardController {
  getStore(): HealthStore | undefined;
  getView(): ViewState;
  approvedRoots(): readonly string[];
  approveAndLoad(paths: string[]): Promise<HealthStore>;
  loadApproved(paths: string[]): Promise<HealthStore>;
  loadFetched(input: InMemoryJsonInput): HealthStore;
  loadFetchedMany(inputs: InMemoryJsonInput[]): HealthStore;
  replaceStore(store: HealthStore): HealthStore;
  query(options: QueryOptions): object;
  view(action: ViewAction, options?: Omit<Parameters<typeof updateView>[1], "action">): ViewState;
  reset(): void;
}

function textResult(value: unknown) {
  const text = typeof value === "string" ? truncateUtf8(value, MAX_TOOL_BYTES, "\n…[tool output truncated]") : boundedJson(value, MAX_TOOL_BYTES);
  return { content: [{ type: "text" as const, text }], details: { bounded: true, chars: text.length, bytes: utf8ByteLength(text) } };
}

export function createController(onChange: () => void = () => {}, initiallyVisible = true): DashboardController {
  let store: HealthStore | undefined;
  const resetView = (): ViewState => ({ ...initialView(), visible: initiallyVisible });
  let view = resetView();
  const roots = new Set<string>();
  const performLoad = async (paths: string[], confinementRoots: readonly string[]) => { store = await loadHealthData(paths, {}, confinementRoots); onChange(); return store; };
  return {
    getStore: () => store, getView: () => view, approvedRoots: () => [...roots],
    async approveAndLoad(paths) { const canonical = await Promise.all(paths.map(canonicalRoot)); canonical.forEach(root => roots.add(root)); return performLoad(canonical, canonical); },
    async loadApproved(paths) { const canonical = await Promise.all(paths.map(path => requireApprovedPath(path, [...roots]))); return performLoad(canonical, [...roots]); },
    loadFetched(input) { store = loadHealthDataText([input]); onChange(); return store; },
    loadFetchedMany(inputs) { store = loadHealthDataText(inputs); onChange(); return store; },
    replaceStore(nextStore) { store = nextStore; onChange(); return store; },
    query(options) { if (!store) throw new Error("No Health.md evidence loaded. Use /healthmd load or healthmd_fetch first."); return formatEvidence(queryStore(store, options)); },
    view(action, options = {}) { view = updateView(view, { action, ...options }); onChange(); return view; },
    reset() { store = undefined; view = resetView(); roots.clear(); onChange(); },
  };
}

export default function healthmdDashboardExtension(pi: ExtensionAPI): void {
  let lastContext: ExtensionContext | undefined;
  const refresh = () => {
    if (!lastContext?.hasUI || lastContext.mode !== "tui") return;
    const controllerView = controller.getView();
    if (!controllerView.visible) lastContext.ui.setWidget(WIDGET_KEY, undefined);
    else lastContext.ui.setWidget(WIDGET_KEY, (_tui, _theme) => ({ render: (width: number) => renderDashboard(controller.getStore(), controllerView, width), invalidate() {} }), { placement: "aboveEditor" });
  };
  const controller = createController(refresh, false);
  let cacheDirectory: string | undefined;
  let lastFetchedInput: InMemoryJsonInput | undefined;
  pi.registerFlag("healthmd-data", { type: "string", description: "Approve and load a Health.md JSON root read-only at startup" });
  pi.registerFlag("healthmd-cache-dir", { type: "string", description: "Persist validated fetched evidence and restore it across Pi reloads" });
  pi.registerFlag("healthmd-cli-path", { type: "string", description: "Health.md CLI executable (default: healthmd on PATH)" });
  pi.registerFlag("healthmd-mcp-path", { type: "string", description: "Standalone Health.md MCP stdio helper; omit to use healthmd mcp serve-read-only" });
  pi.registerFlag("healthmd-fetch-transport", { type: "string", description: "Default fetched-data transport: mcp (default) or cli" });
  pi.registerFlag("healthmd-device", { type: "string", description: "Explicit paired Health.md device UUID for the portable CLI" });
  pi.registerFlag("healthmd-port", { type: "string", description: "Explicit Health.md direct Manual IP port" });

  const flagString = (name: string): string | undefined => { const value = pi.getFlag(name); return typeof value === "string" && value.trim() ? value.trim() : undefined; };
  const sourceConfig = (): HealthMdSourceConfig => {
    const portText = flagString("healthmd-port") ?? process.env.HEALTHMD_CLI_PORT;
    const transport = flagString("healthmd-fetch-transport") ?? process.env.HEALTHMD_FETCH_TRANSPORT;
    let defaultTransport: "cli" | "mcp" | undefined;
    if (transport === "cli" || transport === "mcp") defaultTransport = transport;
    else if (transport) throw new Error("HEALTHMD fetch transport must be cli or mcp");
    const mcpExecutable = flagString("healthmd-mcp-path") ?? process.env.HEALTHMD_MCP_PATH;
    const deviceId = flagString("healthmd-device") ?? process.env.HEALTHMD_DEVICE_ID;
    return {
      cliExecutable: flagString("healthmd-cli-path") ?? process.env.HEALTHMD_CLI_PATH ?? "healthmd",
      ...(mcpExecutable ? { mcpExecutable } : {}), ...(deviceId ? { deviceId } : {}),
      ...(portText ? { port: Number(portText) } : {}),
      ...(defaultTransport ? { defaultTransport } : {}),
    };
  };
  const fetchAndLoad = async (options: HealthMdFetchOptions, signal?: AbortSignal) => {
    const fetched = await fetchHealthMd(sourceConfig(), options, signal);
    const input: InMemoryJsonInput = { path: fetched.syntheticPath, text: fetched.text, origin: fetched.transport === "cli" ? "healthmd-cli" : "healthmd-mcp", operation: fetched.operation };
    let nextStore = loadHealthDataText([input]);
    let cache: PersistedCacheReceipt | undefined;
    if (cacheDirectory) {
      cache = await persistFetchedEvidence(cacheDirectory, { text: input.text, origin: input.origin as "healthmd-cli" | "healthmd-mcp", operation: fetched.operation });
      const cached = await loadCachedEvidence(cacheDirectory);
      if (cached.length) nextStore = loadHealthDataText(cached);
    }
    const store = controller.replaceStore(nextStore);
    lastFetchedInput = input;
    return { fetched, store, cache };
  };

  pi.registerTool({
    name: "healthmd_load", label: "Load approved Health.md JSON",
    description: "Load JSON only at/below roots approved by --healthmd-data, HEALTHMD_DATA_PATH, or user-authored /healthmd load. No confirmation is requested.",
    promptSnippet: "Load read-only Health.md JSON from an already approved realpath root.", promptGuidelines: GUIDELINES,
    parameters: Type.Object({ paths: Type.Array(Type.String({ minLength: 1 }), { minItems: 1, maxItems: 32 }) }),
    async execute(_id, params, _signal, _update, ctx) {
      lastContext = ctx;
      const store = await controller.loadApproved(params.paths);
      const documents = store.documents.slice(0, 100).map(({ value: _value, contractErrors, ...document }) => ({ ...document, contractErrors: contractErrors.slice(0, 10) }));
      return textResult({ summary: storeSummary(store), disclosure: "Loaded evidence enters model context and Pi session/JSON output.", warnings: store.warnings.slice(0, 100), references: store.references.slice(0, 100), documentCount: store.documents.length, documents, omittedDocuments: store.documents.length - documents.length });
    },
  });

  pi.registerTool({
    name: "healthmd_fetch", label: "Fetch Health.md evidence",
    description: "Run one fixed read-only typed Health.md operation through the configured CLI or MCP stdio server, then replace the in-memory dashboard store with its bounded canonical JSON response. MCP uses serve-read-only and no transport fallback occurs.",
    promptSnippet: "Fetch bounded typed evidence from a paired foreground iPhone through explicit Health.md CLI/MCP configuration.", promptGuidelines: GUIDELINES,
    parameters: Type.Object({
      operation: StringEnum(HEALTHMD_READ_OPERATIONS),
      arguments: Type.Object({}, { additionalProperties: true }),
      transport: Type.Optional(StringEnum(["mcp", "cli"] as const)),
      timeoutSeconds: Type.Optional(Type.Integer({ minimum: 1, maximum: 3_600 })),
    }),
    async execute(_id, params, signal, _update, ctx) {
      lastContext = ctx;
      const { fetched, store, cache } = await fetchAndLoad({ operation: params.operation, arguments: params.arguments as HealthMdFetchOptions["arguments"], ...(params.transport ? { transport: params.transport } : {}), ...(params.timeoutSeconds ? { timeoutSeconds: params.timeoutSeconds } : {}) }, signal);
      const document = store.documents[0];
      return textResult({
        summary: storeSummary(store), operation: fetched.operation, transport: fetched.transport, fetchedBytes: fetched.bytes,
        contract: document ? { kind: document.contractKind, valid: document.contractValid, schema: document.schema, schemaVersion: document.schemaVersion, origin: document.origin } : undefined,
        warnings: store.warnings, ...(cache ? { cache: { directory: cache.directory, file: cache.file, digest: cache.digest } } : {}), disclosure: cache ? "Fetched evidence is held in memory and persisted in the explicitly configured Health.md cache directory." : "Fetched evidence is held in memory for healthmd_query/healthmd_view and may enter model context or Pi session output.",
      });
    },
  });

  pi.registerTool({
    name: "healthmd_query", label: "Query Health.md evidence", description: "Query loaded or fetched contracts by semantic metric, generic JSON path, or text. Returns strictly bounded model-visible evidence.",
    promptSnippet: "Query bounded evidence across every loaded Health.md JSON path.", promptGuidelines: GUIDELINES,
    parameters: Type.Object({ path: Type.Optional(Type.String()), search: Type.Optional(Type.String()), metric: Type.Optional(Type.String()), limit: Type.Optional(Type.Integer({ minimum: 1, maximum: 100 })), offset: Type.Optional(Type.Integer({ minimum: 0 })) }),
    async execute(_id, params, _signal, _update, ctx) { lastContext = ctx; return textResult(controller.query(params)); },
  });

  pi.registerTool({
    name: "healthmd_view", label: "Control Health.md dashboard", description: "Show/hide and control the compact persistent dashboard.",
    promptSnippet: "Control the dashboard without confirmation.", promptGuidelines: GUIDELINES,
    parameters: Type.Object({
      action: StringEnum(["show", "hide", "select", "focus", "mode", "date_window", "zoom_in", "zoom_out", "pan_left", "pan_right", "reset"] as const),
      target: Type.Optional(Type.String()), targetKind: Type.Optional(StringEnum(["metric", "path", "search"] as const)),
      mode: Type.Optional(StringEnum(["chart", "table"] as const)), startDate: Type.Optional(Type.String()), endDate: Type.Optional(Type.String()),
    }),
    async execute(_id, params, _signal, _update, ctx) { lastContext = ctx; const { action, ...options } = params; return textResult(controller.view(action, options)); },
  });

  const localDate = (date: Date): string => `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
  const guidedFetch = async (days: 7 | 30 | 90, metricIds: string[], signal?: AbortSignal): Promise<void> => {
    const end = new Date(), start = new Date(end.getFullYear(), end.getMonth(), end.getDate() - days + 1);
    const argumentsValue: HealthMdFetchOptions["arguments"] = {
      all_pages: true,
      dates: { type: "exact", range: { start_date: localDate(start), end_date: localDate(end) } },
      metrics: metricIds.length ? { type: "explicit", metric_ids: metricIds } : { type: "all_available" },
      detail_level: "summary",
    };
    await fetchAndLoad({ operation: "healthmd_metric_chart", arguments: argumentsValue, timeoutSeconds: 300 }, signal);
  };
  const openFullDashboard = async (ctx: ExtensionCommandContext) => {
    if (ctx.mode !== "tui") { if (ctx.hasUI) ctx.ui.notify("The full Health.md dashboard requires interactive TUI mode", "error"); return; }
    let dashboardHeight = 30;
    await ctx.ui.custom<void>((tui, theme, _keybindings, done) => new FullDashboardComponent(tui, theme, controller.getStore, () => done(), () => dashboardHeight, (days, metricIds, signal) => guidedFetch(days, metricIds, ctx.signal ? AbortSignal.any([ctx.signal, signal]) : signal)), {
      overlay: true,
      overlayOptions: { width: "96%", maxHeight: "95%", anchor: "center", margin: 1, visible: (_terminalWidth, terminalHeight) => { dashboardHeight = Math.max(1, Math.floor((terminalHeight - 2) * 0.95)); return true; } },
    });
  };

  pi.registerCommand("healthmd", {
    description: "Health.md dashboard: dashboard/load/fetch/cache/show/hide/reset/status",
    async handler(args, ctx) {
      lastContext = ctx;
      const trimmed = args.trim();
      const separator = trimmed.search(/\s/);
      const command = (separator === -1 ? trimmed : trimmed.slice(0, separator)) || "status";
      const argument = separator === -1 ? "" : trimmed.slice(separator).trim();
      try {
        if (command === "load") { if (!argument) throw new Error("Usage: /healthmd load <file-or-directory>"); const store = await controller.approveAndLoad([argument]); if (ctx.hasUI) ctx.ui.notify(storeSummary(store), "info"); }
        else if (command === "fetch") {
          const operationSeparator = argument.search(/\s/);
          if (operationSeparator < 1) throw new Error("Usage: /healthmd fetch <operation> <JSON-object>");
          const operation = argument.slice(0, operationSeparator);
          if (!(HEALTHMD_READ_OPERATIONS as readonly string[]).includes(operation)) throw new Error(`Unsupported read-only Health.md operation: ${operation}`);
          const parsed = JSON.parse(argument.slice(operationSeparator).trim()) as unknown;
          if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("Health.md query arguments must be one JSON object");
          const { store } = await fetchAndLoad({ operation: operation as HealthMdReadOperation, arguments: parsed as HealthMdFetchOptions["arguments"] }, ctx.signal);
          if (ctx.hasUI) ctx.ui.notify(storeSummary(store), "info");
        }
        else if (command === "dashboard") await openFullDashboard(ctx);
        else if (command === "cache") {
          if (!argument) throw new Error("Usage: /healthmd cache <directory|off>");
          if (argument === "off") { await forgetCacheDirectory(); cacheDirectory = undefined; if (ctx.hasUI) ctx.ui.notify("Health.md persistent cache disabled; existing cached files were retained", "info"); }
          else {
            cacheDirectory = await rememberCacheDirectory(argument);
            if (lastFetchedInput) await persistFetchedEvidence(cacheDirectory, { text: lastFetchedInput.text, origin: lastFetchedInput.origin as "healthmd-cli" | "healthmd-mcp", operation: lastFetchedInput.operation ?? "unknown" });
            else { const cached = await loadCachedEvidence(cacheDirectory); if (cached.length) controller.loadFetchedMany(cached); }
            if (ctx.hasUI) ctx.ui.notify(`Health.md persistent cache: ${cacheDirectory}`, "info");
          }
        }
        else if (command === "show" || command === "hide") controller.view(command);
        else if (command === "reset") controller.reset();
        else if (command === "status") { if (ctx.hasUI) ctx.ui.notify(`${controller.getStore() ? storeSummary(controller.getStore()!) : "No Health.md evidence loaded"}; cache ${cacheDirectory ?? "disabled"}`, "info"); }
        else throw new Error("Usage: /healthmd dashboard|load|fetch|cache|show|hide|reset|status");
      } catch (error) {
        if (ctx.hasUI) ctx.ui.notify(error instanceof Error ? error.message : String(error), "error");
        else throw error;
      }
    },
  });

  pi.on("session_start", async (_event, ctx) => {
    lastContext = ctx; refresh();
    const explicitCache = flagString("healthmd-cache-dir") ?? process.env.HEALTHMD_CACHE_DIR;
    try {
      cacheDirectory = await configuredCacheDirectory(explicitCache);
      if (cacheDirectory) { const cached = await loadCachedEvidence(cacheDirectory); if (cached.length) { controller.loadFetchedMany(cached); if (ctx.hasUI) ctx.ui.notify(`Restored ${cached.length} cached Health.md response${cached.length === 1 ? "" : "s"}`, "info"); } }
    } catch (error) { if (ctx.hasUI) ctx.ui.notify(`Health.md cache restore failed: ${error instanceof Error ? error.message : String(error)}`, "error"); else throw error; }
    const startup = pi.getFlag("healthmd-data") || process.env.HEALTHMD_DATA_PATH;
    if (typeof startup === "string" && startup.trim()) try { await controller.approveAndLoad([startup]); if (ctx.hasUI) ctx.ui.notify(storeSummary(controller.getStore()!), "info"); } catch (error) { if (ctx.hasUI) ctx.ui.notify(`Health.md startup load failed: ${error instanceof Error ? error.message : String(error)}`, "error"); else throw error; }
  });
}
