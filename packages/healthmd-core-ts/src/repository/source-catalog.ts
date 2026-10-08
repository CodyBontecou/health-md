/** Private metadata-only candidate. Owned handles do not authenticate actual source grants. */
import * as Effect from "effect/Effect";
import type * as Scope from "effect/Scope";
const requestBrand: unique symbol = Symbol("OwnedCatalogRequest");
const ticketBrand: unique symbol = Symbol("OwnedCatalogTicket");
export interface OwnedCatalogRequest { readonly [requestBrand]: true }
export interface OwnedCatalogTicket { readonly [ticketBrand]: true }
export type FailureCode = "invalid_request" | "candidate_limit_exceeded" | "scope_not_authorized" | "scope_binding_mismatch" | "owned_handoff_closed" | "private_catalog_codec" | "private_catalog_busy";
export type CatalogFailure = { readonly code: FailureCode };
export type Domain = "health" | "location" | "device_usage";
export type PayloadKind = "health_fact" | "location_point" | "usage_aggregate" | "foreground_app_session";
export type TaggedIdentity = { readonly state: "known"; readonly value: string } | { readonly state: "unknown"; readonly reason: "not_reported" };
export type Availability = { readonly state: "available" } | { readonly state: "unavailable"; readonly reason: "not_authorized" | "unsupported" | "display_only" | "not_qualified" | "not_reported" } | { readonly state: "unknown"; readonly reason: "not_reported" } | { readonly state: "planned"; readonly reason: "not_qualified" };
export interface RequestedBinding {
 readonly source_id: string; readonly domain: Domain; readonly payload_kind: PayloadKind;
 readonly source_contract_revision: string; readonly source_purpose: "local_catalog";
 readonly destination: "local"; readonly grant_revision: string; readonly suppression_revision: string;
}
export interface CatalogMetadata {
 readonly source_id: string; readonly domain: Domain; readonly payload_kind: PayloadKind;
 readonly source_contract_revision: string;
 readonly device: TaggedIdentity; readonly installation: TaggedIdentity; readonly native_profile: TaggedIdentity;
 readonly authority_kind: "native_health_store" | "native_usage_aggregate" | "collector_metadata";
 readonly capabilities: { readonly capture: Availability; readonly display: Availability; readonly query: Availability; readonly export: Availability; readonly detail: Availability };
 readonly history: { readonly completeness: "complete" | "partial" | "unknown"; readonly range: "source_reported" | "not_reported"; readonly freshness: "source_reported" | "unknown"; readonly short_sessions: "not_applicable" | "historical_loss" | "all_observed_new_semantics" };
 readonly detail: { readonly granularity: "health_native" | "location_point" | "app_aggregate" | "observed_app_session"; readonly focused_title: "excluded" | "not_observed" | "separate_grant_required" };
 readonly eligibility: "native_authority" | "aggregate_display_only" | "unqualified";
}
export interface CatalogIssuer {
 /** Actual trusted source callback only; primitive preflight FIRST. Exact owned request,
  * current callback/factory/originalScope and matching source/domain/kind/revision bind issuance.
  * A callback may issue multiple tickets; only the returned exact ticket is consumed. */
 issue(primitiveClosedMetadataWire: unknown, request: unknown): OwnedCatalogTicket | null;
}
export interface MetadataSource {
 capture(request: OwnedCatalogRequest, requested: RequestedBinding, issuer: CatalogIssuer): Effect.Effect<OwnedCatalogTicket, CatalogFailure>;
}
export type Phase = "before_capture" | "after_capture" | "before_consume" | "before_metadata_read" | "after_consume" | "assert_current";
export interface CurrentAuthority {
 /** Captured host binds actual catalog/source classification/caller/purpose/detail/destination
  * and latest independent suppression/frontier. Request strings, revision, flags and caller JSON
  * request bindings only; no issuer or fake authenticates actual source grants. */
 check(request: OwnedCatalogRequest, requested: RequestedBinding, phase: Phase): Effect.Effect<void, CatalogFailure>;
}
export interface AuthorizedMetadataView {
 /** Lazy EACH execution; unknown/foreign request/ticket -> fixed invalid_request before
  * properties/check; exact returned ticket/request/callback membership is required.
  * Valid but escaped inactive callback -> null with zero callbacks/checks/materialization.
  * Own active read checks captured original current before_metadata_read on EACH run,
  * then originalScope/context/callback/exact ticket/request again AFTER await, and returns
  * primitive validated source metadata wire without an intervening yield. No payload read. */
 metadata(request: unknown, ticket: unknown): Effect.Effect<string | null, CatalogFailure>;
}
export interface MetadataConsumer {
 /** A trusted metadata-only sink, no real I/O or external delivery. */
 consume(request: OwnedCatalogRequest, ticket: OwnedCatalogTicket, view: AuthorizedMetadataView): Effect.Effect<void, CatalogFailure>;
}
export interface CapturedCatalogLifetime {
 isLive(): boolean;
 /** Replayable same factory-owned closure signal; closes before any source/current callback,
  * no fresh Scope/Layer lookup, no join of the active callback, no resource ACK claim. */
 readonly closed: Effect.Effect<void>;
}
export interface SourceCatalog {
 request(primitiveBindingWire: unknown): Effect.Effect<OwnedCatalogRequest, CatalogFailure>;
 capture(request: unknown): Effect.Effect<OwnedCatalogTicket, CatalogFailure>;
 consume(request: unknown, ticket: unknown, consumer: MetadataConsumer): Effect.Effect<void, CatalogFailure>;
 assertCurrent(request: unknown, ticket: unknown): Effect.Effect<void, CatalogFailure>;
 readonly lifetime: CapturedCatalogLifetime;
}
export interface SourceCatalogFactory {
 create(services: { readonly source: MetadataSource; readonly current: CurrentAuthority }): Effect.Effect<SourceCatalog, CatalogFailure, Scope.Scope>;
}
import * as Result from "effect/Result";
import { decodeCanonicalInteger } from "../contracts/exact-values.js";

type Code = FailureCode;
const ownFailures = new WeakMap<object, Code>();
function failure(code: Code): CatalogFailure {
  const token = Object.freeze({ code }); ownFailures.set(token, code); return token;
}
function reject(code: Code): never { throw failure(code); }
function objectToken(value: unknown): value is object { return typeof value === "object" && value !== null; }
function ownedCode(value: unknown, fallback: Code): Code {
  return objectToken(value) ? ownFailures.get(value) ?? fallback : fallback;
}
function attempt<A>(body: () => A, fallback: Code): Effect.Effect<A, CatalogFailure> {
  return Effect.try({ try: body, catch: error => failure(ownedCode(error, fallback)) });
}
/** Only a trusted capability's closed data failure can select these two dispositions.
 * No message, getter value, cause text, source record or caller argument is consumed. */
function portCode(error: unknown, fallback: Code): Code {
  const own = ownedCode(error, fallback); if (own !== fallback) return own;
  if (!objectToken(error)) return fallback;
  try {
    const fields = Object.getOwnPropertyDescriptors(error);
    if (Object.keys(fields).length !== 1 || !fields.code || !("value" in fields.code)) return fallback;
    const code: unknown = fields.code.value;
    return code === "scope_not_authorized" || code === "scope_binding_mismatch" ? code : fallback;
  } catch { return fallback; }
}
/** Bounded UTF-16 scalar scan, used for raw-wire admission and decoded string limits. */
function utf8(text: string, cap: number, malformed: Code, oversized: Code): void {
  if (text.length > cap) reject(oversized);
  let bytes = 0;
  for (let n = 0; n < text.length; n++) {
    const c = text.charCodeAt(n);
    if (c >= 0xd800 && c <= 0xdbff) {
      const low = text.charCodeAt(++n);
      if (!(low >= 0xdc00 && low <= 0xdfff)) reject(malformed);
      bytes += 4;
    } else if (c >= 0xdc00 && c <= 0xdfff) reject(malformed);
    else bytes += c < 0x80 ? 1 : c < 0x800 ? 2 : 3;
    if (bytes > cap) reject(oversized);
  }
}
type Value = string | boolean | null | readonly Value[] | ReadonlyMap<string, Value>;
type Context = "request" | "metadata" | "identity" | "capabilities" | "availability" | "history" | "detail" | "unsupported";
const keys: Record<Context, readonly string[] | null> = {
  request: ["source_id", "domain", "payload_kind", "source_contract_revision", "source_purpose", "destination", "grant_revision", "suppression_revision"],
  metadata: ["source_id", "domain", "payload_kind", "source_contract_revision", "device", "installation", "native_profile", "authority_kind", "capabilities", "history", "detail", "eligibility"],
  identity: ["state", "value", "reason"], capabilities: ["capture", "display", "query", "export", "detail"],
  availability: ["state", "reason"], history: ["completeness", "range", "freshness", "short_sessions"],
  detail: ["granularity", "focused_title"], unsupported: [],
};
function childContext(parent: Context, key: string): Context {
  if (parent === "metadata") {
    if (["device", "installation", "native_profile"].includes(key)) return "identity";
    if (key === "capabilities" || key === "history" || key === "detail") return key;
  }
  return parent === "capabilities" ? "availability" : "unsupported";
}
/** New private closed metadata grammar, not the public JSON/serde parser.
 * Keys are admitted before any unknown value token is decoded or traversed. */
function parse(input: unknown, metadata: boolean): Value {
  const malformed: Code = metadata ? "private_catalog_codec" : "invalid_request";
  const limit: Code = metadata ? "private_catalog_codec" : "candidate_limit_exceeded";
  if (typeof input !== "string") reject(malformed);
  utf8(input, metadata ? 16384 : 4096, malformed, limit);
  let at = 0, nodes = 0;
  const bad = (): never => reject(malformed);
  const ws = () => { while (at < input.length && /[\x20\t\r\n]/.test(input[at]!)) at++; };
  const string = (): string => {
    if (input[at++] !== '"') bad();
    let out = "";
    while (at < input.length) {
      let c = input[at++]!;
      if (c === '"') { utf8(out, 512, malformed, limit); if (out.includes("\0")) bad(); return out; }
      if (c === "\\") {
        c = input[at++]!;
        const escapes: Readonly<Record<string, string>> = { '"': '"', "\\": "\\", "/": "/", b: "\b", f: "\f", n: "\n", r: "\r", t: "\t" };
        if (c === "u") {
          const token = input.slice(at, at + 4); if (!/^[0-9a-fA-F]{4}$/.test(token)) bad();
          const code = parseInt(token, 16); at += 4;
          if (code >= 0xd800 && code <= 0xdbff) {
            if (input.slice(at, at + 2) !== "\\u") bad(); at += 2;
            const lowToken = input.slice(at, at + 4); if (!/^[0-9a-fA-F]{4}$/.test(lowToken)) bad();
            const low = parseInt(lowToken, 16); at += 4;
            if (!(low >= 0xdc00 && low <= 0xdfff)) bad(); out += String.fromCharCode(code, low);
          } else { if (code >= 0xdc00 && code <= 0xdfff) bad(); out += String.fromCharCode(code); }
        } else { if (!Object.hasOwn(escapes, c)) bad(); out += escapes[c]!; }
      } else { if (c.charCodeAt(0) < 32) bad(); out += c; }
      // Bound construction as well as final decoded UTF8 count.
      if (out.length > 512) reject(limit);
    }
    return bad();
  };
  const value = (depth: number, context: Context, shape?: "string" | "object"): Value => {
    if (depth > 16 || ++nodes > 256) reject(limit);
    ws(); const c = input[at];
    // Reject recognized slot types before traversing or decoding their excluded descendants.
    if (shape === "string" && c !== '"') bad();
    if (shape === "object" && c !== "{") bad();
    if (c === '"') return string();
    if (c === "{") {
      at++; ws(); const out = new Map<string, Value>();
      if (input[at] === "}") { at++; return out; }
      while (true) {
        ws(); const key = string();
        if (out.has(key)) bad();
        // The per-key512 guard in string precedes this closed-key check.
        if (keys[context] !== null && !keys[context]!.includes(key)) bad();
        ws(); if (input[at++] !== ":") bad();
        const child = childContext(context, key);
        out.set(key, value(depth + 1, child, child === "unsupported" ? "string" : "object")); ws();
        if (input[at] === "}") { at++; return out; }
        if (input[at++] !== ",") bad();
      }
    }
    if (c === "[") {
      at++; ws(); const out: Value[] = [];
      if (input[at] === "]") { at++; return out; }
      while (true) { out.push(value(depth + 1, "unsupported")); ws(); if (input[at] === "]") { at++; return out; } if (input[at++] !== ",") bad(); }
    }
    for (const [word, result] of [["null", null], ["true", true], ["false", false]] as const) {
      if (input.slice(at, at + word.length) === word) { at += word.length; return result; }
    }
    // Raw numeric tokens are intentionally unadmitted; no Number/JSON parse conversion.
    return bad();
  };
  const result = value(1, metadata ? "metadata" : "request"); ws(); if (at !== input.length) bad(); return result;
}
function map(value: Value | undefined, expected: readonly string[], code: Code): ReadonlyMap<string, Value> {
  if (!(value instanceof Map) || value.size !== expected.length || expected.some(k => !value.has(k))) reject(code);
  return value;
}
function text(value: Value | undefined, code: Code): string { if (typeof value !== "string") reject(code); return value; }
function oneOf(value: Value | undefined, choices: readonly string[], code: Code): string {
  const s = text(value, code); if (!choices.includes(s)) reject(code); return s;
}
function identity(value: Value | undefined, code: Code, limit: Code): string {
  const s = text(value, code); if (!s) reject(code); utf8(s, 128, code, limit); return s;
}
function revision(value: Value | undefined, source: boolean, code: Code): string {
  const s = text(value, code), number = decodeCanonicalInteger(s, "ordinal");
  if (Result.isFailure(number) || (source && (number.success < 1n || number.success > 4294967295n))) reject(code);
  return s;
}
function binding(input: unknown): RequestedBinding {
  const code = "invalid_request", x = map(parse(input, false), keys.request!, code);
  const domain = oneOf(x.get("domain"), ["health", "location", "device_usage"], code) as Domain;
  const kind = oneOf(x.get("payload_kind"), ["health_fact", "location_point", "usage_aggregate", "foreground_app_session"], code) as PayloadKind;
  if ((domain === "health" && kind !== "health_fact") || (domain === "location" && kind !== "location_point") || (domain === "device_usage" && !["usage_aggregate", "foreground_app_session"].includes(kind))) reject(code);
  oneOf(x.get("source_purpose"), ["local_catalog"], code); oneOf(x.get("destination"), ["local"], code);
  return Object.freeze({ source_id: identity(x.get("source_id"), code, "candidate_limit_exceeded"), domain, payload_kind: kind,
    source_contract_revision: revision(x.get("source_contract_revision"), true, code), source_purpose: "local_catalog", destination: "local",
    grant_revision: revision(x.get("grant_revision"), false, code), suppression_revision: revision(x.get("suppression_revision"), false, code) });
}
function metadataWire(input: unknown, req: RequestedBinding): string {
  const code = "private_catalog_codec", x = map(parse(input, true), keys.metadata!, code);
  for (const key of ["source_id", "domain", "payload_kind", "source_contract_revision"] as const) if (x.get(key) !== req[key]) reject(code);
  for (const key of ["device", "installation", "native_profile"]) {
    const v = x.get(key); if (!(v instanceof Map)) reject(code);
    const state = oneOf(v.get("state"), ["known", "unknown"], code);
    if (state === "known") { map(v, ["state", "value"], code); identity(v.get("value"), code, code); }
    else { map(v, ["state", "reason"], code); oneOf(v.get("reason"), ["not_reported"], code); }
  }
  const caps = map(x.get("capabilities"), keys.capabilities!, code);
  for (const key of keys.capabilities!) {
    const v = caps.get(key); if (!(v instanceof Map)) reject(code);
    const state = oneOf(v.get("state"), ["available", "unavailable", "unknown", "planned"], code);
    if (state === "available") map(v, ["state"], code);
    else {
      map(v, ["state", "reason"], code);
      oneOf(v.get("reason"), state === "planned" ? ["not_qualified"] : state === "unknown" ? ["not_reported"] : ["not_authorized", "unsupported", "display_only", "not_qualified", "not_reported"], code);
    }
  }
  const h = map(x.get("history"), keys.history!, code);
  oneOf(h.get("completeness"), ["complete", "partial", "unknown"], code);
  oneOf(h.get("range"), ["source_reported", "not_reported"], code); oneOf(h.get("freshness"), ["source_reported", "unknown"], code);
  oneOf(h.get("short_sessions"), ["not_applicable", "historical_loss", "all_observed_new_semantics"], code);
  const detail = map(x.get("detail"), keys.detail!, code);
  oneOf(detail.get("focused_title"), ["excluded", "not_observed", "separate_grant_required"], code);
  const profile = req.payload_kind === "health_fact" ? ["native_health_store", "health_native", "native_authority"]
    : req.payload_kind === "location_point" ? ["collector_metadata", "location_point", "unqualified"]
    : req.payload_kind === "usage_aggregate" ? ["native_usage_aggregate", "app_aggregate", "aggregate_display_only"]
    : ["collector_metadata", "observed_app_session", "unqualified"];
  if (x.get("authority_kind") !== profile[0] || detail.get("granularity") !== profile[1] || x.get("eligibility") !== profile[2]) reject(code);
  return input as string;
}
type RequestData = { readonly binding: RequestedBinding; returned: OwnedCatalogTicket | null };
type TicketData = { readonly request: OwnedCatalogRequest; readonly context: object; readonly wire: string };
/** Original-Scope-bound metadata orchestration. No allocation, store or payload port. */
export function createSourceCatalog(services: { readonly source: MetadataSource; readonly current: CurrentAuthority }): Effect.Effect<SourceCatalog, CatalogFailure, Scope.Scope> {
  return Effect.gen(function* () {
    let live = true, busy = false;
    // Pure replayable closure notification; waiter interruption removes only its own resume.
    // This signal acknowledges lifetime expiration, never resource cleanup or external delivery.
    const waiters = new Set<(effect: Effect.Effect<void>) => void>();
    const closed = Effect.callback<void>(resume => {
      if (!live) { resume(Effect.void); return; }
      waiters.add(resume);
      return Effect.sync(() => { waiters.delete(resume); });
    });
    yield* Effect.addFinalizer(() => Effect.sync(() => {
      live = false;
      const pending = [...waiters]; waiters.clear();
      for (const resume of pending) resume(Effect.void);
    }));
    const lifetime: CapturedCatalogLifetime = Object.freeze({ isLive: () => live, closed });
    const source = services.source.capture.bind(services.source), current = services.current.check.bind(services.current);
    const requests = new WeakMap<object, RequestData>(), tickets = new WeakMap<object, TicketData>();
    const alive = () => { if (!live) reject("owned_handoff_closed"); };
    const ownRequest = (r: unknown): RequestData => { if (!objectToken(r) || !requests.has(r)) reject("invalid_request"); return requests.get(r)!; };
    const ownPair = (r: unknown, t: unknown): TicketData => {
      const q = ownRequest(r);
      if (!objectToken(t) || !tickets.has(t) || q.returned !== t || tickets.get(t)!.request !== r) reject("invalid_request");
      return tickets.get(t)!;
    };
    const sanitize = <A, E, R>(work: Effect.Effect<A, E, R>, fallback: Code): Effect.Effect<A, CatalogFailure, R> =>
      Effect.uninterruptibleMask(restore => restore(work).pipe(Effect.catchCause(cause => {
        if (cause.reasons.some(r => r._tag === "Interrupt")) return Effect.interrupt;
        if (!live) return Effect.fail(failure("owned_handoff_closed"));
        const reason = cause.reasons.find(r => r._tag === "Fail");
        return Effect.fail(failure(reason?._tag === "Fail" ? portCode(reason.error, fallback) : fallback));
      })));
    const check = (r: OwnedCatalogRequest, phase: Phase) => Effect.gen(function* () {
      const data = yield* attempt(() => { const q = ownRequest(r); alive(); return q; }, "invalid_request");
      yield* sanitize(Effect.suspend(() => current(r, data.binding, phase)), "scope_not_authorized");
      yield* attempt(alive, "owned_handoff_closed");
    });
    const exclusive = <A>(work: () => Effect.Effect<A, CatalogFailure>): Effect.Effect<A, CatalogFailure> =>
      Effect.uninterruptibleMask(restore => Effect.gen(function* () {
        yield* attempt(() => { alive(); if (busy) reject("private_catalog_busy"); busy = true; }, "private_catalog_busy");
        return yield* restore(Effect.suspend(work)).pipe(Effect.ensuring(Effect.sync(() => { busy = false; })));
      }));
    const catalog: SourceCatalog = Object.freeze({
      lifetime,
      request: (wire: unknown) => attempt(() => { alive(); const q = binding(wire); const token = Object.freeze({}) as OwnedCatalogRequest; requests.set(token, { binding: q, returned: null }); return token; }, "invalid_request"),
      capture: (r: unknown) => Effect.gen(function* () {
        const data = yield* attempt(() => { const q = ownRequest(r); alive(); return q; }, "invalid_request");
        return yield* exclusive(() => Effect.gen(function* () {
          yield* check(r as OwnedCatalogRequest, "before_capture");
          const context = Object.freeze({}); let active = true; data.returned = null;
          const issuer: CatalogIssuer = Object.freeze({ issue: (wire: unknown, request: unknown) => {
            if (!objectToken(request) || !requests.has(request) || request !== r || !active || !live) return null;
            try {
              const validated = metadataWire(wire, data.binding), token = Object.freeze({}) as OwnedCatalogTicket;
              tickets.set(token, { request: r as OwnedCatalogRequest, context, wire: validated }); return token;
            } catch { return null; }
          } });
          const ticket = yield* sanitize(Effect.suspend(() => source(r as OwnedCatalogRequest, data.binding, issuer)).pipe(Effect.ensuring(Effect.sync(() => { active = false; }))), "private_catalog_codec");
          yield* attempt(() => {
            alive(); if (!objectToken(ticket) || tickets.get(ticket)?.request !== r || tickets.get(ticket)?.context !== context) reject("private_catalog_codec");
            data.returned = ticket;
          }, "private_catalog_codec");
          yield* check(r as OwnedCatalogRequest, "after_capture"); return ticket;
        }));
      }),
      consume: (r: unknown, t: unknown, consumer: MetadataConsumer) => Effect.gen(function* () {
        const data = yield* attempt(() => { const q = ownPair(r, t); alive(); return q; }, "invalid_request");
        return yield* exclusive(() => Effect.gen(function* () {
          yield* check(r as OwnedCatalogRequest, "before_consume");
          const consume = consumer.consume.bind(consumer); let active = true;
          const view: AuthorizedMetadataView = Object.freeze({ metadata: (request: unknown, ticket: unknown) => Effect.gen(function* () {
            // Unknown membership precedes liveness, callbacks and every property access.
            const pair = yield* attempt(() => ownPair(request, ticket), "invalid_request");
            if (!active) return null;
            yield* attempt(() => { alive(); if (request !== r || ticket !== t || pair.context !== data.context) reject("invalid_request"); }, "invalid_request");
            yield* check(r as OwnedCatalogRequest, "before_metadata_read");
            return yield* attempt(() => {
              alive(); if (!active || request !== r || ticket !== t || ownPair(request, ticket) !== data) reject("owned_handoff_closed");
              return data.wire;
            }, "owned_handoff_closed");
          }) });
          yield* sanitize(Effect.suspend(() => consume(r as OwnedCatalogRequest, t as OwnedCatalogTicket, view)).pipe(Effect.ensuring(Effect.sync(() => { active = false; }))), "private_catalog_codec");
          yield* attempt(alive, "owned_handoff_closed"); yield* check(r as OwnedCatalogRequest, "after_consume");
        }));
      }),
      assertCurrent: (r: unknown, t: unknown) => Effect.gen(function* () {
        yield* attempt(() => { ownPair(r, t); alive(); }, "invalid_request"); yield* check(r as OwnedCatalogRequest, "assert_current");
      }),
    });
    yield* attempt(alive, "owned_handoff_closed"); return catalog;
  });
}
