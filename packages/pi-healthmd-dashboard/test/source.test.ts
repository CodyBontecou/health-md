import assert from "node:assert/strict";
import { chmod, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { loadHealthDataText } from "../src/loader.js";
import { initialView } from "../src/model.js";
import { formatEvidence, queryStore } from "../src/query.js";
import { renderDashboard } from "../src/render.js";
import { fetchHealthMd } from "../src/source.js";
import { updateView } from "../src/view.js";

const digest = "a".repeat(64);
const response = {
  schema: "healthmd.query_response",
  schema_version: 1,
  items: [{
    type: "metric",
    metric: {
      metric_id: "steps",
      display_name: "Steps",
      owner_date: "2026-03-15",
      status: "available",
      value: { type: "count", value: 12_345 },
      evidence: [{ evidence_id: "evidence-steps", locator: { type: "summary_key", owner_date: "2026-03-15", key: "steps" }, source_id: "apple_health", source: { schema: "healthmd.health_data", schema_version: 8, digest } }],
      limitations: [],
    },
  }],
  coverage: { status: "available", days_considered: 1, days_with_values: 1, missing: [] },
  sources: [{ schema: "healthmd.health_data", schema_version: 8, digest }],
  evidence: [], limitations: [], next_cursor: null,
};

async function executable(directory: string, name: string, source: string): Promise<string> {
  const path = join(directory, name);
  await writeFile(path, `#!/usr/bin/env node\n${source}`);
  await chmod(path, 0o755);
  return path;
}

test("CLI typed queries are fetched without a shell and become provenance-aware dashboard evidence", async () => {
  const directory = await mkdtemp(join(tmpdir(), "healthmd-source-cli-"));
  const log = join(directory, "argv.json");
  const cli = await executable(directory, "fake healthmd", `
    const fs = require("node:fs");
    fs.writeFileSync(${JSON.stringify(log)}, JSON.stringify(process.argv.slice(2)));
    process.stdout.write(${JSON.stringify(JSON.stringify(response))});
  `);
  const fetched = await fetchHealthMd({ cliExecutable: cli, defaultTransport: "cli" }, {
    operation: "healthmd_metric_chart",
    arguments: { dates: { type: "all_available" }, metrics: { type: "explicit", metric_ids: ["steps"] } },
  });
  assert.equal(fetched.transport, "cli");
  const argv = JSON.parse(await readFile(log, "utf8"));
  assert.deepEqual(argv.slice(0, 2), ["query", "healthmd_metric_chart"]);
  assert.equal(argv.at(-2), "--timeout");
  assert.equal(argv.at(-1), "1200");

  const store = loadHealthDataText([{ path: fetched.syntheticPath, text: fetched.text, origin: "healthmd-cli", operation: fetched.operation }]);
  const value = store.entries.find(entry => entry.path.endsWith(".metric.value.value"));
  assert.equal(value?.semanticId, "steps");
  assert.equal(value?.unit, "count");
  assert.equal(value?.source, "apple_health");
  assert.equal(value?.origin, "healthmd-cli");
  const evidence = JSON.stringify(formatEvidence(queryStore(store, { metric: "steps", limit: 100 })));
  assert.match(evidence, /apple_health/);
  assert.match(evidence, /healthmd-cli/);
  let view = updateView(initialView(), { action: "select", target: "steps", targetKind: "metric" });
  view = updateView(view, { action: "mode", mode: "chart" });
  assert.match(renderDashboard(store, view, 100).join("\n"), /12345 count/);
});

test("standalone read-only MCP stdio queries are initialized, called, and ingested", async () => {
  const directory = await mkdtemp(join(tmpdir(), "healthmd-source-mcp-"));
  const mcp = await executable(directory, "fake-mcp", `
    const readline = require("node:readline");
    const payload = ${JSON.stringify(response)};
    const rl = readline.createInterface({ input: process.stdin });
    rl.on("line", line => {
      const request = JSON.parse(line);
      if (request.method === "initialize") process.stdout.write(JSON.stringify({ jsonrpc: "2.0", id: request.id, result: { protocolVersion: "2025-11-25", capabilities: { tools: {} }, serverInfo: { name: "fake", version: "1" } } }) + "\\n");
      if (request.method === "tools/call") process.stdout.write(JSON.stringify({ jsonrpc: "2.0", id: request.id, result: { content: [{ type: "text", text: JSON.stringify(payload) }], isError: false } }) + "\\n");
    });
  `);
  const fetched = await fetchHealthMd({ cliExecutable: "unused", mcpExecutable: mcp }, {
    operation: "healthmd_sleep_sessions", arguments: { dates: { type: "all_available" } }, transport: "mcp",
  });
  assert.equal(fetched.transport, "mcp");
  assert.equal(JSON.parse(fetched.text).schema, "healthmd.query_response");
  const store = loadHealthDataText([{ path: fetched.syntheticPath, text: fetched.text, origin: "healthmd-mcp", operation: fetched.operation }]);
  assert.equal(store.documents[0]?.origin, "healthmd-mcp");
  assert.equal(store.documents[0]?.operation, "healthmd_sleep_sessions");
});

test("fetch rejects non-canonical query contracts from both CLI and MCP and accepts bounded multipage receipts", async () => {
  const directory = await mkdtemp(join(tmpdir(), "healthmd-source-contracts-"));
  const invalid = { schema: "healthmd.query_response", schema_version: 2, items: "bad" };
  const invalidCli = await executable(directory, "invalid-cli", `process.stdout.write(${JSON.stringify(JSON.stringify(invalid))});`);
  await assert.rejects(fetchHealthMd({ cliExecutable: invalidCli, defaultTransport: "cli" }, { operation: "healthmd_metric_chart", arguments: {} }), /healthmd\.query_response\/1|did not return/);
  const inventedItem = { ...response, items: [{ type: "invented", invented: {} }] };
  const inventedCli = await executable(directory, "invented-cli", `process.stdout.write(${JSON.stringify(JSON.stringify(inventedItem))});`);
  await assert.rejects(fetchHealthMd({ cliExecutable: inventedCli, defaultTransport: "cli" }, { operation: "healthmd_metric_chart", arguments: {} }), /invalid canonical fields|structurally canonical/);
  const decimalVersionText = JSON.stringify(response).replace('"schema_version":1', '"schema_version":1.0');
  const decimalVersion = await executable(directory, "decimal-version", `process.stdout.write(${JSON.stringify(decimalVersionText)});`);
  await assert.rejects(fetchHealthMd({ cliExecutable: decimalVersion, defaultTransport: "cli" }, { operation: "healthmd_metric_chart", arguments: {} }), /non-integer JSON token/);
  const oversizedCounterText = JSON.stringify(response).replace('"days_considered":1', '"days_considered":18446744073709551616');
  const oversizedCounter = await executable(directory, "oversized-counter", `process.stdout.write(${JSON.stringify(oversizedCounterText)});`);
  await assert.rejects(fetchHealthMd({ cliExecutable: oversizedCounter, defaultTransport: "cli" }, { operation: "healthmd_metric_chart", arguments: {} }), /out of range|invalid canonical fields/);
  const nullProvider = structuredClone(response);
  (nullProvider.items[0]!.metric.evidence[0] as any).provider_id = null;
  const nullProviderCli = await executable(directory, "null-provider", `process.stdout.write(${JSON.stringify(JSON.stringify(nullProvider))});`);
  await assert.rejects(fetchHealthMd({ cliExecutable: nullProviderCli, defaultTransport: "cli" }, { operation: "healthmd_metric_chart", arguments: {} }), /invalid canonical fields/);
  const invalidMcp = await executable(directory, "invalid-mcp", `
    const readline=require("node:readline"); const rl=readline.createInterface({input:process.stdin});
    rl.on("line",line=>{const r=JSON.parse(line); if(r.method==="initialize") process.stdout.write(JSON.stringify({jsonrpc:"2.0",id:r.id,result:{protocolVersion:"2025-11-25"}})+"\\n"); if(r.method==="tools/call") process.stdout.write(JSON.stringify({jsonrpc:"2.0",id:r.id,result:{content:[{type:"text",text:${JSON.stringify(JSON.stringify(invalid))}}],isError:false}})+"\\n");});
  `);
  await assert.rejects(fetchHealthMd({ mcpExecutable: invalidMcp }, { operation: "healthmd_sleep_sessions", arguments: {}, transport: "mcp" }), /healthmd\.query_response\/1|did not return/);

  const pages = { schema: "healthmd.mcp_query_pages", schema_version: 1, pages: [response], receipt: { page_count: 1, item_count: 1, packet_fact_count: 0, traversal_complete: true, next_cursor: null, limit_reason: null } };
  const multipage = await executable(directory, "multipage", `process.stdout.write(${JSON.stringify(JSON.stringify(pages))});`);
  const fetched = await fetchHealthMd({ cliExecutable: multipage, defaultTransport: "cli" }, { operation: "healthmd_metric_chart", arguments: { all_pages: true } });
  const store = loadHealthDataText([{ path: fetched.syntheticPath, text: fetched.text, origin: "healthmd-cli", operation: fetched.operation }]);
  assert.equal(store.documents[0]?.schema, "healthmd.mcp_query_pages");
  assert.ok(store.entries.some(entry => entry.semanticId === "steps" && entry.value === 12_345));
  const inconsistentPages: any = structuredClone(pages);
  inconsistentPages.pages[0].next_cursor = "invented-next";
  inconsistentPages.receipt.limit_reason = "invented_reason";
  const inconsistent = await executable(directory, "inconsistent-pages", `process.stdout.write(${JSON.stringify(JSON.stringify(inconsistentPages))});`);
  await assert.rejects(fetchHealthMd({ cliExecutable: inconsistent, defaultTransport: "cli" }, { operation: "healthmd_metric_chart", arguments: { all_pages: true } }), /completed traversal receipt|limited traversal receipt/);
});

test("fetch rejects unknown operations, subprocess failures, and oversized output", async () => {
  await assert.rejects(fetchHealthMd({ cliExecutable: "not-run", defaultTransport: "cli" }, {
    operation: "healthmd_export_files" as never, arguments: {},
  }), /Unsupported read-only/);
  await assert.rejects(fetchHealthMd({ cliExecutable: "not-run", defaultTransport: "cli" }, {
    operation: "healthmd_metrics", arguments: {},
  }), /requires the MCP transport; no transport fallback/);
  await assert.rejects(fetchHealthMd({ cliExecutable: "not-run", mcpExecutable: "not-run", deviceId: "00000000-0000-4000-8000-000000000001" }, {
    operation: "healthmd_metrics", arguments: {}, transport: "mcp",
  }), /standalone Health.md MCP helper cannot accept.*device\/port/);
  const directory = await mkdtemp(join(tmpdir(), "healthmd-source-bounds-"));
  const pidFile = join(directory, "oversized.pid");
  const oversized = await executable(directory, "oversized", `const fs=require("node:fs"); fs.writeFileSync(${JSON.stringify(pidFile)},String(process.pid)); process.on("SIGTERM",()=>{}); process.stdout.write(JSON.stringify({value:"x".repeat(1000)})); setInterval(()=>{},1000);`);
  await assert.rejects(fetchHealthMd({ cliExecutable: oversized, defaultTransport: "cli", maxOutputBytes: 100 }, {
    operation: "healthmd_metric_chart", arguments: {},
  }), /output exceeds 100 bytes/);
  if (process.platform !== "win32") {
    await new Promise(resolve => setTimeout(resolve, 500));
    const pid = Number(await readFile(pidFile, "utf8"));
    assert.throws(() => process.kill(pid, 0), /ESRCH/);
  }
  const failed = await executable(directory, "failed", `process.stdout.write(JSON.stringify({error:"healthmd_unavailable",message:"No paired foreground iPhone."})); process.exitCode=1;`);
  await assert.rejects(fetchHealthMd({ cliExecutable: failed, defaultTransport: "cli" }, {
    operation: "healthmd_metric_chart", arguments: {},
  }), /healthmd_unavailable: No paired foreground iPhone/);
});

test("fetch cancellation reaps the process tree and subprocesses receive only the source environment allowlist", async () => {
  const directory = await mkdtemp(join(tmpdir(), "healthmd-source-process-"));
  const pidFile = join(directory, "cancel.pid");
  const hanging = await executable(directory, "hanging", `const fs=require("node:fs"); fs.writeFileSync(${JSON.stringify(pidFile)},String(process.pid)); process.on("SIGTERM",()=>{}); setInterval(()=>{},1000);`);
  const controller = new AbortController();
  setTimeout(() => controller.abort(), 500);
  await assert.rejects(fetchHealthMd({ cliExecutable: hanging, defaultTransport: "cli" }, { operation: "healthmd_metric_chart", arguments: {}, timeoutSeconds: 30 }, controller.signal), /cancelled/);
  if (process.platform !== "win32") {
    await new Promise(resolve => setTimeout(resolve, 500));
    const pidText = await readFile(pidFile, "utf8").catch(error => (error as NodeJS.ErrnoException).code === "ENOENT" ? undefined : Promise.reject(error));
    if (pidText) assert.throws(() => process.kill(Number(pidText), 0), /ESRCH/);
  }

  await assert.rejects(fetchHealthMd({ cliExecutable: hanging, defaultTransport: "cli" }, { operation: "healthmd_metric_chart", arguments: {}, timeoutSeconds: 1 }), /timed out after 1 seconds/);
  if (process.platform !== "win32") {
    await new Promise(resolve => setTimeout(resolve, 500));
    const pid = Number(await readFile(pidFile, "utf8"));
    assert.throws(() => process.kill(pid, 0), /ESRCH/);
  }

  const environmentLog = join(directory, "environment.json");
  const environmentProbe = await executable(directory, "environment", `const fs=require("node:fs"); fs.writeFileSync(${JSON.stringify(environmentLog)},JSON.stringify({unrelated_secret:process.env.HEALTHMD_TEST_SECRET,allowed_data_dir:process.env.HEALTHMD_CLI_DATA_DIR})); process.stdout.write(${JSON.stringify(JSON.stringify(response))});`);
  const previousSecret = process.env.HEALTHMD_TEST_SECRET, previousData = process.env.HEALTHMD_CLI_DATA_DIR;
  process.env.HEALTHMD_TEST_SECRET = "must-not-leak";
  process.env.HEALTHMD_CLI_DATA_DIR = "/tmp/healthmd-test-data";
  try {
    const fetched = await fetchHealthMd({ cliExecutable: environmentProbe, defaultTransport: "cli" }, { operation: "healthmd_metric_chart", arguments: {} });
    assert.equal(JSON.parse(fetched.text).schema, "healthmd.query_response");
    const childEnvironment = JSON.parse(await readFile(environmentLog, "utf8"));
    assert.equal(childEnvironment.unrelated_secret, undefined);
    assert.equal(childEnvironment.allowed_data_dir, "/tmp/healthmd-test-data");
  } finally {
    if (previousSecret === undefined) delete process.env.HEALTHMD_TEST_SECRET; else process.env.HEALTHMD_TEST_SECRET = previousSecret;
    if (previousData === undefined) delete process.env.HEALTHMD_CLI_DATA_DIR; else process.env.HEALTHMD_CLI_DATA_DIR = previousData;
  }
});
