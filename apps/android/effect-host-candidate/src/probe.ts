import * as Effect from "effect/Effect";
import * as Fiber from "effect/Fiber";
import * as Layer from "effect/Layer";
import * as Exit from "effect/Exit";
import { CandidateSession, inspectCandidate } from "healthmd-candidate-capabilities";
import { createReadinessModel } from "healthmd-candidate-ui";

interface Counts { acquired: number; released: number; active: number; inspecting: number; unresolved_inspections: number; releasing: number; accepted_frames: number; acknowledged_frames: number; max_active: number; max_queued: number; active_frames: number; queued_frames: number }
interface NativeProbe {
  acquire(delay: number): Promise<number>;
  inspect(token: number): Promise<string>;
  release(token: number): Promise<void>;
  stats(): Promise<Counts>;
  frame(value: string): Promise<string>;
  reset(): Promise<void>;
  report(value: string): void;
}
const pause = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));
const assert = (condition: unknown) => { if (!condition) throw new Error("probe_assertion"); };
export async function runHostProbe(native: NativeProbe, engine: { react: string; hermes: boolean; hermes_release?: string; bytecode_version?: number; engine_build?: string }) {
  const observations: Array<{case_id: string; result: "passed"; observed: object}> = [];
  const record = (case_id: string, observed: object) => observations.push({case_id, result: "passed", observed});
  const layer = (delay = 0) => Layer.succeed(CandidateSession)({acquire: Effect.promise(async () => {
    const token = await native.acquire(delay);
    return {inspect: Effect.promise(async () => {
      assert(await native.inspect(token) === "ready");
      return "ready" as const;
    }), release: Effect.promise(() => native.release(token))};
  })});
  try {
    assert(engine.react === "19.2.3" && engine.hermes);
    record("single_react_effect_identity", {...engine, effect: "4.0.1", mounted_react: false});
    await native.reset();
    assert(await Effect.runPromise(inspectCandidate.pipe(Effect.provide(layer()))) === "ready");
    let counts = await native.stats();
    assert(counts.acquired === 1 && counts.released === 1 && counts.active === 0);
    record("offline_success", {...counts, value: "ready"});

    await native.reset();
    const model = createReadinessModel({read: async () => {
      await Effect.runPromise(inspectCandidate.pipe(Effect.provide(layer())));
      return [];
    }});
    model.subscribe(() => { if (model.getSnapshot().phase === "loading") void model.cancel(); });
    await model.refresh();
    counts = await native.stats();
    assert(counts.acquired === 0 && counts.released === 0);
    record("cancel_before_acquire", {...counts, stale_reads: 0});
    await model.dispose();

    await native.reset();
    const operation = Effect.runFork(inspectCandidate.pipe(Effect.provide(layer(1000))));
    for (let i = 0; i < 200 && (await native.stats()).inspecting === 0; i++) await pause(5);
    assert((await native.stats()).inspecting === 1);
    const started = Date.now();
    const cancellation = Effect.runFork(Fiber.interrupt(operation));
    let pending = await native.stats();
    for (let i = 0; i < 100 && pending.releasing === 0; i++) { await pause(1); pending = await native.stats(); }
    assert(pending.releasing === 1 && pending.released === 0 && pending.active === 1 && cancellation.pollUnsafe() === undefined);
    await Effect.runPromise(Fiber.join(cancellation));
    counts = await native.stats();
    const cleanup_ms = Date.now() - started;
    assert(counts.released === 1 && counts.active === 0 && counts.inspecting === 0 && counts.unresolved_inspections === 0 && cleanup_ms >= 30 && cleanup_ms < 5000);
    const cancellationCounts = counts;
    await native.reset();
    const expired = await Effect.runPromiseExit(inspectCandidate.pipe(Effect.provide(layer(5100)), Effect.timeout("5 seconds")));
    counts = await native.stats();
    assert(Exit.isFailure(expired) && counts.released === 1 && counts.active === 0 && counts.inspecting === 0 && counts.unresolved_inspections === 0);
    record("cancel_waits_release_ack", {...cancellationCounts, cleanup_ms, ack_before_completion: true, expiry_ack_before_completion: true, incomplete_during_native_release: true});

    let stale_reads = 0; let fresh_reads = 0; let released = 0;
    for (const action of ["dispose", "cancel", "refresh"] as const) {
      let entered = false;
      const reentry = createReadinessModel({read: async (scope) => {
        if (action !== "refresh" || scope.isCancelled() || reentry.getSnapshot().phase !== "loading") stale_reads++;
        else fresh_reads++;
        scope.addFinalizer(() => { released++; });
        return [];
      }});
      reentry.subscribe(() => {
        if (reentry.getSnapshot().phase === "loading" && !entered) { entered = true; void reentry[action](); }
      });
      await reentry.refresh(); await pause(10); await reentry.dispose();
    }
    assert(stale_reads === 0 && fresh_reads === 1 && released === 1);
    record("reentry_dispose_cancel_supersede", {stale_reads, fresh_reads, released, active: (await native.stats()).active});

    await native.reset();
    const invalid = async (value: string, code: string) => {
      try { await native.frame(value); throw new Error("unexpected_admission"); }
      catch (error) { assert(typeof error === "object" && error !== null && "code" in error && error.code === code); }
      assert((await native.stats()).acquired === 0);
    };
    await invalid("é".repeat(32768) + "a", "frame_limit");
    await invalid("é".repeat(32768), "schema_invalid");
    await invalid("\uD800", "schema_invalid");
    await invalid("\uDC00", "schema_invalid");
    record("frame_limit", {code: "frame_limit", acquired: 0, utf8_multibyte_rejected: true});
    await invalid(JSON.stringify({schema: "wrong", version: 1}), "schema_invalid");
    for (const value of [{version: true, sequence: 0}, {version: 1, sequence: false}, {version: 1.5, sequence: 0}]) {
      await invalid(JSON.stringify({schema: "healthmd.candidate_host_probe", case_id: "queue_backpressure", ...value}), "schema_invalid");
    }
    const validFrame = {schema: "healthmd.candidate_host_probe", version: 1, case_id: "queue_backpressure", sequence: 0};
    for (const changed of [{schema: 1}, {schema: true}, {case_id: 1}, {case_id: false}, {version: "1"}, {version: 2}, {sequence: "0"}, {sequence: 1}, {sequence: 0.5}, {extra: "rejected"}]) {
      await invalid(JSON.stringify({...validFrame, ...changed}), "schema_invalid");
    }
    for (const value of ["{", "[]", "null"]) await invalid(value, "schema_invalid");
    record("unknown_schema_before_acquire", {code: "schema_invalid", acquired: 0, boolean_and_fractional_negatives: 3});
    const frame = JSON.stringify({schema: "healthmd.candidate_host_probe", version: 1, case_id: "queue_backpressure", sequence: 0});
    const acknowledgments: number[] = [];
    const results = await Promise.all(Array.from({length: 7}, (_, index) => native.frame(frame).then(() => { acknowledgments.push(index); return true; }, (error) => { assert(error.code === "backpressure"); return false; })));
    assert(results.filter(Boolean).length === 6 && results.filter((x) => !x).length === 1);
    counts = await native.stats();
    assert(counts.accepted_frames === 6 && counts.acknowledged_frames === 6 && counts.max_active === 2 && counts.max_queued === 4 && counts.active_frames === 0 && counts.queued_frames === 0);
    const fifo = acknowledgments.every((value, index) => value === index);
    assert(fifo);
    record("queue_backpressure", {accepted: counts.accepted_frames, rejected: 1, max_active: counts.max_active, max_queued: counts.max_queued, acknowledged: counts.acknowledged_frames, active_frames: counts.active_frames, queued_frames: counts.queued_frames, fifo});
    assert(await native.frame(frame) === "ack");

    await native.reset();
    await Effect.runPromise(inspectCandidate.pipe(Effect.provide(layer())));
    counts = await native.stats();
    assert(counts.acquired === 1 && counts.released === 1 && counts.active === 0);
    record("teardown_fresh_restart", {...counts, private_state_writes: 0});
    // These adapter counters are separately checked against the merged APK manifest.
    record("no_native_grant_expansion", {health_permissions: 0, internet_permissions: 0, health_reads: 0, persistent_writes: 0, scope: "candidate_owned_adapter"});
    native.report(JSON.stringify({schema: "healthmd.candidate_host_probe", version: 1, result: "passed", observations}));
  } catch {
    native.report(JSON.stringify({schema: "healthmd.candidate_host_probe", version: 1, result: "failed", code: "probe_assertion", completed_cases: observations.length}));
  }
}
