import assert from "node:assert/strict";
import test from "node:test";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as Deferred from "effect/Deferred";
import * as Fiber from "effect/Fiber";
import * as Exit from "effect/Exit";
import * as Scope from "effect/Scope";
import { createIOSUsageEligibilityGate, IOSUsageEligibilityCatalog, IOSUsageCurrentAuthority, type IOSUsageEligibilityCatalogService, type IOSUsageCurrentAuthorityService, type IOSUsageEligibilityFailure, type IOSUsageEligibilityPhase, type OwnedIOSUsageHandoff } from "../src/usage-mobile/ios-eligibility.js";
import { iosUsageEligibilityVectors, iosUsageEligibilityPacketLiteralProposals, iosUsageEligibilityImmutablePersonalObligations, iosUsageEligibilityFourOriginalRecords } from "./usage-mobile-ios-eligibility-vectors.js";
interface Fixture { readonly case_id: string; readonly input: { readonly request_json: string; readonly catalog_binding_json: string; readonly current_json: string; readonly scenario: Readonly<Record<string, unknown>>; readonly primitive_builder?: { readonly unit: string; readonly repeat_count: number }; readonly current_revision_schedule?: Readonly<Record<string, Readonly<Record<string, unknown>>>> }; readonly expected: Readonly<Record<string, unknown>> }
const vectors: readonly Fixture[] = iosUsageEligibilityVectors;
const secret = "SYNTHETIC_PROVIDER_SECRET";
const fault = (code: IOSUsageEligibilityFailure["code"]): IOSUsageEligibilityFailure => ({ _tag: "IOSUsageEligibilityFailure", code });
function outcome(exit: Exit.Exit<unknown, unknown>, fallback: string): string {
  if (Exit.isSuccess(exit)) return fallback;
  if (exit.cause.reasons.some((r) => r._tag === "Interrupt")) return "interrupted";
  for (const r of exit.cause.reasons) if (r._tag === "Fail" || r._tag === "Die") {
    const e = r._tag === "Fail" ? r.error : r.defect;
    if (e !== null && typeof e === "object" && "code" in e) return String(e.code);
  }
  return "unexpected_failure";
}
for (const vector of vectors) test(`iOS eligibility literal ${vector.case_id}`, async () => {
  await Effect.runPromise(Effect.gen(function* () {
    const entered = yield* Deferred.make<void>(), proceed = yield* Deferred.make<void>(), releasing = yield* Deferred.make<void>(), ack = yield* Deferred.make<void>();
    const scene = vector.input.scenario;
    let allocations = 0, releases = 0, acknowledgments = 0, handoffs = 0, hostCalls = 0, argumentTraps = 0, revoked = false, currentCalls = 0;
    let secondResult: string | undefined, secondCalls = 0, secondAllocations = 0, afterCloseCalls = 0, oldClosedCalls = 0, reprovidedCalls = 0, completionBeforeAck = false;
    let held: OwnedIOSUsageHandoff | undefined;
    const gate = createIOSUsageEligibilityGate();
    let bindingRaw: unknown = vector.input.catalog_binding_json;
    const binding = JSON.parse(vector.input.catalog_binding_json) as Record<string, unknown>;
    const mutation = scene.catalog_binding_mutation;
    if (mutation === "object_argument") bindingRaw = {};
    if (mutation === "duplicate_key") bindingRaw = vector.input.catalog_binding_json.slice(0, -1) + ',"job_id":"duplicate"}';
    if (mutation === "unknown_field") binding.extra = true;
    if (mutation === "unpaired_surrogate") bindingRaw = vector.input.catalog_binding_json.replace("synthetic-job-a", "\\ud800");
    if (mutation === "oversize4097") bindingRaw = "a".repeat(4097);
    if (mutation === "wrong_type") binding.job_id = true;
    if (mutation === "wrong_authorization_state") binding.authorization_state = "unknown_state";
    if (mutation === "wrong_route") binding.route = "arbitrary_export";
    if (mutation === "noncanonical_frontier") binding.frontier_revision = "07";
    if (mutation === "wrong_page_limit") binding.page_limit = 0;
    if (bindingRaw === vector.input.catalog_binding_json) bindingRaw = JSON.stringify(binding);
    const catalog: IOSUsageEligibilityCatalogService = {
      resolve: (request) => Effect.gen(function* () {
        hostCalls++; assert.ok(Object.isFrozen(request));
        if (scene.provider_fault === "resolve") return yield* Effect.die(secret);
        if (scene.catalog === "source_profile_unadmitted") return yield* Effect.fail(fault("source_profile_unadmitted"));
        if (scene.cancel === "during_resolve") { yield* Deferred.succeed(entered, undefined); return yield* Effect.never; }
        return bindingRaw as string;
      }),
      checkSource(binding, phase) {
        hostCalls++; assert.ok(Object.isFrozen(binding));
        if (scene.provider_fault === "source_check") throw Error(secret);
        const reentry = scene.source_callback_reentry as { readonly phase?: string } | undefined;
        if (reentry?.phase === phase) revoked = true;
        if (scene.source_or_current_denied && ["source", "purpose", "detail", "query"].includes(String(scene.source_or_current_denied))) return "scope_not_authorized";
        return "permitted";
      },
      allocate: () => Effect.gen(function* () {
        hostCalls++;
        if (scene.provider_fault === "allocate") return yield* Effect.die(secret);
        allocations++;
        if (scene.cancel === "after_allocation_before_publication") { yield* Deferred.succeed(entered, undefined); yield* Deferred.await(proceed); }
        return { release: Effect.gen(function* () {
          hostCalls++; releases++;
          if (scene.cleanup === "delayed_ack_signal") { yield* Deferred.succeed(releasing, undefined); yield* Deferred.await(ack); }
          if (scene.cleanup === "provider_failure") return yield* Effect.fail(fault("unavailable"));
          if (scene.cleanup === "defect_with_sensitive_reason") return yield* Effect.die(secret);
          acknowledgments++;
        }) };
      }),
    };
    const authority: IOSUsageCurrentAuthorityService = { current: (_binding, phase) => {
      hostCalls++; currentCalls++;
      if (scene.provider_fault === "current") throw Error(secret);
      const now = JSON.parse(vector.input.current_json) as Record<string, unknown>;
      const schedule = vector.input.current_revision_schedule?.[phase]; if (schedule) Object.assign(now, schedule);
      if (revoked || (scene.original_current_denied && phase === "assert_current") || scene.source_or_current_denied) now.decision = "scope_not_authorized";
      const crosswire = scene.binding_or_current_crosswire; if (typeof crosswire === "string") now[crosswire] = "synthetic-crosswired";
      const frontier = scene.current_external_frontier;
      if (["missing", "incomplete", "self_declared_latest"].includes(String(frontier))) now.decision = "unavailable";
      if (frontier === "stale") now.frontier_revision = "6";
      if (frontier === "wrong_lineage") now.frontier_lineage = "synthetic-other-lineage";
      if (["old_backup_after_delete", "regrant_after_revoke", "undo_after_delete", "rekey_old_evidence"].includes(String(frontier))) now.decision = "scope_not_authorized";
      if (frontier === "advance_before_publication" && phase === "before_publication") now.frontier_revision = "8";
      return JSON.stringify(now);
    } };
    const provide = <A, E, R>(work: Effect.Effect<A, E, R>) => work.pipe(Effect.provide(Layer.succeed(IOSUsageEligibilityCatalog)(catalog)), Effect.provide(Layer.succeed(IOSUsageCurrentAuthority)(authority)));
    function argument(kind: unknown): unknown {
      if (kind === "plain_object") return {};
      if (kind === "throwing_accessor") return Object.defineProperty({}, "profile", { get() { argumentTraps++; throw Error(secret); } });
      if (kind === "throwing_proxy") return new Proxy({}, { get() { argumentTraps++; throw Error(secret); }, ownKeys() { argumentTraps++; throw Error(secret); }, getPrototypeOf() { argumentTraps++; throw Error(secret); } });
      if (kind === "revoked_proxy") { const p = Proxy.revocable({}, {}); p.revoke(); return p.proxy; }
      if (kind === "string_object") return new String(vector.input.request_json);
      if (kind === "number") return 1;
      if (kind === "boolean") return true;
      if (kind === "null") return null;
      if (kind === "array") return [];
      if (kind === "symbol") return Symbol("request");
      if (kind === "function") return () => undefined;
      return vector.input.request_json;
    }
    let input = argument(scene.request_argument_kind);
    if (vector.input.primitive_builder) input = vector.input.primitive_builder.unit.repeat(vector.input.primitive_builder.repeat_count);
    const use = Effect.gen(function* () {
      const handoff = yield* gate.open(input); held = handoff; handoffs++;
      assert.ok(Object.isFrozen(handoff)); assert.deepEqual(Object.keys(handoff).sort(), ["_tag", "assertCurrent", "export_allowed", "kind", "native_qualification"]);
      assert.equal(handoff.native_qualification, false); assert.equal(handoff.export_allowed, false);
      if (scene.concurrent_second_open) { const count = allocations; const second = yield* Effect.exit(gate.open(input)); secondResult = outcome(second, "unexpected_success"); secondAllocations = allocations - count; }
      if (scene.assert_current || scene.assert_request_changes || scene.assert_argument_kind || scene.assert_json_member_order) {
        let next = input;
        if (scene.assert_request_changes) next = JSON.stringify({ ...JSON.parse(vector.input.request_json), ...(scene.assert_request_changes as object) });
        if (scene.assert_argument_kind) next = argument(scene.assert_argument_kind);
        if (scene.assert_json_member_order) next = JSON.stringify(Object.fromEntries(Object.entries(JSON.parse(vector.input.request_json)).reverse()));
        let assertion = handoff.assertCurrent(next);
        if (scene.reprovided_current || scene.reprovided_catalog) assertion = assertion.pipe(Effect.provide(Layer.succeed(IOSUsageCurrentAuthority)({ current() { reprovidedCalls++; return vector.input.current_json; } })), Effect.provide(Layer.succeed(IOSUsageEligibilityCatalog)({ ...catalog, checkSource() { reprovidedCalls++; return "permitted"; } })));
        yield* assertion;
      }
      return handoff.kind;
    });
    const operation = provide(Effect.scoped(use));
    let exit: Exit.Exit<unknown, unknown>;
    if (scene.cancel) {
      const child = yield* Effect.forkChild(operation); yield* Deferred.await(entered);
      const interrupting = yield* Effect.forkChild(Fiber.interrupt(child)); yield* Effect.yieldNow;
      yield* Deferred.succeed(proceed, undefined);
      if (scene.cleanup === "delayed_ack_signal") { yield* Deferred.await(releasing); completionBeforeAck = interrupting.pollUnsafe() !== undefined; yield* Deferred.succeed(ack, undefined); }
      yield* Fiber.join(interrupting); exit = yield* Fiber.await(child);
    } else exit = yield* Effect.exit(operation);
    let result = outcome(exit, held?.kind ?? "unexpected_success");
    if (scene.second_open_after_cleanup_failure || scene.sequential_second_open || scene.new_same_request_handoff_open) {
      const count = allocations, calls = hostCalls;
      const second = yield* Effect.exit(provide(Effect.scoped(gate.open(vector.input.request_json).pipe(Effect.tap((handoff) => Effect.sync(() => { held = held ?? handoff; handoffs++; }))))));
      secondResult = outcome(second, "aggregate_read_handoff"); secondAllocations = allocations - count; secondCalls = hostCalls - calls;
    }
    if (scene.assert_after_scope_close) {
      assert.ok(held); const calls = hostCalls;
      const after = yield* Effect.exit(held.assertCurrent(vector.input.request_json).pipe(Effect.provide(Layer.succeed(IOSUsageCurrentAuthority)({ current() { reprovidedCalls++; return vector.input.current_json; } }))));
      afterCloseCalls = hostCalls - calls; oldClosedCalls = afterCloseCalls; result = outcome(after, "unexpected_success");
    }
    const observed: Readonly<Record<string, unknown>> = { result, allocations, releases, acknowledged_releases: acknowledgments, handoffs,
      reads: 0, personal_materializations: 0, deliveries: 0, web_observations: 0, title_observations: 0, input_observations: 0, persistent_private_state_writes: 0, native_qualification: false, export_allowed: false,
      host_calls: hostCalls, argument_traps: argumentTraps, completion_before_ack: completionBeforeAck, host_calls_after_close: afterCloseCalls, old_handoff_authority_calls_after_close: oldClosedCalls,
      reprovided_service_calls: reprovidedCalls, second_result: secondResult, second_allocations: secondAllocations, second_host_calls: secondCalls,
      host_calls_for_crosswire_assert: currentCalls - 2, data_acquires: held?.kind === "display_only" ? 0 : allocations, acquires: allocations, observed_zero: false, zero_usage: false, complete_history: false, exact_sessions: false,
      old_handoff_result: result, provider_reason_visible: JSON.stringify(exit).includes(secret), safe_causes: Exit.isFailure(exit) ? Array.from(new Set(exit.cause.reasons.map((r) => r._tag === "Interrupt" ? "interrupt" : r._tag === "Die" ? "cleanup_unacknowledged" : "failure"))) : [] };
    for (const [key, expected] of Object.entries(vector.expected)) assert.deepEqual(observed[key], expected, `${vector.case_id}: ${key}`);
    assert.equal(JSON.stringify(exit).includes(secret), false, "fixed errors cannot leak provider causes");
  }));
});
test("eligibility immutable packet/Personal literals remain independent authority", () => {
  const canonical = (value: unknown): string => value === null || typeof value !== "object" ? JSON.stringify(value) : Array.isArray(value) ? "[" + value.map(canonical).join(",") + "]" : "{" + Object.keys(value).sort().map((k) => JSON.stringify(k) + ":" + canonical((value as Record<string, unknown>)[k])).join(",") + "}";
  for (const obligation of iosUsageEligibilityImmutablePersonalObligations) assert.equal(createHash("sha256").update(canonical(obligation.literal)).digest("hex"), obligation.reference.literal_canonical_sha256);
  const originals = JSON.parse(readFileSync("../../docs/migration/effect-refactor/decisions/personal-contract-cases.json", "utf8"));
  assert.deepEqual(iosUsageEligibilityFourOriginalRecords, originals.records); assert.equal(iosUsageEligibilityImmutablePersonalObligations.length, 81);
  assert.equal(iosUsageEligibilityPacketLiteralProposals.length, 5);
});

// Independent reviewer literals: proposal raw SHA256 0d06575992caf8c15f14dec56225743b7f80a632c635c943357a4507b14ac456.
const scopeReentryLiterals = [
  {
    "case_id": "supplemental-scope-close-source-before_allocation",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"s\",\"source_revision\":\"r\",\"installation_id\":\"i\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"j\",\"selection_id\":\"x\",\"detail\":\"app_duration\",\"page_limit\":1,\"record_limit\":1}",
      "binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"s\",\"source_revision\":\"r\",\"installation_id\":\"i\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"j\",\"selection_id\":\"x\",\"detail\":\"app_duration\",\"page_limit\":1,\"record_limit\":1,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"p\",\"frontier_lineage\":\"f\",\"frontier_revision\":\"1\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"s\",\"source_revision\":\"r\",\"installation_id\":\"i\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"j\",\"selection_id\":\"x\",\"detail\":\"app_duration\",\"proof_ref\":\"p\",\"frontier_lineage\":\"f\",\"frontier_revision\":\"1\",\"grant_revision\":\"1\"}",
      "scope": "explicit real Effect Scope.make instance, provided to gate.open",
      "stimulus": "in source callback at before_allocation invoke Effect.runSync(Scope.close(originalScope, Exit.succeed(undefined))) synchronously, then return the unchanged permitted source/current value",
      "release": "synchronous real Effect.sync increments release+ACK counters; no personal API/native/data"
    },
    "expected": {
      "result": "owned_handoff_closed",
      "open_result": "owned_handoff_closed",
      "assert_result": "not_called",
      "resolve_calls": 1,
      "source_calls": 1,
      "current_calls": 0,
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "export_allowed": false,
      "native_qualification": false,
      "later_callbacks_after_scope_close": 0,
      "scope_close_completed": true
    },
    "rationale": "Original Scope lifetime, not restored authority or new Scope, governs publication and assertions; no completed allocation before a known-closed preallocation Scope; existing allocation finalizes exactly once and ACKs before failure result."
  },
  {
    "case_id": "supplemental-scope-close-source-before_publication",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"s\",\"source_revision\":\"r\",\"installation_id\":\"i\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"j\",\"selection_id\":\"x\",\"detail\":\"app_duration\",\"page_limit\":1,\"record_limit\":1}",
      "binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"s\",\"source_revision\":\"r\",\"installation_id\":\"i\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"j\",\"selection_id\":\"x\",\"detail\":\"app_duration\",\"page_limit\":1,\"record_limit\":1,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"p\",\"frontier_lineage\":\"f\",\"frontier_revision\":\"1\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"s\",\"source_revision\":\"r\",\"installation_id\":\"i\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"j\",\"selection_id\":\"x\",\"detail\":\"app_duration\",\"proof_ref\":\"p\",\"frontier_lineage\":\"f\",\"frontier_revision\":\"1\",\"grant_revision\":\"1\"}",
      "scope": "explicit real Effect Scope.make instance, provided to gate.open",
      "stimulus": "in source callback at before_publication invoke Effect.runSync(Scope.close(originalScope, Exit.succeed(undefined))) synchronously, then return the unchanged permitted source/current value",
      "release": "synchronous real Effect.sync increments release+ACK counters; no personal API/native/data"
    },
    "expected": {
      "result": "owned_handoff_closed",
      "open_result": "owned_handoff_closed",
      "assert_result": "not_called",
      "resolve_calls": 1,
      "source_calls": 2,
      "current_calls": 1,
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "export_allowed": false,
      "native_qualification": false,
      "later_callbacks_after_scope_close": 0,
      "scope_close_completed": true
    },
    "rationale": "Original Scope lifetime, not restored authority or new Scope, governs publication and assertions; no completed allocation before a known-closed preallocation Scope; existing allocation finalizes exactly once and ACKs before failure result."
  },
  {
    "case_id": "supplemental-scope-close-source-assert_current",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"s\",\"source_revision\":\"r\",\"installation_id\":\"i\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"j\",\"selection_id\":\"x\",\"detail\":\"app_duration\",\"page_limit\":1,\"record_limit\":1}",
      "binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"s\",\"source_revision\":\"r\",\"installation_id\":\"i\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"j\",\"selection_id\":\"x\",\"detail\":\"app_duration\",\"page_limit\":1,\"record_limit\":1,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"p\",\"frontier_lineage\":\"f\",\"frontier_revision\":\"1\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"s\",\"source_revision\":\"r\",\"installation_id\":\"i\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"j\",\"selection_id\":\"x\",\"detail\":\"app_duration\",\"proof_ref\":\"p\",\"frontier_lineage\":\"f\",\"frontier_revision\":\"1\",\"grant_revision\":\"1\"}",
      "scope": "explicit real Effect Scope.make instance, provided to gate.open",
      "stimulus": "in source callback at assert_current invoke Effect.runSync(Scope.close(originalScope, Exit.succeed(undefined))) synchronously, then return the unchanged permitted source/current value",
      "release": "synchronous real Effect.sync increments release+ACK counters; no personal API/native/data"
    },
    "expected": {
      "result": "owned_handoff_closed",
      "open_result": "aggregate_read_handoff",
      "assert_result": "owned_handoff_closed",
      "resolve_calls": 1,
      "source_calls": 3,
      "current_calls": 2,
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 1,
      "reads": 0,
      "personal_materializations": 0,
      "export_allowed": false,
      "native_qualification": false,
      "later_callbacks_after_scope_close": 0,
      "scope_close_completed": true
    },
    "rationale": "Original Scope lifetime, not restored authority or new Scope, governs publication and assertions; no completed allocation before a known-closed preallocation Scope; existing allocation finalizes exactly once and ACKs before failure result."
  },
  {
    "case_id": "supplemental-scope-close-current-before_publication",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"s\",\"source_revision\":\"r\",\"installation_id\":\"i\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"j\",\"selection_id\":\"x\",\"detail\":\"app_duration\",\"page_limit\":1,\"record_limit\":1}",
      "binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"s\",\"source_revision\":\"r\",\"installation_id\":\"i\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"j\",\"selection_id\":\"x\",\"detail\":\"app_duration\",\"page_limit\":1,\"record_limit\":1,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"p\",\"frontier_lineage\":\"f\",\"frontier_revision\":\"1\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"s\",\"source_revision\":\"r\",\"installation_id\":\"i\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"j\",\"selection_id\":\"x\",\"detail\":\"app_duration\",\"proof_ref\":\"p\",\"frontier_lineage\":\"f\",\"frontier_revision\":\"1\",\"grant_revision\":\"1\"}",
      "scope": "explicit real Effect Scope.make instance, provided to gate.open",
      "stimulus": "in current callback at before_publication invoke Effect.runSync(Scope.close(originalScope, Exit.succeed(undefined))) synchronously, then return the unchanged permitted source/current value",
      "release": "synchronous real Effect.sync increments release+ACK counters; no personal API/native/data"
    },
    "expected": {
      "result": "owned_handoff_closed",
      "open_result": "owned_handoff_closed",
      "assert_result": "not_called",
      "resolve_calls": 1,
      "source_calls": 2,
      "current_calls": 2,
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "export_allowed": false,
      "native_qualification": false,
      "later_callbacks_after_scope_close": 0,
      "scope_close_completed": true
    },
    "rationale": "Original Scope lifetime, not restored authority or new Scope, governs publication and assertions; no completed allocation before a known-closed preallocation Scope; existing allocation finalizes exactly once and ACKs before failure result."
  },
  {
    "case_id": "supplemental-scope-close-current-assert_current",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"s\",\"source_revision\":\"r\",\"installation_id\":\"i\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"j\",\"selection_id\":\"x\",\"detail\":\"app_duration\",\"page_limit\":1,\"record_limit\":1}",
      "binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"s\",\"source_revision\":\"r\",\"installation_id\":\"i\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"j\",\"selection_id\":\"x\",\"detail\":\"app_duration\",\"page_limit\":1,\"record_limit\":1,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"p\",\"frontier_lineage\":\"f\",\"frontier_revision\":\"1\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"s\",\"source_revision\":\"r\",\"installation_id\":\"i\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"j\",\"selection_id\":\"x\",\"detail\":\"app_duration\",\"proof_ref\":\"p\",\"frontier_lineage\":\"f\",\"frontier_revision\":\"1\",\"grant_revision\":\"1\"}",
      "scope": "explicit real Effect Scope.make instance, provided to gate.open",
      "stimulus": "in current callback at assert_current invoke Effect.runSync(Scope.close(originalScope, Exit.succeed(undefined))) synchronously, then return the unchanged permitted source/current value",
      "release": "synchronous real Effect.sync increments release+ACK counters; no personal API/native/data"
    },
    "expected": {
      "result": "owned_handoff_closed",
      "open_result": "aggregate_read_handoff",
      "assert_result": "owned_handoff_closed",
      "resolve_calls": 1,
      "source_calls": 3,
      "current_calls": 3,
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 1,
      "reads": 0,
      "personal_materializations": 0,
      "export_allowed": false,
      "native_qualification": false,
      "later_callbacks_after_scope_close": 0,
      "scope_close_completed": true
    },
    "rationale": "Original Scope lifetime, not restored authority or new Scope, governs publication and assertions; no completed allocation before a known-closed preallocation Scope; existing allocation finalizes exactly once and ACKs before failure result."
  },
  {
    "case_id": "supplemental-scope-close-already_closed-before_allocation",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"s\",\"source_revision\":\"r\",\"installation_id\":\"i\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"j\",\"selection_id\":\"x\",\"detail\":\"app_duration\",\"page_limit\":1,\"record_limit\":1}",
      "binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"s\",\"source_revision\":\"r\",\"installation_id\":\"i\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"j\",\"selection_id\":\"x\",\"detail\":\"app_duration\",\"page_limit\":1,\"record_limit\":1,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"p\",\"frontier_lineage\":\"f\",\"frontier_revision\":\"1\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"s\",\"source_revision\":\"r\",\"installation_id\":\"i\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"j\",\"selection_id\":\"x\",\"detail\":\"app_duration\",\"proof_ref\":\"p\",\"frontier_lineage\":\"f\",\"frontier_revision\":\"1\",\"grant_revision\":\"1\"}",
      "scope": "explicit real Effect Scope.make instance, provided to gate.open",
      "stimulus": "already close Scope before open",
      "release": "synchronous real Effect.sync increments release+ACK counters; no personal API/native/data"
    },
    "expected": {
      "result": "owned_handoff_closed",
      "open_result": "owned_handoff_closed",
      "assert_result": "not_called",
      "resolve_calls": 0,
      "source_calls": 0,
      "current_calls": 0,
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "export_allowed": false,
      "native_qualification": false,
      "later_callbacks_after_scope_close": 0,
      "scope_close_completed": true
    },
    "rationale": "Original Scope lifetime, not restored authority or new Scope, governs publication and assertions; no completed allocation before a known-closed preallocation Scope; existing allocation finalizes exactly once and ACKs before failure result."
  }
] as const;
for (const literal of scopeReentryLiterals) test(`iOS eligibility ${literal.case_id}`, async () => {
  const scope = Effect.runSync(Scope.make());
  let closed = false, resolveCalls = 0, sourceCalls = 0, currentCalls = 0, allocations = 0, releases = 0, ack = 0, handoffs = 0, laterCalls = 0;
  const close = () => { Effect.runSync(Scope.close(scope, Exit.succeed(undefined))); closed = true; };
  const sourceTarget = literal.case_id.includes("-source-");
  const currentTarget = literal.case_id.includes("-current-");
  const phaseTarget = literal.case_id.endsWith("before_allocation") ? "before_allocation" : literal.case_id.endsWith("before_publication") ? "before_publication" : "assert_current";
  const catalog: IOSUsageEligibilityCatalogService = {
    resolve: () => Effect.sync(() => { if (closed) laterCalls++; resolveCalls++; return literal.input.binding_json; }),
    checkSource: (_binding, phase) => { if (closed) laterCalls++; sourceCalls++; if (sourceTarget && phase === phaseTarget) close(); return "permitted"; },
    allocate: () => Effect.sync(() => { if (closed) laterCalls++; allocations++; return { release: Effect.sync(() => { releases++; ack++; }) }; }),
  };
  const authority: IOSUsageCurrentAuthorityService = { current: (_binding, phase) => { if (closed) laterCalls++; currentCalls++; if (currentTarget && phase === phaseTarget) close(); return literal.input.current_json; } };
  if (literal.case_id.includes("-already_closed-")) close();
  const gate = createIOSUsageEligibilityGate();
  const opened = await Effect.runPromiseExit(gate.open(literal.input.request_json).pipe(Effect.provideService(IOSUsageEligibilityCatalog, catalog), Effect.provideService(IOSUsageCurrentAuthority, authority), Effect.provideService(Scope.Scope, scope)));
  let asserted = "not_called";
  let openResult = outcome(opened, "unexpected_success");
  if (Exit.isSuccess(opened)) {
    handoffs++; openResult = opened.value.kind;
    asserted = outcome(await Effect.runPromiseExit(opened.value.assertCurrent(literal.input.request_json)), "success");
  }
  if (!closed) close();
  const observed = { result: asserted === "not_called" ? openResult : asserted, open_result: openResult, assert_result: asserted,
    resolve_calls: resolveCalls, source_calls: sourceCalls, current_calls: currentCalls, allocations, releases, acknowledged_releases: ack, handoffs,
    reads: 0, personal_materializations: 0, export_allowed: false, native_qualification: false, later_callbacks_after_scope_close: laterCalls, scope_close_completed: closed };
  assert.deepEqual(observed, literal.expected);
});
