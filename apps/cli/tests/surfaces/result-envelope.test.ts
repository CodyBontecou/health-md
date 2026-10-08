/** Independently frozen stimuli drive semantic ports; expected records are assertions only. */
import assert from "node:assert/strict";
import test from "node:test";
import * as Effect from "effect/Effect";
import * as Exit from "effect/Exit";
import * as Deferred from "effect/Deferred";
import * as Fiber from "effect/Fiber";
import * as Scope from "effect/Scope";
import {
  CliEnvelopeFactory, fixedFailure, type FixedFailure, type TrustedServices,
  type CliEnvelope, type CommonOutcomeIssuer, type OwnedCommonOutcome, type OwnedValue,
  type OwnedBytes, type OwnedMode, type OwnedDecision, type OwnedOutputLease,
  type AuthorizedOutcomeView, type AuthorizedBytesView, type ByteIssuer,
  type AuthorityPhase, type CapturedOutputLifetime, type SourceValue
} from "../../src/surfaces/result-envelope.js";
import { resultEnvelopeFixture } from "./result-envelope-vectors.js";
type Stimulus = (typeof resultEnvelopeFixture.cases)[number]["stimulus"];
type Code = FixedFailure["code"];
interface Counts {
  common_calls: number; authority_calls: number; renderer_calls: number; raw_validator_calls: number;
  allocation_calls: number; sink_calls: number; release_attempts: number; release_ACKs: number;
  value_materializations: number; byte_observations: number; source_calls: number;
  forbidden_IO_calls: number; property_traps: number; new_noncleanup_callbacks_after_close: number;
}
const blank = (): Counts => ({ common_calls: 0, authority_calls: 0, renderer_calls: 0, raw_validator_calls: 0, allocation_calls: 0, sink_calls: 0, release_attempts: 0, release_ACKs: 0, value_materializations: 0, byte_observations: 0, source_calls: 0, forbidden_IO_calls: 0, property_traps: 0, new_noncleanup_callbacks_after_close: 0 });
/** Restricted inert input renderer, not general JSON/numerical/source-codec parity.
 * No stimulus ID or expected bytes is visible to this function or any trusted port. */
function plainValue(v: SourceValue): unknown {
  if (v === null || typeof v !== "object") return v;
  if (Array.isArray(v)) return v.map((x) => plainValue(x));
  if (!("kind" in v)) throw new Error("private test source grammar");
  if (v.kind === "object") return Object.fromEntries([...v.entries].sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0).map(([k, x]) => [k, plainValue(x)]));
  if (v.kind === "signed_integer" || v.kind === "unsigned_integer") {
    assert.match(v.decimal, /^(0|-?[1-9][0-9]*)$/); const n = BigInt(v.decimal);
    assert.ok(n >= -9007199254740991n && n <= 9007199254740991n); return Number(n);
  }
  throw new Error("unadmitted test binary64 codec");
}
function renderInput(wire: string, mode: "json" | "human"): string {
  const v: SourceValue = JSON.parse(wire); const plain = plainValue(v);
  if (mode === "json") return JSON.stringify(plain, null, 2) + "\n";
  assert.ok(plain !== null && typeof plain === "object" && !Array.isArray(plain));
  const rows = Object.entries(plain).map(([key, value]) => {
    assert.ok(typeof value === "boolean");
    const label = key.slice(0, 1).toUpperCase() + key.slice(1).replaceAll("_", " ");
    return label + ": " + (value ? "Yes" : "No");
  });
  return "Health.md result\n================\n\n" + rows.join("\n") + "\n";
}
function actionText(stimulus: Stimulus, key: string): string {
  return stimulus.actions.flatMap((action) => {
    if (!(key in action)) return []; const value: unknown = Reflect.get(action, key); return typeof value === "string" ? [value] : [];
  }).join("\n");
}
function proxy(counts: Counts, revoked = false): object {
  const trap = () => { counts.property_traps++; throw new Error("SYNTHETIC_SECRET"); };
  const r = Proxy.revocable({}, { get: trap, set: trap, ownKeys: trap, getPrototypeOf: trap, getOwnPropertyDescriptor: trap, has: trap, defineProperty: trap, deleteProperty: trap, isExtensible: trap, preventExtensions: trap, setPrototypeOf: trap });
  if (revoked) r.revoke(); return r.proxy;
}
function override(value: unknown, counts: Counts): unknown {
  if (value === undefined) return undefined;
  assert.ok(value !== null && typeof value === "object" && "kind" in value);
  const kind = value.kind;
  if (kind === "throwing_Proxy_all_traps") return proxy(counts);
  if (kind === "revoked_Proxy") return proxy(counts, true);
  if (kind === "coercion_object_all_hooks") return Object.freeze({ toString: () => { counts.property_traps++; throw new Error("SYNTHETIC_SECRET"); }, valueOf: () => { counts.property_traps++; throw new Error("SYNTHETIC_SECRET"); }, [Symbol.toPrimitive]: () => { counts.property_traps++; throw new Error("SYNTHETIC_SECRET"); } });
  if (kind === "primitive" && "value" in value) return value.value;
  if (kind === "UTF16_units" && "units" in value) { assert.ok(Array.isArray(value.units)); return String.fromCharCode(...value.units); }
  if (kind === "repeat_ASCII" && "character" in value && "count" in value) { assert.equal(typeof value.character, "string"); assert.equal(typeof value.count, "number"); return String(value.character).repeat(Number(value.count)); }
  if (kind === "nested_array" && "levels" in value && "leaf" in value) return "[".repeat(Number(value.levels)) + String(value.leaf) + "]".repeat(Number(value.levels));
  if (kind === "flat_array" && "elements" in value && "leaf" in value) return "[" + Array(Number(value.elements)).fill(String(value.leaf)).join(",") + "]";
  throw new Error("unknown closed fixture override");
}
function failCode<A = never>(code: Code): Effect.Effect<A, FixedFailure> { return Effect.fail(fixedFailure(code)); }
function ownFailure(exit: Exit.Exit<unknown, FixedFailure>): string | null {
  if (Exit.isSuccess(exit)) return null;
  const reason = exit.cause.reasons.find((x) => x._tag === "Fail"); return reason?._tag === "Fail" ? reason.error.code : null;
}
function interrupted(exit: Exit.Exit<unknown, FixedFailure>): boolean { return Exit.isFailure(exit) && exit.cause.reasons.some((x) => x._tag === "Interrupt"); }
function runScene(stimulus: Stimulus) {
  return Effect.scoped(Effect.gen(function* () {
    const original = yield* Scope.make(); yield* Effect.addFinalizer(() => Scope.close(original, Exit.succeed(undefined)));
    let originalClosed = false, revoked = false; const counts = blank();
    const close = () => { Effect.runSync(Scope.close(original, Exit.succeed(undefined))); originalClosed = true; };
    const record = (key: keyof Counts) => { counts[key]++; if (originalClosed && key !== "release_attempts" && key !== "release_ACKs" && key !== "property_traps") counts.new_noncleanup_callbacks_after_close++; };
    const entered = yield* Deferred.make<void>(), proceed = yield* Deferred.make<void>(), releasing = yield* Deferred.make<void>(), ack = yield* Deferred.make<void>();
    const commonAction = actionText(stimulus, "common"), rendererAction = actionText(stimulus, "renderer"), sinkAction = actionText(stimulus, "sink"), currentAction = actionText(stimulus, "current"), allocationAction = actionText(stimulus, "allocation"), releaseAction = actionText(stimulus, "release"), rawAction = actionText(stimulus, "raw_validator"), phaseAction = actionText(stimulus, "phase"), controllerAction = actionText(stimulus, "controller");
    const externalPrepare = phaseAction.includes("before commit"), externalRegistered = phaseAction.includes("local finalizer registration");
    const variantAction = stimulus.actions.find((x) => "variant" in x);
    const variant: unknown = variantAction && "variant" in variantAction ? variantAction.variant : null;
    const observed: string[] = [], variantResults: unknown[] = [], escapedResults: unknown[] = [], lateResults: unknown[] = [];
    let variantChecks = 0, variantMaterials = 0, escapedChecks = 0, escapedMaterials = 0, lateChecks = 0, replacementChecks = 0;
    let escapedIssuer: CommonOutcomeIssuer | null = null, savedRenderIssuer: ByteIssuer | null = null, savedRead: Effect.Effect<string | null, FixedFailure> | null = null;
    let savedSinkRead: Effect.Effect<string | null, FixedFailure> | null = null, savedRequest: OwnedCommonOutcome | null = null, capturedValue: OwnedValue | null = null;
    let watchers = 0, phaseFibers = 0, prepCancelled = false, useCalls = 0, afterAllocationCalls = 0, terminalBeforeAck = false, closeWhileAck = false, busyWhileAck = false;
    let foreignBytes: OwnedBytes | null = null, foreignValidated: unknown = null;
    let sameCallbackOtherValue: OwnedValue | null = null, sameCallbackOtherValueResult: string | null = null;
    let sameCallbackOtherValueChecks = 0, sameCallbackOtherValueMaterials = 0;
    const countValue = (read: Effect.Effect<string | null, FixedFailure>) => read.pipe(Effect.tap((value) => Effect.sync(() => { if (value !== null) record("value_materializations"); })));
    const countBytes = (read: Effect.Effect<string | null, FixedFailure>) => read.pipe(Effect.tap((value) => Effect.sync(() => { if (value !== null) { record("byte_observations"); observed.push(value); } })));
    const escapedProbe = (read: Effect.Effect<string | null, FixedFailure>) => Effect.gen(function* () {
      const before = counts.authority_calls, materials = counts.value_materializations + counts.byte_observations; const result = yield* read; escapedResults.push(result); escapedChecks += counts.authority_calls - before; escapedMaterials += counts.value_materializations + counts.byte_observations - materials;
    });
    const services: TrustedServices = {
      capabilities: { rawFamilies: stimulus.host.rawFamilies, plainText: stimulus.host.plainText },
      common: { receive: (_wire, issuer) => Effect.gen(function* () {
        record("common_calls");
        if (commonAction.includes("die with")) return yield* Effect.die("SYNTHETIC_SECRET");
        const value = issuer.value(stimulus.port_inputs.value_wire); assert.ok(value); capturedValue = value;
        const outcome = issuer.outcome(stimulus.port_inputs.descriptor_wire, value); assert.ok(outcome);
        if ("common_extra_value_wire" in stimulus.port_inputs) {
          sameCallbackOtherValue = issuer.value(stimulus.port_inputs.common_extra_value_wire);
          assert.ok(sameCallbackOtherValue);
        }
        if (commonAction.includes("save own")) escapedIssuer = issuer;
        if (commonAction.includes("Scope.close original")) close();
        return outcome;
      }) },
      current: { check: (_outcome, phase) => Effect.gen(function* () {
        record("authority_calls"); if (phase === "after_allocation") afterAllocationCalls++;
        if (currentAction.includes("Scope.close at " + phase)) close();
        if (revoked || currentAction.includes("deny") && currentAction.includes(phase)) return yield* failCode("private_cli_authority");
        if (phase === "before_materialization" && rendererAction.includes("waiting in Deferred")) { yield* Deferred.succeed(entered, undefined); yield* Deferred.await(proceed); }
        if (phase === "before_publication" && sinkAction.includes("current Deferred")) { yield* Deferred.succeed(entered, undefined); yield* Deferred.await(proceed); }
        if (phase === "after_common" && escapedIssuer) {
          const before = counts.authority_calls; escapedResults.push(escapedIssuer.value(stimulus.port_inputs.value_wire)); escapedChecks += counts.authority_calls - before;
        }
        if (phase === "after_render" && rendererAction.includes("save own")) {
          assert.ok(savedRead && savedRenderIssuer && savedRequest); yield* escapedProbe(savedRead);
          assert.equal(savedRenderIssuer.encodedUTF8("SYNTHETIC_SECRET", savedRequest), null);
        }
        if (phase === "after_publication" && sinkAction.includes("save own")) { assert.ok(savedSinkRead); yield* escapedProbe(savedSinkRead); }
      }) },
      renderer: { render: (outcome, mode, issuer, view) => Effect.gen(function* () {
        record("renderer_calls"); const metadata = view.inspect(outcome); assert.ok(metadata && metadata.value);
        if (rendererAction.includes("die with")) return yield* Effect.die("SYNTHETIC_SECRET");
        if (rendererAction.includes("Scope.close original before")) close();
        if (sameCallbackOtherValue !== null) {
          const before = counts.authority_calls, materials = counts.value_materializations;
          sameCallbackOtherValueResult = yield* countValue(view.sourceValueWire(outcome, sameCallbackOtherValue));
          sameCallbackOtherValueChecks += counts.authority_calls - before;
          sameCallbackOtherValueMaterials += counts.value_materializations - materials;
        }
        const read = countValue(view.sourceValueWire(outcome, metadata.value));
        if (rendererAction.includes("save")) { savedRead = read; savedRenderIssuer = issuer; savedRequest = outcome; }
        if (variant !== null && rendererAction.includes("foreign membership")) {
          assert.ok(typeof variant === "object" && "request" in variant && "payload" in variant);
          const before = counts.authority_calls, materials = counts.value_materializations;
          const request = variant.request === "throwing_Proxy_all_traps" ? proxy(counts) : outcome;
          const payload = variant.payload === "revoked_value" ? proxy(counts, true) : metadata.value;
          variantResults.push(yield* countValue(view.sourceValueWire(request, payload))); variantChecks += counts.authority_calls - before; variantMaterials += counts.value_materializations - materials;
        }
        const wire = yield* read; assert.ok(wire !== null);
        if (rendererAction.includes("revoke trusted frontier")) { revoked = true; yield* read; }
        if (rendererAction.includes("other-factory")) { assert.ok(foreignBytes); return foreignBytes; }
        const modeMetadata = view.mode(mode); assert.ok(modeMetadata);
        const text = rendererAction.includes("repeat ASCII") ? "x".repeat(65537) : rendererAction.includes("lone high") ? "\ud800" : renderInput(wire, modeMetadata.mode);
        const encoded = issuer.encodedUTF8(text, outcome); if (!encoded) return yield* failCode("private_cli_codec"); return encoded;
      }) },
      raw: { validate: (outcome, issuer, view) => Effect.gen(function* () {
        record("raw_validator_calls");
        if (rawAction.includes("validated-looking")) return proxy(counts) as never;
        if (rawAction.includes("Scope.close before")) close();
        const m = view.inspect(outcome); // Closed Scope views return null before payload or current.
        if (!m || !m.value) return yield* failCode("owned_handoff_closed");
        const wire = yield* countValue(view.sourceValueWire(outcome, m.value)); assert.ok(wire !== null);
        if (rawAction.includes("foreign authentic")) { assert.ok(foreignValidated); return foreignValidated as never; }
        const text: unknown = JSON.parse(wire); assert.equal(typeof text, "string");
        const token = issuer.validated(text, m.value, outcome); assert.ok(token); return token;
      }) },
      writer: {
        /** Execute the reviewed bracket protocol. Fakes never return unknown acquisition handles.
         * The only allocated resource is a local owned lease; counters observe actual transitions. */
        withLease: <A>(decision: OwnedDecision, _view: unknown, lifetime: CapturedOutputLifetime, use: (lease: OwnedOutputLease) => Effect.Effect<A, FixedFailure>) => Effect.uninterruptibleMask((restore) => Effect.gen(function* () {
          if (!lifetime.isLive()) return yield* failCode<A>("owned_handoff_closed");
          let originalClosed = false, cleanupFailed = false, allocated = false, released = false;
          const phaseReady = yield* Deferred.make<Fiber.Fiber<A, FixedFailure>>();
          const leases = new WeakSet<object>();
          watchers++;
          const watcher = yield* Effect.forkChild(Effect.interruptible(lifetime.closed.pipe(Effect.andThen(Effect.gen(function* () {
            originalClosed = true; const phase = yield* Deferred.await(phaseReady); yield* Fiber.interrupt(phase);
          })), Effect.ensuring(Effect.sync(() => { watchers--; })))));
          const stage = Effect.uninterruptibleMask((stageRestore) => Effect.gen(function* () {
            const body = stageRestore(Effect.gen(function* () {
              if (externalPrepare || allocationAction.includes("pending Deferred")) {
                yield* Effect.gen(function* () {
                  yield* Deferred.succeed(entered, undefined);
                  yield* Deferred.await(proceed);
                }).pipe(Effect.onInterrupt(() => Effect.sync(() => { prepCancelled = true; })));
              }
              const lease = yield* Effect.uninterruptible(Effect.sync(() => {
                if (!lifetime.isLive()) throw fixedFailure("owned_handoff_closed");
                const token = Object.freeze({ decision }); allocated = true; leases.add(token); record("allocation_calls");
                // The stage's protected finally below is already installed before this sync creates.
                return token as unknown as OwnedOutputLease;
              }));
              if (allocationAction.includes("close originalScope")) close();
              if (externalRegistered || allocationAction.includes("completed allocation held")) { yield* Deferred.succeed(entered, undefined); yield* Deferred.await(proceed); }
              if (!lifetime.isLive()) return yield* failCode<A>("owned_handoff_closed");
              if (!leases.has(lease)) return yield* failCode<A>("private_cli_owned");
              useCalls++; return yield* use(lease);
            }));
            const result = yield* Effect.exit(body);
            if (allocated && !released) {
              released = true; record("release_attempts"); yield* Deferred.succeed(releasing, undefined);
              if (releaseAction.includes("save own")) { assert.ok(savedSinkRead); yield* escapedProbe(savedSinkRead); }
              if (releaseAction.includes("Scope.close original")) close();
              if (releaseAction.includes("fail with")) cleanupFailed = true;
              else {
                if (releaseAction.includes("Deferred pending") || externalRegistered || allocationAction.includes("completed allocation held")) yield* Deferred.await(ack);
                record("release_ACKs");
              }
            }
            if (cleanupFailed) return yield* failCode<A>("private_cli_cleanup");
            if (Exit.isFailure(result)) return yield* Effect.failCause(result.cause);
            return result.value;
          }));
          phaseFibers++;
          const phase = yield* Effect.forkChild(restore(stage).pipe(Effect.ensuring(Effect.sync(() => { phaseFibers--; }))));
          yield* Deferred.succeed(phaseReady, phase);
          if (!lifetime.isLive()) originalClosed = true;
          const awaited = yield* Effect.exit(restore(Fiber.await(phase)));
          let externalInterrupt = false; let result: Exit.Exit<A, FixedFailure>;
          if (Exit.isFailure(awaited)) { externalInterrupt = true; yield* Fiber.interrupt(phase); result = yield* Fiber.await(phase); }
          else result = awaited.value;
          yield* Fiber.interrupt(watcher);
          if (cleanupFailed) return yield* failCode<A>("private_cli_cleanup");
          if (externalInterrupt) return yield* Effect.interrupt;
          if (originalClosed || !lifetime.isLive()) return yield* failCode<A>("owned_handoff_closed");
          if (Exit.isFailure(result)) return yield* Effect.failCause(result.cause);
          return result.value;
        })),
        publish: (decision, bytes, _lease, view) => Effect.gen(function* () {
          record("sink_calls"); const read = countBytes(view.utf8(decision, bytes));
          if (sinkAction.includes("save own") || releaseAction.includes("save own")) savedSinkRead = read;
          if (stimulus.procedure === "second_publish_while_first_pending") { yield* Deferred.succeed(entered, undefined); yield* Deferred.await(proceed); }
          if (sinkAction.includes("await proceed")) { yield* Deferred.succeed(entered, undefined); yield* Deferred.await(proceed); }
          if (variant !== null && sinkAction.includes("foreign membership")) {
            assert.ok(typeof variant === "object" && "request" in variant && "payload" in variant);
            const before = counts.authority_calls, materials = counts.byte_observations;
            const request = variant.request === "throwing_Proxy_all_traps" ? proxy(counts) : decision;
            const payload = variant.payload === "revoked_bytes" ? proxy(counts, true) : bytes;
            variantResults.push(yield* countBytes(view.utf8(request, payload))); variantChecks += counts.authority_calls - before; variantMaterials += counts.byte_observations - materials;
          }
          const text = yield* read; assert.ok(text !== null);
          if (sinkAction.includes("then die")) return yield* Effect.die("SYNTHETIC_SECRET");
          if (sinkAction.includes("revoke frontier")) { revoked = true; yield* read; }
          if (sinkAction.includes("close originalScope")) close();
        })
      }
    };
    const otherScope = yield* Scope.make(); yield* Effect.addFinalizer(() => Scope.close(otherScope, Exit.succeed(undefined)));
    const foreignServices: TrustedServices = {
      ...services,
      common: { receive: (_wire, issuer) => Effect.sync(() => {
        const value = issuer.value(stimulus.port_inputs.value_wire); assert.ok(value); const outcome = issuer.outcome(stimulus.port_inputs.descriptor_wire, value); assert.ok(outcome); return outcome;
      }) },
      current: { check: () => Effect.void },
      renderer: { render: (outcome, mode, issuer, view) => Effect.gen(function* () {
        const m = view.inspect(outcome); assert.ok(m?.value); const wire = yield* view.sourceValueWire(outcome, m.value); assert.ok(wire !== null); const mm = view.mode(mode); assert.ok(mm);
        const token = issuer.encodedUTF8(renderInput(wire, mm.mode), outcome); assert.ok(token); foreignBytes = token; return token;
      }) },
      raw: { validate: (outcome, issuer, view) => Effect.gen(function* () {
        const m = view.inspect(outcome); assert.ok(m?.value); const wire = yield* view.sourceValueWire(outcome, m.value); assert.ok(wire !== null); const text: unknown = JSON.parse(wire);
        const token = issuer.validated(text, m.value, outcome); assert.ok(token); foreignValidated = token; return token;
      }) }
    };
    let foreignOutcome: OwnedCommonOutcome | null = null, foreignMode: OwnedMode | null = null;
    const needForeign = rendererAction.includes("other-factory") || rawAction.includes("foreign authentic") || actionText(stimulus, "override").includes("other_factory");
    if (needForeign) {
      const other = yield* CliEnvelopeFactory.create(foreignServices).pipe(Effect.provideService(Scope.Scope, otherScope));
      foreignMode = yield* other.selectMode(stimulus.mode_wire); foreignOutcome = yield* other.receive(stimulus.common_input_wire);
      if (rendererAction.includes("other-factory") || rawAction.includes("foreign authentic")) yield* other.render(foreignOutcome, foreignMode);
    }
    const envelope = yield* CliEnvelopeFactory.create(services).pipe(Effect.provideService(Scope.Scope, original));
    if (controllerAction.includes("before receive")) close();
    const commonOverride: unknown = "input_override" in stimulus ? stimulus.input_override : undefined;
    const modeOverride: unknown = "mode_override" in stimulus ? stimulus.mode_override : undefined;
    const commonInput = commonOverride === undefined ? stimulus.common_input_wire : override(commonOverride, counts);
    const modeInput = modeOverride === undefined ? stimulus.mode_wire : override(modeOverride, counts);
    let decision: OwnedDecision | null = null;
    const operation = Effect.gen(function* () {
      if (stimulus.procedure === "receive_only") { yield* envelope.receive(commonInput); return null; }
      if (stimulus.procedure === "select_mode_only") { yield* envelope.selectMode(modeInput); return null; }
      const mode = yield* envelope.selectMode(modeInput), outcome = yield* envelope.receive(commonInput);
      if (stimulus.procedure === "render_foreign") {
        Object.assign(counts, blank()); // Target counter window excludes authenticated setup.
        const name = actionText(stimulus, "override");
        const badOutcome = name === "outcome_Proxy" ? proxy(counts) : name === "outcome_revoked_Proxy" ? proxy(counts, true) : name === "other_factory_outcome" ? foreignOutcome : outcome;
        const badMode = name === "mode_Proxy" ? proxy(counts) : name === "other_factory_mode" ? foreignMode : mode;
        yield* envelope.render(badOutcome, badMode); return null;
      }
      decision = yield* envelope.render(outcome, mode); const completion = yield* envelope.publish(decision); return yield* envelope.exit(completion);
    });
    let result: Exit.Exit<0 | 1 | 2 | null, FixedFailure>;
    let backgroundReleaseACKs = 0;
    if (stimulus.procedure === "second_publish_while_first_pending") {
      const mode = yield* envelope.selectMode(modeInput), outcome = yield* envelope.receive(commonInput); decision = yield* envelope.render(outcome, mode);
      const background = yield* Effect.forkChild(envelope.publish(decision)); yield* Deferred.await(entered);
      const before = { ...counts }; result = yield* Effect.exit(envelope.publish(decision).pipe(Effect.as(null)));
      const window = { ...counts }; yield* Fiber.interrupt(background); const end = yield* Fiber.await(background); assert.ok(interrupted(end));
      backgroundReleaseACKs = counts.release_ACKs - before.release_ACKs;
      for (const k of Object.keys(counts) as (keyof Counts)[]) counts[k] = window[k] - before[k];
    } else if (allocationAction.includes("interrupt") || externalPrepare || externalRegistered) {
      const child = yield* Effect.forkChild(operation); yield* Deferred.await(entered);
      if (externalPrepare || externalRegistered) {
        close();
        if (externalRegistered) { yield* Deferred.await(releasing); closeWhileAck = originalClosed && child.pollUnsafe() === undefined; terminalBeforeAck = child.pollUnsafe() !== undefined; busyWhileAck = child.pollUnsafe() === undefined; yield* Deferred.succeed(ack, undefined); }
        result = yield* Fiber.await(child);
      } else {
        const stopping = yield* Effect.forkChild(Fiber.interrupt(child));
        if (allocationAction.includes("completed allocation held")) { yield* Deferred.await(releasing); assert.equal(child.pollUnsafe(), undefined); yield* Deferred.succeed(ack, undefined); }
        yield* Fiber.join(stopping); result = yield* Fiber.await(child);
      }
    } else if (rendererAction.includes("waiting in Deferred") || sinkAction.includes("await proceed") || sinkAction.includes("current Deferred")) {
      const child = yield* Effect.forkChild(operation); yield* Deferred.await(entered);
      if (sinkAction.includes("await proceed")) revoked = true; else close();
      yield* Deferred.succeed(proceed, undefined); result = yield* Fiber.await(child);
    } else if (releaseAction.includes("Deferred pending")) {
      const child = yield* Effect.forkChild(operation); yield* Deferred.await(releasing); terminalBeforeAck = child.pollUnsafe() !== undefined; assert.equal(terminalBeforeAck, false);
      yield* Deferred.succeed(ack, undefined); result = yield* Fiber.await(child);
    } else result = yield* Effect.exit(operation);
    if (releaseAction.includes("fail with")) {
      assert.ok(decision); const before = counts.authority_calls; const again = yield* Effect.exit(envelope.publish(decision)); assert.equal(ownFailure(again), "private_cli_cleanup"); assert.equal(counts.authority_calls, before);
    }
    const completedMetadata = decision ? envelope.inspect(decision) : null;
    if (controllerAction.includes("provide fresh Scope")) {
      const lateRead = (() : Effect.Effect<string | null, FixedFailure> | null => savedRead)();
      assert.ok(lateRead); services.current.check = () => Effect.sync(() => { replacementChecks++; });
      const fresh = yield* Scope.make(); yield* Effect.addFinalizer(() => Scope.close(fresh, Exit.succeed(undefined)));
      const before = counts.authority_calls; lateResults.push(yield* lateRead.pipe(Effect.provideService(Scope.Scope, fresh))); close(); lateResults.push(yield* lateRead.pipe(Effect.provideService(Scope.Scope, fresh))); lateChecks += counts.authority_calls - before;
    }
    const completedExit = Exit.isSuccess(result) ? result.value : null;
    const completed = completedExit !== null;
    const metadata = completedMetadata;
    const output = completed ? observed.at(-1) ?? null : null;
    const extras: Record<string, unknown> = {};
    if ("common_extra_value_wire" in stimulus.port_inputs) Object.assign(extras, {
      same_callback_other_value_result: sameCallbackOtherValueResult,
      same_callback_other_value_authority_calls: sameCallbackOtherValueChecks,
      same_callback_other_value_materializations: sameCallbackOtherValueMaterials
    });
    if (variant !== null) Object.assign(extras, { variant_results: variantResults, variant_authority_calls: variantChecks, variant_materializations: variantMaterials });
    if (commonAction.includes("save own") || rendererAction.includes("save own") || sinkAction.includes("save own") || releaseAction.includes("save own")) Object.assign(extras, { escaped_results: escapedResults, escaped_authority_calls: escapedChecks, escaped_materializations: escapedMaterials, revival: escapedResults.some((x) => x !== null) });
    if (controllerAction.includes("provide fresh Scope")) Object.assign(extras, { late_results: lateResults, late_authority_calls: lateChecks, replacement_authority_calls: replacementChecks, revival: lateResults.some((x) => x !== null) });
    if (stimulus.procedure === "second_publish_while_first_pending") Object.assign(extras, { background_release_ACKs: backgroundReleaseACKs, busy_until_ACK: backgroundReleaseACKs === 1 });
    if (externalPrepare || externalRegistered) Object.assign(extras, {
      external_close_notification_completed: originalClosed,
      phase_Deferred_resumed: false, use_calls: useCalls, after_allocation_authority_calls: afterAllocationCalls,
      original_close_claims_resource_ACK: false, completed_release_ACK_before_bracket_terminal: externalRegistered && counts.release_ACKs === 1,
      preparation_cancellation_acknowledged: prepCancelled, watcher_outstanding_after_terminal: watchers, owned_phase_Fibers_outstanding_after_terminal: phaseFibers,
      ...(externalRegistered ? { Scope_close_completed_while_release_ACK_pending: closeWhileAck, publish_terminal_before_ACK: terminalBeforeAck, busy_held_while_ACK_pending: busyWhileAck } : {})
    });
    const descriptor: unknown = JSON.parse(stimulus.port_inputs.descriptor_wire);
    if (descriptor !== null && typeof descriptor === "object" && "artifactFamily" in descriptor && descriptor.artifactFamily !== null && !stimulus.host.rawFamilies.includes(descriptor.artifactFamily as never)) Object.assign(extras, { source_family_identity_retained: descriptor.artifactFamily, public_unsupported_claim: false });
    return {
      kind: completed ? "completion" : interrupted(result) ? "interruption" : "private_failure",
      mode: completed ? metadata?.mode ?? null : null, stdout_utf8: output, stderr_utf8: "", exit: completedExit,
      private_failure: ownFailure(result), ...counts, provider_echo: output?.includes("SYNTHETIC_SECRET") ?? false,
      publication_ambiguous: !completed && observed.length > 0, byte_text_observations: observed,
      stdout_field_meaning: "owned returned bytes on completed private publication; null is no returned decision, NOT rollback of observed text or actual external delivery guarantee",
      ...extras
    };
  }));
}
for (const scene of resultEnvelopeFixture.cases) {
  test("independent CLI result envelope literal: " + scene.case_id, async () => {
    // Expected enters only this final assertion. runScene receives stimulus and trusted input data.
    const observed = await Effect.runPromise(runScene(scene.stimulus));
    assert.deepEqual(observed, scene.expected);
  });
}
