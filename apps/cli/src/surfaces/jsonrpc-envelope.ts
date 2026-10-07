/** Private owned orchestration. Injected semantic ports are not a public MCP codec. */
import * as Effect from "effect/Effect";
import * as Exit from "effect/Exit";
import type * as Scope from "effect/Scope";
declare const frameBrand: unique symbol;
declare const parsedBrand: unique symbol;
declare const parseErrorBrand: unique symbol;
declare const sessionBrand: unique symbol;
declare const outputBrand: unique symbol;
declare const leaseBrand: unique symbol;
declare const valueBrand: unique symbol;
declare const spanBrand: unique symbol;
declare const replyBrand: unique symbol;
export interface OwnedFrame { readonly [frameBrand]: true }
export interface OwnedParsed { readonly [parsedBrand]: true }
export interface OwnedSourceParseError { readonly [parseErrorBrand]: true }
export type OwnedInspectionOutcome = OwnedParsed | OwnedSourceParseError;
export interface OwnedSession { readonly [sessionBrand]: true }
export interface OwnedOutput { readonly [outputBrand]: true }
export interface OwnedLease { readonly [leaseBrand]: true }
export interface OwnedJson { readonly [valueBrand]: true }
export interface OwnedSpan { readonly [spanBrand]: true }
export interface OwnedReply { readonly [replyBrand]: true }
export type FixedFailure = { readonly code: "private_rpc_input" | "private_rpc_codec" | "private_rpc_dispatch" | "private_rpc_authority" | "private_rpc_busy" | "private_rpc_owned" | "private_rpc_cleanup" | "owned_handoff_closed" };
export type SourceNumber = { readonly kind: "signed_integer" | "unsigned_integer"; readonly decimal: string } | { readonly kind: "binary64"; readonly bits: string };
export type SourceValue = null | boolean | string | SourceNumber | readonly SourceValue[] | { readonly kind: "object"; readonly entries: readonly (readonly [string, SourceValue])[] };
export type SourceId = { readonly present: false } | { readonly present: true; readonly scalar: "string" | "signed_integer" | "unsigned_integer" | "binary64" | "invalid"; readonly canonicalEncoded: string; readonly validI64OrString: boolean };
export interface InspectionMetadata { readonly rootObject: boolean; readonly version2: boolean; readonly id: SourceId; readonly method: string | null; readonly params: OwnedSpan | null; readonly paramsDefaulted: boolean; readonly progressToken: OwnedSpan | null }
export interface CodecIssuer {
  inspection(primitiveMetadataWire: unknown, frame: OwnedFrame): OwnedParsed | null;
  /** Fixed source Parse error/null ID; no arbitrary code/cause/payload from parser. */
  sourceParseError(frame: OwnedFrame): OwnedSourceParseError | null;
  json(primitiveSourceValueWire: unknown): OwnedJson | null;
  encoded(primitiveUTF8Text: unknown, request: OwnedInspectionOutcome): OwnedOutput | null;
}
export interface LexicalView { frameText(frame: unknown): string | null }
export interface InertRequestView { inspect(request: unknown): InspectionMetadata | null }
export interface AuthorizedRequestView extends InertRequestView {
  /** Only granted current request spans; membership, Scope and permit checked on EACH read. */
  spanText(request: unknown, span: unknown): Effect.Effect<string | null, FixedFailure>;
}
export type ReplyView = { readonly kind: "success"; readonly idCanonicalEncoded: string; readonly result: OwnedJson } | { readonly kind: "error"; readonly idCanonicalEncoded: string; readonly code: number; readonly fixedMessage: string } | { readonly kind: "progress"; readonly notification: OwnedJson };
export interface OwnedValueView { readJson(value: unknown): SourceValue | null; inspectReply(reply: unknown): ReplyView | null }
export interface ExactScalarPort { render(representation: unknown, primitivePayload: unknown): unknown }
/** Pure trusted scalar renderer port: existing exact-number source is authoritative; no import
 * bypass, numeric algorithm duplication or current package export asserted. Separately admitted
 * real codec adapter wires this port; this child's fake serializer has fixed independent literals. */
export interface OwnedOutputView { encodedText(output: unknown): Effect.Effect<string | null, FixedFailure> }
export interface LosslessCodec {
  inspect(frame: OwnedFrame, issuer: CodecIssuer, view: LexicalView): unknown;
  serialize(request: OwnedInspectionOutcome, reply: OwnedReply, issuer: CodecIssuer, view: OwnedValueView): unknown;
}
export type AuthorityPhase = "before_materialization" | "before_allocation" | "before_progress" | "before_publication" | "assert_current";
export interface CurrentAuthority { check(request: OwnedParsed, phase: AuthorityPhase, view: InertRequestView): Effect.Effect<void, FixedFailure> }
export interface OperationIssuer {
  /** json ALWAYS issues a success-tagged value, including objects containing error/code/message. */
  json(primitiveSourceValueWire: unknown): OwnedJson | null;
  /** error issues a distinct private WeakMap tag with admitted fixed code/message; no JSON shape
   * examination may turn a success-tagged value into an error or authenticate arbitrary caller data. */
  error(code: unknown, fixedMessage: unknown): OwnedJson | null;
}
export interface FixedDispatcher {
  acquire(request: OwnedParsed, view: InertRequestView): Effect.Effect<unknown, FixedFailure>;
  release(allocationHandle: unknown): Effect.Effect<void, FixedFailure>;
  dispatch(request: OwnedParsed, lease: OwnedLease, emit: (progress: OwnedJson) => Effect.Effect<void, FixedFailure>, view: AuthorizedRequestView, issuer: OperationIssuer): Effect.Effect<OwnedJson, FixedFailure>;
}
export interface LocalMetadataPort {
  /** initialize/list tools/list resources/read resource use fixed common source metadata,
   * no acquired lease. Real schema/HTML/tool catalog adapters remain next owner. */
  describe(request: OwnedParsed, view: AuthorizedRequestView, issuer: OperationIssuer): Effect.Effect<OwnedJson, FixedFailure>;
}
export interface OwnedProgressSink { publish(output: OwnedOutput, view: OwnedOutputView): Effect.Effect<void, FixedFailure> }
export interface RpcEnvelope {
  open(): Effect.Effect<OwnedSession, FixedFailure, Scope.Scope>;
  handle(session: unknown, frame: unknown): Effect.Effect<OwnedOutput | null, FixedFailure>;
  encode(session: unknown, output: unknown): Effect.Effect<string, FixedFailure>;
  assertCurrent(session: unknown, output: unknown): Effect.Effect<void, FixedFailure>;
}
export interface TrustedFactoryInputs { readonly codec: LosslessCodec; readonly authority: CurrentAuthority; readonly dispatcher: FixedDispatcher; readonly metadata: LocalMetadataPort; readonly progress: OwnedProgressSink }
export interface RpcFactory { create(inputs: TrustedFactoryInputs): Effect.Effect<RpcEnvelope, FixedFailure, Scope.Scope> }
/** Trusted ports, never caller JSON, hold source semantics. Each issuer accepts only a bounded
 * primitive private wire; it does not reflect arbitrary objects and is invalidated when its
 * callback returns. Inspection issues frame-bound opaque spans without decoding params.
 * inspect returns only an OWN callback-issued OwnedInspectionOutcome: parsed or fixed source
 * parse error. The parse-error token is bound to this exact OwnedFrame/factory/original Scope;
 * serializer receives the same owned context with factory-issued ReplyView error/null ID.
 * Foreign, malformed or expired callback outcomes fail private_rpc_codec, never source parse
 * error. Closure after any callback wins before publication; no allocation/metadata/dispatch
 * follows owned source parse failure. Full serde parsing/numeric conversion/rendering remains
 * a separately admitted adapter.
 * Factory/session/request/output/issuer membership precedes properties, including every view.
 * Completed acquire handles are opaque and atomically registered with captured release; Scope
 * sentinel precedes first trusted callback. Current checks and liveness follow every callback,
 * pending allocation completion, prepublication and assertion. All views capture original Scope;
 * a new Scope/provided Layer cannot revive them. Dispatcher owns common semantics, no case-ID
 * response table or second evaluator. No trusted parser metadata authenticates caller grants.
 */

type Code = FixedFailure["code"];
const failures = new WeakMap<object, Code>();
function failure(code: Code): FixedFailure { const value = Object.freeze({ code }); failures.set(value, code); return value; }
function refuse(code: Code): never { throw failure(code); }
function ownCode(value: unknown, fallback: Code): Code {
  return value !== null && typeof value === "object" ? failures.get(value) ?? fallback : fallback;
}
function attempt<A>(body: () => A, fallback: Code): Effect.Effect<A, FixedFailure> {
  return Effect.try({ try: body, catch: (value) => failure(ownCode(value, fallback)) });
}
function sanitize<A, E, R>(effect: Effect.Effect<A, E, R>, fallback: Code): Effect.Effect<A, FixedFailure, R> {
  return Effect.uninterruptibleMask((restore) => restore(effect).pipe(Effect.catchCause((cause) => {
    if (cause.reasons.some((reason) => reason._tag === "Interrupt")) return Effect.interrupt;
    const failed = cause.reasons.find((reason) => reason._tag === "Fail");
    return Effect.fail(failure(failed && failed._tag === "Fail" ? ownCode(failed.error, fallback) : fallback));
  })));
}
const syntax = Object.freeze({});
function badJSON(): never { throw syntax; }
/** Count scalar UTF8 without replacement or coercion. Limits are private and unmeasured. */
function bytes(text: string, maximum: number): number {
  if (text.length > maximum) refuse("private_rpc_input");
  let count = 0;
  for (let i = 0; i < text.length; i++) {
    const c = text.charCodeAt(i);
    if (c >= 0xd800 && c <= 0xdbff) {
      const low = text.charCodeAt(++i);
      if (!(low >= 0xdc00 && low <= 0xdfff)) refuse("private_rpc_input");
      count += 4;
    } else if (c >= 0xdc00 && c <= 0xdfff) refuse("private_rpc_input");
    else count += c < 128 ? 1 : c < 2048 ? 2 : 3;
    if (count > maximum) refuse("private_rpc_input");
  }
  return count;
}
interface Node { readonly kind: "object" | "array" | "string" | "number" | "true" | "false" | "null"; readonly start: number; readonly end: number; readonly fields?: ReadonlyMap<string, Node>; readonly items?: readonly Node[] }
/** Linear structural grammar, raw number tokens retained, string values left unmaterialized.
 * Only member names are decoded to apply last-decoded-key source semantics. This is NOT a
 * numerical serde parser. Strict private descriptors reject duplicates instead of overwriting. */
function scan(text: string, strict: boolean, limit = 65536): Node {
  bytes(text, limit);
  let index = 0, nodes = 0;
  const white = () => { while (index < text.length && /[ \t\r\n]/.test(text[index]!)) index++; };
  const string = (): Node => {
    const start = index++;
    let decodedBytes = 0;
    while (index < text.length) {
      const c = text.charCodeAt(index++);
      if (c === 34) return Object.freeze({ kind: "string", start, end: index });
      if (c < 32) badJSON();
      let scalar = c;
      if (c === 92) {
        const escape = text[index++];
        if (escape === "u") {
          const raw = text.slice(index, index + 4);
          if (!/^[0-9a-fA-F]{4}$/.test(raw)) badJSON();
          scalar = parseInt(raw, 16); index += 4;
          if (scalar >= 0xd800 && scalar <= 0xdbff) {
            if (text.slice(index, index + 2) !== "\\u") badJSON();
            const lowRaw = text.slice(index + 2, index + 6);
            if (!/^[0-9a-fA-F]{4}$/.test(lowRaw)) badJSON();
            const low = parseInt(lowRaw, 16);
            if (!(low >= 0xdc00 && low <= 0xdfff)) badJSON();
            index += 6; scalar = 0x10000;
          } else if (scalar >= 0xdc00 && scalar <= 0xdfff) badJSON();
        } else if (!['"', "\\", "/", "b", "f", "n", "r", "t"].includes(escape ?? "")) badJSON();
        else scalar = 32;
      } else if (scalar >= 0xd800 && scalar <= 0xdbff) { index++; scalar = 0x10000; }
      decodedBytes += scalar < 128 ? 1 : scalar < 2048 ? 2 : scalar < 65536 ? 3 : 4;
      if (decodedBytes > 32768) refuse("private_rpc_input");
    }
    return badJSON();
  };
  const value = (depth: number): Node => {
    if (depth > 32 || ++nodes > 4096) refuse("private_rpc_input");
    white(); const start = index, first = text[index];
    if (first === '"') return string();
    if (first === "{" || first === "[") {
      const object = first === "{", end = object ? "}" : "]"; index++; white();
      const fields = new Map<string, Node>(), items: Node[] = [];
      if (text[index] !== end) while (true) {
        if (object) {
          if (text[index] !== '"') badJSON();
          const keyNode = string();
          // Key-only bounded scalar decode; params string VALUES remain raw spans.
          const key: unknown = JSON.parse(text.slice(keyNode.start, keyNode.end));
          if (typeof key !== "string") badJSON();
          if (strict && fields.has(key)) badJSON();
          white(); if (text[index++] !== ":") badJSON();
          fields.set(key, value(depth + 1));
        } else items.push(value(depth + 1));
        white(); if (text[index] === end) break;
        if (text[index++] !== ",") badJSON(); white();
      }
      if (text[index++] !== end) badJSON();
      return Object.freeze(object ? { kind: "object", start, end: index, fields } : { kind: "array", start, end: index, items: Object.freeze(items) });
    }
    for (const kind of ["true", "false", "null"] as const) {
      if (text.startsWith(kind, index)) { index += kind.length; return Object.freeze({ kind, start, end: index }); }
    }
    const raw = /^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/.exec(text.slice(index));
    if (!raw) return badJSON();
    if (raw[0].length > 256) refuse("private_rpc_input");
    index += raw[0].length;
    return Object.freeze({ kind: "number", start, end: index });
  };
  const root = value(1); white(); if (index !== text.length) badJSON(); return root;
}
function privateTree(wire: unknown): { text: string; root: Node } {
  if (typeof wire !== "string") refuse("private_rpc_codec");
  try { return { text: wire, root: scan(wire, true) }; }
  catch { return refuse("private_rpc_codec"); }
}
function fields(node: Node, keys: readonly string[]): ReadonlyMap<string, Node> {
  if (node.kind !== "object" || !node.fields || node.fields.size !== keys.length || !keys.every((key) => node.fields!.has(key))) refuse("private_rpc_codec");
  return node.fields;
}
function stringValue(text: string, node: Node): string {
  if (node.kind !== "string") refuse("private_rpc_codec");
  const value: unknown = JSON.parse(text.slice(node.start, node.end));
  if (typeof value !== "string") refuse("private_rpc_codec");
  return value;
}
function booleanValue(node: Node): boolean {
  if (node.kind !== "true" && node.kind !== "false") refuse("private_rpc_codec");
  return node.kind === "true";
}
function integer(text: string, node: Node, maximum: number): number {
  const raw = text.slice(node.start, node.end);
  if (node.kind !== "number" || !/^(0|[1-9][0-9]*)$/.test(raw) || raw.length > 16 || BigInt(raw) > BigInt(maximum)) refuse("private_rpc_codec");
  return Number(raw); // Exact canonical bounded integer proved BEFORE conversion.
}
function sourceValue(text: string, node: Node): SourceValue {
  if (node.kind === "string") return stringValue(text, node);
  if (node.kind === "null") return null;
  if (node.kind === "true" || node.kind === "false") return booleanValue(node);
  if (node.kind === "array") return Object.freeze(node.items!.map((child) => sourceValue(text, child)));
  if (node.kind !== "object") refuse("private_rpc_codec");
  const kindNode = node.fields!.get("kind"); if (!kindNode) refuse("private_rpc_codec");
  const kind = stringValue(text, kindNode);
  if (kind === "object") {
    const row = fields(node, ["kind", "entries"]), entries = row.get("entries")!;
    if (entries.kind !== "array") refuse("private_rpc_codec");
    const seen = new Set<string>(), result: (readonly [string, SourceValue])[] = [];
    for (const pair of entries.items!) {
      if (pair.kind !== "array" || pair.items!.length !== 2) refuse("private_rpc_codec");
      const key = stringValue(text, pair.items![0]!); if (seen.has(key)) refuse("private_rpc_codec"); seen.add(key);
      result.push(Object.freeze([key, sourceValue(text, pair.items![1]!)] as const));
    }
    return Object.freeze({ kind: "object", entries: Object.freeze(result) });
  }
  if (kind === "signed_integer" || kind === "unsigned_integer") {
    const row = fields(node, ["kind", "decimal"]), decimal = stringValue(text, row.get("decimal")!);
    if (!/^(0|-?[1-9][0-9]*)$/.test(decimal) || decimal.length > 20) refuse("private_rpc_codec");
    const number = BigInt(decimal);
    if (kind === "signed_integer" ? number < -(1n << 63n) || number > (1n << 63n) - 1n : number < 0n || number > (1n << 64n) - 1n) refuse("private_rpc_codec");
    return Object.freeze({ kind, decimal });
  }
  if (kind === "binary64") {
    const row = fields(node, ["kind", "bits"]), bits = stringValue(text, row.get("bits")!);
    if (!/^[0-9a-f]{16}$/.test(bits) || ((BigInt("0x" + bits) >> 52n) & 0x7ffn) === 0x7ffn) refuse("private_rpc_codec");
    return Object.freeze({ kind, bits });
  }
  return refuse("private_rpc_codec");
}
const objectToken = (): object => Object.freeze({});
const member = (input: unknown): input is object => input !== null && typeof input === "object";
const sourceErrors = new Map<number, ReadonlySet<string>>([
  [-32700, new Set(["Parse error"])], [-32600, new Set(["Invalid request", "Duplicate request identifier"])],
  [-32001, new Set(["Session request limit exceeded"])], [-32601, new Set(["Method not found", "Unknown resource URI"])],
  [-32602, new Set(["Unknown tool", "Invalid tool arguments", "Unsupported MCP protocol version"])],
  [-32003, new Set(["The caller lacks the required Health.md read scope."])],
]);
interface Life { live: boolean; poisoned: boolean; busy: boolean; uiEnabled: boolean; readonly used: Set<string> }
interface FrameData { readonly text: string; readonly root: Node | null; readonly session: Life; readonly call: object }
interface InspectionData { readonly frame: object; readonly session: Life; readonly call: object; readonly metadata: InspectionMetadata | null }
interface ValueData { readonly context: object; readonly session: Life; readonly tag: "success" | "error"; readonly value?: SourceValue; readonly code?: number; readonly fixedMessage?: string }
interface OutputData { readonly context: object; readonly session: Life; readonly text: string }
/** Trusted host setup is captured once, outside untrusted frames. No actual parser/serializer,
 * credential/source grant, network/native acquisition or data evaluator is implemented here. */
export function createRpcEnvelope(inputs: TrustedFactoryInputs): Effect.Effect<RpcEnvelope, FixedFailure, Scope.Scope> {
  return sanitize(Effect.gen(function* () {
    let factoryLive = true;
    yield* Effect.addFinalizer(() => Effect.sync(() => { factoryLive = false; }));
    const codec = inputs.codec, authority = inputs.authority, dispatcher = inputs.dispatcher, metadataPort = inputs.metadata, progressSink = inputs.progress;
    const inspectCallback = codec.inspect.bind(codec), serializeCallback = codec.serialize.bind(codec);
    const checkCallback = authority.check.bind(authority), allocateCallback = dispatcher.acquire.bind(dispatcher), releaseCallback = dispatcher.release.bind(dispatcher), dispatchCallback = dispatcher.dispatch.bind(dispatcher);
    const metadataCallback = metadataPort.describe.bind(metadataPort), publishCallback = progressSink.publish.bind(progressSink);
    const sessions = new WeakMap<object, Life>(), frames = new WeakMap<object, FrameData>(), inspections = new WeakMap<object, InspectionData>();
    const spans = new WeakMap<object, { readonly context: object; readonly node: Node }>(), values = new WeakMap<object, ValueData>(), replies = new WeakMap<object, { readonly context: object; readonly view: ReplyView }>(), outputs = new WeakMap<object, OutputData>();
    const requireLife = (life: Life) => { if (!factoryLive || !life.live) refuse("owned_handoff_closed"); if (life.poisoned) refuse("private_rpc_cleanup"); };
    const session = (input: unknown): Life => { const own = member(input) ? sessions.get(input) : undefined; if (!own) refuse("private_rpc_owned"); requireLife(own); return own; };
    const ownInspection = (context: unknown): InspectionData | undefined => member(context) ? inspections.get(context) : undefined;
    const inert: InertRequestView = Object.freeze({ inspect(request: unknown) {
      const data = ownInspection(request); if (!data || !factoryLive || !data.session.live || data.session.poisoned) return null;
      return data.metadata;
    } });
    const port = <A>(context: object, body: () => Effect.Effect<A, FixedFailure>, fallback: Code): Effect.Effect<A, FixedFailure> => Effect.gen(function* () {
      const data = inspections.get(context)!;
      const exit = yield* Effect.exit(sanitize(Effect.suspend(body), fallback));
      yield* attempt(() => requireLife(data.session), "owned_handoff_closed");
      if (Exit.isFailure(exit)) return yield* Effect.failCause(exit.cause);
      return exit.value;
    });
    const current = (context: object, phase: AuthorityPhase): Effect.Effect<void, FixedFailure> => Effect.gen(function* () {
      const data = inspections.get(context)!; yield* attempt(() => requireLife(data.session), "owned_handoff_closed");
      if (data.metadata !== null) yield* port(context, () => checkCallback(context as OwnedParsed, phase, inert), "private_rpc_authority");
      yield* attempt(() => requireLife(data.session), "owned_handoff_closed");
    });
    const authorizeView = (context: object, alive: () => boolean): AuthorizedRequestView => Object.freeze({ ...inert, spanText(request: unknown, span: unknown) {
      // Execution, not construction, checks membership and current authority. No cached permit.
      return sanitize(Effect.suspend(() => {
        if (request !== context || !member(span) || !alive()) return Effect.succeed(null);
        const data = inspections.get(context)!, own = spans.get(span);
        if (!own || own.context !== context) return Effect.succeed(null);
        return Effect.gen(function* () {
          yield* attempt(() => requireLife(data.session), "owned_handoff_closed");
          yield* current(context, "before_materialization");
          return yield* attempt(() => {
            requireLife(data.session); // Closure during the awaited check wins.
            if (!alive() || request !== context || spans.get(span) !== own || own.context !== context) return null;
            const frame = frames.get(data.frame)!;
            return frame.text.slice(own.node.start, own.node.end); // No intervening yield/callback.
          }, "private_rpc_authority");
        });
      }), "private_rpc_authority");
    } });
    function issueInspection(wire: unknown, frameToken: object, call: object): OwnedParsed {
      const fd = frames.get(frameToken)!; const parsed = privateTree(wire), row = fields(parsed.root, ["rootObject", "version2", "id", "method", "params", "paramsDefaulted", "progressToken"]);
      const text = parsed.text, rootObject = booleanValue(row.get("rootObject")!), version2 = booleanValue(row.get("version2")!);
      const methodNode = row.get("method")!, method = methodNode.kind === "null" ? null : stringValue(text, methodNode);
      if (!fd.root || rootObject !== (fd.root.kind === "object")) refuse("private_rpc_codec");
      const sourceFields = fd.root.fields, rawMethod = sourceFields?.get("method"), rawVersion = sourceFields?.get("jsonrpc");
      if (method !== (rawMethod?.kind === "string" ? stringValue(fd.text, rawMethod) : null) || version2 !== (rawVersion?.kind === "string" && stringValue(fd.text, rawVersion) === "2.0")) refuse("private_rpc_codec");
      const idNode = row.get("id")!, presentNode = idNode.fields?.get("present"); if (!presentNode) refuse("private_rpc_codec");
      const present = booleanValue(presentNode); let id: SourceId;
      if (!present) { fields(idNode, ["present"]); id = Object.freeze({ present: false }); }
      else {
        const ir = fields(idNode, ["present", "scalar", "canonicalEncoded", "validI64OrString"]), scalar = stringValue(text, ir.get("scalar")!), canonicalEncoded = stringValue(text, ir.get("canonicalEncoded")!);
        if (!["string", "signed_integer", "unsigned_integer", "binary64", "invalid"].includes(scalar)) refuse("private_rpc_codec");
        scan(canonicalEncoded, false); id = Object.freeze({ present: true, scalar: scalar as Extract<SourceId, { present: true }>["scalar"], canonicalEncoded, validI64OrString: booleanValue(ir.get("validI64OrString")!) });
      }
      if (present !== Boolean(sourceFields?.has("id"))) refuse("private_rpc_codec");
      const context = objectToken(), paramsDefaulted = booleanValue(row.get("paramsDefaulted")!);
      if (paramsDefaulted !== !sourceFields?.has("params")) refuse("private_rpc_codec");
      const span = (node: Node, sourceNode?: Node): OwnedSpan | null => {
        if (node.kind === "null") { if (sourceNode) refuse("private_rpc_codec"); return null; }
        const sr = fields(node, ["start", "end"]), start = integer(text, sr.get("start")!, fd.text.length), end = integer(text, sr.get("end")!, fd.text.length);
        if (start >= end || !sourceNode || start !== sourceNode.start || end !== sourceNode.end) refuse("private_rpc_codec");
        const token = objectToken(); spans.set(token, { context, node: sourceNode }); return token as OwnedSpan;
      };
      const params = span(row.get("params")!, sourceFields?.get("params"));
      const progressDescriptor = row.get("progressToken")!, rawProgress = sourceFields?.get("params")?.fields?.get("_meta")?.fields?.get("progressToken");
      const progressToken = progressDescriptor.kind === "null" ? null : span(progressDescriptor, rawProgress);
      const md: InspectionMetadata = Object.freeze({ rootObject, version2, id, method, params, paramsDefaulted, progressToken });
      inspections.set(context, { frame: frameToken, session: fd.session, call, metadata: md }); return context as OwnedParsed;
    }
    function operationIssuer(context: object, alive: () => boolean): OperationIssuer {
      const data = inspections.get(context)!;
      const ready = () => alive() && factoryLive && data.session.live && !data.session.poisoned;
      return Object.freeze({ json(wire: unknown) {
        if (!ready()) return null;
        try { const tree = privateTree(wire), value = sourceValue(tree.text, tree.root), token = objectToken(); values.set(token, { context, session: data.session, tag: "success", value }); return token as OwnedJson; } catch { return null; }
      }, error(code: unknown, fixedMessage: unknown) {
        if (!ready() || typeof code !== "number" || typeof fixedMessage !== "string" || !sourceErrors.get(code)?.has(fixedMessage)) return null;
        const token = objectToken(); values.set(token, { context, session: data.session, tag: "error", code, fixedMessage }); return token as OwnedJson;
      } });
    }
    const valueView = (context: object, alive: () => boolean): OwnedValueView => Object.freeze({ readJson(input: unknown) {
      const data = member(input) ? values.get(input) : undefined;
      return data && data.context === context && alive() && data.tag === "success" && factoryLive && data.session.live && !data.session.poisoned ? data.value ?? null : null;
    }, inspectReply(input: unknown) {
      const own = member(input) ? replies.get(input) : undefined, data = inspections.get(context);
      return own && own.context === context && alive() && data && factoryLive && data.session.live && !data.session.poisoned ? own.view : null;
    } });
    const reply = (view: ReplyView, context: object): OwnedReply => { const token = objectToken(); replies.set(token, { context, view: Object.freeze(view) }); return token as OwnedReply; };
    const localError = (idCanonicalEncoded: string, code: number, fixedMessage: string, context: object): OwnedReply => reply({ kind: "error", idCanonicalEncoded, code, fixedMessage }, context);
    function replyFor(context: object, token: unknown, id: string): OwnedReply {
      const value = member(token) ? values.get(token) : undefined;
      if (!value || value.context !== context) refuse("private_rpc_dispatch");
      return value.tag === "error" ? reply({ kind: "error", idCanonicalEncoded: id, code: value.code!, fixedMessage: value.fixedMessage! }, context) : reply({ kind: "success", idCanonicalEncoded: id, result: token as OwnedJson }, context);
    }
    const serialize = (context: object, body: OwnedReply): Effect.Effect<OwnedOutput, FixedFailure> => Effect.gen(function* () {
      const data = inspections.get(context)!; yield* current(context, "before_publication");
      let issuing = true; const issued = new WeakSet<object>();
      const issuer: CodecIssuer = Object.freeze({ inspection: () => null, sourceParseError: () => null, json: () => null, encoded(wire: unknown, request: OwnedInspectionOutcome) {
        if (!issuing || request !== context || !factoryLive || !data.session.live || data.session.poisoned || typeof wire !== "string") return null;
        try { scan(wire, false, 262144); const token = objectToken(); outputs.set(token, { context, session: data.session, text: wire }); issued.add(token); return token as OwnedOutput; } catch { return null; }
      } });
      let result: unknown;
      yield* attempt(() => { try { result = serializeCallback(context as OwnedInspectionOutcome, body, issuer, valueView(context, () => issuing)); } catch (error) { requireLife(data.session); throw error; } finally { issuing = false; } requireLife(data.session); }, "private_rpc_codec");
      yield* current(context, "before_publication");
      return yield* attempt(() => { if (!member(result) || !issued.has(result)) refuse("private_rpc_codec"); requireLife(data.session); return result as OwnedOutput; }, "private_rpc_codec");
    });
    const checkOutput = (sessionToken: unknown, outputToken: unknown): { readonly life: Life; readonly data: OutputData } => {
      // Membership BEFORE inspecting any unknown properties, even revoked Proxies.
      const life = session(sessionToken), data = member(outputToken) ? outputs.get(outputToken) : undefined;
      if (!data || data.session !== life) refuse("private_rpc_owned"); requireLife(life); return { life, data };
    };
    const envelope: RpcEnvelope = Object.freeze({ open: () => sanitize(Effect.gen(function* () {
      const life: Life = { live: true, poisoned: false, busy: false, uiEnabled: false, used: new Set() }, token = objectToken();
      yield* Effect.addFinalizer(() => Effect.sync(() => { life.live = false; }));
      yield* attempt(() => requireLife(life), "owned_handoff_closed"); sessions.set(token, life); return token as OwnedSession;
    }), "private_rpc_owned"),
    handle: (sessionToken: unknown, input: unknown) => sanitize(Effect.gen(function* () {
      const life = yield* attempt(() => session(sessionToken), "private_rpc_owned");
      yield* attempt(() => { if (typeof input !== "string") refuse("private_rpc_input"); bytes(input, 65536); if (life.busy) refuse("private_rpc_busy"); life.busy = true; }, "private_rpc_input");
      const work = Effect.gen(function* () {
        let root: Node | null = null;
        yield* attempt(() => { try { root = scan(input as string, false); } catch (error) { if (error !== syntax) throw error; } }, "private_rpc_input");
        const call = objectToken(), frame = objectToken(); frames.set(frame, { text: input as string, root, session: life, call });
        let returned: unknown; const issued = new WeakSet<object>(); let issuing = true;
        const issuer: CodecIssuer = Object.freeze({ inspection(wire: unknown, requested: OwnedFrame) {
          if (!issuing || requested !== frame || !factoryLive || !life.live || life.poisoned) return null;
          try { const token = issueInspection(wire, frame, call); issued.add(token); return token; } catch { return null; }
        }, sourceParseError(requested: OwnedFrame) {
          if (!issuing || requested !== frame || !factoryLive || !life.live || life.poisoned) return null;
          const token = objectToken(); inspections.set(token, { frame, session: life, call, metadata: null }); issued.add(token); return token as OwnedSourceParseError;
        }, json: () => null, encoded: () => null });
        yield* attempt(() => {
          try { returned = root === null ? issuer.sourceParseError(frame as OwnedFrame) : inspectCallback(frame as OwnedFrame, issuer, Object.freeze({ frameText(value: unknown) { return value === frame && issuing && factoryLive && life.live ? input as string : null; } })); }
          catch (error) { requireLife(life); throw error; } finally { issuing = false; }
          requireLife(life); if (!member(returned) || !issued.has(returned)) refuse("private_rpc_codec");
        }, "private_rpc_codec");
        const context = returned as object, data = inspections.get(context)!;
        if (data.metadata === null) return yield* serialize(context, localError("null", -32700, "Parse error", context));
        const md = data.metadata;
        const error = (id: string, code = -32600, message = "Invalid request") => serialize(context, localError(id, code, message, context));
        if (!md.rootObject || !md.version2) return yield* error("null");
        if (md.method === null) return yield* error(md.id.present ? md.id.canonicalEncoded : "null");
        if (!md.id.present) return null;
        const id = md.id.canonicalEncoded;
        let valid = md.id.validI64OrString;
        if (valid && md.id.scalar === "string") {
          const idTree = scan(id, false); valid = idTree.kind === "string" && bytes(stringValue(id, idTree), 65536) <= 128;
        } else if (valid && (md.id.scalar === "signed_integer" || md.id.scalar === "unsigned_integer")) {
          valid = /^(0|-?[1-9][0-9]*)$/.test(id) && id.length <= 20 && BigInt(id) >= -(1n << 63n) && BigInt(id) <= (1n << 63n) - 1n;
        } else valid = false;
        if (!valid || bytes(id, 65536) > 128) return yield* error(id);
        if (life.used.has(id)) return yield* error(id, -32600, "Duplicate request identifier");
        if (life.used.size >= 16384) return yield* error(id, -32001, "Session request limit exceeded");
        life.used.add(id);
        if (md.method === "ping") {
          const token = objectToken(); values.set(token, { context, session: life, tag: "success", value: Object.freeze({ kind: "object", entries: Object.freeze([]) }) });
          return yield* serialize(context, replyFor(context, token, id));
        }
        if ((md.method === "resources/list" || md.method === "resources/read") && !life.uiEnabled) return yield* error(id, -32601, "Method not found");
        const metadataMethods = ["initialize", "tools/list", "resources/list", "resources/read"];
        if (md.method !== "tools/call" && !metadataMethods.includes(md.method)) return yield* error(id, -32601, "Method not found");
        let active = true; const view = authorizeView(context, () => active), operation = operationIssuer(context, () => active);
        const describe = Effect.gen(function* () {
          yield* current(context, "before_materialization");
          const result = yield* port(context, () => Effect.suspend(() => metadataCallback(context as OwnedParsed, view, operation)).pipe(
            Effect.ensuring(Effect.sync(() => { active = false; })),
          ), "private_rpc_dispatch");
          yield* attempt(() => requireLife(life), "owned_handoff_closed"); yield* current(context, "before_publication");
          return yield* attempt(() => {
            const resultReply = replyFor(context, result, id), owned = member(result) ? values.get(result) : undefined;
            if (md.method === "initialize" && owned?.tag === "success") {
              const value = owned.value;
              const capabilities = value !== null && typeof value === "object" && "kind" in value && value.kind === "object" ? value.entries.find(([key]) => key === "capabilities")?.[1] : undefined;
              life.uiEnabled = capabilities !== null && typeof capabilities === "object" && "kind" in capabilities && capabilities.kind === "object" && capabilities.entries.some(([key]) => key === "resources");
            }
            return resultReply;
          }, "private_rpc_dispatch");
        });
        const dispatch = Effect.scoped(Effect.gen(function* () {
          yield* current(context, "before_materialization"); yield* current(context, "before_allocation");
          const allocation = yield* Effect.acquireRelease(Effect.suspend(() => allocateCallback(context as OwnedParsed, inert)), (handle) => Effect.uninterruptible(Effect.gen(function* () {
            yield* Effect.suspend(() => releaseCallback(handle)).pipe(Effect.catchCause(() => { life.poisoned = true; return Effect.die(failure("private_rpc_cleanup")); }));
          })));
          void allocation; // Opaque handle is supplied only to captured release, never reflected.
          yield* attempt(() => requireLife(life), "owned_handoff_closed"); yield* current(context, "before_allocation");
          const lease = objectToken() as OwnedLease;
          let pending = 0;
          const emit = (value: OwnedJson): Effect.Effect<void, FixedFailure> => Effect.gen(function* () {
            while (pending >= 16) { yield* attempt(() => { requireLife(life); if (!active) refuse("owned_handoff_closed"); }, "owned_handoff_closed"); yield* Effect.sleep("1 millis"); }
            pending++;
            const send = Effect.gen(function* () {
              yield* attempt(() => { requireLife(life); const owned = member(value) ? values.get(value) : undefined; if (!active || !owned || owned.context !== context || owned.tag !== "success") refuse("private_rpc_dispatch"); }, "private_rpc_dispatch");
              if (md.progressToken === null) return;
              yield* current(context, "before_progress");
              const encoded = yield* serialize(context, reply({ kind: "progress", notification: value }, context));
              yield* current(context, "before_progress");
              // The sink owns a separate callback lifetime; dispatch may remain active afterward.
              let sinkCallbackLive = true;
              const outputView: OwnedOutputView = Object.freeze({ encodedText(token: unknown) {
                return sanitize(Effect.suspend(() => {
                  if (!member(token) || token !== encoded || !sinkCallbackLive || !active) return Effect.succeed(null);
                  const own = outputs.get(token);
                  if (!own || own.context !== context) return Effect.succeed(null);
                  return Effect.gen(function* () {
                    yield* attempt(() => requireLife(life), "owned_handoff_closed");
                    yield* current(context, "before_progress");
                    return yield* attempt(() => {
                      requireLife(life);
                      if (!sinkCallbackLive || !active || token !== encoded || outputs.get(token) !== own || own.context !== context) return null;
                      return own.text; // No intervening yield or callback after current/lifetime check.
                    }, "private_rpc_authority");
                  });
                }), "private_rpc_authority");
              } });
              yield* port(context, () => Effect.suspend(() => publishCallback(encoded, outputView)).pipe(
                Effect.ensuring(Effect.sync(() => { sinkCallbackLive = false; })),
              ), "private_rpc_dispatch");
              yield* attempt(() => requireLife(life), "owned_handoff_closed"); yield* current(context, "before_progress");
            });
            yield* send.pipe(Effect.ensuring(Effect.sync(() => { pending--; })));
          });
          const result = yield* port(context, () => Effect.suspend(() => dispatchCallback(context as OwnedParsed, lease, emit, view, operation)).pipe(
            Effect.ensuring(Effect.sync(() => { active = false; })),
          ), "private_rpc_dispatch");
          yield* attempt(() => requireLife(life), "owned_handoff_closed"); yield* current(context, "before_publication");
          return yield* attempt(() => replyFor(context, result, id), "private_rpc_dispatch");
        }));
        // Effect finalization covers interruption/failure as well as normal completion.
        // A generator's JavaScript finally alone is not our lifetime authority.
        const body = yield* (md.method === "tools/call" ? dispatch : describe).pipe(
          Effect.ensuring(Effect.sync(() => { active = false; })),
        );
        yield* attempt(() => requireLife(life), "owned_handoff_closed"); return yield* serialize(context, body);
      });
      return yield* work.pipe(Effect.catchCause((cause) => attempt(() => requireLife(life), "owned_handoff_closed").pipe(Effect.andThen(Effect.failCause(cause)))), Effect.onExit(() => Effect.sync(() => { life.busy = false; })));
    }), "private_rpc_dispatch"),
    encode: (sessionToken: unknown, outputToken: unknown) => sanitize(Effect.gen(function* () {
      const own = yield* attempt(() => checkOutput(sessionToken, outputToken), "private_rpc_owned");
      yield* current(own.data.context, "assert_current"); yield* attempt(() => requireLife(own.life), "owned_handoff_closed"); return own.data.text;
    }), "private_rpc_owned"),
    assertCurrent: (sessionToken: unknown, outputToken: unknown) => sanitize(Effect.gen(function* () {
      const own = yield* attempt(() => checkOutput(sessionToken, outputToken), "private_rpc_owned");
      yield* current(own.data.context, "assert_current"); yield* attempt(() => requireLife(own.life), "owned_handoff_closed");
    }), "private_rpc_owned") });
    return envelope;
  }), "private_rpc_codec");
}
export const rpcFactory: RpcFactory = Object.freeze({ create: createRpcEnvelope });
