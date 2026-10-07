import assert from "node:assert/strict";
import test from "node:test";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import * as Effect from "effect/Effect";
import * as Context from "effect/Context";
import * as Layer from "effect/Layer";
import * as Deferred from "effect/Deferred";
import * as Fiber from "effect/Fiber";
import * as Exit from "effect/Exit";
import { createPersonalSliceOperation, type PersonalSliceDependencies, type SliceSelector, type SlicePage, type SliceSourceLease, type SliceDeliveryLease, type SliceCommitDecision, type OwnedSliceArtifact } from "../src/operations/personal-slice.js";
import { combinedSliceVectors, combinedSliceOriginalRecords, combinedSliceAcceptedObligations, combinedSliceSourceRecipes, combinedSliceBaselineRequest } from "./combined-slice-vectors.js";
import { personalRecordVectors, acceptedContractCaseMap } from "./personal-codecs-vectors.js";
interface Fixture {
  readonly case_id: string; readonly request_json: string | null; readonly input_kind?: string;
  readonly scenario: { readonly source_fixture: string; readonly authority: string; readonly delivery: string; readonly cancel_at?: string; readonly release_fault?: string; readonly change_at?: string };
  readonly expected: Readonly<Record<string, unknown>>;
}
const vectors: readonly Fixture[] = combinedSliceVectors;
class FixtureEnvironment extends Context.Service<FixtureEnvironment, PersonalSliceDependencies>()("candidate.test.PersonalSliceEnvironment") {}
const json = <A>(value: unknown): A => JSON.parse(JSON.stringify(value)) as A;
function frozen(value: unknown): void { if (value !== null && typeof value === "object") { assert.ok(Object.isFrozen(value)); for (const child of Object.values(value)) frozen(child); } }
const scopeSlots = combinedSliceBaselineRequest.slots;
function sourcePages(slot: SliceSelector, recipe: string): readonly SlicePage[] {
  const index = slot.slot === "health" ? 0 : slot.slot === "location" ? 1 : 2;
  const base = (ordinal: number, terminal: boolean, records: readonly string[]): SlicePage => ({ ordinal, terminal, dataset_revision: "synthetic-revision-a", snapshot_id: recipe === "snapshot_crosswire" && slot.slot === "location" ? "synthetic-snapshot-other" : "synthetic-snapshot-a", source_binding: slot, records_json: records });
  const raw = combinedSliceOriginalRecords[index]!.input_json;
  if (slot.slot !== "health") return [base(0, true, [raw])];
  if (recipe === "same_original_twice") return [base(0, true, [raw, raw])];
  if (recipe === "same_key_changed_bytes") { const changed = json<{ payload: { value: { decimal: string } } }>(JSON.parse(raw)); changed.payload.value.decimal = "9007199254740994"; return [base(0, true, [raw, JSON.stringify(changed)])]; }
  if (recipe === "nine_pages") return Array.from({ length: 9 }, (_, ordinal) => base(ordinal, ordinal === 8, []));
  if (recipe === "thirty_three_records") return Array.from({ length: 5 }, (_, ordinal) => base(ordinal, ordinal === 4, Array.from({ length: Math.min(8, 33 - ordinal * 8) }, () => raw)));
  if (recipe === "record_65537_utf8") return [base(0, true, [raw + " ".repeat(65537 - Buffer.byteLength(raw, "utf8"))])];
  if (recipe === "page_1048577_utf8") return [{ ...base(0, true, []), source_binding: { ...slot, profile: "x".repeat(1048577) } }];
  if (recipe === "output_over_limit") {
    const template = combinedSliceSourceRecipes.output_over_limit;
    const records = template.records.map((record) => { const value = json<{ record_id: string; lineage: { original_record: { value: string } } }>(JSON.parse(raw)); value.record_id = record.record_id_prefix + "x".repeat(record.record_id_total_scalar_count - record.record_id_prefix.length); value.lineage.original_record.value = record.original_record_value; const text = JSON.stringify(value); assert.ok(Buffer.byteLength(text) <= 65536); return text; });
    return template.pages.map((p) => base(p.ordinal, p.terminal, p.recipe_record_ordinals.map((i) => records[i]!)));
  }
  return [base(0, true, [raw])];
}
for (const vector of vectors) test(`combined literal ${vector.case_id}`, async () => {
  await Effect.runPromise(Effect.gen(function* () {
    const entered = yield* Deferred.make<void>(), proceed = yield* Deferred.make<void>(), cleanupEntered = yield* Deferred.make<void>(), cleanupAck = yield* Deferred.make<void>();
    let sourceAcquires = 0, sourceReleases = 0, sourceReads = 0, deliveryAcquires = 0, deliveryReleases = 0, commitCalls = 0, authorityCalls = 0, traps = 0;
    let suppressed = false, cancelStarted = false;
    let terminalDecision: SliceCommitDecision | null = null, submitted: OwnedSliceArtifact | undefined;
    const scenario = vector.scenario;
    const releaseAck = Effect.gen(function* () { if (cancelStarted) { yield* Deferred.succeed(cleanupEntered, undefined); yield* Deferred.await(cleanupAck); } });
    const dependencies: PersonalSliceDependencies = {
      authority: {
        check(r, slot, phase) {
          authorityCalls++; frozen(r); if (slot) frozen(slot);
          // Synthetic catalog is independent of caller strings and payload flags.
          const binding = r.dataset_id === "synthetic-dataset-a" && r.dataset_revision === "synthetic-revision-a" && r.snapshot_id === "synthetic-snapshot-a" && r.caller_binding === "synthetic-caller-a" && r.grant_revision === "1" && r.suppression_revision === "1"
            && (!slot || scopeSlots.some((s) => Object.keys(s).every((key) => s[key as keyof typeof s] === slot[key as keyof SliceSelector])));
          if (scenario.authority === "initial_permitted_then_suppressed" && phase === scenario.change_at) suppressed = true;
          const permitted = !suppressed && !["destination_denied", "frontier_absent", "purpose_denied"].includes(scenario.authority)
            && !(slot?.slot === "location" && ["location_denied", "location_detail_denied"].includes(scenario.authority)) && scenario.source_fixture !== "browser_title_capability";
          return { permitted, binding_matches: binding && !["crosswire", "frontier_stale"].includes(scenario.authority), availability: slot?.slot === "location" && scenario.authority === "location_unavailable" ? "unavailable" : slot?.slot === "location" && scenario.authority === "location_unknown" ? "unknown" : "available", coverage: "partial" };
        },
        codec_context: { authorize(descriptor) {
          frozen(descriptor); assert.ok(!JSON.stringify(descriptor).includes("9007199254740993")); assert.ok(!Object.hasOwn(descriptor, "payload"));
          const l = descriptor.lineage;
          const bound = l.dataset_id === "synthetic-dataset-a" && l.source_revision === "synthetic-source-contract1" && l.purpose === "synthetic_local_collection"
            && scopeSlots.some((s) => s.domain === descriptor.domain && s.payload_kind === descriptor.payload_kind && s.source_id === l.source_id);
          // Host classification, not descriptor.claimed_app_class, determines title eligibility.
          return { permitted: bound && !suppressed, authority_binding: "synthetic-authoritative-catalog", frontier_binding: "synthetic-external-current-frontier", app_class: descriptor.payload_kind === "usage_aggregate" ? "browser" : null, title_permitted: false };
        } },
      },
      sources: { open: (_r, selector) => Effect.gen(function* () {
        if (scenario.cancel_at === "before_source") { yield* Deferred.succeed(entered, undefined); return yield* Effect.never; }
        const pages = sourcePages(selector, scenario.source_fixture);
        const lease: SliceSourceLease = { readPage: (ordinal) => Effect.gen(function* () {
          sourceReads++;
          if (scenario.cancel_at === "page_pending") { yield* Deferred.succeed(entered, undefined); return yield* Effect.never; }
          const page = pages[ordinal]; assert.ok(page); return page;
        }) };
        return yield* Effect.acquireRelease(Effect.gen(function* () {
          sourceAcquires++;
          if (scenario.cancel_at === "allocation_completed_before_registration") { yield* Deferred.succeed(entered, undefined); yield* Deferred.await(proceed); }
          return lease;
        }), () => Effect.gen(function* () {
          if ((scenario.cancel_at === "source_release_pending" && selector.slot === "health") || (scenario.cancel_at === "before_commit" && selector.slot === "usage")) { yield* Deferred.succeed(entered, undefined); yield* Deferred.await(proceed); }
          yield* releaseAck;
          if (scenario.source_fixture === "source_cleanup_defect") return yield* Effect.die("SYNTHETIC_PROVIDER_SECRET");
          sourceReleases++;
        }));
      }) },
      delivery: { open: () => Effect.acquireRelease(Effect.sync(() => {
        deliveryAcquires++;
        const lease: SliceDeliveryLease = { commit: (artifact, guard) => Effect.gen(function* () {
          commitCalls++; assert.equal(sourceAcquires, sourceReleases, "sources must acknowledge cleanup before delivery"); frozen(artifact);
          if (scenario.cancel_at === "commit_pending") { yield* Deferred.succeed(entered, undefined); yield* Deferred.await(proceed); }
          if (!guard()) { terminalDecision = "definitely_not_committed"; return terminalDecision; }
          submitted = artifact;
          terminalDecision = scenario.delivery as SliceCommitDecision; return terminalDecision;
        }) };
        return lease;
      }), () => Effect.gen(function* () {
        if (scenario.cancel_at === "delivery_release_pending") { yield* Deferred.succeed(entered, undefined); yield* Deferred.await(proceed); }
        yield* releaseAck;
        if (scenario.release_fault) return yield* Effect.die(scenario.release_fault);
        deliveryReleases++;
      })) },
    };
    let input: unknown = vector.request_json;
    if (vector.input_kind === "object" || vector.input_kind === "array" || vector.input_kind === "foreign_owned_record") input = vector.input_kind === "array" ? [] : vector.input_kind === "foreign_owned_record" ? json(combinedSliceOriginalRecords[0]!.expected_record) : {};
    if (vector.input_kind === "proxy") input = new Proxy({}, { get() { traps++; throw Error("SYNTHETIC_PROVIDER_SECRET"); }, ownKeys() { traps++; throw Error("SYNTHETIC_PROVIDER_SECRET"); }, getPrototypeOf() { traps++; throw Error("SYNTHETIC_PROVIDER_SECRET"); } });
    if (vector.input_kind === "accessor") input = Object.defineProperty({}, "schema", { get() { traps++; throw Error("SYNTHETIC_PROVIDER_SECRET"); } });
    const operation = Effect.gen(function* () { const environment = yield* FixtureEnvironment; return yield* createPersonalSliceOperation(environment).run(input); }).pipe(Effect.provide(Layer.succeed(FixtureEnvironment)(dependencies)));
    const exit = scenario.cancel_at ? yield* Effect.gen(function* () {
      const work = yield* Effect.forkChild(operation); yield* Deferred.await(entered); cancelStarted = true;
      const interrupting = yield* Effect.forkChild(Fiber.interrupt(work)); yield* Effect.yieldNow;
      yield* Deferred.succeed(proceed, undefined);
      if (scenario.cancel_at !== "before_source") { yield* Deferred.await(cleanupEntered); assert.equal(interrupting.pollUnsafe(), undefined, "cancellation cannot complete before owned cleanup acknowledgment"); yield* Deferred.succeed(cleanupAck, undefined); }
      yield* Fiber.join(interrupting); return yield* Fiber.await(work);
    }) : yield* Effect.exit(operation);
    const expected = vector.expected;
    if (expected.result) {
      assert.ok(Exit.isSuccess(exit)); assert.deepEqual(exit.value, expected.result); assert.ok(submitted); assert.deepEqual(submitted.files, expected.artifacts);
      const indices = expected.record_indices as readonly number[];
      assert.deepEqual(submitted.records.map((r) => json(r)), indices.map((i) => combinedSliceOriginalRecords[i]!.expected_record));
    } else {
      assert.ok(Exit.isFailure(exit)); assert.ok(!JSON.stringify(exit.cause).includes("SYNTHETIC_PROVIDER_SECRET"));
      if (expected.exit) assert.ok(Exit.hasInterrupts(exit));
      else { const fails = exit.cause.reasons.filter((r) => r._tag === "Fail"); assert.equal(fails.length, 1); assert.deepEqual(fails[0]!.error, expected.failure); assert.ok(Object.isFrozen(fails[0]!.error)); }
    }
    for (const [name, actual] of [["source_acquisitions", sourceAcquires], ["source_releases", sourceReleases], ["delivery_acquisitions", deliveryAcquires], ["delivery_releases", deliveryReleases], ["commit_calls", commitCalls], ["authority_calls", authorityCalls], ["property_or_proxy_traps", traps]] as const) if (expected[name] !== undefined) assert.equal(actual, expected[name], name);
    if (Object.hasOwn(expected, "job_terminal_decision")) assert.equal(terminalDecision, expected.job_terminal_decision);
    if (scenario.cancel_at === "allocation_completed_before_registration") assert.equal(sourceReads, 0, "canceled ownership handoff must never read");
    assert.equal(traps, 0); assert.equal(commitCalls <= 1, true); assert.equal(deliveryAcquires <= 1, true);
    if (!expected.result && !expected.job_terminal_decision) assert.equal(submitted, undefined);
  }));
});

test("combined immutable Personal authority and frozen vector provenance", () => {
  assert.deepEqual(combinedSliceOriginalRecords, personalRecordVectors); assert.deepEqual(combinedSliceAcceptedObligations, acceptedContractCaseMap); assert.equal(combinedSliceAcceptedObligations.length, 81);
  const bytes = readFileSync(new URL("../../tests/combined-slice-vectors.ts", import.meta.url));
  assert.equal(createHash("sha256").update(bytes).digest("hex"), "2a87777579998eab5901cf4b3089c11bfad01789060904680d40ef7848d52b35");
});

test("combined interruption with failed cleanup reports unavailable acknowledgment without provider cause", async () => {
  await Effect.runPromise(Effect.gen(function* () {
    const reading = yield* Deferred.make<void>(); let releaseAttempts = 0, deliveries = 0;
    const request = { ...combinedSliceBaselineRequest, slots: [combinedSliceBaselineRequest.slots[0]!] };
    const dependencies: PersonalSliceDependencies = {
      authority: { check: () => ({ permitted: true, binding_matches: true, availability: "available", coverage: "partial" }), codec_context: { authorize: () => { throw Error("must not decode an interrupted read"); } } },
      sources: { open: () => Effect.acquireRelease(Effect.succeed<SliceSourceLease>({ readPage: () => Deferred.succeed(reading, undefined).pipe(Effect.andThen(Effect.never)) }), () => Effect.gen(function* () { releaseAttempts++; return yield* Effect.die({ secret: "SYNTHETIC_PROVIDER_SECRET" }); })) },
      delivery: { open: () => Effect.sync(() => { deliveries++; throw Error("must not deliver"); }) },
    };
    const work = yield* Effect.forkChild(createPersonalSliceOperation(dependencies).run(JSON.stringify(request)));
    yield* Deferred.await(reading); yield* Fiber.interrupt(work); const exit = yield* Fiber.await(work);
    assert.ok(Exit.isFailure(exit)); assert.ok(Exit.hasInterrupts(exit)); assert.equal(releaseAttempts, 1); assert.equal(deliveries, 0);
    assert.ok(!JSON.stringify(exit.cause).includes("SYNTHETIC_PROVIDER_SECRET"));
    const errors = exit.cause.reasons.filter((reason) => reason._tag === "Fail"); assert.equal(errors.length, 1);
    assert.deepEqual(errors[0]!.error, { _tag: "PersonalSliceFailure", code: "cleanup_unacknowledged" });
  }));
});

for (const revokeAt of ["before_page", "before_record", "before_encode", "inside_codec_callback"] as const) test(`combined distinct job-only revocation ${revokeAt}`, async () => {
  await Effect.runPromise(Effect.gen(function* () {
    let destinationGranted = true, sourceAcquires = 0, sourceReleases = 0, pageReads = 0, codecCalls = 0, deliveries = 0;
    const request = { ...combinedSliceBaselineRequest, slots: [combinedSliceBaselineRequest.slots[0]!] };
    const selector: SliceSelector = request.slots[0]!;
    const dependencies: PersonalSliceDependencies = {
      authority: {
        check(_r, slot, phase) {
          if (slot === null && phase === revokeAt) destinationGranted = false;
          // Source/detail grants remain independently permitted throughout.
          return { permitted: slot !== null || destinationGranted, binding_matches: true, availability: "available", coverage: "partial" };
        },
        codec_context: { authorize() {
          codecCalls++; if (revokeAt === "inside_codec_callback") destinationGranted = false;
          return { permitted: true, authority_binding: "synthetic-source-still-granted", frontier_binding: "current-external-frontier", app_class: null, title_permitted: false };
        } },
      },
      sources: { open: () => Effect.acquireRelease(Effect.sync(() => {
        sourceAcquires++;
        return { readPage: () => Effect.sync(() => { pageReads++; return { ordinal: 0, terminal: true, dataset_revision: "synthetic-revision-a", snapshot_id: "synthetic-snapshot-a", source_binding: selector, records_json: [combinedSliceOriginalRecords[0]!.input_json] }; }) };
      }), () => Effect.sync(() => { sourceReleases++; })) },
      delivery: { open: () => Effect.sync(() => { deliveries++; throw Error("destination revoked: must not open delivery"); }) },
    };
    const exit = yield* Effect.exit(createPersonalSliceOperation(dependencies).run(JSON.stringify(request)));
    assert.ok(Exit.isFailure(exit)); assert.ok(!JSON.stringify(exit.cause).includes("synthetic-source-still-granted"));
    const errors = exit.cause.reasons.filter((reason) => reason._tag === "Fail"); assert.equal(errors.length, 1);
    assert.deepEqual(errors[0]!.error, { _tag: "PersonalSliceFailure", code: "scope_not_authorized" });
    assert.equal(sourceAcquires, 1); assert.equal(sourceReleases, 1); assert.equal(deliveries, 0);
    assert.equal(pageReads, revokeAt === "before_page" ? 0 : 1);
    assert.equal(codecCalls, revokeAt === "before_page" || revokeAt === "before_record" ? 0 : 1, "no later decode/encode authorization after job grant revocation");
  }));
});

test("combined source authority reentry revokes destination before page materialization", async () => {
  const revokeAt = "before_page";
  await Effect.runPromise(Effect.gen(function* () {
    let destinationGranted = true, sourceAcquires = 0, sourceReleases = 0, pageReads = 0, payloadMaterializations = 0, codecCalls = 0, deliveries = 0;
    const request = { ...combinedSliceBaselineRequest, slots: [combinedSliceBaselineRequest.slots[0]!] };
    const selector: SliceSelector = request.slots[0]!;
    const dependencies: PersonalSliceDependencies = {
      authority: {
        check(_r, slot, phase) {
          if (slot !== null && phase === revokeAt) destinationGranted = false;
          // Source/detail grants remain independently permitted throughout.
          return { permitted: slot !== null || destinationGranted, binding_matches: true, availability: "available", coverage: "partial" };
        },
        codec_context: { authorize() {
          codecCalls++;
          return { permitted: true, authority_binding: "synthetic-source-still-granted", frontier_binding: "current-external-frontier", app_class: null, title_permitted: false };
        } },
      },
      sources: { open: () => Effect.acquireRelease(Effect.sync(() => {
        sourceAcquires++;
        return { readPage: () => Effect.sync(() => { pageReads++; payloadMaterializations++; return { ordinal: 0, terminal: true, dataset_revision: "synthetic-revision-a", snapshot_id: "synthetic-snapshot-a", source_binding: selector, records_json: [combinedSliceOriginalRecords[0]!.input_json] }; }) };
      }), () => Effect.sync(() => { sourceReleases++; })) },
      delivery: { open: () => Effect.sync(() => { deliveries++; throw Error("destination revoked: must not open delivery"); }) },
    };
    const exit = yield* Effect.exit(createPersonalSliceOperation(dependencies).run(JSON.stringify(request)));
    assert.ok(Exit.isFailure(exit)); assert.ok(!JSON.stringify(exit.cause).includes("synthetic-source-still-granted"));
    const errors = exit.cause.reasons.filter((reason) => reason._tag === "Fail"); assert.equal(errors.length, 1);
    assert.deepEqual(errors[0]!.error, { _tag: "PersonalSliceFailure", code: "scope_not_authorized" });
    assert.equal(sourceAcquires, 1); assert.equal(sourceReleases, 1); assert.equal(deliveries, 0);
    assert.equal(pageReads, 0); assert.equal(payloadMaterializations, 0);
    assert.equal(codecCalls, 0, "no later decode/encode authorization after job grant revocation");
  }));
});

test("combined crosswired source record refuses metadata before globally permitted codec authorization", async () => {
  await Effect.runPromise(Effect.gen(function* () {
    let acquisitions = 0, releases = 0, codecCalls = 0, deliveries = 0;
    const dependencies: PersonalSliceDependencies = {
      authority: {
        check: () => ({ permitted: true, binding_matches: true, availability: "available", coverage: "partial" }),
        codec_context: { authorize() { codecCalls++; return { permitted: true, authority_binding: "synthetic-globally-permitted", frontier_binding: "synthetic-current", app_class: null, title_permitted: false }; } },
      },
      sources: { open: (_request, selector) => Effect.acquireRelease(Effect.sync(() => {
        acquisitions++;
        // The health lease is valid and empty; the location lease crosswires the health raw record.
        const records = selector.slot === "location" ? [combinedSliceOriginalRecords[0]!.input_json] : [];
        return { readPage: () => Effect.succeed({ ordinal: 0, terminal: true, dataset_revision: "synthetic-revision-a", snapshot_id: "synthetic-snapshot-a", source_binding: selector, records_json: records }) };
      }), () => Effect.sync(() => { releases++; })) },
      delivery: { open: () => Effect.sync(() => { deliveries++; throw Error("crosswire must not deliver"); }) },
    };
    const exit = yield* Effect.exit(createPersonalSliceOperation(dependencies).run(JSON.stringify(combinedSliceBaselineRequest)));
    assert.ok(Exit.isFailure(exit)); const failures = exit.cause.reasons.filter((reason) => reason._tag === "Fail"); assert.equal(failures.length, 1);
    assert.deepEqual(failures[0]!.error, { _tag: "PersonalSliceFailure", code: "scope_binding_mismatch" });
    assert.equal(acquisitions, 2); assert.equal(releases, 2); assert.equal(codecCalls, 0, "no globally admitted health callback for a location-bound record"); assert.equal(deliveries, 0);
  }));
});
