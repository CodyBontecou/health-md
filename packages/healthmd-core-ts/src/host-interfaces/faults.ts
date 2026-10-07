import * as Data from "effect/Data";

/** Stable health-free failures: never wrap provider errors or request payloads. */
export class CapabilityUnavailable extends Data.TaggedError("CapabilityUnavailable")<{}> {
  readonly code = "capability_unavailable";
  override readonly message = "Candidate capability unavailable";
}

export class CapabilityFailed extends Data.TaggedError("CapabilityFailed")<{}> {
  readonly code = "capability_failed";
  override readonly message = "Candidate capability failed";
}

export type CapabilityFault = CapabilityUnavailable | CapabilityFailed;
