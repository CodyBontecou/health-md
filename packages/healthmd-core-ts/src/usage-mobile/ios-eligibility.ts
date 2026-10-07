import * as Context from "effect/Context";
import * as Effect from "effect/Effect";
import type * as Scope from "effect/Scope";
export type IOSUsageEligibilityFailureCode = "unsupported_request" | "source_profile_unadmitted" | "candidate_limit_exceeded" | "invalid_host_binding" | "scope_not_authorized" | "unavailable" | "scope_binding_mismatch" | "owned_handoff_closed" | "cleanup_unacknowledged";
export interface IOSUsageEligibilityFailure { readonly _tag: "IOSUsageEligibilityFailure"; readonly code: IOSUsageEligibilityFailureCode }
export type IOSUsageEligibilityPhase = "before_allocation" | "before_publication" | "assert_current";
export interface IOSUsageEligibilityRequest { readonly profile: "synthetic.ios.usage.eligibility.v1"; readonly source_id: string; readonly source_revision: string; readonly installation_id: string; readonly purpose: "local_usage" | "local_display"; readonly requested: "data_read" | "report_display"; readonly destination: "local_report" | "local_query" | "local_file" | "paired_device" | "external_agent"; readonly job_id: string; readonly selection_id: string; readonly detail: "app_duration" | "app_label"; readonly page_limit: number; readonly record_limit: number }
export interface IOSUsageEligibilityBinding extends IOSUsageEligibilityRequest { readonly authorization_state: "approved" | "approvedWithDataAccess" | "denied" | "notDetermined" | "unavailable"; readonly route: "display_only" | "aggregate_read_handoff" | "unavailable"; readonly admission: "synthetic_qualified" | "unproven"; readonly proof_ref: string; readonly frontier_lineage: string; readonly frontier_revision: string }
export interface IOSUsageEligibilityResource { readonly release: Effect.Effect<void, IOSUsageEligibilityFailure> }
export interface IOSUsageEligibilityCatalogService { readonly resolve: (request: IOSUsageEligibilityRequest) => Effect.Effect<string, IOSUsageEligibilityFailure>; readonly checkSource: (binding: IOSUsageEligibilityBinding, phase: IOSUsageEligibilityPhase) => "permitted" | "scope_not_authorized" | "unavailable" | "scope_binding_mismatch"; readonly allocate: (binding: IOSUsageEligibilityBinding) => Effect.Effect<IOSUsageEligibilityResource, IOSUsageEligibilityFailure> }
export interface IOSUsageCurrentAuthorityService { readonly current: (binding: IOSUsageEligibilityBinding, phase: IOSUsageEligibilityPhase) => string }
export interface OwnedIOSUsageHandoff { readonly _tag: "OwnedIOSUsageHandoff"; readonly kind: "display_only" | "aggregate_read_handoff"; readonly native_qualification: false; readonly export_allowed: false; readonly assertCurrent: (input: unknown) => Effect.Effect<void, IOSUsageEligibilityFailure> }

export class IOSUsageEligibilityCatalog extends Context.Service<IOSUsageEligibilityCatalog, IOSUsageEligibilityCatalogService>()("healthmd.candidate.IOSUsageEligibilityCatalog") {}
export class IOSUsageCurrentAuthority extends Context.Service<IOSUsageCurrentAuthority, IOSUsageCurrentAuthorityService>()("healthmd.candidate.IOSUsageCurrentAuthority") {}
export interface IOSUsageEligibilityGate { readonly open: (input: unknown) => Effect.Effect<OwnedIOSUsageHandoff, IOSUsageEligibilityFailure, IOSUsageEligibilityCatalog | IOSUsageCurrentAuthority | Scope.Scope> }
type Code = IOSUsageEligibilityFailureCode;
const tokens = new WeakMap<object, Code>();
const failure = (code: Code): IOSUsageEligibilityFailure => Object.freeze({ _tag: "IOSUsageEligibilityFailure", code });
function reject(code: Code): never { const token = Object.freeze({}); tokens.set(token, code); throw token; }
function attempt<A>(body: () => A, fallback: Code): Effect.Effect<A, IOSUsageEligibilityFailure> {
  return Effect.try({ try: body, catch: (error) => failure(typeof error === "object" && error !== null ? tokens.get(error) ?? fallback : fallback) });
}
function utf8(s: string, max: number, invalid: Code, limit: Code): void {
  if (s.length > max) reject(limit);
  let bytes = 0;
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c === 0) reject(invalid);
    if (c >= 0xd800 && c <= 0xdbff) { const d = s.charCodeAt(++i); if (!(d >= 0xdc00 && d <= 0xdfff)) reject(invalid); bytes += 4; }
    else if (c >= 0xdc00 && c <= 0xdfff) reject(invalid);
    else bytes += c < 128 ? 1 : c < 2048 ? 2 : 3;
    if (bytes > max) reject(limit);
  }
}
/** Linear bounded token admission precedes JSON map creation/number conversion.
 * Unknown arguments are rejected before any caller property or Proxy trap. */
function parse(input: unknown, host = false): unknown {
  const invalid: Code = host ? "invalid_host_binding" : "unsupported_request";
  const limit: Code = host ? "invalid_host_binding" : "candidate_limit_exceeded";
  if (typeof input !== "string") reject(invalid);
  const text = input;
  utf8(text, 4096, invalid, limit);
  let position = 0, nodes = 0;
  const space = () => { while (position < text.length && /[\x20\t\r\n]/.test(text[position]!)) position++; };
  function string(): string {
    const begin = position++;
    while (position < text.length) {
      const c = text[position++]!;
      if (c === '"') { const value: unknown = JSON.parse(text.slice(begin, position)); if (typeof value !== "string") reject(invalid); utf8(value, 4096, invalid, limit); return value; }
      if (c === "\\") position++; else if (c.charCodeAt(0) < 32) reject(invalid);
    }
    return reject(invalid);
  }
  function value(depth: number): unknown {
    if (depth > 4 || ++nodes > 64) reject(limit);
    space(); const c = text[position];
    if (c === '"') return string();
    if (c === "{" || c === "[") {
      position++; space(); const object: Record<string, unknown> = Object.create(null) as Record<string, unknown>; const array: unknown[] = [];
      const end = c === "{" ? "}" : "]";
      if (text[position] === end) { position++; return c === "{" ? object : array; }
      while (true) {
        if (c === "{") { if (text[position] !== '"') reject(invalid); const key = string(); if (Object.hasOwn(object, key)) reject(invalid); space(); if (text[position++] !== ":") reject(invalid); object[key] = value(depth + 1); }
        else array.push(value(depth + 1));
        space(); const next = text[position++]; if (next === end) break; if (next !== ",") reject(invalid); space();
      }
      return c === "{" ? object : array;
    }
    for (const [token, primitive] of [["true", true], ["false", false], ["null", null]] as const) if (text.startsWith(token, position)) { position += token.length; return primitive; }
    const begin = position;
    if (text[position] === "0") position++;
    else { if (!/[1-9]/.test(text[position] ?? "")) reject(invalid); while (/[0-9]/.test(text[position] ?? "")) { if (position - begin > 9) reject(invalid); position++; } }
    if (/[.eE0-9]/.test(text[position] ?? "")) reject(invalid);
    return Number(text.slice(begin, position));
  }
  const result = value(0); space(); if (position !== text.length) reject(invalid); return result;
}
const requestKeys = ["profile", "source_id", "source_revision", "installation_id", "purpose", "requested", "destination", "job_id", "selection_id", "detail", "page_limit", "record_limit"] as const;
const bindingKeys = [...requestKeys, "authorization_state", "route", "admission", "proof_ref", "frontier_lineage", "frontier_revision"];
const currentKeys = ["decision", "source_id", "source_revision", "installation_id", "purpose", "destination", "job_id", "selection_id", "detail", "proof_ref", "frontier_lineage", "frontier_revision", "grant_revision"];
function object(value: unknown, keys: readonly string[], code: Code): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) reject(code);
  const out = value as Record<string, unknown>;
  if (Object.keys(out).length !== keys.length || keys.some((key) => !Object.hasOwn(out, key))) reject(code);
  return out;
}
function identity(value: unknown, host: boolean): string {
  const invalid: Code = host ? "invalid_host_binding" : "unsupported_request";
  if (typeof value !== "string" || !value) reject(invalid);
  utf8(value, 128, invalid, host ? "invalid_host_binding" : "candidate_limit_exceeded"); return value;
}
function u64(value: unknown): string {
  if (typeof value !== "string" || !/^(0|[1-9][0-9]{0,19})$/.test(value) || (value.length === 20 && value > "18446744073709551615")) reject("invalid_host_binding"); return value;
}
function request(input: unknown, host = false, parsed = false): IOSUsageEligibilityRequest {
  const code: Code = host ? "invalid_host_binding" : "unsupported_request";
  const x = object(parsed ? input : parse(input, host), requestKeys, code);
  for (const key of requestKeys) if (key !== "page_limit" && key !== "record_limit") identity(x[key], host);
  if (x.profile !== "synthetic.ios.usage.eligibility.v1") reject(host ? "invalid_host_binding" : "source_profile_unadmitted");
  if (!["local_usage", "local_display"].includes(x.purpose as string) || !["data_read", "report_display"].includes(x.requested as string)
    || !["local_report", "local_query", "local_file", "paired_device", "external_agent"].includes(x.destination as string) || !["app_duration", "app_label"].includes(x.detail as string)) reject(code);
  for (const [key, max] of [["page_limit", 32], ["record_limit", 4096]] as const) {
    if (typeof x[key] !== "number" || !Number.isInteger(x[key])) reject(code);
    if (x[key] < 1 || x[key] > max) reject(host ? code : "candidate_limit_exceeded");
  }
  return Object.freeze(x) as unknown as IOSUsageEligibilityRequest;
}
function decodeBinding(input: unknown, req: IOSUsageEligibilityRequest): IOSUsageEligibilityBinding {
  const x = object(parse(input, true), bindingKeys, "invalid_host_binding");
  const subset = Object.fromEntries(requestKeys.map((key) => [key, x[key]])); request(subset, true, true);
  for (const key of requestKeys) if (x[key] !== req[key]) reject("scope_binding_mismatch");
  for (const key of ["authorization_state", "route", "admission", "proof_ref", "frontier_lineage"]) identity(x[key], true);
  u64(x.frontier_revision);
  if (!["approved", "approvedWithDataAccess", "denied", "notDetermined", "unavailable"].includes(x.authorization_state as string) || !["display_only", "aggregate_read_handoff", "unavailable"].includes(x.route as string) || !["synthetic_qualified", "unproven"].includes(x.admission as string)) reject("invalid_host_binding");
  if (x.authorization_state === "denied") reject("scope_not_authorized");
  if (x.admission !== "synthetic_qualified" || x.route === "unavailable" || x.authorization_state === "notDetermined" || x.authorization_state === "unavailable") reject("unavailable");
  if (x.route === "display_only") { if (req.purpose !== "local_display" || req.destination !== "local_report") reject("scope_binding_mismatch"); }
  else if (x.authorization_state !== "approvedWithDataAccess" || req.purpose !== "local_usage" || req.requested !== "data_read") reject("scope_binding_mismatch");
  return Object.freeze(x) as unknown as IOSUsageEligibilityBinding;
}
function sanitize<A, E, R>(work: Effect.Effect<A, E, R>): Effect.Effect<A, IOSUsageEligibilityFailure, R> {
  return Effect.uninterruptibleMask((restore) => restore(work).pipe(Effect.catchCause((cause) => {
    if (cause.reasons.some((reason) => reason._tag === "Interrupt")) return Effect.interrupt;
    const fail = cause.reasons.find((reason) => reason._tag === "Fail");
    // Only our private failure objects carry approved codes; provider objects are never inspected.
    return Effect.fail(failure(fail && fail._tag === "Fail" ? safeFailure(fail.error) : "unavailable"));
  })));
}
const ownFailures = new WeakMap<object, Code>();
function safeFailure(error: unknown): Code {
  if (typeof error !== "object" || error === null) return "unavailable";
  const known = ownFailures.get(error); if (known) return known;
  // Trusted typed adapter failures are closed data descriptors; getters/extra payload never escape.
  try {
    const fields = Object.getOwnPropertyDescriptors(error);
    const codes: readonly Code[] = ["unsupported_request", "source_profile_unadmitted", "candidate_limit_exceeded", "invalid_host_binding", "scope_not_authorized", "unavailable", "scope_binding_mismatch", "owned_handoff_closed", "cleanup_unacknowledged"];
    if (Object.keys(fields).length === 2 && fields._tag?.value === "IOSUsageEligibilityFailure" && typeof fields.code?.value === "string" && codes.includes(fields.code.value as Code)) return fields.code.value as Code;
  } catch { /* Fixed unavailable below. */ }
  return "unavailable";
}
function checked<A>(body: () => A, fallback: Code): Effect.Effect<A, IOSUsageEligibilityFailure> {
  return attempt(body, fallback).pipe(Effect.mapError((error) => { ownFailures.set(error, error.code); return error; }));
}
/** Gate-only owned metadata seam. No personal observation, SDK or report API exists here. */
export function createIOSUsageEligibilityGate(): IOSUsageEligibilityGate {
  let busy = false, poisoned = false;
  return Object.freeze({ open: (input: unknown) => sanitize(Effect.gen(function* () {
    const req = yield* checked(() => request(input), "unsupported_request");
    // The original Scope owns lifetime even before allocation; closed scopes run this immediately.
    let scopeLive = true;
    yield* Effect.addFinalizer(() => Effect.sync(() => { scopeLive = false; }));
    const requireScope = () => { if (!scopeLive) reject("owned_handoff_closed"); };
    yield* checked(requireScope, "unavailable");
    yield* checked(() => { if (poisoned) reject("cleanup_unacknowledged"); if (busy) reject("candidate_limit_exceeded"); busy = true; }, "unavailable");
    let allocated = false, live = false;
    const work = Effect.gen(function* () {
      const catalog = yield* IOSUsageEligibilityCatalog; const authority = yield* IOSUsageCurrentAuthority;
      const raw = yield* Effect.suspend(() => catalog.resolve(req));
      const binding = yield* checked(() => { requireScope(); return decodeBinding(raw, req); }, "invalid_host_binding");
      let grant: string | undefined;
      const authorize = (phase: IOSUsageEligibilityPhase) => checked(() => {
        requireScope();
        const source = catalog.checkSource(binding, phase);
        requireScope();
        if (source !== "permitted") { if (["scope_not_authorized", "unavailable", "scope_binding_mismatch"].includes(source)) reject(source as Code); reject("invalid_host_binding"); }
        // Source callbacks may reenter policy. This independent atomic snapshot follows them.
        const currentRaw = authority.current(binding, phase);
        requireScope();
        const now = object(parse(currentRaw, true), currentKeys, "invalid_host_binding");
        const revision = u64(now.grant_revision); u64(now.frontier_revision);
        if (now.decision !== "permitted") { if (["scope_not_authorized", "unavailable", "scope_binding_mismatch"].includes(now.decision as string)) reject(now.decision as Code); reject("invalid_host_binding"); }
        for (const key of currentKeys) if (!["decision", "grant_revision"].includes(key) && now[key] !== binding[key as keyof IOSUsageEligibilityBinding]) reject("scope_binding_mismatch");
        if (grant !== undefined && revision !== grant) reject("scope_binding_mismatch"); grant = revision;
      }, "unavailable");
      yield* authorize("before_allocation");
      yield* checked(requireScope, "unavailable");
      yield* Effect.acquireRelease(Effect.suspend(() => catalog.allocate(binding)).pipe(Effect.tap(() => Effect.sync(() => { allocated = true; live = scopeLive; }))), (resource) => Effect.uninterruptible(Effect.gen(function* () {
        live = false;
        yield* Effect.suspend(() => resource.release).pipe(Effect.catchCause(() => { poisoned = true; return Effect.die(failure("cleanup_unacknowledged")); }));
        busy = false;
      })));
      yield* checked(requireScope, "unavailable");
      yield* authorize("before_publication");
      yield* checked(requireScope, "unavailable");
      const handoff: OwnedIOSUsageHandoff = Object.freeze({ _tag: "OwnedIOSUsageHandoff", kind: binding.route as OwnedIOSUsageHandoff["kind"], native_qualification: false, export_allowed: false,
        assertCurrent: (value: unknown) => sanitize(Effect.gen(function* () {
          yield* checked(() => { const next = request(value); for (const key of requestKeys) if (next[key] !== req[key]) reject("scope_binding_mismatch"); if (!live) reject("owned_handoff_closed"); requireScope(); }, "unavailable");
          yield* authorize("assert_current");
          yield* checked(requireScope, "unavailable");
        })),
      });
      return handoff;
    });
    return yield* work.pipe(Effect.onExit(() => Effect.sync(() => { if (!allocated) busy = false; })));
  })) });
}
