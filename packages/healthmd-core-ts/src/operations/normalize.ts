import * as Result from "effect/Result";
import { catalogFailure, type CatalogResult, type JsonValue, type StaticCatalog, type SurfaceProfile } from "./catalog.js";

export interface QueryInvocation {
  readonly query: {
    readonly schema: "healthmd.query_request";
    readonly schema_version: 1;
    readonly dates: JsonValue;
    readonly metrics: JsonValue;
    readonly sources: JsonValue;
    readonly operation: { readonly type: "metric_series" };
    readonly page: JsonValue;
  };
  readonly detail_level: "summary" | "lossless";
  readonly all_pages: boolean;
}
function copyJson(value: JsonValue): JsonValue {
  if (value === null || typeof value === "string" || typeof value === "boolean" || typeof value === "number") return value;
  if (Array.isArray(value)) return value.map(copyJson);
  if (typeof value !== "object") throw new Error("invalid_json_value");
  return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, copyJson(item)]));
}
export function normalizeDiscovery(catalog: StaticCatalog, profile: SurfaceProfile, name?: string): CatalogResult<unknown> {
  return catalog.discover(profile, name);
}
/**
 * Port of registry.rs query_invocation/typed_query for metric_chart only.
 * Nested date/metric/source/page validation, protocol IDs and execution belong to the next boundary.
 * Input is an already-parsed JSON object; no raw JSON/parser/byte guarantees are implied.
 */
export function normalizeMetricChart(input: unknown): CatalogResult<QueryInvocation> {
  try {
    if (input === null || typeof input !== "object" || Array.isArray(input)) return Result.fail(catalogFailure);
    const args = input as Record<string, JsonValue>;
    const allowed = ["dates", "metrics", "sources", "page", "detail_level", "all_pages"];
    const has = (key: string): boolean => Object.hasOwn(args, key);
    if (Object.keys(args).some((key) => !allowed.includes(key)) || !has("dates") || !has("metrics")) return Result.fail(catalogFailure);
    if (has("all_pages") && typeof args.all_pages !== "boolean") return Result.fail(catalogFailure);
    const detail = typeof args.detail_level === "string" ? args.detail_level : "summary";
    if (detail !== "summary" && detail !== "lossless") return Result.fail(catalogFailure);
    return Result.succeed({
      query: {
        schema: "healthmd.query_request", schema_version: 1,
        dates: copyJson(args.dates!), metrics: copyJson(args.metrics!),
        sources: has("sources") ? copyJson(args.sources!) : { type: "all_available" },
        operation: { type: "metric_series" },
        page: has("page") ? copyJson(args.page!) : { max_items: 250, max_bytes: 262144, cursor: null },
      },
      detail_level: detail,
      all_pages: args.all_pages === true,
    });
  } catch { return Result.fail(catalogFailure); }
}
