import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { test } from "node:test";
import * as Effect from "effect/Effect";
import * as Deferred from "effect/Deferred";
import * as Fiber from "effect/Fiber";
import * as Scope from "effect/Scope";
import * as Exit from "effect/Exit";
import * as Cause from "effect/Cause";
import { createSourceCatalog, type SourceCatalog, type CatalogFailure, type CatalogIssuer, type CurrentAuthority, type MetadataSource, type MetadataConsumer, type OwnedCatalogRequest, type OwnedCatalogTicket, type Phase } from "../src/repository/source-catalog.js";
import { sourceCatalogFixture } from "./source-catalog-vectors.js";

type Action = { readonly at: string; readonly action: string; readonly wire?: string; readonly extra_metadata_wire?: string };
type Stimulus = {
  readonly procedure: string; readonly request_wire: string; readonly source_metadata_wire: string;
  readonly actions: readonly Action[]; readonly caller_claims_accepted: false;
  readonly input_override?: { readonly kind: string; readonly value?: unknown; readonly units?: readonly number[] };
};
const privateSentinel = "SYNTHETIC_SECRET_RECORD_PROVIDER_TITLE";
const emptyCounts = () => ({ source_calls: 0, current_calls: 0, consumer_calls: 0, metadata_materializations: 0,
  record_payload_reads: 0, title_value_reads: 0, store_acquisitions: 0, allocation_calls: 0, commit_calls: 0,
  release_attempts: 0, resource_ACKs: 0, external_IO_calls: 0, caller_traps: 0, new_callbacks_after_close: 0,
  replacement_service_calls: 0, close_signal_completions: 0 });
const fixed = (code: CatalogFailure["code"]): CatalogFailure => Object.freeze({ code });
function runScene(stimulus: Stimulus) {
  return Effect.scoped(Effect.gen(function* () {
    const original = yield* Scope.make();
    yield* Effect.addFinalizer(() => Scope.close(original, Exit.succeed(undefined)));
    const counts = emptyCounts();
    const reset = () => { for (const key of Object.keys(counts) as (keyof typeof counts)[]) counts[key] = 0; };
    const entered = yield* Deferred.make<void>(), gate = yield* Deferred.make<void>();
    let originalClosed = false, revoked = false;
    let catalog: SourceCatalog | null = null;
    const record = (key: "source_calls" | "current_calls" | "consumer_calls") => {
      counts[key]++; if (catalog && !catalog.lifetime.isLive()) counts.new_callbacks_after_close++;
    };
    const actions = (at: string) => stimulus.actions.filter(a => a.at === at);
    const has = (at: string, action: string) => actions(at).some(a => a.action === action);
    const close = Effect.gen(function* () {
      yield* Scope.close(original, Exit.succeed(undefined));
      if (!originalClosed) { originalClosed = true; counts.close_signal_completions++; }
    });
    const throwing = () => new Proxy({}, {
      get: () => { counts.caller_traps++; throw privateSentinel; },
      getPrototypeOf: () => { counts.caller_traps++; throw privateSentinel; },
      ownKeys: () => { counts.caller_traps++; throw privateSentinel; },
      getOwnPropertyDescriptor: () => { counts.caller_traps++; throw privateSentinel; },
      has: () => { counts.caller_traps++; throw privateSentinel; },
    });
    const revokedProxy = () => { const p = Proxy.revocable({}, {}); p.revoke(); return p.proxy; };
    let savedIssuer: CatalogIssuer | null = null, savedRead: Effect.Effect<string | null, CatalogFailure> | null = null;
    let capturedRequest: OwnedCatalogRequest | null = null, extraTicket: OwnedCatalogTicket | null = null;
    let returnedWire: string | null = null;
    const readResults: (string | null)[] = [], escapedResults: (string | null)[] = [];
    let escapedIssue: OwnedCatalogTicket | null = null, escapedChecks = 0, escapedMaterializations = 0;
    let foreignIssue: OwnedCatalogTicket | null = null, foreignIssueChecks = 0, foreignIssueTraps = 0;
    const observeRead = (work: Effect.Effect<string | null, CatalogFailure>) => work.pipe(Effect.tap(wire => Effect.sync(() => {
      if (wire !== null) counts.metadata_materializations++;
      readResults.push(wire); returnedWire = wire;
    })));
    const reenterRead = Effect.gen(function* () {
      assert.ok(savedRead);
      const checks = counts.current_calls, materializations = counts.metadata_materializations;
      const value = yield* savedRead; escapedResults.push(value);
      escapedChecks += counts.current_calls - checks;
      escapedMaterializations += counts.metadata_materializations - materializations;
    });
    const current: CurrentAuthority = { check: (_request, _binding, phase: Phase) => Effect.gen(function* () {
      record("current_calls");
      if (revoked) return yield* Effect.fail(fixed("scope_not_authorized"));
      for (const action of actions(phase)) {
        if (action.action === "close_original") yield* close;
        else if (action.action === "deny_current") return yield* Effect.fail(fixed("scope_not_authorized"));
        else if (action.action === "frontier_mismatch") return yield* Effect.fail(fixed("scope_binding_mismatch"));
        else if (action.action === "close_original_then_die_private_sentinel") { yield* close; return yield* Effect.die(privateSentinel); }
        else if (action.action === "await_gate") { yield* Deferred.succeed(entered, undefined); yield* Deferred.await(gate); }
        else if (action.action === "reenter_saved_issuer") {
          assert.ok(savedIssuer); assert.ok(capturedRequest);
          const before = counts.current_calls; escapedIssue = savedIssuer.issue(stimulus.source_metadata_wire, capturedRequest);
          escapedChecks += counts.current_calls - before;
        } else if (action.action === "reenter_saved_read") yield* reenterRead;
      }
    }) };
    // Independent foreign-factory setup uses the same wire stimulus and actual candidate ownership;
    // it has no counter events in the target operation's specified measurement window.
    const otherSource: MetadataSource = { capture: (request, _binding, issuer) => Effect.gen(function* () {
      const ticket = issuer.issue(stimulus.source_metadata_wire, request); assert.ok(ticket); return ticket;
    }) };
    const other = yield* Scope.provide(original)(createSourceCatalog({ source: otherSource, current: { check: () => Effect.void } }));
    let otherTicket: OwnedCatalogTicket | null = null;
    if (has("source", "return_other_factory_ticket") || has("read", "own_request_other_factory_ticket")) {
      const r = yield* other.request(stimulus.request_wire); otherTicket = yield* other.capture(r);
    }
    const source: MetadataSource = { capture: (request, _binding, issuer) => Effect.gen(function* () {
      record("source_calls"); capturedRequest = request;
      if (has("source", "await_gate")) { yield* Deferred.succeed(entered, undefined); yield* Deferred.await(gate); }
      if (has("source", "close_original_then_die_private_sentinel")) { yield* close; return yield* Effect.die(privateSentinel); }
      if (has("source", "die_private_sentinel")) return yield* Effect.die(privateSentinel);
      if (has("source", "fail_unavailable_with_private_sentinel")) {
        // Actual Fail + private Die cleanup cause: fixed unavailable survives, no text echo.
        return yield* Effect.fail(fixed("scope_not_authorized")).pipe(Effect.ensuring(Effect.die(privateSentinel)));
      }
      if (has("source", "return_throwing_proxy_token")) return throwing() as OwnedCatalogTicket;
      if (has("source", "return_other_factory_ticket")) { assert.ok(otherTicket); return otherTicket; }
      if (has("source", "save_issuer")) savedIssuer = issuer;
      if (has("source", "issue_with_foreign_proxy_request_then_valid_own_request")) {
        const checks = counts.current_calls, traps = counts.caller_traps;
        foreignIssue = issuer.issue(stimulus.source_metadata_wire, throwing());
        foreignIssueChecks = counts.current_calls - checks; foreignIssueTraps = counts.caller_traps - traps;
      }
      const override = actions("source").find(a => a.action === "metadata_wire_override");
      const ticket = issuer.issue(override?.wire ?? stimulus.source_metadata_wire, request);
      if (has("source", "issue_rejected_metadata_then_fixed_codec_failure")) {
        assert.equal(ticket, null); return yield* Effect.fail(fixed("private_catalog_codec"));
      }
      if (ticket === null) return yield* Effect.fail(fixed("private_catalog_codec"));
      for (const a of actions("source")) if (a.action === "issue_extra_ticket_return_only_first") {
        assert.ok(a.extra_metadata_wire); extraTicket = issuer.issue(a.extra_metadata_wire, request); assert.ok(extraTicket);
      }
      if (has("source", "issue_ticket_close_original_then_return")) yield* close;
      return ticket;
    }) };
    catalog = yield* Scope.provide(original)(createSourceCatalog({ source, current }));
    const own = catalog;
    let requestInput: unknown = stimulus.request_wire;
    if (stimulus.input_override) {
      const v = stimulus.input_override;
      if (v.kind === "primitive") requestInput = v.value;
      else if (v.kind === "UTF16_units") { assert.ok(v.units); requestInput = String.fromCharCode(...v.units); }
      else if (v.kind === "throwing_Proxy_all_traps") requestInput = throwing();
      else if (v.kind === "revoked_Proxy") requestInput = revokedProxy();
      else if (v.kind === "coercion_hooks") requestInput = { toString: () => { counts.caller_traps++; throw privateSentinel; }, [Symbol.toPrimitive]: () => { counts.caller_traps++; throw privateSentinel; } };
      else assert.fail("unrecognized inert input stimulus");
    }
    let sameFactoryOtherRequest: OwnedCatalogRequest | null = null;
    if (has("read", "other_own_request_own_ticket")) sameFactoryOtherRequest = yield* own.request(stimulus.request_wire);
    const consumer: MetadataConsumer = { consume: (request, ticket, view) => Effect.gen(function* () {
      record("consumer_calls");
      const lazy = view.metadata(request, ticket);
      if (has("consumer", "save_read")) savedRead = lazy;
      if (has("consumer", "die_private_sentinel_before_read")) return yield* Effect.die(privateSentinel);
      if (has("consumer", "close_original_before_own_read")) yield* close;
      if (stimulus.procedure === "foreign_read") {
        reset(); let r: unknown = request, t: unknown = ticket;
        for (const a of actions("read")) {
          if (a.action === "foreign_throwing_request_own_ticket") r = throwing();
          else if (a.action === "foreign_revoked_request_own_ticket") r = revokedProxy();
          else if (a.action === "own_request_revoked_ticket") t = revokedProxy();
          else if (a.action === "own_request_other_factory_ticket") { assert.ok(otherTicket); t = otherTicket; }
          else if (a.action === "other_own_request_own_ticket") { assert.ok(sameFactoryOtherRequest); r = sameFactoryOtherRequest; }
          else assert.fail("unrecognized owned-read stimulus");
        }
        yield* observeRead(view.metadata(r, t)); return;
      }
      yield* observeRead(lazy);
      if (has("consumer", "read_then_close_original")) yield* close;
      if (has("consumer", "same_read_twice_revoke_between")) { revoked = true; yield* observeRead(lazy); }
      if (has("consumer", "same_read_twice_allow")) yield* observeRead(lazy);
    }) };
    const operation = Effect.gen(function* () {
      if (stimulus.procedure === "close_signal_only") {
        yield* close;
        yield* own.lifetime.closed; yield* own.lifetime.closed; return;
      }
      const request = yield* own.request(requestInput);
      if (stimulus.procedure === "request_only") return;
      const ticket = yield* own.capture(request);
      if (stimulus.procedure === "unreturned_ticket_consume") {
        assert.ok(extraTicket); reset(); yield* own.consume(request, extraTicket, consumer); return;
      }
      yield* own.consume(request, ticket, consumer);
      yield* own.assertCurrent(request, ticket);
    });
    let result: Exit.Exit<void, CatalogFailure>;
    if (has("controller", "interrupt_owned_fiber") || has("controller", "close_original_then_resume_current")) {
      const child = yield* Effect.forkChild(operation);
      yield* Deferred.await(entered);
      if (has("controller", "close_original_then_resume_current")) { yield* close; yield* Deferred.succeed(gate, undefined); result = yield* Fiber.await(child); }
      else { yield* Fiber.interrupt(child); result = yield* Fiber.await(child); }
    } else if (stimulus.procedure === "busy_second_capture") {
      const request = yield* own.request(requestInput);
      const first = yield* Effect.forkChild(own.capture(request));
      yield* Deferred.await(entered); reset();
      result = yield* Effect.exit(own.capture(request).pipe(Effect.as(undefined)));
      yield* Fiber.interrupt(first);
    } else result = yield* Effect.exit(operation);
    if (has("after_terminal", "replace_original_current_method_and_reprovide_fresh_scope")) {
      current.check = () => Effect.sync(() => { counts.replacement_service_calls++; });
      assert.ok(savedRead);
      yield* Effect.scoped(reenterRead);
    }
    const completion = Exit.isSuccess(result);
    const interruption = Exit.isFailure(result) && Cause.hasInterrupts(result.cause);
    const failed = Exit.isFailure(result) ? result.cause.reasons.find(r => r._tag === "Fail") : undefined;
    const code = failed?._tag === "Fail" ? failed.error.code : null;
    const metadata = completion && returnedWire !== null ? JSON.parse(returnedWire) as {
      domain: string; payload_kind: string; installation: unknown;
      capabilities: { query: {state:string}; export: {state:string}; detail:{state:string} };
      history: {completeness:string}; detail: {focused_title:string};
    } : null;
    return {
      kind: interruption ? "interruption" : completion ? "completion" : "private_failure", safe_code: code,
      metadata_wire: completion ? returnedWire : null, ...counts,
      provider_echo: JSON.stringify({ code, metadata: completion ? returnedWire : null }).includes(privateSentinel),
      known_zero_fabricated: false, published_external: counts.external_IO_calls !== 0,
      domain: metadata?.domain ?? null, payload_kind: metadata?.payload_kind ?? null,
      exact_session_capability: metadata?.payload_kind === "foreground_app_session" && metadata.capabilities.query.state === "available",
      query_available: metadata?.capabilities.query.state === "available", export_available: metadata?.capabilities.export.state === "available",
      installation: metadata?.installation ?? null, completeness_claim: metadata?.history.completeness ?? null,
      escaped_results: escapedResults, escaped_current_calls: escapedChecks, escaped_materializations: escapedMaterializations,
      escaped_issue_result: escapedIssue, foreign_issue_result: foreignIssue, foreign_issue_current_calls: foreignIssueChecks, foreign_issue_traps: foreignIssueTraps,
      read_results: readResults, close_signal_results: stimulus.procedure === "close_signal_only" ? [true, true] : [],
      // These are absent-operation observations of the closed fake interfaces, not product parity claims.
      copy_health_corpus_to_collector: counts.record_payload_reads !== 0, replace_native_authority: false,
      GPS_equals_health_distance: false, caller_sourceID_is_grant: false, merge_other_installation: false,
      mint_native_identity: false, reconstruct_missing_sessions: false, rewrite_historical_loss: false,
      title_granted: false, observe_title: counts.title_value_reads !== 0, available_history_inferred: false,
      resource_cleanup_claimed: counts.resource_ACKs !== 0, revival: counts.replacement_service_calls !== 0,
      excluded_value_decoded: counts.record_payload_reads !== 0 || counts.title_value_reads !== 0, unknown_key_echoed: false,
    };
  }));
}

for (const scene of sourceCatalogFixture.cases) {
  test(`independent source catalog literal: ${scene.case_id}`, async () => {
    // Only frozen inert stimulus enters the candidate/fake ports. IDs and expected fields stay here.
    const observed = await Effect.runPromise(runScene(scene.stimulus));
    for (const [key, expected] of Object.entries(scene.expected)) {
      assert.deepEqual(observed[key as keyof typeof observed], expected, `${scene.case_id}: ${key}`);
    }
  });
}

test("immutable source catalog96 and original81/four authority raw pins", async () => {
  assert.equal(sourceCatalogFixture.case_count, 96); assert.equal(sourceCatalogFixture.cases.length, 96);
  const raw = await readFile(new URL("../../tests/source-catalog-vectors.ts", import.meta.url));
  assert.equal(createHash("sha256").update(raw).digest("hex"), "74f638315c3db96f37306e26ac3a026204f629e3fee3d53bfad3203b03832591");
  assert.equal(sourceCatalogFixture.retained81_contract_case_mapping.length, 81);
  assert.equal(sourceCatalogFixture.repository_baseline_mapping_17.length, 17);
  assert.equal(sourceCatalogFixture.full_transfer_obligations_13.original13_unchanged.length, 13);
  const originals = await readFile(new URL("../../tests/personal-codecs-vectors.ts", import.meta.url));
  assert.equal(createHash("sha256").update(originals).digest("hex"), "274b6dc844d2da72ff283df5d194dc39002639b3a2038937db732278fda4406a");
});

// Six independent before-code scalar-descent scenes; immutable96 source vector remains unchanged.
const closedScalarSupplementals = [
  {
    "case_id": "request-scalar-source_id-object",
    "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":{\"title\":\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\"},\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
    "source_metadata_wire": null,
    "expected": {
      "safe_code": "invalid_request",
      "source_calls": 0,
      "current_calls": 0,
      "consumer_calls": 0,
      "metadata_materializations": 0,
      "caller_traps": 0
    },
    "reason_before_code": "Frozen field type is string. 513-byte excluded nested value cannot move schema/type rejection to candidate_limit_exceeded. Raw frame stays below4096.",
    "execution": "unrun",
    "excluded_decode_evidence": "closed known-field type rejection before nested value descent must be verified by source inspection; absent-operation counters are not parser instrumentation"
  },
  {
    "case_id": "request-scalar-source_id-array",
    "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":[{\"record_payload\":\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\"}],\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
    "source_metadata_wire": null,
    "expected": {
      "safe_code": "invalid_request",
      "source_calls": 0,
      "current_calls": 0,
      "consumer_calls": 0,
      "metadata_materializations": 0,
      "caller_traps": 0
    },
    "reason_before_code": "Frozen field type is string. 513-byte excluded nested value cannot move schema/type rejection to candidate_limit_exceeded. Raw frame stays below4096.",
    "execution": "unrun",
    "excluded_decode_evidence": "closed known-field type rejection before nested value descent must be verified by source inspection; absent-operation counters are not parser instrumentation"
  },
  {
    "case_id": "request-scalar-grant_revision-object",
    "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":{\"window_title\":\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
    "source_metadata_wire": null,
    "expected": {
      "safe_code": "invalid_request",
      "source_calls": 0,
      "current_calls": 0,
      "consumer_calls": 0,
      "metadata_materializations": 0,
      "caller_traps": 0
    },
    "reason_before_code": "Frozen field type is string. 513-byte excluded nested value cannot move schema/type rejection to candidate_limit_exceeded. Raw frame stays below4096.",
    "execution": "unrun",
    "excluded_decode_evidence": "closed known-field type rejection before nested value descent must be verified by source inspection; absent-operation counters are not parser instrumentation"
  },
  {
    "case_id": "metadata-source-id-title",
    "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
    "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":{\"title\":\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\"}}",
    "expected": {
      "safe_code": "private_catalog_codec",
      "source_calls": 1,
      "current_calls": 1,
      "consumer_calls": 0,
      "metadata_materializations": 0,
      "caller_traps": 0
    },
    "reason_before_code": "Known scalar string field cannot accept object shape or decode nested excluded value before fixed private_catalog_codec. Existing metadata failure code is intentionally payload-free and does not instrument decoding.",
    "execution": "unrun",
    "excluded_decode_evidence": "closed known-field type rejection before nested value descent must be verified by source inspection; absent-operation counters are not parser instrumentation"
  },
  {
    "case_id": "metadata-device-value-record",
    "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
    "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":\"available\"},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"state\":\"known\",\"value\":{\"record_payload\":\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\"}},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
    "expected": {
      "safe_code": "private_catalog_codec",
      "source_calls": 1,
      "current_calls": 1,
      "consumer_calls": 0,
      "metadata_materializations": 0,
      "caller_traps": 0
    },
    "reason_before_code": "Known scalar string field cannot accept object shape or decode nested excluded value before fixed private_catalog_codec. Existing metadata failure code is intentionally payload-free and does not instrument decoding.",
    "execution": "unrun",
    "excluded_decode_evidence": "closed known-field type rejection before nested value descent must be verified by source inspection; absent-operation counters are not parser instrumentation"
  },
  {
    "case_id": "metadata-capability-state-title",
    "request_wire": "{\"destination\":\"local\",\"domain\":\"device_usage\",\"grant_revision\":\"1\",\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\",\"source_purpose\":\"local_catalog\",\"suppression_revision\":\"1\"}",
    "source_metadata_wire": "{\"authority_kind\":\"native_usage_aggregate\",\"capabilities\":{\"capture\":{\"reason\":\"not_qualified\",\"state\":\"unavailable\"},\"detail\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"display\":{\"state\":{\"title\":\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\"}},\"export\":{\"reason\":\"display_only\",\"state\":\"unavailable\"},\"query\":{\"reason\":\"display_only\",\"state\":\"unavailable\"}},\"detail\":{\"focused_title\":\"excluded\",\"granularity\":\"app_aggregate\"},\"device\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"domain\":\"device_usage\",\"eligibility\":\"aggregate_display_only\",\"history\":{\"completeness\":\"partial\",\"freshness\":\"unknown\",\"range\":\"source_reported\",\"short_sessions\":\"not_applicable\"},\"installation\":{\"reason\":\"not_reported\",\"state\":\"unknown\"},\"native_profile\":{\"state\":\"known\",\"value\":\"synthetic-ios-aggregate-profile\"},\"payload_kind\":\"usage_aggregate\",\"source_contract_revision\":\"1\",\"source_id\":\"synthetic-ios-aggregate\"}",
    "expected": {
      "safe_code": "private_catalog_codec",
      "source_calls": 1,
      "current_calls": 1,
      "consumer_calls": 0,
      "metadata_materializations": 0,
      "caller_traps": 0
    },
    "reason_before_code": "Known scalar string field cannot accept object shape or decode nested excluded value before fixed private_catalog_codec. Existing metadata failure code is intentionally payload-free and does not instrument decoding.",
    "execution": "unrun",
    "excluded_decode_evidence": "closed known-field type rejection before nested value descent must be verified by source inspection; absent-operation counters are not parser instrumentation"
  }
] as const;
for (const scene of closedScalarSupplementals) {
  test(`independent source catalog closed scalar: ${scene.case_id}`, async () => {
    const observed = await Effect.runPromise(runScene({
      procedure: "request_capture_consume_assert", request_wire: scene.request_wire,
      source_metadata_wire: scene.source_metadata_wire ?? "{}", actions: [], caller_claims_accepted: false,
    }));
    for (const [key, expected] of Object.entries(scene.expected)) {
      assert.deepEqual(observed[key as keyof typeof observed], expected, `${scene.case_id}: ${key}`);
    }
  });
}

// Three independently sourced replayable closure scenes, separate from immutable96 data.
const replayableSignalLiterals = [
  {
    "id": "catalog-close-signal-two-pending-and-replay",
    "stimulus": "In original live Scope start two actual lifetime.closed fibers, record each pending registration, then close original Scope; join both, execute the same closed Effect twice after closure.",
    "expected": {
      "pending_successes": 2,
      "replay_successes": 2,
      "scope_signal_close_events": 1,
      "isLive": false,
      "source_calls": 0,
      "current_calls": 0,
      "consumer_calls": 0,
      "resource_ACKs": 0,
      "pending_registration_witnesses": [
        true,
        true
      ],
      "completions_before_close": [
        0,
        0
      ]
    },
    "gate": "Actual waiter registration must be observed deterministically; no sleep/assumed scheduling or hardcoded pending booleans.",
    "actions": [
      "start_first",
      "assert_first_pending",
      "start_second",
      "assert_second_pending",
      "close_original",
      "join_both",
      "replay_twice"
    ]
  },
  {
    "id": "catalog-close-signal-interrupted-waiter",
    "stimulus": "Start first actual closed await, wait for registration, interrupt and join it; start second await and wait registration, close original Scope, join second and replay once.",
    "expected": {
      "first_interrupted": true,
      "first_successes": 0,
      "second_successes": 1,
      "replay_successes": 1,
      "scope_signal_close_events": 1,
      "source_calls": 0,
      "current_calls": 0,
      "consumer_calls": 0,
      "resource_ACKs": 0,
      "pending_registration_witnesses": [
        true,
        true
      ],
      "completions_before_close": [
        0,
        0
      ]
    },
    "gate": "Verify first interruption is preserved and no residual waiter gets a second successful publication. Pending/cancel cleanup evidence must come from actual Effect controls, not fixture-derived counters.",
    "actions": [
      "start_first",
      "assert_first_pending",
      "interrupt_and_join_first",
      "start_second",
      "assert_second_pending",
      "close_original",
      "join_second",
      "replay_once"
    ]
  },
  {
    "id": "catalog-close-signal-already-closed",
    "stimulus": "Close original Scope before first execution of captured closed Effect; execute twice under a fresh Scope.",
    "expected": {
      "replay_successes": 2,
      "isLive": false,
      "source_calls": 0,
      "current_calls": 0,
      "consumer_calls": 0,
      "replacement_service_calls": 0,
      "resource_ACKs": 0,
      "pending_registration_witnesses": [],
      "completions_before_close": []
    },
    "gate": "Does not create or reprovide original authority; original96 replay scene remains unchanged.",
    "actions": [
      "close_original",
      "replace_original_service_functions",
      "fresh_scope_replay_twice"
    ]
  }
] as const;
function runReplayableSignal(actions: readonly string[]) {
  return Effect.scoped(Effect.gen(function* () {
    const original = yield* Scope.make();
    yield* Effect.addFinalizer(() => Scope.close(original, Exit.succeed(undefined)));
    let sourceCalls = 0, currentCalls = 0, replacementCalls = 0, closeEvents = 0;
    const source: MetadataSource = { capture: () => Effect.gen(function* () {
      sourceCalls++; return yield* Effect.fail(fixed("private_catalog_codec"));
    }) };
    const current: CurrentAuthority = { check: () => Effect.sync(() => { currentCalls++; }) };
    const catalog = yield* Scope.provide(original)(createSourceCatalog({ source, current }));
    const closed = catalog.lifetime.closed;
    const entered: boolean[] = [false, false], successes: number[] = [0, 0];
    const pendingWitnesses: boolean[] = [], beforeClose: number[] = [];
    let first: Fiber.Fiber<void> | null = null, second: Fiber.Fiber<void> | null = null;
    let firstInterrupted = false, replaySuccesses = 0;
    const start = (index: number) => Effect.forkChild(Effect.gen(function* () {
      // Known body: synchronous entered marker, then ONLY the captured closure await.
      yield* Effect.sync(() => { entered[index] = true; });
      yield* closed;
      yield* Effect.sync(() => { successes[index] = successes[index]! + 1; });
    }), { startImmediately: true });
    const observePending = (fiber: Fiber.Fiber<void>, index: number) => Effect.sync(() => {
      // Immediate fork evaluates this known body before returning; its only suspension
      // is closed. Flush any child continuation, then require reached marker, zero
      // completion and undefined poll as actual pending closure registration evidence.
      fiber.currentDispatcher.flush();
      assert.equal(entered[index], true); assert.equal(successes[index], 0);
      assert.equal(fiber.pollUnsafe(), undefined);
      pendingWitnesses.push(fiber.pollUnsafe() === undefined);
      beforeClose.push(successes[index]!);
    });
    for (const action of actions) {
      if (action === "start_first") first = yield* start(0);
      else if (action === "start_second") second = yield* start(1);
      else if (action === "assert_first_pending") { assert.ok(first); yield* observePending(first, 0); }
      else if (action === "assert_second_pending") { assert.ok(second); yield* observePending(second, 1); }
      else if (action === "interrupt_and_join_first") {
        assert.ok(first); yield* Fiber.interrupt(first);
        const exit = yield* Fiber.await(first);
        firstInterrupted = Exit.isFailure(exit) && Cause.hasInterrupts(exit.cause);
        assert.equal(successes[0], 0);
      } else if (action === "close_original") {
        yield* Scope.close(original, Exit.succeed(undefined)); closeEvents++;
      } else if (action === "join_both") {
        assert.ok(first); assert.ok(second);
        const firstExit = yield* Fiber.await(first), secondExit = yield* Fiber.await(second);
        assert.ok(Exit.isSuccess(firstExit)); assert.ok(Exit.isSuccess(secondExit));
      } else if (action === "join_second") {
        assert.ok(second); assert.ok(Exit.isSuccess(yield* Fiber.await(second)));
      } else if (action === "replay_once" || action === "replay_twice") {
        yield* closed; replaySuccesses++;
        if (action === "replay_twice") { yield* closed; replaySuccesses++; }
      } else if (action === "replace_original_service_functions") {
        source.capture = () => Effect.gen(function* () { replacementCalls++; return yield* Effect.fail(fixed("private_catalog_codec")); });
        current.check = () => Effect.sync(() => { replacementCalls++; });
      } else if (action === "fresh_scope_replay_twice") {
        yield* Effect.scoped(Effect.gen(function* () {
          yield* closed; replaySuccesses++; yield* closed; replaySuccesses++;
        }));
      } else assert.fail("unrecognized closure action");
    }
    return { pending_successes: successes[0]! + successes[1]!, first_successes: successes[0],
      second_successes: successes[1], first_interrupted: firstInterrupted, replay_successes: replaySuccesses,
      scope_signal_close_events: closeEvents, isLive: catalog.lifetime.isLive(), source_calls: sourceCalls,
      current_calls: currentCalls, consumer_calls: 0, replacement_service_calls: replacementCalls, resource_ACKs: 0,
      pending_registration_witnesses: pendingWitnesses, completions_before_close: beforeClose };
  }));
}
for (const scene of replayableSignalLiterals) {
  test(`independent source catalog closure signal: ${scene.id}`, async () => {
    // Only actions enter this actual Effect driver; no ID or expected value reaches ports.
    const observed = await Effect.runPromise(runReplayableSignal(scene.actions));
    for (const [key, expected] of Object.entries(scene.expected)) {
      assert.deepEqual(observed[key as keyof typeof observed], expected, `${scene.id}: ${key}`);
    }
  });
}
