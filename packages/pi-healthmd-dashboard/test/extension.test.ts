import assert from "node:assert/strict";
import { chmod, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import test from "node:test";
import healthmdDashboardExtension from "../src/extension.js";

interface FakePi {
  tools: Map<string, any>;
  commands: Map<string, any>;
  flags: Map<string, any>;
  handlers: Map<string, any>;
  registerTool(tool: any): void;
  registerCommand(name: string, command: any): void;
  registerFlag(name: string, flag: any): void;
  getFlag(name: string): unknown;
  on(event: string, handler: any): void;
}

function fakePi(flagValues: Record<string, unknown> = {}): FakePi {
  const api: FakePi = {
    tools: new Map(), commands: new Map(), flags: new Map(), handlers: new Map(),
    registerTool(tool) { this.tools.set(tool.name, tool); },
    registerCommand(name, command) { this.commands.set(name, command); },
    registerFlag(name, flag) { this.flags.set(name, flag); },
    getFlag(name) { return flagValues[name]; },
    on(event, handler) { this.handlers.set(event, handler); },
  };
  return api;
}

test("registers tools, starts with the compact widget hidden, and synchronizes show/hide/reset", async () => {
  const cache = await mkdtemp(join(tmpdir(), "healthmd-empty-cache-"));
  const pi = fakePi({ "healthmd-cache-dir": cache });
  healthmdDashboardExtension(pi as any);
  assert.deepEqual([...pi.tools.keys()], ["healthmd_load", "healthmd_fetch", "healthmd_query", "healthmd_view"]);
  assert.ok(pi.commands.has("healthmd"));
  for (const flag of ["healthmd-data", "healthmd-cache-dir", "healthmd-cli-path", "healthmd-mcp-path", "healthmd-fetch-transport", "healthmd-device", "healthmd-port"]) assert.ok(pi.flags.has(flag));
  const widgets: unknown[][] = [];
  let dashboardLines: string[] = [], dashboardOptions: any;
  const theme = { fg: (_color: string, text: string) => text, bg: (_color: string, text: string) => text, bold: (text: string) => text };
  const ctx = { hasUI: true, mode: "tui", cwd: process.cwd(), ui: {
    setWidget: (...args: unknown[]) => widgets.push(args), notify() {},
    async custom(factory: any, options: any) { dashboardOptions = options; const component = factory({ requestRender() {} }, theme, {}, () => {}); dashboardLines = component.render(120); },
  } };
  await pi.handlers.get("session_start")({ type: "session_start", reason: "startup" }, ctx);
  assert.equal(widgets.at(-1)?.[1], undefined);
  await pi.commands.get("healthmd").handler("dashboard", ctx);
  assert.match(dashboardLines.join("\n"), /Welcome to Health\.md/);
  assert.match(dashboardLines.join("\n"), /30 days is recommended/);
  assert.match(dashboardLines.join("\n"), /F fetch/);

  const fixture = resolve(import.meta.dirname, "../../../packages/contracts/proposals/unified-health-data-v9/fixtures/apple-minimal.json");
  await pi.commands.get("healthmd").handler(`load ${fixture}`, ctx);
  assert.equal(widgets.at(-1)?.[1], undefined);
  await pi.commands.get("healthmd").handler("dashboard", ctx);
  assert.equal(dashboardOptions.overlay, true);
  assert.match(dashboardLines.join("\n"), /interactive health evidence dashboard/);
  assert.match(dashboardLines.join("\n"), /steps/i);

  await pi.tools.get("healthmd_view").execute("show", { action: "show" }, undefined, undefined, ctx);
  let shownFactory = widgets.at(-1)?.[1] as ((tui: unknown, theme: unknown) => { render(width: number): string[] });
  assert.match(shownFactory({}, {}).render(80).join("\n"), /EXPERIMENTAL proposed v9 reader/);
  assert.match(shownFactory({}, {}).render(80).join("\n"), /Coverage:/);
  await pi.tools.get("healthmd_view").execute("hide", { action: "hide" }, undefined, undefined, ctx);
  assert.equal(widgets.at(-1)?.[1], undefined);
  await pi.tools.get("healthmd_view").execute("reset", { action: "reset" }, undefined, undefined, ctx);
  assert.equal(widgets.at(-1)?.[1], undefined);
  await pi.tools.get("healthmd_view").execute("show", { action: "show" }, undefined, undefined, ctx);
  shownFactory = widgets.at(-1)?.[1] as ((tui: unknown, theme: unknown) => { render(width: number): string[] });
  assert.match(shownFactory({}, {}).render(80).join("\n"), /Coverage:/);
  await pi.commands.get("healthmd").handler("reset", ctx);
  assert.equal(widgets.at(-1)?.[1], undefined);

  for (const tool of pi.tools.values()) {
    assert.ok(tool.promptGuidelines.some((line: string) => /diagnos/i.test(line)));
    assert.ok(tool.promptGuidelines.some((line: string) => /WHOOP HRV/i.test(line)));
  }
});

test("user-authored load command accepts an explicit path containing spaces", async () => {
  const pi = fakePi();
  healthmdDashboardExtension(pi as any);
  const directory = await mkdtemp(join(tmpdir(), "healthmd path with spaces "));
  const file = join(directory, "daily export.json");
  await writeFile(file, JSON.stringify({ date: "2026-01-01", type: "health-data", steps: 1 }));
  const notifications: string[] = [];
  const ctx = { hasUI: true, mode: "tui", cwd: process.cwd(), ui: { setWidget() {}, notify(message: string) { notifications.push(message); } } };
  await pi.commands.get("healthmd").handler(`load ${file}`, ctx);
  assert.match(notifications.at(-1) ?? "", /1 documents/);
});

test("healthmd_fetch uses configured CLI and makes its response queryable in memory", async () => {
  const directory = await mkdtemp(join(tmpdir(), "healthmd-extension-fetch-"));
  const executable = join(directory, "healthmd");
  const digest = "a".repeat(64);
  const response = { schema: "healthmd.query_response", schema_version: 1, items: [{ type: "metric", metric: { metric_id: "steps", display_name: "Steps", owner_date: "2026-03-15", status: "available", value: { type: "count", value: 123 }, evidence: [{ evidence_id: "steps-evidence", locator: { type: "summary_key", owner_date: "2026-03-15", key: "steps" }, source_id: "apple_health", source: { schema: "healthmd.health_data", schema_version: 8, digest } }], limitations: [] } }], coverage: { status: "available", days_considered: 1, days_with_values: 1, missing: [] }, sources: [], evidence: [], limitations: [], next_cursor: null };
  await writeFile(executable, `#!/usr/bin/env node\nprocess.stdout.write(${JSON.stringify(JSON.stringify(response))});\n`);
  await chmod(executable, 0o755);
  const cache = join(directory, "cache");
  const flags = { "healthmd-cli-path": executable, "healthmd-fetch-transport": "cli", "healthmd-cache-dir": cache };
  const pi = fakePi(flags);
  healthmdDashboardExtension(pi as any);
  const ctx = { hasUI: false, mode: "print", cwd: process.cwd(), ui: { setWidget() { throw new Error("TUI used in print mode"); } } };
  await pi.handlers.get("session_start")({ type: "session_start", reason: "startup" }, ctx);
  const fetched = await pi.tools.get("healthmd_fetch").execute("fetch", { operation: "healthmd_metric_chart", arguments: { dates: { type: "all_available" }, metrics: { type: "explicit", metric_ids: ["steps"] } } }, undefined, undefined, ctx);
  assert.match(fetched.content[0].text, /healthmd-cli/);
  assert.match(fetched.content[0].text, /cache/);
  const queried = await pi.tools.get("healthmd_query").execute("query", { metric: "steps", limit: 20 }, undefined, undefined, ctx);
  assert.match(queried.content[0].text, /apple_health/);
  assert.match(queried.content[0].text, /123/);

  const manifestPath = join(cache, "healthmd-cache.json"), validManifest = await readFile(manifestPath, "utf8"), revised: any = structuredClone(response);
  revised.items[0].metric.value.value = 999;
  await writeFile(executable, `#!/usr/bin/env node\nprocess.stdout.write(${JSON.stringify(JSON.stringify(revised))});\n`);
  await chmod(executable, 0o755);
  await writeFile(manifestPath, "{invalid");
  await assert.rejects(pi.tools.get("healthmd_fetch").execute("fetch-atomic", { operation: "healthmd_metric_chart", arguments: { dates: { type: "all_available" }, metrics: { type: "explicit", metric_ids: ["steps"] } } }, undefined, undefined, ctx));
  const afterFailedCache = await pi.tools.get("healthmd_query").execute("query-atomic", { metric: "steps", limit: 20 }, undefined, undefined, ctx);
  assert.match(afterFailedCache.content[0].text, /123/);
  assert.doesNotMatch(afterFailedCache.content[0].text, /999/);
  await writeFile(manifestPath, validManifest);

  const restored = fakePi(flags);
  healthmdDashboardExtension(restored as any);
  await restored.handlers.get("session_start")({ type: "session_start", reason: "startup" }, ctx);
  const restoredQuery = await restored.tools.get("healthmd_query").execute("query", { metric: "steps", limit: 20 }, undefined, undefined, ctx);
  assert.match(restoredQuery.content[0].text, /123/);
});

test("headless slash-command fetch failures are not swallowed", async () => {
  const directory = await mkdtemp(join(tmpdir(), "healthmd-extension-failed-fetch-"));
  const executable = join(directory, "healthmd");
  await writeFile(executable, `#!/usr/bin/env node\nprocess.stdout.write(JSON.stringify({error:"healthmd_unavailable",message:"No paired source."})); process.exitCode=1;\n`);
  await chmod(executable, 0o755);
  const pi = fakePi({ "healthmd-cli-path": executable, "healthmd-fetch-transport": "cli" });
  healthmdDashboardExtension(pi as any);
  const ctx = { hasUI: false, mode: "rpc", cwd: process.cwd(), ui: { setWidget() {} } };
  await assert.rejects(pi.commands.get("healthmd").handler(`fetch healthmd_metric_chart {}`, ctx), /healthmd_unavailable: No paired source/);
});

test("extension implementation never invokes confirmation or custom-entry persistence", async () => {
  const source = await readFile(resolve(import.meta.dirname, "../src/extension.ts"), "utf8");
  assert.doesNotMatch(source, /\.confirm\s*\(/);
  assert.doesNotMatch(source, /appendEntry|customType|sendMessage/);
});

test("tools load/query/view in print mode without touching TUI", async () => {
  const pi = fakePi();
  healthmdDashboardExtension(pi as any);
  const fixture = resolve(import.meta.dirname, "../../../packages/contracts/proposals/unified-health-data-v9/fixtures/apple-minimal.json");
  const ctx = { hasUI: false, mode: "print", cwd: process.cwd(), ui: { setWidget() { throw new Error("TUI used in print mode"); } } };
  await pi.commands.get("healthmd").handler(`load ${fixture}`, ctx);
  const loaded = await pi.tools.get("healthmd_load").execute("1", { paths: [fixture] }, undefined, undefined, ctx);
  assert.match(loaded.content[0].text, /proposed v9 readers 1/);
  assert.ok(Buffer.byteLength(loaded.content[0].text, "utf8") < 50_000);
  assert.deepEqual(loaded.details, { bounded: true, chars: loaded.content[0].text.length, bytes: Buffer.byteLength(loaded.content[0].text, "utf8") });
  const queried = await pi.tools.get("healthmd_query").execute("2", { metric: "steps", limit: 5 }, undefined, undefined, ctx);
  assert.match(queried.content[0].text, /steps/);
  const viewed = await pi.tools.get("healthmd_view").execute("3", { action: "select", target: "steps", targetKind: "metric" }, undefined, undefined, ctx);
  assert.match(viewed.content[0].text, /steps/);
});
