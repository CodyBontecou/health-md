import * as Effect from "effect/Effect";
import * as Cause from "effect/Cause";
import * as Result from "effect/Result";
import { normalizeMetricChart, type QueryInvocation } from "@healthmd/core-ts/candidate/normalize";
import { traverseQuery, type QueryBinding, type QueryFailure, type QuerySource, type QueryBody, type TraversalReceipt } from "@healthmd/core-ts/candidate/query";

export interface TrustedCliQueryHost {
  /** Host must decode/validate raw bytes without numeric loss; this candidate implements no parser. */
  readonly decodeArguments: (text: string) => Effect.Effect<unknown, unknown>;
  /** Resolved current authority/grammar/capabilities, never inferred from argv or JSON claims.
   * This preparation owns no resource. QuerySource.open owns scoped final allocation. */
  readonly admit: (invocation: QueryInvocation, timeoutSeconds: number) => Effect.Effect<{
    readonly binding: QueryBinding; readonly grants: readonly string[];
  }, QueryFailure>;
}
export interface CliQueryFailure {
  readonly exitCode: 1 | 2;
  readonly error: { readonly code: "invalid_request" | "healthmd_query_failed" | "candidate_presentation_unavailable"; readonly message: string };
}
export type CliQueryOutcome = CliQueryFailure | {
  readonly exitCode: 0; readonly value: QueryBody | TraversalReceipt; readonly stdout: string;
};
const failures = {
  parse: { exitCode: 2, error: { code: "invalid_request", message: "Unsupported candidate query arguments." } },
  timeout: { exitCode: 1, error: { code: "invalid_request", message: "query timeout must be between 1 and 3600 seconds" } },
  decode: { exitCode: 1, error: { code: "invalid_request", message: "--arguments must be one valid JSON object" } },
  normalize: { exitCode: 1, error: { code: "invalid_request", message: "invalid typed query arguments" } },
  query: { exitCode: 1, error: { code: "healthmd_query_failed", message: "The candidate query failed." } },
  presentation: { exitCode: 1, error: { code: "candidate_presentation_unavailable", message: "The candidate JSON presentation is unavailable." } },
} as const satisfies Record<string, CliQueryFailure>;
// Fixed failures may be shared across calls; recipients cannot change later diagnostics.
for (const failure of Object.values(failures)) { Object.freeze(failure.error); Object.freeze(failure); }
Object.freeze(failures);
interface Parsed { readonly text: string; readonly timeoutSeconds: number; }
function parse(argv: readonly string[]): Result.Result<Parsed, CliQueryFailure> {
  // Private syntax only. Legacy unknown-operation discovery uses different public semantics.
  if (argv.length > 10 || argv[0] !== "query" || argv[1] !== "healthmd_metric_chart") return Result.fail(failures.parse);
  let text: string | undefined; let timeoutSeconds = 1200; const seen = new Set<string>();
  for (let i = 2; i < argv.length; i++) {
    const flag = argv[i]!;
    if (seen.has(flag) || !["--arguments", "--timeout", "--json"].includes(flag)) return Result.fail(failures.parse);
    seen.add(flag);
    if (flag === "--json") continue;
    const value = argv[++i]; if (value === undefined) return Result.fail(failures.parse);
    if (flag === "--arguments") { if (value.length > 65536) return Result.fail(failures.parse); text = value; }
    else {
      if (!/^[0-9]{1,4}$/.test(value)) return Result.fail(failures.parse);
      timeoutSeconds = Number(value);
      if (timeoutSeconds < 1 || timeoutSeconds > 3600) return Result.fail(failures.timeout);
    }
  }
  return text === undefined ? Result.fail(failures.parse) : Result.succeed({ text, timeoutSeconds });
}
/** Restricted literal presentation: sorted nonnumeric ASCII keys/strings and safe integers only.
 * No general serde, Unicode, fraction, negative-zero or lossless-number byte equivalence. */
function present(value: unknown): string | undefined {
  let nodes = 4096;
  const ascii = (text: string) => /^[\x00-\x7f]*$/.test(text);
  function walk(item: unknown, depth: number): unknown {
    if (--nodes < 0 || depth > 32) throw new Error("presentation_unavailable");
    if (item === null || typeof item === "boolean") return item;
    if (typeof item === "string" && ascii(item)) return item;
    if (typeof item === "number" && Number.isSafeInteger(item) && !Object.is(item, -0)) return item;
    if (Array.isArray(item)) return item.map((child: unknown) => walk(child, depth + 1));
    if (typeof item === "object" && item !== null && Object.getPrototypeOf(item) === Object.prototype) {
      return Object.fromEntries(Object.entries(item).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0).map(([key, child]) => {
        if (!ascii(key) || /^[0-9]+$/.test(key)) throw new Error("presentation_unavailable"); return [key, walk(child, depth + 1)];
      }));
    }
    throw new Error("presentation_unavailable");
  }
  try { const text = JSON.stringify(walk(value, 0), null, 2) + "\n"; return text.length <= 65536 ? text : undefined; }
  catch { return undefined; }
}
/** One opt-in JSON-mode command. No tty detection, guidance, process signal handlers or durable job mutation.
 * Host attested read-only profiles are a candidate subset; production Rust CLI uses LocalDirect.
 * Source/coverage/page bytes remain trusted adapter attestations, not native authentication proof. */
export function cliQuery(argv: readonly string[], host: TrustedCliQueryHost): Effect.Effect<CliQueryOutcome, never, QuerySource> {
  const program = Effect.gen(function* () {
    const parsed = parse(argv); if (Result.isFailure(parsed)) return yield* Effect.fail(parsed.failure);
    const args = yield* Effect.suspend(() => host.decodeArguments(parsed.success.text)).pipe(
      Effect.mapError(() => failures.decode), Effect.catchDefect(() => Effect.fail(failures.decode)));
    if (args === null || typeof args !== "object" || Array.isArray(args)) return yield* Effect.fail(failures.decode);
    const normalized = normalizeMetricChart(args);
    if (Result.isFailure(normalized)) return yield* Effect.fail(failures.normalize);
    const invocation = normalized.success;
    const admission = yield* Effect.suspend(() => host.admit(invocation, parsed.success.timeoutSeconds)).pipe(Effect.mapError(() => failures.query));
    const value = yield* traverseQuery({ invocation, binding: admission.binding, grants: admission.grants,
      deadlineMilliseconds: parsed.success.timeoutSeconds * 1000 }).pipe(Effect.mapError(() => failures.query));
    const stdout = present(value); if (stdout === undefined) return yield* Effect.fail(failures.presentation);
    return { exitCode: 0 as const, value, stdout };
  });
  // Restore the whole scope, then sanitize completed causes under a small mask, including cleanup races.
  return Effect.uninterruptibleMask((restore) => restore(program).pipe(Effect.catchCause((cause) => {
    if (Cause.hasInterrupts(cause)) return Effect.failCause(Cause.fromReasons<never>(cause.reasons.filter(Cause.isInterruptReason).map((reason) => Cause.makeInterruptReason(reason.fiberId))));
    const failure = cause.reasons.find(Cause.isFailReason);
    return Effect.succeed<CliQueryOutcome>(failure !== undefined ? failure.error : failures.query);
  })));
}
