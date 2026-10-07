import * as Effect from "effect/Effect";
import * as Cause from "effect/Cause";
import * as Layer from "effect/Layer";
import { CandidateSession, inspectCandidate } from "@healthmd/core-ts";

export type CandidateOutcome = { readonly status: "ready" } | {
  readonly status: "failed";
  readonly code: "capability_unavailable" | "capability_failed";
};

/** One host program; the common portable operation owns acquisition and finalization.
 * Restore its interruption mode, then sanitize the completed cause under a small mask.
 * Interruptible catch handlers can be skipped during cancellation, retaining cleanup defects.
 */
export const inspectHost = Effect.uninterruptibleMask((restore) => restore(inspectCandidate).pipe(
  Effect.map((): CandidateOutcome => ({ status: "ready" })),
  Effect.catchTags({
    CapabilityUnavailable: () => Effect.succeed<CandidateOutcome>({ status: "failed", code: "capability_unavailable" }),
    CapabilityFailed: () => Effect.succeed<CandidateOutcome>({ status: "failed", code: "capability_failed" }),
  }),
  // Keep cancellation IDs, but carry no provider reasons or original cause annotations.
  Effect.catchCause((cause) => Cause.hasInterrupts(cause)
    ? Effect.failCause(Cause.fromReasons<never>(cause.reasons.filter(Cause.isInterruptReason).map((reason) => Cause.makeInterruptReason(reason.fiberId))))
    : Effect.succeed<CandidateOutcome>({ status: "failed", code: "capability_failed" })),
));

/** Development envelopes only; these are not public CLI or MCP wire contracts. */
export const cliCandidate = () => Effect.map(inspectHost, (result) => ({ surface: "cli_candidate" as const, result }));
export const mcpCandidate = () => Effect.map(inspectHost, (result) => ({ surface: "mcp_candidate" as const, result }));

/** Explicit fake-only smoke. No device, credential, listener, transport or user state. */
export async function smokeCandidate() {
  const counts = { acquired: 0, released: 0 };
  const fake = Layer.succeed(CandidateSession)({
    acquire: Effect.sync(() => {
      counts.acquired++;
      return { inspect: Effect.succeed("ready" as const), release: Effect.sync(() => { counts.released++; }) };
    }),
  });
  const cli = await Effect.runPromise(cliCandidate().pipe(Effect.provide(fake)));
  const mcp = await Effect.runPromise(mcpCandidate().pipe(Effect.provide(fake)));
  return { cli, mcp, counts };
}
