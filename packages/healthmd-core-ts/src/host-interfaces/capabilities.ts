import * as Context from "effect/Context";
import * as Effect from "effect/Effect";
import type { CapabilityFault } from "./faults.js";

/** Foundation-only owned handle. No native object, identity or personal payload crosses it. */
export interface CandidateResource {
  readonly inspect: Effect.Effect<"ready", CapabilityFault>;
  readonly release: Effect.Effect<void>;
}

export class CandidateSession extends Context.Service<CandidateSession, {
  readonly acquire: Effect.Effect<CandidateResource, CapabilityFault>;
}>()("healthmd.candidate.Session") {}

/** Exercise the same coarse resource scope that fake and future host Layers implement. */
export const inspectCandidate = Effect.scoped(
  Effect.gen(function* () {
    const capability = yield* CandidateSession;
    const resource = yield* Effect.acquireRelease(capability.acquire, (owned) => owned.release);
    return yield* resource.inspect;
  }),
);
