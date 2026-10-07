import * as Effect from "effect/Effect";
import * as Cause from "effect/Cause";
import * as Result from "effect/Result";
import type { SurfaceProfile } from "@healthmd/core-ts/candidate/catalog";
import { normalizeMetricChart, type QueryInvocation } from "@healthmd/core-ts/candidate/normalize";
import { traverseQuery, traversalBounds, type QueryBinding, type QueryFailure, type QuerySource } from "@healthmd/core-ts/candidate/query";

export interface ResolvedMcpCaller {
  readonly id: string; readonly profile: SurfaceProfile;
  readonly grants: readonly string[]; readonly allowedTools: readonly string[];
}
export interface TrustedMcpQueryHost {
  /** Current authenticated session principal, never derived from tool JSON. No owned resources here. */
  readonly resolveCaller: Effect.Effect<ResolvedMcpCaller, unknown>;
  /** Transport already supplied a reviewed lossless parsed envelope; decode operation arguments without rounding. */
  readonly decodeArguments: (input: unknown) => Effect.Effect<unknown, unknown>;
  /** Complete grammar/source/cursor/current capability admission; allocation belongs to QuerySource.open. */
  readonly admit: (invocation: QueryInvocation, caller: ResolvedMcpCaller) => Effect.Effect<{
    readonly binding: QueryBinding; readonly deadlineMilliseconds: number;
  }, QueryFailure>;
  /** Reviewed raw codec boundary. No candidate JSON serializer or lossless-byte equivalence is implied. */
  readonly encodeResult: (value: unknown) => Effect.Effect<string, unknown>;
}
export type McpQueryOutcome = {
  readonly error: { readonly code: -32601 | -32602 | -32003; readonly message: string };
} | {
  readonly result: { readonly content: readonly { readonly type: "text"; readonly text: string }[]; readonly isError: boolean };
};
const applicationErrors = {
  method: { error: { code: -32601, message: "Method not found" } },
  unknown: { error: { code: -32602, message: "Unknown tool" } },
  forbidden: { error: { code: -32003, message: "The caller lacks the required Health.md read scope." } },
  arguments: { error: { code: -32602, message: "Invalid tool arguments" } },
} as const;
for (const value of Object.values(applicationErrors)) { Object.freeze(value.error); Object.freeze(value); }
const codes: readonly string[] = ["healthmd_invalid_arguments", "healthmd_not_authorized", "healthmd_query_binding_mismatch", "healthmd_protocol_error", "healthmd_response_too_large", "healthmd_query_unavailable", "healthmd_query_deadline"];
function toolResult(text: string, isError: boolean): McpQueryOutcome {
  return { result: { content: [{ type: "text", text }], isError } };
}
function failed(code: string): McpQueryOutcome {
  const safe = codes.includes(code) ? code : "healthmd_protocol_error";
  // Only known ASCII code literals enter this private fixed diagnostic projection.
  return toolResult('{"error":"' + safe + '","message":"The candidate query failed."}', true);
}
function failureCode(error: unknown): string {
  // Never execute a provider getter while sanitizing its cause; proxies also fail closed.
  try {
    if (typeof error !== "object" || error === null) return "healthmd_protocol_error";
    const descriptor = Object.getOwnPropertyDescriptor(error, "code");
    return descriptor !== undefined && "value" in descriptor && typeof descriptor.value === "string"
      ? descriptor.value : "healthmd_protocol_error";
  } catch { return "healthmd_protocol_error"; }
}
const object = (input: unknown): input is Record<string, unknown> => typeof input === "object" && input !== null && !Array.isArray(input);
/** Private tools/call + metric_chart subset. Rust supports tools/list and other tools; this adapter does not.
 * Text-only fixed corpus: no JSONRPC IDs/version/session, Apps/PNG, listeners/concurrency or cancellation-wire claim.
 * Rust backend messages differ from the private fixed diagnostic; interruption stays interruption after cleanup. */
export function mcpQuery(method: string, call: unknown, host: TrustedMcpQueryHost): Effect.Effect<McpQueryOutcome, never, QuerySource> {
  const program = Effect.gen(function* () {
    if (method !== "tools/call") return applicationErrors.method;
    if (!object(call) || call.name !== "healthmd_metric_chart") return applicationErrors.unknown;
    const resolved = yield* host.resolveCaller;
    const caller: ResolvedMcpCaller = Object.freeze({ id: resolved.id, profile: resolved.profile,
      grants: Object.freeze([...resolved.grants]), allowedTools: Object.freeze([...resolved.allowedTools]) });
    if (!caller.allowedTools.includes("healthmd_metric_chart")) return applicationErrors.unknown;
    if (!caller.grants.includes("healthmd:read")) return applicationErrors.forbidden;
    const decoded = yield* Effect.exit(Effect.suspend(() => host.decodeArguments(Object.hasOwn(call, "arguments") ? call.arguments : {})));
    if (decoded._tag === "Failure") {
      if (Cause.hasInterrupts(decoded.cause)) return yield* Effect.failCause(decoded.cause);
      return applicationErrors.arguments;
    }
    const normalized = normalizeMetricChart(decoded.value);
    if (Result.isFailure(normalized)) return applicationErrors.arguments;
    const invocation = normalized.success;
    const admission = yield* Effect.suspend(() => host.admit(invocation, caller));
    if (admission.binding.caller !== caller.id || admission.binding.profile !== caller.profile) return failed("healthmd_query_binding_mismatch");
    const value = yield* traverseQuery({ invocation, binding: admission.binding, grants: caller.grants,
      deadlineMilliseconds: admission.deadlineMilliseconds });
    const text = yield* Effect.suspend(() => host.encodeResult(value)).pipe(Effect.mapError((): QueryFailure => ({ code: "healthmd_protocol_error" })));
    // This candidate bounds JS text capacity; raw UTF8 frames/memory/codec accounting remain host obligations.
    if (typeof text !== "string" || text.length > traversalBounds.aggregateBytes) return failed("healthmd_protocol_error");
    return toolResult(text, false);
  });
  return Effect.uninterruptibleMask((restore) => restore(program).pipe(Effect.catchCause((cause) => {
    if (Cause.hasInterrupts(cause)) return Effect.failCause(Cause.fromReasons<never>(cause.reasons.filter(Cause.isInterruptReason).map((reason) => Cause.makeInterruptReason(reason.fiberId))));
    const failure = cause.reasons.find(Cause.isFailReason);
    const error: unknown = failure?.error;
    return Effect.succeed(failed(failureCode(error)));
  })));
}
