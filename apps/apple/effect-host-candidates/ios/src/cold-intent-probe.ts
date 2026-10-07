import React from "react";
import { NativeModules } from "react-native";
import * as Effect from "effect/Effect";
import * as Fiber from "effect/Fiber";
import * as Layer from "effect/Layer";
import * as Exit from "effect/Exit";
import { CandidateSession, inspectCandidate } from "healthmd-candidate-capabilities";

// A callable headless entry. Importing this module performs no synthetic acquisition.
declare const global: { RN$registerCallableModule(name: string, factory: () => object): void; HermesInternal?: { getRuntimeProperties(): Record<string, unknown> } };
type Code = "ready" | "schema_invalid" | "frame_limit" | "expired" | "backpressure" | "cancelled" | "runtime_unavailable" | "probe_assertion";
interface Counts { acquired: number; released: number; active: number; releasing: number; inspecting: number; unresolved_inspections: number; accepted_frames: number; acknowledged_frames: number; max_active: number; max_queued: number }
interface Resource { acquire(delay: number): Promise<number>; inspect(token: number): Promise<string>; release(token: number): Promise<void>; reset(): Promise<void>; stats(): Promise<Counts>; frame(value: string): Promise<string> }
interface Mailbox { ready(): void; admit(ticket: string): Promise<Code>; complete(ticket: string, code: Code, acquired: number, released: number, active: number, ack: boolean, interruptedDuringRelease: boolean, creditOK: boolean): void }
const native = NativeModules.NativeProbe as Resource;
const mailbox = NativeModules.ColdProbeMailbox as Mailbox;
const cases = "actual_ingress_no_view|unknown_schema_before_acquire|expiry_before_acquire|cancel_waits_native_ack|restart_no_grant_expansion";
const grammar = new RegExp(`^\\{"schema":"healthmd\\.candidate_cold_intent","version":1,"case_id":"(${cases})","sequence":(0|[1-9][0-9]{0,3}),"deadline_milliseconds":(0|[1-9][0-9]{0,3})\\}$`);
const pause = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));
const running = new Map<string, ReturnType<typeof Effect.runFork>>();
const cancelled = new Set<string>();
function assert(value: unknown): asserts value { if (!value) throw new Error("probe_assertion"); }
async function invoke(ticket: string, input: unknown) {
  let code: Code = "probe_assertion";
  let interruptedDuringRelease = false;
  let creditOK = false;
  try {
    assert(typeof input === "string" && input.length <= 65536 && /^[\x20-\x7e]*$/.test(input));
    const match = grammar.exec(input);
    assert(match && Number(match[2]) <= 1023 && Number(match[3]) <= 5000);
    assert(React.version === "19.2.3" && global.HermesInternal);
    const engine = global.HermesInternal.getRuntimeProperties();
    assert(engine["Build"] === "Release" && engine["OSS Release Version"] === "250829098.0.17" && engine["Bytecode Version"] === 98);
    const admitted = await mailbox.admit(ticket);
    if (admitted !== "ready" || cancelled.has(ticket)) { code = admitted === "ready" ? "cancelled" : admitted; return; }
    await native.reset();
    const cancelCase = match[1] === "cancel_waits_native_ack";
    const layer = Layer.succeed(CandidateSession)({ acquire: Effect.promise(async () => {
      // Native monotonic deadline and ownership are checked immediately before acquire.
      const status = await mailbox.admit(ticket);
      if (status !== "ready" || cancelled.has(ticket)) throw new Error("cancelled");
      const token = await native.acquire(cancelCase ? 1000 : 0);
      return { inspect: Effect.promise(async () => {
        assert(await native.inspect(token) === "ready"); return "ready" as const;
      }), release: Effect.promise(() => native.release(token)) };
    }) });
    const fiber = Effect.runFork(inspectCandidate.pipe(Effect.provide(layer)));
    running.set(ticket, fiber);
    if (cancelled.has(ticket)) void Effect.runPromise(Fiber.interrupt(fiber));
    if (cancelCase) {
      for (let i = 0; i < 200 && (await native.stats()).inspecting === 0 && fiber.pollUnsafe() === undefined; i++) await pause(5);
      const cancellation = Effect.runFork(Fiber.interrupt(fiber));
      for (let i = 0; i < 100; i++) {
        const stats = await native.stats();
        if (stats.releasing === 1) { interruptedDuringRelease = stats.active === 1 && stats.released === 0 && cancellation.pollUnsafe() === undefined; break; }
        await pause(1);
      }
      await Effect.runPromise(Fiber.join(cancellation));
    }
    const exit = await Effect.runPromise(Fiber.await(fiber));
    code = Exit.isSuccess(exit) ? "ready" : cancelCase || cancelled.has(ticket) ? "cancelled" : "probe_assertion";
    // The seven-frame check is synthetic credit evidence, not OS cancellation evidence.
    if (cancelCase) {
      const frame = '{"schema":"healthmd.candidate_host_probe","version":1,"case_id":"queue_backpressure","sequence":0}';
      const results = await Promise.all(Array.from({length: 7}, () => native.frame(frame).then(() => true, () => false)));
      const counts = await native.stats();
      creditOK = results.filter(Boolean).length === 6 && counts.accepted_frames === 6 && counts.acknowledged_frames === 6 && counts.max_active === 2 && counts.max_queued === 4;
      assert(interruptedDuringRelease && creditOK);
    }
  } catch { code = "probe_assertion"; }
  finally {
    running.delete(ticket);
    try {
      const stats = await native.stats();
      const ack = stats.active === 0 && stats.releasing === 0 && stats.unresolved_inspections === 0;
      mailbox.complete(ticket, code, stats.acquired, stats.released, stats.active, ack, interruptedDuringRelease, creditOK);
    } catch { mailbox.complete(ticket, "runtime_unavailable", 0, 0, 0, false, false, false); }
    cancelled.delete(ticket);
  }
}
global.RN$registerCallableModule("CandidateColdProbe", () => ({
  invoke,
  cancel(ticket: string) {
    if (cancelled.size < 6) cancelled.add(ticket);
    const fiber = running.get(ticket);
    if (fiber) void Effect.runPromise(Fiber.interrupt(fiber));
  },
}));
mailbox.ready();
