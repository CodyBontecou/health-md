import * as Context from "effect/Context";
import * as Effect from "effect/Effect";
import type { JsonValue, SurfaceProfile } from "./catalog.js";
import type { QueryInvocation } from "./normalize.js";

export const traversalBounds = Object.freeze({ aggregateBytes: 2097152, receiptReserveBytes: 16384, pages: 4096, pageBytes: 1048576, pageItems: 1000 });
export type QueryFailureCode = "healthmd_invalid_arguments" | "healthmd_not_authorized" | "healthmd_query_binding_mismatch"
  | "healthmd_protocol_error" | "healthmd_response_too_large" | "healthmd_query_unavailable" | "healthmd_query_deadline";
export interface QueryFailure { readonly code: QueryFailureCode; }
const fail = (code: QueryFailureCode): QueryFailure => ({ code });
const codes: readonly string[] = ["healthmd_invalid_arguments", "healthmd_not_authorized", "healthmd_query_binding_mismatch", "healthmd_protocol_error", "healthmd_response_too_large", "healthmd_query_unavailable", "healthmd_query_deadline"];
const sanitize = (error: QueryFailure): QueryFailure => codes.includes(error?.code) ? fail(error.code) : fail("healthmd_protocol_error");
/** Resolved adapter attestations, never raw claims from an operation caller. */
export interface QueryBinding {
  readonly caller: string;
  readonly source: string;
  readonly profile: SurfaceProfile;
  readonly coverage: string;
  readonly logicalQuery: string;
  readonly dataset: string;
}
export interface TraversalRequest {
  readonly invocation: QueryInvocation;
  readonly binding: QueryBinding;
  readonly grants: readonly string[];
  readonly deadlineMilliseconds: number;
  readonly limits?: { readonly maximumBytes: number; readonly maximumPages: number };
}
export type QueryBody = { readonly [key: string]: JsonValue };
export interface AttributedPage {
  readonly body: QueryBody;
  /** Exact encoded bytes attested by adapter; pure traversal does not reserialize numeric values. */
  readonly encodedBytes: number;
  readonly binding: QueryBinding;
  readonly requestedCursor: string | null;
}
export type QueryScope = Effect.Success<typeof Effect.scope>;
export interface QueryResource {
  readonly binding: QueryBinding;
  /** Owned immutable validated body: source/coverage attribution inside the native page must match binding. */
  readonly read: (cursor: string | null) => Effect.Effect<AttributedPage, QueryFailure>;
  readonly release: Effect.Effect<void>;
}
/** Bounded final allocation and release registration share one uninterruptible ownership handoff. */
export function ownQueryResource(allocation: Effect.Effect<QueryResource, QueryFailure>): Effect.Effect<QueryResource, QueryFailure, QueryScope> {
  return Effect.acquireRelease(allocation, (owned) => owned.release);
}
/**
 * One coarse admission/capture scope. Before returning an owned resource the adapter validates
 * complete query grammar, current authority/coverage and cursor signature/dataset/query binding.
 * Preparation is interruptible and rolls back partial state. Final allocation must use
 * ownQueryResource in the supplied operation scope before returning an owned resource.
 * Adapters must not mask all preparation or return an unregistered owned handle.
 * Page body attribution must be verified before read returns; sidecars alone are not authentication.
 * No cursor is decoded or reconstructed here; native request IDs may change independently.
 */
export class QuerySource extends Context.Service<QuerySource, {
  readonly open: (request: TraversalRequest) => Effect.Effect<QueryResource, QueryFailure, QueryScope>;
}>()("healthmd.candidate.QuerySource") {}
export interface TraversalReceipt {
  readonly schema: "healthmd.mcp_query_pages";
  readonly schema_version: 1;
  readonly pages: readonly QueryBody[];
  readonly receipt: {
    readonly page_count: number;
    readonly item_count: number;
    readonly packet_fact_count: number;
    readonly traversal_complete: boolean;
    readonly next_cursor: string | null;
    readonly limit_reason: "maximum_pages" | "maximum_aggregate_bytes" | null;
  };
}
const bindingKeys = ["caller", "source", "profile", "coverage", "logicalQuery", "dataset"] as const;
const sameBinding = (a: QueryBinding, b: QueryBinding): boolean => bindingKeys.every((key) => a[key] === b[key]);
const object = (value: unknown): value is Record<string, unknown> => value !== null && typeof value === "object" && !Array.isArray(value);
const bound = (value: unknown, maximum: number): value is number => typeof value === "number" && Number.isInteger(value) && value >= 1 && value <= maximum;

/** Common traversal of admitted pages; receipt completion is not a claim of complete health coverage. */
export function traverseQuery(request: TraversalRequest): Effect.Effect<QueryBody | TraversalReceipt, QueryFailure, QuerySource> {
  if (!Number.isFinite(request.deadlineMilliseconds) || request.deadlineMilliseconds <= 0) return Effect.fail(fail("healthmd_invalid_arguments"));
  const work = Effect.scoped(Effect.gen(function* () {
    const invocation = request.invocation;
    const page = invocation.query.page;
    const maximumBytes = request.limits?.maximumBytes ?? traversalBounds.aggregateBytes;
    const maximumPages = request.limits?.maximumPages ?? traversalBounds.pages;
    if (!object(page) || !bound(page.max_items, traversalBounds.pageItems) || !bound(page.max_bytes, traversalBounds.pageBytes)
      || (page.cursor !== null && page.cursor !== undefined && typeof page.cursor !== "string")
      || !bound(maximumBytes, traversalBounds.aggregateBytes) || !bound(maximumPages, traversalBounds.pages)
      || !Number.isFinite(request.deadlineMilliseconds) || request.deadlineMilliseconds <= 0
      || !bindingKeys.every((key) => typeof request.binding[key] === "string" && request.binding[key].length > 0)
      || !["local_direct", "local_read_only", "remote_read_only"].includes(request.binding.profile)) {
      return yield* Effect.fail(fail("healthmd_invalid_arguments"));
    }
    if (!request.grants.includes("healthmd:read")) return yield* Effect.fail(fail("healthmd_not_authorized"));
    const source = yield* QuerySource;
    const resource = yield* source.open(request);
    if (!sameBinding(resource.binding, request.binding)) return yield* Effect.fail(fail("healthmd_query_binding_mismatch"));
    const pages: QueryBody[] = [];
    let cursor = typeof page.cursor === "string" ? page.cursor : null;
    const seen = new Set<string>();
    if (cursor !== null) seen.add(cursor);
    let bytes = 0;
    let complete = true;
    let continuation: string | null = null;
    let reason: "maximum_pages" | "maximum_aggregate_bytes" | null = null;
    const budget = Math.max(0, maximumBytes - traversalBounds.receiptReserveBytes);
    while (true) {
      if (invocation.all_pages && pages.length >= maximumPages) { complete = false; continuation = cursor; reason = "maximum_pages"; break; }
      const response = yield* resource.read(cursor);
      if (!sameBinding(response.binding, request.binding) || response.requestedCursor !== cursor) return yield* Effect.fail(fail("healthmd_query_binding_mismatch"));
      if (!object(response.body) || !bound(response.encodedBytes, page.max_bytes)) return yield* Effect.fail(fail("healthmd_response_too_large"));
      if (Array.isArray(response.body.items) && response.body.items.length > page.max_items) return yield* Effect.fail(fail("healthmd_protocol_error"));
      if (bytes + response.encodedBytes > budget) {
        if (!invocation.all_pages || pages.length === 0) return yield* Effect.fail(fail("healthmd_response_too_large"));
        complete = false; continuation = cursor; reason = "maximum_aggregate_bytes"; break;
      }
      bytes += response.encodedBytes;
      pages.push(response.body);
      const next = typeof response.body.next_cursor === "string" ? response.body.next_cursor : null;
      if (!invocation.all_pages || next === null) break;
      if (seen.has(next)) return yield* Effect.fail(fail("healthmd_protocol_error"));
      seen.add(next);
      cursor = next;
    }
    if (!invocation.all_pages) return pages[0]!;
    return {
      schema: "healthmd.mcp_query_pages" as const, schema_version: 1 as const, pages,
      receipt: {
        page_count: pages.length,
        item_count: pages.reduce((count, item) => count + (Array.isArray(item.items) ? item.items.length : 0), 0),
        packet_fact_count: pages.reduce((count, item) => {
          const packet = item.packet;
          return count + (object(packet) && Array.isArray(packet.facts) ? packet.facts.length : 0);
        }, 0),
        traversal_complete: complete, next_cursor: continuation, limit_reason: reason,
      },
    };
  }));
  return work.pipe(
    Effect.mapError(sanitize),
    Effect.catchDefect(() => Effect.fail(fail("healthmd_protocol_error"))),
    Effect.timeoutOrElse({ duration: request.deadlineMilliseconds, orElse: () => Effect.fail(fail("healthmd_query_deadline")) }),
  );
}
