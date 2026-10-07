import assert from "node:assert/strict";
import test from "node:test";
import * as Effect from "effect/Effect";
import * as Deferred from "effect/Deferred";
import * as Fiber from "effect/Fiber";
import * as Exit from "effect/Exit";
import { createLocationPointProjector, type LocationPointAuthority, type LocationPointLease, type LocationPointProjectionFailure, type LocationPointProjectionFailureCode } from "../src/location/point-projection.js";
import { locationPointProjectionVectors, locationPointProjectionProvenance } from "./location-point-projection-vectors.js";
interface Fixture { case_id: string; request_json: string; request_argument_kind?: string; source_json: string; host_fixture: { acquire: string; codec_authorize: readonly string[]; materialize: string; cleanup: string }; expected: { outcome: string; failure_code?: string; expected_record?: unknown; expected_canonical_json?: string; eligible_evidence_ref?: string; retained_original_bits_via_eligible_evidence_ref?: string; acquire_calls: number; materialize_calls: number; codec_authorize_calls: number; published: boolean; cleanup_acknowledged: boolean } }
const fixtures: readonly Fixture[] = locationPointProjectionVectors;
const failure = (code: LocationPointProjectionFailureCode): LocationPointProjectionFailure => Object.freeze({ _tag: "LocationPointProjectionFailure", code });
function freezeTree(value: unknown): void { if (value !== null && typeof value === "object") { assert.ok(Object.isFrozen(value)); for (const child of Object.values(value)) freezeTree(child); } }
for (const vector of fixtures) test(`location literal ${vector.case_id}`, async () => {
  await Effect.runPromise(Effect.gen(function* () {
    const entered = yield* Deferred.make<void>();
    let acquireCalls = 0, materializeCalls = 0, authorizeCalls = 0, cleanup = false, traps = 0;
    let revoked = false;
    const authority: LocationPointAuthority = { acquire: (descriptor) => Effect.gen(function* () {
      acquireCalls++; freezeTree(descriptor); assert.deepEqual(Object.keys(descriptor).sort(), ["dataset_id", "profile", "purpose", "record_id", "source_id", "source_revision"]);
      const config = vector.host_fixture;
      if (config.acquire === "throw_synthetic_private_provider") return yield* Effect.die({ private_payload: "synthetic-private" });
      if (config.acquire === "interrupt_preparation") return yield* Effect.interrupt;
      if (config.acquire !== "allow_current" && config.acquire !== "complete_allocation_then_interrupt_registered_scope") return yield* Effect.fail(failure("scope_not_authorized"));
      const lease: LocationPointLease = {
        materializeOriginalJSON: () => Effect.gen(function* () {
          materializeCalls++;
          if (config.materialize === "throw_synthetic_private_provider") return yield* Effect.die({ private_payload: "synthetic-private" });
          if (config.materialize === "wait_until_interrupted") { yield* Deferred.succeed(entered, undefined); return yield* Effect.never; }
          return vector.source_json;
        }),
        authorize(d) {
          freezeTree(d); const decision = config.codec_authorize[authorizeCalls++];
          if (authorizeCalls > 1) assert.equal(cleanup, true, "publication authority must follow cleanup acknowledgment");
          assert.ok(!JSON.stringify(d).includes("synthetic-original-evidence-a"));
          if (decision === "throw_synthetic_private_provider") throw { private_payload: "synthetic-private" };
          const lineage = d.lineage;
          const bound = d.domain === "location" && d.payload_kind === "location_point" && d.record_id === descriptor.record_id
            && lineage.dataset_id === descriptor.dataset_id && lineage.source_id === descriptor.source_id && lineage.source_revision === descriptor.source_revision && lineage.purpose === descriptor.purpose
            && d.requested_detail.length === 1 && d.requested_detail[0] === "location_exact_point";
          return { permitted: decision === "allow_current" && !revoked && bound, authority_binding: "synthetic-qualified-source", frontier_binding: "synthetic-current-independent-frontier", app_class: null, title_permitted: false };
        },
      };
      const owned = yield* Effect.acquireRelease(Effect.succeed(lease), () => Effect.gen(function* () {
        if (config.cleanup === "fail_synthetic_private_provider") return yield* Effect.die({ private_payload: "synthetic-private" });
        cleanup = true; if (config.cleanup === "acknowledged_then_revoke_current") revoked = true;
      }));
      if (config.acquire === "complete_allocation_then_interrupt_registered_scope") return yield* Effect.interrupt;
      return owned;
    }) };
    let input: unknown = vector.request_json;
    if (vector.request_argument_kind === "throwing_proxy") input = new Proxy({}, { get() { traps++; throw Error("private"); }, ownKeys() { traps++; throw Error("private"); }, getPrototypeOf() { traps++; throw Error("private"); } });
    if (vector.request_argument_kind === "revoked_proxy") { const proxy = Proxy.revocable({}, {}); proxy.revoke(); input = proxy.proxy; }
    const operation = createLocationPointProjector(authority).project(input);
    const exit = vector.host_fixture.materialize === "wait_until_interrupted"
      ? yield* Effect.gen(function* () { const fiber = yield* Effect.forkChild(operation); yield* Deferred.await(entered); yield* Fiber.interrupt(fiber); return yield* Fiber.await(fiber); })
      : yield* Effect.exit(operation);
    const expected = vector.expected;
    if (expected.outcome === "projected") {
      assert.ok(Exit.isSuccess(exit)); freezeTree(exit.value);
      assert.equal(exit.value._tag, "ProjectedLocationPoint"); assert.deepEqual(JSON.parse(JSON.stringify(exit.value.record)), expected.expected_record);
      assert.equal(exit.value.canonical_json, expected.expected_canonical_json); assert.equal(exit.value.eligible_evidence_ref, expected.eligible_evidence_ref);
      if (expected.retained_original_bits_via_eligible_evidence_ref) {
        const retained = JSON.parse(vector.source_json) as { eligible_evidence_ref: string; point: { payload: { horizontal_accuracy: { bits?: string }; speed: { value?: { bits: string } } } } };
        assert.equal(retained.eligible_evidence_ref, exit.value.eligible_evidence_ref);
        assert.ok(retained.point.payload.horizontal_accuracy.bits === expected.retained_original_bits_via_eligible_evidence_ref || retained.point.payload.speed.value?.bits === expected.retained_original_bits_via_eligible_evidence_ref);
        assert.ok(!exit.value.canonical_json.includes(expected.retained_original_bits_via_eligible_evidence_ref));
      }
    } else {
      assert.ok(Exit.isFailure(exit)); assert.ok(!JSON.stringify(exit.cause).includes("synthetic-private"));
      if (expected.outcome === "interrupted") assert.ok(Exit.hasInterrupts(exit));
      else { assert.equal(exit.cause.reasons.length, 1); const reason = exit.cause.reasons[0]!; assert.equal(reason._tag, "Fail"); if (reason._tag === "Fail") { assert.deepEqual(reason.error, { _tag: "LocationPointProjectionFailure", code: expected.failure_code }); assert.ok(Object.isFrozen(reason.error)); } }
    }
    assert.equal(acquireCalls, expected.acquire_calls); assert.equal(materializeCalls, expected.materialize_calls); assert.equal(authorizeCalls, expected.codec_authorize_calls); assert.equal(cleanup, expected.cleanup_acknowledged); assert.equal(traps, 0);
  }));
});

test("location cancellation waits for asynchronous owned cleanup acknowledgment", async () => {
  await Effect.runPromise(Effect.gen(function* () {
    const reading = yield* Deferred.make<void>(), releasing = yield* Deferred.make<void>(), acknowledged = yield* Deferred.make<void>();
    let done = false, published = false, materialize = 0;
    const authority: LocationPointAuthority = { acquire: () => Effect.acquireRelease(Effect.succeed<LocationPointLease>({
      materializeOriginalJSON: () => Deferred.succeed(reading, undefined).pipe(Effect.andThen(Effect.sync(() => { materialize++; })), Effect.andThen(Effect.never)),
      authorize: () => { throw Error("must not authorize canceled read"); },
    }), () => Effect.gen(function* () { yield* Deferred.succeed(releasing, undefined); yield* Deferred.await(acknowledged); done = true; })) };
    const work = yield* Effect.forkChild(createLocationPointProjector(authority).project(fixtures[0]!.request_json).pipe(Effect.tap(() => Effect.sync(() => { published = true; }))));
    yield* Deferred.await(reading); const interruption = yield* Effect.forkChild(Fiber.interrupt(work)); yield* Deferred.await(releasing);
    assert.equal(done, false); assert.equal(published, false); yield* Deferred.succeed(acknowledged, undefined); yield* Fiber.join(interruption);
    const exit = yield* Fiber.await(work); assert.ok(Exit.hasInterrupts(exit)); assert.equal(done, true); assert.equal(materialize, 1); assert.equal(published, false);
  }));
});
test("location completed allocation handoff is owned when cancellation arrives during allocation", async () => {
  await Effect.runPromise(Effect.gen(function* () {
    const allocated = yield* Deferred.make<void>(), finish = yield* Deferred.make<void>(); let allocations = 0, releases = 0, reads = 0;
    const lease: LocationPointLease = { materializeOriginalJSON: () => Effect.sync(() => { reads++; return fixtures[0]!.source_json; }), authorize: () => ({ permitted: true, authority_binding: "synthetic", frontier_binding: "current", app_class: null, title_permitted: false }) };
    const authority: LocationPointAuthority = { acquire: () => Effect.acquireRelease(Effect.gen(function* () { allocations++; yield* Deferred.succeed(allocated, undefined); yield* Deferred.await(finish); return lease; }), () => Effect.sync(() => { releases++; })) };
    const work = yield* Effect.forkChild(createLocationPointProjector(authority).project(fixtures[0]!.request_json)); yield* Deferred.await(allocated);
    const interruption = yield* Effect.forkChild(Fiber.interrupt(work)); yield* Effect.yieldNow; yield* Deferred.succeed(finish, undefined); yield* Fiber.join(interruption);
    assert.ok(Exit.hasInterrupts(yield* Fiber.await(work))); assert.equal(allocations, 1); assert.equal(releases, 1); assert.equal(reads, 0);
  }));
});
test("location cancellation strips cleanup defect payload without claiming acknowledged cleanup", async () => {
  await Effect.runPromise(Effect.gen(function* () {
    const entered = yield* Deferred.make<void>(); let attempted = 0;
    const authority: LocationPointAuthority = { acquire: () => Effect.acquireRelease(Effect.succeed<LocationPointLease>({ materializeOriginalJSON: () => Deferred.succeed(entered, undefined).pipe(Effect.andThen(Effect.never)), authorize: () => { throw Error("unreachable"); } }), () => Effect.gen(function* () { attempted++; return yield* Effect.die({ private_payload: "synthetic-private" }); })) };
    const work = yield* Effect.forkChild(createLocationPointProjector(authority).project(fixtures[0]!.request_json)); yield* Deferred.await(entered); yield* Fiber.interrupt(work);
    const exit = yield* Fiber.await(work); assert.ok(Exit.hasInterrupts(exit)); assert.equal(attempted, 1); assert.ok(!JSON.stringify(exit).includes("synthetic-private"));
  }));
});
test("location source obligations remain81 with10 frozen source refs", () => { assert.equal(locationPointProjectionProvenance.immutable_obligations, 81); assert.equal(locationPointProjectionProvenance.literal_contract_refs.length, 10); });
