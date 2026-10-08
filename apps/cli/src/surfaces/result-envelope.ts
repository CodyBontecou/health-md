/** Stage1 private contract only. All literals independently source-derived before candidate code. */
import * as Effect from "effect/Effect";
import type * as Scope from "effect/Scope";
const outcomeBrand: unique symbol = Symbol("outcomeBrand");
const modeBrand: unique symbol = Symbol("modeBrand");
const valueBrand: unique symbol = Symbol("valueBrand");
const bytesBrand: unique symbol = Symbol("bytesBrand");
const validatedBrand: unique symbol = Symbol("validatedBrand");
const decisionBrand: unique symbol = Symbol("decisionBrand");
const completionBrand: unique symbol = Symbol("completionBrand");
const leaseBrand: unique symbol = Symbol("leaseBrand");
export interface OwnedCommonOutcome { readonly [outcomeBrand]: true }
export interface OwnedMode { readonly [modeBrand]: true }
export interface OwnedValue { readonly [valueBrand]: true }
export interface OwnedBytes { readonly [bytesBrand]: true }
export interface OwnedValidatedRaw { readonly [validatedBrand]: true }
export interface OwnedDecision { readonly [decisionBrand]: true }
export interface OwnedCompletion { readonly [completionBrand]: true }
export interface OwnedOutputLease { readonly [leaseBrand]: true }
export type FixedFailure = { readonly code: "private_cli_input" | "private_cli_owned" | "private_cli_codec" | "private_cli_authority" | "private_cli_cleanup" | "private_cli_busy" | "private_cli_publish" | "private_cli_capability" | "owned_handoff_closed" };
export type ModeMetadata = { readonly mode: "json" | "human"; readonly conflictingFlags: boolean; readonly plainHuman: true; readonly columns: 100 };
export type OutcomeKind = "structured_success" | "local_discovery" | "parse_failure" | "operational_failure" | "raw_artifact" | "plain_text";
export type ArtifactFamily = "raw_json_stdout" | "jsonl_stdout_and_receipt_stderr" | "artifact_destination" | "jsonl_destination_and_receipt";
export type OutcomeMetadata = { readonly kind: OutcomeKind; readonly command: "status" | "query" | "direct"; readonly value: OwnedValue | null; readonly artifactFamily: ArtifactFamily | null; readonly fixedPolicy: "none" | "unknown_argument" | "argument_conflict" | "runtime_unavailable" | "wake_window_expired" | "output_write_failed" };
export type SourceValue = null | boolean | string | { readonly kind: "signed_integer" | "unsigned_integer"; readonly decimal: string } | { readonly kind: "binary64"; readonly bits: string } | readonly SourceValue[] | { readonly kind: "object"; readonly entries: readonly (readonly [string, SourceValue])[] };
export interface CommonOutcomeIssuer {
  /** Issuance only inside captured trusted producer callback, primitive bounds first.
   * Same callback/context/factory owns values and outcomes. Provider cause/message is never an input. */
  value(primitiveSourceValueWire: unknown): OwnedValue | null;
  outcome(primitiveClosedMetadataWire: unknown, value: unknown): OwnedCommonOutcome | null;
}
export interface CommonOutcomePort {
  /** Closed inert synthetic stimulus, never an evaluator/parser/grant or caller-authenticating JSON. */
  receive(primitiveHandoffWire: string, issuer: CommonOutcomeIssuer): Effect.Effect<OwnedCommonOutcome, FixedFailure>;
}
export type AuthorityPhase = "after_common" | "before_raw_validation" | "after_raw_validation" | "before_render" | "before_materialization" | "after_render" | "before_decision" | "before_allocation" | "after_allocation" | "before_publication" | "after_publication" | "assert_current";
export interface InertOutcomeView { inspect(outcome: unknown): OutcomeMetadata | null }
export interface AuthorizedOutcomeView extends InertOutcomeView {
  /** Membership-first inert mode metadata only; unknown/foreign modes return null before properties. */
  mode(mode: unknown): ModeMetadata | null;
  /** LAZY EACH execution: exact request + OWN value membership and exact returned outcome.metadata.value identity before properties/check;
   * captured original current check before materialization, original Scope/context/callback
   * rechecked after await, including exact returned outcome/value identity, then return primitive wire without an intervening yield.
   * Unbound same-callback own values return null before current or materialization. */
  sourceValueWire(outcome: unknown, value: unknown): Effect.Effect<string | null, FixedFailure>;
}
export interface CurrentAuthority {
  /** Host binds original catalog/classification/caller/source/purpose/destination/latest independent
   * suppression frontier. Producer/input metadata, command, TTY and source IDs do not authenticate. */
  check(outcome: OwnedCommonOutcome, phase: AuthorityPhase, view: InertOutcomeView): Effect.Effect<void, FixedFailure>;
}
export interface ByteIssuer { encodedUTF8(primitiveText: unknown, outcome: unknown): OwnedBytes | null }
export interface CanonicalRenderer {
  /** Trusted pure rendering adapter with Effect-valued reads, not a second common evaluator.
   * JSON pretty/human complete algorithms and admitted exact-number adapter remain future owners.
   * Fakes use source-value input witnesses/generic restricted transforms, NEVER case IDs/expected bytes. */
  render(outcome: OwnedCommonOutcome, mode: OwnedMode, issuer: ByteIssuer, view: AuthorizedOutcomeView): Effect.Effect<OwnedBytes, FixedFailure>;
}
export interface RawIssuer { validated(primitiveUTF8Text: unknown, value: unknown, outcome: unknown): OwnedValidatedRaw | null }
export interface RawArtifactValidator {
  /** Callback-issued same-outcome validation witness, never a caller boolean/filename/profile claim. */
  validate(outcome: OwnedCommonOutcome, issuer: RawIssuer, view: AuthorizedOutcomeView): Effect.Effect<OwnedValidatedRaw, FixedFailure>;
}
export type DecisionMetadata = { readonly mode: "json" | "human" | "raw" | "text"; readonly exit: 0 | 1 | 2; readonly outputKind: "structured" | "raw_artifact" | "plain_text"; readonly artifactFamily: ArtifactFamily | null; readonly stderr: "empty" | "owned_receipt"; readonly publication: "not_started" };
export interface InertDecisionView { inspect(decision: unknown): DecisionMetadata | null }
export interface AuthorizedBytesView extends InertDecisionView {
  /** LAZY EACH execution; exact request + OWN byte token membership first. Captured current
   * before_publication then original Scope/poison/context/membership/sink-callback recheck.
   * Foreign Proxy request with OWN bytes returns null with zero checks/traps.
   * Callback expires immediately on actual sink Effect exit, before postcurrent/release ACK. */
  utf8(decision: unknown, bytes: unknown): Effect.Effect<string | null, FixedFailure>;
}
export interface CapturedOutputLifetime {
  /** Original constructor-captured Scope/poison sentinel; not a current-authority permit. */
  isLive(): boolean;
  /** Reusable lazy terminal notification completed by original Scope finalizer.
   * It never consults a caller Scope or replacement Layer and never awaits resource ACK. */
  readonly closed: Effect.Effect<void>;
}
export interface OutputWriter {
  /** Owns prepare, partial cleanup, finite commit/registration and release ACK. */
  withLease<A>(
    decision: OwnedDecision,
    view: InertDecisionView,
    lifetime: CapturedOutputLifetime,
    use: (lease: OwnedOutputLease) => Effect.Effect<A, FixedFailure>
  ): Effect.Effect<A, FixedFailure>;
  publish(decision: OwnedDecision, bytes: OwnedBytes, lease: OwnedOutputLease, view: AuthorizedBytesView): Effect.Effect<void, FixedFailure>;
}
export interface TrustedCapabilities {
  /** Captured host object, not caller wire; still not actual source/OS admission. */
  readonly rawFamilies: readonly ArtifactFamily[];
  readonly plainText: boolean;
}
export interface TrustedServices { readonly common: CommonOutcomePort; readonly current: CurrentAuthority; readonly renderer: CanonicalRenderer; readonly raw: RawArtifactValidator; readonly writer: OutputWriter; readonly capabilities: TrustedCapabilities }
export interface CliEnvelope {
  selectMode(primitiveFlagWire: unknown): Effect.Effect<OwnedMode, FixedFailure>;
  receive(primitiveHandoffWire: unknown): Effect.Effect<OwnedCommonOutcome, FixedFailure>;
  render(outcome: unknown, mode: unknown): Effect.Effect<OwnedDecision, FixedFailure>;
  inspect(decision: unknown): DecisionMetadata | null;
  publish(decision: unknown): Effect.Effect<OwnedCompletion, FixedFailure>;
  exit(completion: unknown): Effect.Effect<0 | 1 | 2, FixedFailure>;
  assertCurrent(decision: unknown): Effect.Effect<void, FixedFailure>;
}
export interface CliEnvelopeFactory { create(trusted: TrustedServices): Effect.Effect<CliEnvelope, FixedFailure, Scope.Scope> }

import * as Deferred from "effect/Deferred";
type Code = FixedFailure["code"];
const failures = new WeakMap<object, Code>();
/** Private adapter/test failure constructor; never accepts a provider cause or message. */
export function fixedFailure(code: Code): FixedFailure {
  const value = Object.freeze({ code }); failures.set(value, code); return value;
}
function refuse(code: Code): never { throw fixedFailure(code); }
function ownCode(error: unknown, fallback: Code): Code {
  return error !== null && typeof error === "object" ? failures.get(error) ?? fallback : fallback;
}
function attempt<A>(body: () => A, fallback: Code): Effect.Effect<A, FixedFailure> {
  return Effect.try({ try: body, catch: (error) => fixedFailure(ownCode(error, fallback)) });
}
function sanitize<A, E, R>(body: Effect.Effect<A, E, R>, fallback: Code): Effect.Effect<A, FixedFailure, R> {
  return Effect.uninterruptibleMask((restore) => restore(body).pipe(Effect.catchCause((cause) => {
    if (cause.reasons.some((reason) => reason._tag === "Interrupt")) return Effect.interrupt;
    const failed = cause.reasons.find((reason) => reason._tag === "Fail");
    return Effect.fail(fixedFailure(failed?._tag === "Fail" ? ownCode(failed.error, fallback) : fallback));
  })));
}
function isObject(value: unknown): value is object { return value !== null && typeof value === "object"; }
function utf8(text: string, maximum: number): void {
  if (text.length > maximum) refuse("private_cli_input");
  let count = 0;
  for (let i = 0; i < text.length; i++) {
    const c = text.charCodeAt(i);
    if (c >= 0xd800 && c <= 0xdbff) {
      const low = text.charCodeAt(++i);
      if (!(low >= 0xdc00 && low <= 0xdfff)) refuse("private_cli_input"); count += 4;
    } else if (c >= 0xdc00 && c <= 0xdfff) refuse("private_cli_input");
    else count += c < 128 ? 1 : c < 2048 ? 2 : 3;
    if (count > maximum) refuse("private_cli_input");
  }
}
interface Node { readonly kind: "object" | "array" | "string" | "number" | "true" | "false" | "null"; readonly start: number; readonly end: number; readonly fields?: ReadonlyMap<string, Node>; readonly items?: readonly Node[] }
/** Bounded PRIVATE grammar only. Number lexemes stay raw; only descriptor/key strings decode.
 * This is not the retained serde parser or a numerical/public serializer replacement. */
function scan(text: string, maximum = 65536): Node {
  utf8(text, maximum); let index = 0, nodes = 0;
  const white = () => { while (index < text.length && /[ \t\r\n]/.test(text[index]!)) index++; };
  const string = (): Node => {
    const start = index++; let decoded = 0;
    while (index < text.length) {
      let c = text.charCodeAt(index++);
      if (c === 34) return { kind: "string", start, end: index };
      if (c < 32) refuse("private_cli_input");
      if (c === 92) {
        const e = text[index++];
        if (e === "u") {
          const raw = text.slice(index, index + 4); if (!/^[0-9a-fA-F]{4}$/.test(raw)) refuse("private_cli_input");
          c = parseInt(raw, 16); index += 4;
          if (c >= 0xd800 && c <= 0xdbff) {
            if (text.slice(index, index + 2) !== "\\u") refuse("private_cli_input");
            const low = text.slice(index + 2, index + 6);
            if (!/^[0-9a-fA-F]{4}$/.test(low) || parseInt(low, 16) < 0xdc00 || parseInt(low, 16) > 0xdfff) refuse("private_cli_input");
            index += 6; c = 0x10000;
          } else if (c >= 0xdc00 && c <= 0xdfff) refuse("private_cli_input");
        } else if (!['"', "\\", "/", "b", "f", "n", "r", "t"].includes(e ?? "")) refuse("private_cli_input");
        else c = 32;
      } else if (c >= 0xd800 && c <= 0xdbff) { index++; c = 0x10000; }
      decoded += c < 128 ? 1 : c < 2048 ? 2 : c < 65536 ? 3 : 4;
      if (decoded > 16384) refuse("private_cli_input");
    }
    return refuse("private_cli_input");
  };
  const value = (depth: number): Node => {
    if (depth > 32 || ++nodes > 4096) refuse("private_cli_input"); white(); const start = index, first = text[index];
    if (first === '"') return string();
    if (first === "{" || first === "[") {
      const object = first === "{", end = object ? "}" : "]"; index++; white();
      const fields = new Map<string, Node>(), items: Node[] = [];
      if (text[index] !== end) while (true) {
        if (object) {
          if (text[index] !== '"') refuse("private_cli_input");
          const keyNode = string(); const key: unknown = JSON.parse(text.slice(keyNode.start, keyNode.end));
          if (typeof key !== "string" || fields.has(key)) refuse("private_cli_input");
          white(); if (text[index++] !== ":") refuse("private_cli_input"); fields.set(key, value(depth + 1));
        } else items.push(value(depth + 1));
        white(); if (text[index] === end) break;
        if (text[index++] !== ",") refuse("private_cli_input"); white();
      }
      if (text[index++] !== end) refuse("private_cli_input");
      return object ? { kind: "object", start, end: index, fields } : { kind: "array", start, end: index, items };
    }
    for (const kind of ["true", "false", "null"] as const) if (text.startsWith(kind, index)) { index += kind.length; return { kind, start, end: index }; }
    const token = /^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/.exec(text.slice(index));
    if (!token || token[0].length > 256) refuse("private_cli_input"); index += token[0].length; return { kind: "number", start, end: index };
  };
  const node = value(1); white(); if (index !== text.length) refuse("private_cli_input"); return node;
}
function tree(wire: unknown, max = 65536): { text: string; root: Node } {
  if (typeof wire !== "string") refuse("private_cli_input"); return { text: wire, root: scan(wire, max) };
}
function fields(node: Node, keys: readonly string[]): ReadonlyMap<string, Node> {
  if (node.kind !== "object" || !node.fields || node.fields.size !== keys.length || !keys.every((key) => node.fields!.has(key))) refuse("private_cli_input"); return node.fields;
}
function stringValue(text: string, node: Node): string {
  if (node.kind !== "string") refuse("private_cli_input"); const value: unknown = JSON.parse(text.slice(node.start, node.end));
  if (typeof value !== "string") refuse("private_cli_input"); return value;
}
function sourceTree(text: string, node: Node): void {
  if (["string", "true", "false", "null"].includes(node.kind)) return;
  if (node.kind === "array") { for (const item of node.items!) sourceTree(text, item); return; }
  if (node.kind !== "object" || !node.fields) refuse("private_cli_input");
  const kindNode = node.fields.get("kind"); if (!kindNode) refuse("private_cli_input"); const kind = stringValue(text, kindNode);
  if (kind === "object") {
    const f = fields(node, ["kind", "entries"]), entries = f.get("entries")!; if (entries.kind !== "array") refuse("private_cli_input");
    const seen = new Set<string>(); for (const entry of entries.items!) {
      if (entry.kind !== "array" || entry.items!.length !== 2) refuse("private_cli_input");
      const key = stringValue(text, entry.items![0]!); if (seen.has(key)) refuse("private_cli_input"); seen.add(key); sourceTree(text, entry.items![1]!);
    }
  } else if (kind === "signed_integer" || kind === "unsigned_integer") {
    const f = fields(node, ["kind", "decimal"]), decimal = stringValue(text, f.get("decimal")!);
    if (!/^(0|-?[1-9][0-9]*)$/.test(decimal) || decimal.length > 40) refuse("private_cli_input");
    const n = BigInt(decimal); if (kind === "unsigned_integer" ? n < 0n || n > (1n << 128n) - 1n : n < -(1n << 127n) || n > (1n << 127n) - 1n) refuse("private_cli_input");
  } else if (kind === "binary64") {
    const f = fields(node, ["kind", "bits"]), bits = stringValue(text, f.get("bits")!);
    if (!/^[0-9a-f]{16}$/.test(bits) || ((BigInt("0x" + bits) >> 52n) & 2047n) === 2047n) refuse("private_cli_input");
  } else refuse("private_cli_input");
}
function valueWire(wire: unknown): string { const t = tree(wire); sourceTree(t.text, t.root); return t.text; }
const kinds: readonly string[] = ["structured_success", "local_discovery", "parse_failure", "operational_failure", "raw_artifact", "plain_text"];
const policies: readonly string[] = ["none", "unknown_argument", "argument_conflict", "runtime_unavailable", "wake_window_expired", "output_write_failed"];
const families: readonly string[] = ["raw_json_stdout", "jsonl_stdout_and_receipt_stderr", "artifact_destination", "jsonl_destination_and_receipt"];
type Descriptor = Omit<OutcomeMetadata, "value">;
function descriptor(wire: unknown): Descriptor {
  const t = tree(wire), f = fields(t.root, ["kind", "command", "artifactFamily", "fixedPolicy"]);
  const kind = stringValue(t.text, f.get("kind")!), command = stringValue(t.text, f.get("command")!), policy = stringValue(t.text, f.get("fixedPolicy")!), family = f.get("artifactFamily")!.kind === "null" ? null : stringValue(t.text, f.get("artifactFamily")!);
  if (!kinds.includes(kind) || !["status", "query", "direct"].includes(command) || !policies.includes(policy) || family !== null && !families.includes(family) || (kind === "raw_artifact") !== (family !== null)) refuse("private_cli_input");
  // Explicit closed metadata validation above, no public source classification inference.
  return Object.freeze({ kind: kind as OutcomeKind, command: command as Descriptor["command"], artifactFamily: family as ArtifactFamily | null, fixedPolicy: policy as Descriptor["fixedPolicy"] });
}
function handoff(wire: unknown): string {
  const t = tree(wire), f = fields(t.root, ["descriptor", "value_wire"]);
  descriptor(t.text.slice(f.get("descriptor")!.start, f.get("descriptor")!.end)); valueWire(stringValue(t.text, f.get("value_wire")!)); return t.text;
}
function modeWire(wire: unknown): ModeMetadata {
  const t = tree(wire, 1024), f = fields(t.root, ["force_json", "force_human", "tty"]);
  const flag = (key: string) => { const n = f.get(key)!; if (n.kind !== "true" && n.kind !== "false") refuse("private_cli_input"); return n.kind === "true"; };
  const json = flag("force_json"), human = flag("force_human"), tty = flag("tty");
  return Object.freeze({ mode: json || (!human && !tty) ? "json" : "human", conflictingFlags: json && human, plainHuman: true, columns: 100 });
}
interface OutcomeData { readonly metadata: OutcomeMetadata; readonly wire: string }
interface DecisionData { readonly metadata: DecisionMetadata; readonly outcome: OwnedCommonOutcome; readonly text: string }
/** Private constructor; no import executes a command or inspects host/native state. */
export const CliEnvelopeFactory: CliEnvelopeFactory = Object.freeze({
  create: (trusted: TrustedServices) => Effect.gen(function* () {
    let live = true, poisoned = false, busy = false;
    const closed = yield* Deferred.make<void>();
    yield* Effect.addFinalizer(() => Effect.gen(function* () { live = false; yield* Deferred.succeed(closed, undefined); }));
    const lifetime: CapturedOutputLifetime = Object.freeze({ isLive: () => live && !poisoned, closed: Deferred.await(closed) });
    const receive = trusted.common.receive.bind(trusted.common), current = trusted.current.check.bind(trusted.current);
    const renderer = trusted.renderer.render.bind(trusted.renderer), validator = trusted.raw.validate.bind(trusted.raw);
    const bracket = trusted.writer.withLease.bind(trusted.writer), publish = trusted.writer.publish.bind(trusted.writer);
    const rawFamilies = Object.freeze([...trusted.capabilities.rawFamilies]), plainText = trusted.capabilities.plainText;
    const outcomes = new WeakMap<object, OutcomeData>(), values = new WeakMap<object, { wire: string; context: object }>();
    const modes = new WeakMap<object, ModeMetadata>(), bytesMap = new WeakMap<object, { text: string; outcome: OwnedCommonOutcome; context: object }>();
    const validated = new WeakMap<object, { text: string; outcome: OwnedCommonOutcome; context: object }>();
    const decisions = new WeakMap<object, DecisionData>(), completions = new WeakMap<object, { decision: OwnedDecision }>();
    const alive = () => { if (poisoned) refuse("private_cli_cleanup"); if (!live) refuse("owned_handoff_closed"); };
    const ownOutcome = (o: unknown): OutcomeData => { if (!isObject(o) || !outcomes.has(o)) refuse("private_cli_owned"); return outcomes.get(o)!; };
    const ownDecision = (o: unknown): DecisionData => { if (!isObject(o) || !decisions.has(o)) refuse("private_cli_owned"); return decisions.get(o)!; };
    const inert: InertOutcomeView = Object.freeze({ inspect: (o: unknown) => isObject(o) && live && !poisoned ? outcomes.get(o)?.metadata ?? null : null });
    const check = (outcome: OwnedCommonOutcome, phase: AuthorityPhase) => Effect.gen(function* () {
      yield* attempt(() => { alive(); ownOutcome(outcome); }, "private_cli_owned");
      yield* sanitize(Effect.suspend(() => current(outcome, phase, inert)), "private_cli_authority"); yield* attempt(alive, "owned_handoff_closed");
    });
    const viewFor = (outcome: OwnedCommonOutcome, context: object, active: () => boolean): AuthorizedOutcomeView => Object.freeze({
      inspect: inert.inspect,
      mode: (m: unknown) => isObject(m) && live && !poisoned ? modes.get(m) ?? null : null,
      sourceValueWire: (o: unknown, v: unknown) => Effect.gen(function* () {
        if (!isObject(o) || !isObject(v) || !outcomes.has(o) || o !== outcome || values.get(v)?.context !== context || outcomes.get(o)?.metadata.value !== v || !active()) return null;
        yield* attempt(alive, "owned_handoff_closed"); yield* check(outcome, "before_materialization");
        yield* attempt(() => { alive(); if (!active() || !outcomes.has(o) || values.get(v)?.context !== context || outcomes.get(o)?.metadata.value !== v) refuse("owned_handoff_closed"); }, "owned_handoff_closed");
        return values.get(v)!.wire;
      })
    });
    const envelope: CliEnvelope = Object.freeze({
      selectMode: (wire: unknown) => attempt(() => { alive(); const data = modeWire(wire); const token = Object.freeze({ [modeBrand]: true as const }); modes.set(token, data); return token; }, "private_cli_input"),
      receive: (wire: unknown) => Effect.gen(function* () {
        const bounded = yield* attempt(() => { alive(); return handoff(wire); }, "private_cli_input");
        const context = Object.freeze({}); let active = true;
        const issuer: CommonOutcomeIssuer = Object.freeze({
          value: (input: unknown) => { if (!active || !live || poisoned) return null; try { const w = valueWire(input), token = Object.freeze({ [valueBrand]: true as const }); values.set(token, { wire: w, context }); return token; } catch { return null; } },
          outcome: (input: unknown, v: unknown) => { if (!active || !live || poisoned || !isObject(v) || values.get(v)?.context !== context) return null; try {
            const metadata = Object.freeze({ ...descriptor(input), value: v as OwnedValue }); const token = Object.freeze({ [outcomeBrand]: true as const }); outcomes.set(token, { metadata, wire: values.get(v)!.wire }); return token;
          } catch { return null; } }
        });
        const token = yield* sanitize(Effect.suspend(() => receive(bounded, issuer)).pipe(Effect.ensuring(Effect.sync(() => { active = false; }))), "private_cli_codec");
        yield* attempt(() => { alive(); const d = ownOutcome(token); if (!isObject(d.metadata.value) || values.get(d.metadata.value)?.context !== context) refuse("private_cli_codec"); }, "private_cli_codec");
        yield* check(token, "after_common"); return token;
      }),
      render: (o: unknown, m: unknown) => Effect.gen(function* () {
        const pair = yield* attempt(() => { alive(); const data = ownOutcome(o); if (!isObject(m) || !modes.has(m)) refuse("private_cli_owned"); return { data, mode: modes.get(m)!, outcome: o as OwnedCommonOutcome, ownedMode: m as OwnedMode }; }, "private_cli_owned");
        const { data, mode, outcome } = pair;
        yield* attempt(() => {
          if (data.metadata.kind === "raw_artifact" && !rawFamilies.includes(data.metadata.artifactFamily!)) refuse("private_cli_capability");
          if (data.metadata.kind === "plain_text" && !plainText) refuse("private_cli_capability");
          if (mode.conflictingFlags && !(data.metadata.kind === "parse_failure" && data.metadata.fixedPolicy === "argument_conflict")) refuse("private_cli_input");
        }, "private_cli_capability");
        const context = values.get(data.metadata.value!)!.context; let active = true; const view = viewFor(outcome, context, () => active);
        let text: string;
        if (data.metadata.kind === "raw_artifact") {
          yield* check(outcome, "before_raw_validation");
          const rawIssuer: RawIssuer = Object.freeze({ validated: (input: unknown, v: unknown, request: unknown) => {
            if (!active || !live || poisoned || request !== outcome || !isObject(v) || values.get(v)?.context !== context || v !== data.metadata.value || typeof input !== "string") return null;
            try { utf8(input, 65536); const token = Object.freeze({ [validatedBrand]: true as const }); validated.set(token, { text: input, outcome, context }); return token; } catch { return null; }
          } });
          const token = yield* sanitize(Effect.suspend(() => validator(outcome, rawIssuer, view)).pipe(Effect.ensuring(Effect.sync(() => { active = false; }))), "private_cli_codec");
          text = yield* attempt(() => { alive(); if (!isObject(token) || validated.get(token)?.context !== context || validated.get(token)?.outcome !== outcome) refuse("private_cli_codec"); return validated.get(token)!.text; }, "private_cli_codec");
          yield* check(outcome, "after_raw_validation");
        } else {
          yield* check(outcome, "before_render");
          const issuer: ByteIssuer = Object.freeze({ encodedUTF8: (input: unknown, request: unknown) => {
            if (!active || !live || poisoned || request !== outcome || typeof input !== "string") return null;
            try { utf8(input, 65536); const token = Object.freeze({ [bytesBrand]: true as const }); bytesMap.set(token, { text: input, outcome, context }); return token; } catch { return null; }
          } });
          const token = yield* sanitize(Effect.suspend(() => renderer(outcome, pair.ownedMode, issuer, view)).pipe(Effect.ensuring(Effect.sync(() => { active = false; }))), "private_cli_codec");
          text = yield* attempt(() => { alive(); if (!isObject(token) || bytesMap.get(token)?.outcome !== outcome || bytesMap.get(token)?.context !== context) refuse("private_cli_codec"); return bytesMap.get(token)!.text; }, "private_cli_codec");
          yield* check(outcome, "after_render");
        }
        yield* check(outcome, "before_decision");
        return yield* attempt(() => {
          alive(); const kind = data.metadata.kind, raw = kind === "raw_artifact", plain = kind === "plain_text";
          const metadata: DecisionMetadata = Object.freeze({ mode: raw ? "raw" : plain ? "text" : mode.mode, exit: kind === "parse_failure" ? 2 : kind === "operational_failure" ? 1 : 0, outputKind: raw ? "raw_artifact" : plain ? "plain_text" : "structured", artifactFamily: data.metadata.artifactFamily, stderr: "empty", publication: "not_started" });
          const token = Object.freeze({ [decisionBrand]: true as const }); decisions.set(token, { metadata, outcome, text }); return token;
        }, "private_cli_owned");
      }),
      inspect: (d: unknown) => isObject(d) && live && !poisoned ? decisions.get(d)?.metadata ?? null : null,
      publish: (d: unknown) => Effect.gen(function* () {
        const data = yield* attempt(() => { alive(); const data = ownDecision(d); if (busy) refuse("private_cli_busy"); busy = true; return data; }, "private_cli_owned");
        const decision = d as OwnedDecision;
        const work = Effect.gen(function* () {
          yield* check(data.outcome, "before_allocation");
          let invocationLive = true, used = false;
          const use = (lease: OwnedOutputLease) => Effect.suspend(() => {
            if (!invocationLive || used) return Effect.fail(fixedFailure("owned_handoff_closed")); used = true;
            return Effect.gen(function* () {
              yield* attempt(alive, "owned_handoff_closed"); yield* check(data.outcome, "after_allocation");
              let sinkLive = true; const byte = Object.freeze({ [bytesBrand]: true as const }); const context = Object.freeze({}); bytesMap.set(byte, { text: data.text, outcome: data.outcome, context });
              const inertDecision: InertDecisionView = Object.freeze({ inspect: envelope.inspect });
              const view: AuthorizedBytesView = Object.freeze({ ...inertDecision, utf8: (request: unknown, payload: unknown) => Effect.gen(function* () {
                if (!isObject(request) || request !== decision || !decisions.has(request) || !isObject(payload) || payload !== byte || bytesMap.get(payload)?.context !== context || !sinkLive) return null;
                yield* attempt(alive, "owned_handoff_closed"); yield* check(data.outcome, "before_publication");
                yield* attempt(() => { alive(); if (!sinkLive || !invocationLive || bytesMap.get(payload)?.context !== context) refuse("owned_handoff_closed"); }, "owned_handoff_closed"); return data.text;
              }) });
              yield* sanitize(Effect.suspend(() => publish(decision, byte, lease, view)).pipe(Effect.ensuring(Effect.sync(() => { sinkLive = false; }))), "private_cli_publish");
              yield* check(data.outcome, "after_publication");
            });
          });
          const inertDecision: InertDecisionView = Object.freeze({ inspect: envelope.inspect });
          yield* sanitize(Effect.suspend(() => bracket(decision, inertDecision, lifetime, use)).pipe(Effect.ensuring(Effect.sync(() => { invocationLive = false; }))), "private_cli_cleanup").pipe(Effect.catch((error) => {
            if (error.code === "private_cli_cleanup") poisoned = true; return Effect.fail(error);
          }));
          yield* attempt(alive, "owned_handoff_closed"); yield* check(data.outcome, "assert_current");
          return yield* attempt(() => { alive(); const token = Object.freeze({ [completionBrand]: true as const }); completions.set(token, { decision }); return token; }, "private_cli_owned");
        });
        return yield* work.pipe(Effect.ensuring(Effect.sync(() => { busy = false; })));
      }),
      exit: (completion: unknown) => attempt(() => { alive(); if (!isObject(completion) || !completions.has(completion)) refuse("private_cli_owned"); return ownDecision(completions.get(completion)!.decision).metadata.exit; }, "private_cli_owned"),
      assertCurrent: (decision: unknown) => Effect.gen(function* () { const data = yield* attempt(() => { alive(); return ownDecision(decision); }, "private_cli_owned"); yield* check(data.outcome, "assert_current"); })
    });
    return envelope;
  })
});
