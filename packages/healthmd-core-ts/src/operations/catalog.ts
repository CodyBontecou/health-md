import * as Result from "effect/Result";

export type JsonValue = null | boolean | number | string | readonly JsonValue[] | { readonly [key: string]: JsonValue };
export interface CatalogTool {
  readonly name: string;
  readonly title: string;
  readonly description: string;
  readonly inputSchema: JsonValue;
  readonly annotations: JsonValue;
  readonly _meta?: JsonValue;
}
export type SurfaceProfile = "local_direct" | "local_read_only" | "remote_read_only";
export interface CatalogFailure { readonly code: "healthmd_invalid_arguments"; }
export type CatalogResult<A> = Result.Result<A, CatalogFailure>;
export const catalogFailure: CatalogFailure = Object.freeze({ code: "healthmd_invalid_arguments" });
export const catalogMirrorSha256 = "31377cf8ac0494d8410a2bd9cf69be0c65d1f0394517730e960f0f9a9016f52d";
export const fullOperationIds = Object.freeze([
  "healthmd_status", "healthmd_doctor", "healthmd_capabilities", "healthmd_metrics",
  "healthmd_metric_chart", "healthmd_sleep_sessions", "healthmd_training_alignment",
  "healthmd_workouts", "healthmd_coverage", "healthmd_compare_periods", "healthmd_training_evidence",
  "healthmd_query", "healthmd_evidence_packet", "healthmd_pairing_start", "healthmd_pairing_status",
  "healthmd_export_files", "healthmd_export_raw", "healthmd_raw_artifact_read",
  "healthmd_export_job_status", "healthmd_export_job_resume", "healthmd_export_job_cancel",
] as const);
export const readOnlyOperationIds = Object.freeze(fullOperationIds.slice(0, 13));
const localOnly = new Set<string>(fullOperationIds.slice(13));
const guidance = Object.freeze({
  typed_tools_are_preferred: true,
  sleep_tool: "healthmd_sleep_sessions",
  workout_tool: "healthmd_workouts",
  metric_series_tool: "healthmd_metric_chart",
  note: "MCP tools and `healthmd query <operation> --arguments <JSON>` use this same registry. The shell `healthmd extract` command returns a different canonical projection.",
});
function freezeJson<A>(value: A): A {
  if (value !== null && typeof value === "object") {
    for (const item of Object.values(value)) freezeJson(item);
    Object.freeze(value);
  }
  return value;
}
const profileValid = (profile: SurfaceProfile): boolean =>
  profile === "local_direct" || profile === "local_read_only" || profile === "remote_read_only";
export interface StaticCatalog {
  list(profile: SurfaceProfile): CatalogResult<readonly CatalogTool[]>;
  discover(profile: SurfaceProfile, name?: string): CatalogResult<unknown>;
  availability(name: string): CatalogResult<{ readonly normalization: "available" | "not_implemented"; readonly execution: "not_implemented" }>;
}
/**
 * Admit reviewed static JSON data supplied by a host/bundler, never by an operation caller.
 * Identity/order checks do not authenticate its schemas: the host must bind the exact mirror hash.
 * JSON snapshotting is limited to this trusted static catalog, not arbitrary query payloads.
 */
export function createStaticCatalog(reviewedMirror: readonly CatalogTool[]): CatalogResult<StaticCatalog> {
  try {
    if (reviewedMirror.length !== fullOperationIds.length || reviewedMirror.some((tool, index) =>
      tool.name !== fullOperationIds[index] || typeof tool.title !== "string" || typeof tool.description !== "string")) {
      return Result.fail(catalogFailure);
    }
    const snapshot = freezeJson(JSON.parse(JSON.stringify(reviewedMirror)) as readonly CatalogTool[]);
    const list = (profile: SurfaceProfile): CatalogResult<readonly CatalogTool[]> => {
      if (!profileValid(profile)) return Result.fail(catalogFailure);
      if (profile === "local_direct") return Result.succeed(snapshot);
      const tools = snapshot.filter((tool) => !localOnly.has(tool.name)).map((tool) => {
        if (tool.name === "healthmd_doctor") return { ...tool, description: profile === "local_read_only"
          ? "Diagnose paired foreground iPhone query readiness. If unpaired, run `healthmd direct pair` outside MCP; pairing and export jobs are unavailable in this read-only surface."
          : "Diagnose paired foreground iPhone query readiness. If unpaired, ask the server operator to pair its source outside MCP; pairing and export jobs are unavailable in this read-only surface." };
        if (tool.name === "healthmd_capabilities") return { ...tool, description:
          "List read-only direct-query, evidence, visualization, and pagination capabilities. This surface exposes no pairing or export jobs." };
        return tool;
      });
      return Result.succeed(freezeJson(tools));
    };
    return Result.succeed(Object.freeze({
      list,
      discover(profile: SurfaceProfile, name?: string): CatalogResult<unknown> {
        return Result.flatMap(list(profile), (tools): CatalogResult<unknown> => {
          if (name === undefined) return Result.succeed(freezeJson({ schema: "healthmd.mcp_tool_catalog", schema_version: 1, guidance, tools }));
          const tool = tools.find((item) => item.name === name);
          return tool === undefined ? Result.fail(catalogFailure)
            : Result.succeed(freezeJson({ schema: "healthmd.mcp_tool_schema", schema_version: 1, guidance, tool }));
        });
      },
      availability(name: string) {
        if (!snapshot.some((tool) => tool.name === name)) return Result.fail(catalogFailure);
        return Result.succeed({ normalization: name === "healthmd_metric_chart" ? "available" as const : "not_implemented" as const, execution: "not_implemented" as const });
      },
    }));
  } catch { return Result.fail(catalogFailure); }
}
