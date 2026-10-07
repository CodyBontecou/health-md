import assert from "node:assert/strict";
import { test } from "node:test";
import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import * as Result from "effect/Result";
import { createStaticCatalog, catalogMirrorSha256, type CatalogTool, type JsonValue } from "../src/operations/catalog.js";
import { normalizeDiscovery, normalizeMetricChart } from "../src/operations/normalize.js";
import { catalogVectors } from "./catalog-vectors.js";

async function frozenMirror(): Promise<readonly CatalogTool[]> {
  const bytes = await readFile("../../apps/cli/crates/healthmd-mcp/assets/mcp-tools-v1.json");
  const expected = "31377cf8ac0494d8410a2bd9cf69be0c65d1f0394517730e960f0f9a9016f52d";
  assert.equal(catalogMirrorSha256, expected);
  assert.equal(createHash("sha256").update(bytes).digest("hex"), expected);
  return JSON.parse(bytes.toString("utf8")) as readonly CatalogTool[];
}
for (const vector of catalogVectors) {
  test(`catalog normalization literal: ${vector.id}`, () => {
    const result = normalizeMetricChart(vector.arguments);
    assert.equal(Result.isSuccess(result), vector.valid);
    if (Result.isSuccess(result)) assert.deepEqual(result.success, vector.expected);
    else assert.deepEqual(result.failure, { code: "healthmd_invalid_arguments" });
  });
}

test("static full catalog preserves every frozen declaration field and order", async () => {
  const mirror = await frozenMirror(); const created = createStaticCatalog(mirror); assert.ok(Result.isSuccess(created));
  const full = created.success.list("local_direct"); assert.ok(Result.isSuccess(full));
  assert.equal(full.success.length, 21); assert.deepEqual(full.success, mirror);
  assert.ok(Object.isFrozen(full.success));
  for (const tool of full.success) { assert.ok(Object.isFrozen(tool)); assert.ok(Object.isFrozen(tool.inputSchema)); }
});

test("both read-only profiles preserve13 schemas and source-specific guidance", async () => {
  const mirror = await frozenMirror(); const created = createStaticCatalog(mirror); assert.ok(Result.isSuccess(created));
  const names = ["healthmd_status", "healthmd_doctor", "healthmd_capabilities", "healthmd_metrics", "healthmd_metric_chart", "healthmd_sleep_sessions", "healthmd_training_alignment", "healthmd_workouts", "healthmd_coverage", "healthmd_compare_periods", "healthmd_training_evidence", "healthmd_query", "healthmd_evidence_packet"];
  for (const profile of ["local_read_only", "remote_read_only"] as const) {
    const result = created.success.list(profile); assert.ok(Result.isSuccess(result));
    assert.deepEqual(result.success.map((tool) => tool.name), names);
    const expected = mirror.slice(0, 13).map((tool) => {
      if (tool.name === "healthmd_doctor") return { ...tool, description: profile === "local_read_only"
        ? "Diagnose paired foreground iPhone query readiness. If unpaired, run `healthmd direct pair` outside MCP; pairing and export jobs are unavailable in this read-only surface."
        : "Diagnose paired foreground iPhone query readiness. If unpaired, ask the server operator to pair its source outside MCP; pairing and export jobs are unavailable in this read-only surface." };
      if (tool.name === "healthmd_capabilities") return { ...tool, description: "List read-only direct-query, evidence, visualization, and pagination capabilities. This surface exposes no pairing or export jobs." };
      return tool;
    });
    assert.deepEqual(result.success, expected);
    assert.ok(Result.isFailure(normalizeDiscovery(created.success, profile, "healthmd_pairing_status")));
  }
});

test("offline discovery reproduces fixed envelopes without host ports", async () => {
  const mirror = await frozenMirror(); const created = createStaticCatalog(mirror); assert.ok(Result.isSuccess(created));
  const guidance = {
    typed_tools_are_preferred: true, sleep_tool: "healthmd_sleep_sessions", workout_tool: "healthmd_workouts", metric_series_tool: "healthmd_metric_chart",
    note: "MCP tools and `healthmd query <operation> --arguments <JSON>` use this same registry. The shell `healthmd extract` command returns a different canonical projection.",
  };
  const all = normalizeDiscovery(created.success, "local_direct"); assert.ok(Result.isSuccess(all));
  assert.deepEqual(all.success, { schema: "healthmd.mcp_tool_catalog", schema_version: 1, guidance, tools: mirror });
  const one = normalizeDiscovery(created.success, "local_direct", "healthmd_metric_chart"); assert.ok(Result.isSuccess(one));
  assert.deepEqual(one.success, { schema: "healthmd.mcp_tool_schema", schema_version: 1, guidance, tool: mirror[4] });
  assert.ok(Result.isFailure(normalizeDiscovery(created.success, "local_direct", "guessed-operation")));
});

test("catalog snapshots reject identity drift and caller mutation", async () => {
  const mirror = await frozenMirror();
  assert.ok(Result.isFailure(createStaticCatalog(mirror.slice(1))));
  assert.ok(Result.isFailure(createStaticCatalog([...mirror].reverse())));
  assert.ok(Result.isFailure(createStaticCatalog(mirror.map((tool) => ({ ...tool, name: "guessed" })))));
  const mutable = JSON.parse(JSON.stringify(mirror)) as CatalogTool[];
  const created = createStaticCatalog(mutable); assert.ok(Result.isSuccess(created));
  (mutable[0] as { title: string }).title = "changed";
  const result = created.success.list("local_direct"); assert.ok(Result.isSuccess(result));
  assert.deepEqual(result.success, mirror);
});

test("normalization availability never implies execution or readiness", async () => {
  const created = createStaticCatalog(await frozenMirror()); assert.ok(Result.isSuccess(created));
  const full = created.success.list("local_direct"); assert.ok(Result.isSuccess(full));
  for (const tool of full.success) {
    const result = created.success.availability(tool.name); assert.ok(Result.isSuccess(result));
    assert.deepEqual(result.success, { normalization: tool.name === "healthmd_metric_chart" ? "available" : "not_implemented", execution: "not_implemented" });
  }
  assert.ok(Result.isFailure(created.success.availability("unknown")));
});

test("normalization clones opaque selections and leaves protocol identifiers outside", () => {
  const input = { dates: { type: "all_available" }, metrics: { type: "explicit", metric_ids: ["steps"] } };
  const result = normalizeMetricChart(input); assert.ok(Result.isSuccess(result));
  input.metrics.metric_ids.push("changed");
  assert.deepEqual(result.success.query.metrics, { type: "explicit", metric_ids: ["steps"] });
  assert.ok(Result.isFailure(normalizeMetricChart({ ...input, request_id: "synthetic" })));
  const opaque = normalizeMetricChart({ dates: null, metrics: null, page: { cursor: "opaque-synthetic", request_id: "unchanged" } });
  assert.ok(Result.isSuccess(opaque));
  assert.deepEqual(opaque.success.query.page, { cursor: "opaque-synthetic", request_id: "unchanged" } satisfies JsonValue);
});
