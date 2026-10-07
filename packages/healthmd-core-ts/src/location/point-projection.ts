import * as Effect from "effect/Effect";
import * as Result from "effect/Result";
import type * as Scope from "effect/Scope";
import { createPersonalRecordCodec, type OwnedPersonalRecord, type TrustedPersonalCodecContext } from "../contracts/personal-slice.js";
import { decodeBinary64 } from "../contracts/exact-values.js";

export type LocationPointProjectionFailureCode = "unsupported_request" | "source_profile_unadmitted" | "scope_not_authorized" | "source_binding_mismatch" | "candidate_limit_exceeded" | "invalid_source_shape" | "invalid_exact_value" | "coordinate_out_of_range" | "source_unavailable";
export interface LocationPointProjectionFailure { readonly _tag: "LocationPointProjectionFailure"; readonly code: LocationPointProjectionFailureCode }
export interface LocationPointDescriptor { readonly profile: "synthetic.location.point.v1"; readonly dataset_id: string; readonly source_id: string; readonly source_revision: string; readonly purpose: string; readonly record_id: string }
export interface LocationPointLease { readonly materializeOriginalJSON: () => Effect.Effect<string, LocationPointProjectionFailure>; readonly authorize: TrustedPersonalCodecContext["authorize"] }
/** Preparation is interruptible. The host owns partial cleanup and atomic final allocation/release registration.
 * Current authorization is independent of the owned source resource and remains valid after its release.
 */
export interface LocationPointAuthority { readonly acquire: (descriptor: LocationPointDescriptor) => Effect.Effect<LocationPointLease, LocationPointProjectionFailure, Scope.Scope> }
export interface ProjectedLocationPoint { readonly _tag: "ProjectedLocationPoint"; readonly record: OwnedPersonalRecord; readonly canonical_json: string; readonly eligible_evidence_ref: string }
const codes = new Set<LocationPointProjectionFailureCode>(["unsupported_request", "source_profile_unadmitted", "scope_not_authorized", "source_binding_mismatch", "candidate_limit_exceeded", "invalid_source_shape", "invalid_exact_value", "coordinate_out_of_range", "source_unavailable"]);
const markers = new WeakMap<object, LocationPointProjectionFailureCode>();
function fail(code: LocationPointProjectionFailureCode): LocationPointProjectionFailure { return Object.freeze({ _tag: "LocationPointProjectionFailure", code }); }
function reject(code: LocationPointProjectionFailureCode): never { const marker = Object.freeze({}); markers.set(marker, code); throw marker; }
function safeCode(error: unknown): LocationPointProjectionFailureCode {
  if (typeof error !== "object" || error === null) return "source_unavailable";
  const marker = markers.get(error); if (marker) return marker;
  try {
    const value = error as LocationPointProjectionFailure;
    if (Object.keys(value).length === 2 && value._tag === "LocationPointProjectionFailure" && codes.has(value.code)) return value.code;
  } catch { /* Provider faults have no returned detail. */ }
  return "source_unavailable";
}
const attempt = <A>(body: () => A): Effect.Effect<A, LocationPointProjectionFailure> => Effect.try({ try: body, catch: (error) => fail(safeCode(error)) });
function object(value: unknown, keys?: readonly string[]): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) reject("invalid_source_shape");
  const record = value as Record<string, unknown>;
  if (keys && (Object.keys(record).length !== keys.length || keys.some((k) => !Object.hasOwn(record, k)))) reject("invalid_source_shape");
  return record;
}
function text(value: unknown): string { if (typeof value !== "string" || value.length === 0) reject("invalid_source_shape"); return value; }
/** Admission scan retains raw integer lexemes and checks escaped-equivalent duplicate keys before parsing. */
function parse(argument: unknown, maximum: number, maximumDepth: number, maximumNodes: number, malformed: LocationPointProjectionFailureCode): unknown {
  if (typeof argument !== "string") reject(malformed);
  const input = argument;
  if (input.length > maximum) reject("candidate_limit_exceeded");
  let bytes = 0;
  for (let i = 0; i < input.length; i++) {
    const c = input.charCodeAt(i); if (c === 0) reject(malformed);
    if (c >= 0xd800 && c <= 0xdbff) { const low = input.charCodeAt(++i); if (!(low >= 0xdc00 && low <= 0xdfff)) reject(malformed); bytes += 4; }
    else if (c >= 0xdc00 && c <= 0xdfff) reject(malformed);
    else bytes += c < 128 ? 1 : c < 2048 ? 2 : 3;
    if (bytes > maximum) reject("candidate_limit_exceeded");
  }
  let position = 0, nodes = 0;
  const white = () => { while (/[ \t\r\n]/.test(input[position] ?? "x")) position++; };
  function string(): string {
    const start = position++; let high = false;
    while (position < input.length) {
      let c = input.charCodeAt(position++);
      if (c === 34) { if (high) reject(malformed); return input.slice(start, position); }
      if (c < 32) reject(malformed);
      if (c === 92) {
        const escape = input[position++];
        if (escape === "u") { const digits = input.slice(position, position + 4); if (!/^[a-fA-F0-9]{4}$/.test(digits)) reject(malformed); c = Number.parseInt(digits, 16); position += 4; }
        else { if (high || !escape || !'"\\/bfnrt'.includes(escape)) reject(malformed); continue; }
      }
      if (c === 0) reject(malformed);
      if (high) { if (c < 0xdc00 || c > 0xdfff) reject(malformed); high = false; }
      else if (c >= 0xd800 && c <= 0xdbff) high = true;
      else if (c >= 0xdc00 && c <= 0xdfff) reject(malformed);
    }
    return reject(malformed);
  }
  function value(depth: number): void {
    if (depth > maximumDepth || ++nodes > maximumNodes) reject("candidate_limit_exceeded"); white();
    const c = input[position];
    if (c === '"') { string(); return; }
    if (c === "{" || c === "[") {
      const map = c === "{"; const end = map ? "}" : "]"; position++; white(); const keys = new Set<string>();
      if (input[position] === end) { position++; return; }
      for (;;) {
        if (map) { if (input[position] !== '"') reject(malformed); const key: unknown = JSON.parse(string()); if (typeof key !== "string" || keys.has(key)) reject(malformed); keys.add(key); white(); if (input[position++] !== ":") reject(malformed); }
        value(depth + 1); white(); const stop = input[position++]; if (stop === end) return; if (stop !== ",") reject(malformed); white();
      }
    }
    for (const token of ["true", "false", "null"]) if (input.startsWith(token, position)) { position += token.length; return; }
    const start = position; while (position < input.length && !/[ \t\r\n,}\]]/.test(input[position]!)) position++;
    const token = input.slice(start, position);
    if (token.length > 10 || !/^(?:0|-?[1-9][0-9]*)$/.test(token) || BigInt(token) < -999999999n || BigInt(token) > 999999999n) reject(malformed);
  }
  value(0); white(); if (position !== input.length) reject(malformed); return JSON.parse(input) as unknown;
}
function descriptor(input: unknown): LocationPointDescriptor {
  const parsed = parse(input, 4096, 8, 64, "unsupported_request");
  let record: Record<string, unknown>;
  try { record = object(parsed, ["profile", "dataset_id", "source_id", "source_revision", "purpose", "record_id"]); for (const value of Object.values(record)) text(value); }
  catch { return reject("unsupported_request"); }
  if (record.profile !== "synthetic.location.point.v1") reject("source_profile_unadmitted");
  return Object.freeze(record) as unknown as LocationPointDescriptor;
}
function scalar(value: unknown, unit: string): number {
  const record = object(value, ["representation", "bits", "unit"]);
  if (record.representation !== "binary64" || record.unit !== unit) reject("invalid_source_shape");
  const decoded = decodeBinary64(record.bits); if (Result.isFailure(decoded)) reject("invalid_exact_value"); return decoded.success;
}
function projectedSource(input: unknown, binding: LocationPointDescriptor): { point: unknown; reference: string } {
  const source = object(parse(input, 65536, 32, 4096, "invalid_source_shape"), ["source_profile", "eligible_evidence_ref", "point"]);
  if (source.source_profile !== binding.profile) reject("source_binding_mismatch");
  const reference = text(source.eligible_evidence_ref), point = object(source.point), lineage = object(point.lineage);
  if (point.domain !== "location" || point.payload_kind !== "location_point") reject("invalid_source_shape");
  if (point.record_id !== binding.record_id || ["dataset_id", "source_id", "source_revision", "purpose"].some((key) => lineage[key] !== binding[key as keyof LocationPointDescriptor])) reject("source_binding_mismatch");
  const payload = object(point.payload);
  for (const [key, bound] of [["latitude", 90], ["longitude", 180]] as const) { const n = scalar(payload[key], "degree"); if (n < -bound || n > bound) reject("coordinate_out_of_range"); }
  const accuracy = object(payload.horizontal_accuracy);
  if (!Object.hasOwn(accuracy, "state") && scalar(accuracy, "meter") < 0) payload.horizontal_accuracy = { state: "unavailable", reason: "native_invalid_accuracy" };
  const speed = object(payload.speed);
  if (speed.state === "known") { object(speed, ["state", "value"]); if (scalar(speed.value, "meter_per_second") < 0) payload.speed = { state: "unavailable", reason: "native_invalid_speed" }; }
  return { point, reference };
}
/** A private synthetic projection. Scope completion precedes the final current-authority publication check. */
export function createLocationPointProjector(authority: LocationPointAuthority): { readonly project: (input: unknown) => Effect.Effect<ProjectedLocationPoint, LocationPointProjectionFailure> } {
  return Object.freeze({ project(input: unknown) {
    const work = Effect.gen(function* () {
      const request = yield* attempt(() => descriptor(input));
      const prepared = yield* Effect.scoped(Effect.gen(function* () {
        const lease = yield* Effect.suspend(() => authority.acquire(request));
        const source = yield* Effect.suspend(() => lease.materializeOriginalJSON());
        const transformed = yield* attempt(() => projectedSource(source, request));
        const codec = createPersonalRecordCodec({ authorize: (d) => lease.authorize(d) });
        const decoded = codec.decode(JSON.stringify(transformed.point));
        if (Result.isFailure(decoded)) return yield* Effect.fail(fail(decoded.failure.code === "unsupported_shape" ? "invalid_source_shape" : decoded.failure.code === "scope_not_authorized" ? "scope_not_authorized" : decoded.failure.code === "candidate_limit_exceeded" ? "candidate_limit_exceeded" : "invalid_exact_value"));
        return { codec, record: decoded.success, reference: transformed.reference };
      }));
      const encoded = prepared.codec.encode(prepared.record);
      if (Result.isFailure(encoded)) return yield* Effect.fail(fail(encoded.failure.code === "scope_not_authorized" ? "scope_not_authorized" : "invalid_source_shape"));
      return Object.freeze({ _tag: "ProjectedLocationPoint" as const, record: prepared.record, canonical_json: encoded.success, eligible_evidence_ref: prepared.reference });
    });
    return Effect.uninterruptibleMask((restore) => restore(work).pipe(Effect.catchCause((cause) => {
      if (cause.reasons.some((reason) => reason._tag === "Interrupt")) return Effect.interrupt;
      const failed = cause.reasons.find((reason) => reason._tag === "Fail");
      return Effect.fail(fail(failed && failed._tag === "Fail" ? safeCode(failed.error) : "source_unavailable"));
    })));
  } });
}
