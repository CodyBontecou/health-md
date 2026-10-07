import * as Effect from "effect/Effect";
import * as Result from "effect/Result";
import type * as Scope from "effect/Scope";
import { createPersonalRecordCodec, type OwnedPersonalRecord, type TrustedPersonalCodecContext } from "../contracts/personal-slice.js";
import { decodeCanonicalInteger } from "../contracts/exact-values.js";

export type SliceSlot = "health" | "location" | "usage";
export type SliceFailureCode = "unsupported_request" | "scope_not_authorized" | "scope_binding_mismatch" | "source_required" | "coverage_incomplete" | "aggregate_partial_overlap" | "candidate_limit_exceeded" | "record_identity_conflict" | "invalid_record" | "cleanup_unacknowledged" | "source_failed";
export interface SliceFailure { readonly _tag: "PersonalSliceFailure"; readonly code: SliceFailureCode }
export interface SliceInstant { readonly epoch_seconds: string; readonly nanoseconds: number }
export interface SliceSelector {
  readonly slot: SliceSlot; readonly domain: "health" | "location" | "device_usage";
  readonly source_id: string; readonly source_revision: string;
  readonly device_id: string; readonly installation_id: string;
  readonly payload_kind: "health_fact" | "location_point" | "usage_aggregate";
  readonly statistic: "observation" | "original_point" | "source_total_duration";
  readonly profile: string; readonly detail: "health_value" | "location_exact_point" | "usage_app_duration";
}
export interface SliceRequest {
  readonly schema: "candidate.personal_slice_request"; readonly revision: 1;
  readonly dataset_id: string; readonly dataset_revision: string; readonly snapshot_id: string;
  readonly purpose: string; readonly destination: string; readonly caller_binding: string;
  readonly grant_revision: string; readonly suppression_revision: string;
  readonly slots: readonly SliceSelector[];
  readonly time_scope: { readonly mode: "instant"; readonly epoch: "unix"; readonly start: SliceInstant; readonly end: SliceInstant; readonly boundaries: "half_open" };
  readonly strictness: "strict" | "allow_partial"; readonly require_complete: boolean;
}
export interface SliceCoverage {
  readonly slot: SliceSlot; readonly domain: SliceSelector["domain"];
  readonly status: "complete" | "partial" | "unavailable" | "unknown" | "denied" | "partial_overlap";
  readonly reason_codes: readonly string[];
}
export interface SliceAuthority {
  /** Host catalog/current external suppression and distinct source/detail/destination grants.
   * Caller fields are requested bindings, never proof. Receives inert deeply frozen metadata only.
   * Slot null means job/destination authority. No title/measurement payload enters descriptors. */
  readonly check: (request: SliceRequest, slot: SliceSelector | null, phase: "before_source" | "before_page" | "before_record" | "before_encode" | "before_commit") => {
    readonly permitted: boolean; readonly binding_matches: boolean;
    readonly availability: "available" | "unavailable" | "unknown";
    readonly coverage: "complete" | "partial" | "unknown";
  };
  readonly codec_context: TrustedPersonalCodecContext;
}
export interface SlicePage {
  readonly ordinal: number; readonly terminal: boolean;
  readonly dataset_revision: string; readonly snapshot_id: string;
  readonly source_binding: SliceSelector;
  /** Primitive raw JSON only after source-purpose/detail/current authorization.
   * Fake source accounts actual UTF-8 bytes; no trusted encodedBytes assertion. */
  readonly records_json: readonly string[];
}
export interface SliceSourceLease {
  readonly readPage: (ordinal: number) => Effect.Effect<SlicePage, SliceFailure>;
}
export interface SliceSources {
  /** Coarse scoped capability. Must register cleanup atomically with completed allocation.
   * Interruptible preparation may precede owned allocation; cancellation cannot strand it.
   * Scope closure waits real fake release acknowledgment, faults use only closed SliceFailure. */
  readonly open: (request: SliceRequest, selector: SliceSelector) => Effect.Effect<SliceSourceLease, SliceFailure, Scope.Scope>;
}
export interface SliceArtifactFile { readonly name: "manifest.json" | "records.ndjson"; readonly utf8: string }
export interface OwnedSliceArtifact {
  readonly files: readonly SliceArtifactFile[];
  readonly records: readonly OwnedPersonalRecord[];
  readonly __ownedSliceArtifact: unique symbol;
}
export type SliceCommitDecision = "committed" | "definitely_not_committed" | "ambiguous";
export interface SliceDeliveryLease {
  /** One job and one commit attempt. Owns indivisible fake commitment and current guard at its
   * linearization point. Cancellation/typed transport failure after possible commit resolves
   * to a terminal decision (ambiguous when acknowledgment cannot prove committed/not).
   * Operation masks the bounded owned handoff until this acknowledgment; no automatic retry.
   * Terminal decision lives in the trusted fake job ledger even if caller Fiber is interrupted.
   * This seam is no proof of real atomic grants, durable store/ledger, or authenticated delivery. */
  readonly commit: (artifact: OwnedSliceArtifact, currentGuard: () => boolean) => Effect.Effect<SliceCommitDecision>;
}
export interface SliceDelivery {
  readonly open: (request: SliceRequest) => Effect.Effect<SliceDeliveryLease, SliceFailure, Scope.Scope>;
}
export interface SliceDelivered {
  readonly _tag: "PersonalSliceCompleted"; readonly decision: SliceCommitDecision;
  readonly accounted_jobs: 1; readonly cleanup_acknowledged: true;
}
export interface PersonalSliceDependencies {
  readonly authority: SliceAuthority; readonly sources: SliceSources; readonly delivery: SliceDelivery;
}
export type PersonalSliceFactoryProposal = (dependencies: PersonalSliceDependencies) => PersonalSliceOperationProposal;
export interface PersonalSliceOperationProposal {
  /** Proposed private factory createPersonalSliceOperation({authority,sources,delivery}) returns
   * this single run operation. Unknown admitted only as primitive JSON string; same internal
   * codec factory owns decoded records and WeakMap artifact identity; foreign objects refused
   * before properties. Context services are trusted adapters, not caller JSON inputs. */
  readonly run: (input: unknown) => Effect.Effect<SliceDelivered, SliceFailure>;
}

type Json = null | boolean | number | string | readonly Json[] | { readonly [key: string]: Json };
const LIMIT = 65536, PAGE_LIMIT = 1048576, OUTPUT_LIMIT = 1048576;
const failureCodes: readonly SliceFailureCode[] = ["unsupported_request", "scope_not_authorized", "scope_binding_mismatch", "source_required", "coverage_incomplete", "aggregate_partial_overlap", "candidate_limit_exceeded", "record_identity_conflict", "invalid_record", "cleanup_unacknowledged", "source_failed"];
const rejected = new WeakMap<object, SliceFailureCode>();
const fail = (code: SliceFailureCode): SliceFailure => Object.freeze({ _tag: "PersonalSliceFailure", code });
function reject(code: SliceFailureCode): never { const token = Object.freeze({}); rejected.set(token, code); throw token; }
function attempt<A>(body: () => A, fallback: SliceFailureCode): Effect.Effect<A, SliceFailure> {
  return Effect.try({ try: body, catch: (error) => fail(typeof error === "object" && error !== null ? rejected.get(error) ?? fallback : fallback) });
}
function scalarCompare(a: string, b: string): number {
  const x = Array.from(a), y = Array.from(b);
  for (let i = 0; i < Math.min(x.length, y.length); i++) { const d = x[i]!.codePointAt(0)! - y[i]!.codePointAt(0)!; if (d) return d; }
  return x.length - y.length;
}
function bytes(value: string, maximum: number, code: SliceFailureCode = "candidate_limit_exceeded"): number {
  if (value.length > maximum) reject(code);
  let total = 0;
  for (let i = 0; i < value.length; i++) {
    const c = value.charCodeAt(i);
    if (c === 0) reject(code);
    if (c >= 0xd800 && c <= 0xdbff) { const d = value.charCodeAt(++i); if (!(d >= 0xdc00 && d <= 0xdfff)) reject(code); total += 4; }
    else if (c >= 0xdc00 && c <= 0xdfff) reject(code);
    else total += c < 128 ? 1 : c < 2048 ? 2 : 3;
    if (total > maximum) reject(code);
  }
  return total;
}
function freeze<A>(value: A): A {
  if (value !== null && typeof value === "object") { for (const child of Object.values(value)) freeze(child); Object.freeze(value); }
  return value;
}
function canonical(value: unknown): string {
  if (value === null || typeof value === "boolean" || typeof value === "number" || typeof value === "string") return JSON.stringify(value);
  if (Array.isArray(value)) return "[" + value.map(canonical).join(",") + "]";
  const object = value as Readonly<Record<string, unknown>>;
  return "{" + Object.keys(object).sort(scalarCompare).map((k) => JSON.stringify(k) + ":" + canonical(object[k])).join(",") + "}";
}
/** New private request grammar. Number lexemes are checked before conversion; strings only
 * are passed to JSON.parse after token-boundary scanning. No caller objects are traversed. */
function parse(input: unknown): Json {
  if (typeof input !== "string") reject("unsupported_request");
  const text = input; bytes(text, LIMIT, "unsupported_request");
  let position = 0, nodes = 0;
  const space = () => { while (position < text.length && /[\x20\t\r\n]/.test(text[position]!)) position++; };
  function string(): string {
    const begin = position++;
    while (position < text.length) {
      const c = text[position++]!;
      if (c === '"') { const value = JSON.parse(text.slice(begin, position)) as string; bytes(value, LIMIT, "unsupported_request"); return value; }
      if (c === "\\") position++; else if (c.charCodeAt(0) < 32) reject("unsupported_request");
    }
    return reject("unsupported_request");
  }
  function value(depth: number): Json {
    if (depth > 32 || ++nodes > 4096) reject("unsupported_request"); space();
    const c = text[position];
    if (c === '"') return string();
    if (c === "{" || c === "[") {
      position++; space(); const object: Record<string, Json> = Object.create(null) as Record<string, Json>; const array: Json[] = [];
      const end = c === "{" ? "}" : "]";
      if (text[position] === end) { position++; return c === "{" ? object : array; }
      while (true) {
        if (c === "{") { if (text[position] !== '"') reject("unsupported_request"); const key = string(); if (Object.hasOwn(object, key)) reject("unsupported_request"); space(); if (text[position++] !== ":") reject("unsupported_request"); object[key] = value(depth + 1); }
        else array.push(value(depth + 1));
        space(); const next = text[position++]; if (next === end) break; if (next !== ",") reject("unsupported_request"); space();
      }
      return c === "{" ? object : array;
    }
    for (const [token, primitive] of [["true", true], ["false", false], ["null", null]] as const) if (text.startsWith(token, position)) { position += token.length; return primitive; }
    const match = /^-?(?:0|[1-9][0-9]*)/.exec(text.slice(position));
    if (!match || match[0] === "-0" || match[0].length > 10) reject("unsupported_request");
    position += match[0].length; if (/[.eE0-9]/.test(text[position] ?? "")) reject("unsupported_request"); return Number(match[0]);
  }
  const result = value(0); space(); if (position !== text.length) reject("unsupported_request"); return result;
}
function object(value: unknown, keys: readonly string[], code: SliceFailureCode = "unsupported_request"): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) reject(code);
  const out = value as Record<string, unknown>;
  if (Object.keys(out).length !== keys.length || keys.some((k) => !Object.hasOwn(out, k))) reject(code); return out;
}
function id(value: unknown): string { if (typeof value !== "string" || !value) reject("unsupported_request"); bytes(value, 256, "unsupported_request"); return value; }
function integer(value: unknown, kind: "epoch" | "ordinal", code: SliceFailureCode): bigint { const out = decodeCanonicalInteger(value, kind); if (Result.isFailure(out)) reject(code); return out.success; }
type Rational = { readonly n: bigint; readonly d: bigint };
const compare = (a: Rational, b: Rational) => { const difference = a.n * b.d - b.n * a.d; return difference < 0n ? -1 : difference > 0n ? 1 : 0; };
function unix(value: SliceInstant): Rational { return { n: integer(value.epoch_seconds, "epoch", "unsupported_request") * 1000000000n + BigInt(value.nanoseconds), d: 1000000000n }; }
function instant(value: unknown): Rational {
  const v = value as Record<string, unknown>;
  if (v.representation === "seconds_nanos") return { n: BigInt(v.epoch_seconds as string) * 1000000000n + BigInt(v.nanoseconds as number), d: 1000000000n };
  const raw = BigInt("0x" + (v.bits as string)), exponent = Number((raw >> 52n) & 2047n), fraction = raw & ((1n << 52n) - 1n);
  const shift = exponent === 0 ? -1074 : exponent - 1023 - 52;
  const magnitude = exponent === 0 ? fraction : (1n << 52n) + fraction;
  let n = raw >> 63n ? -magnitude : magnitude; let d = 1n;
  if (shift >= 0) n <<= BigInt(shift); else d <<= BigInt(-shift);
  if (v.epoch === "apple_reference_2001") n += 978307200n * d;
  return { n, d };
}
const selectorKeys = ["slot", "domain", "source_id", "source_revision", "device_id", "installation_id", "payload_kind", "statistic", "profile", "detail"] as const;
const slots = ["health", "location", "usage"] as const;
const combinations = {
  health: ["health", "health_fact", "observation", "health_value"],
  location: ["location", "location_point", "original_point", "location_exact_point"],
  usage: ["device_usage", "usage_aggregate", "source_total_duration", "usage_app_duration"],
} as const;
function request(input: unknown): SliceRequest {
  const r = object(parse(input), ["schema", "revision", "dataset_id", "dataset_revision", "snapshot_id", "purpose", "destination", "caller_binding", "grant_revision", "suppression_revision", "slots", "time_scope", "strictness", "require_complete"]);
  if (r.schema !== "candidate.personal_slice_request" || r.revision !== 1 || (r.strictness !== "strict" && r.strictness !== "allow_partial") || typeof r.require_complete !== "boolean") reject("unsupported_request");
  for (const key of ["dataset_id", "dataset_revision", "snapshot_id", "purpose", "destination", "caller_binding"]) id(r[key]);
  integer(r.grant_revision, "ordinal", "unsupported_request"); integer(r.suppression_revision, "ordinal", "unsupported_request");
  if (!Array.isArray(r.slots) || r.slots.length > 3) reject("unsupported_request");
  const seen = new Set<string>();
  for (const raw of r.slots) {
    const s = object(raw, selectorKeys); if (!slots.includes(s.slot as SliceSlot) || seen.has(s.slot as string)) reject("unsupported_request"); seen.add(s.slot as string);
    const c = combinations[s.slot as SliceSlot]; if ([s.domain, s.payload_kind, s.statistic, s.detail].some((value, i) => value !== c[i])) reject("unsupported_request");
    for (const k of selectorKeys) id(s[k]);
  }
  r.slots.sort((a: SliceSelector, b: SliceSelector) => slots.indexOf(a.slot) - slots.indexOf(b.slot));
  const time = object(r.time_scope, ["mode", "epoch", "start", "end", "boundaries"]);
  if (time.mode !== "instant" || time.epoch !== "unix" || time.boundaries !== "half_open") reject("unsupported_request");
  for (const raw of [time.start, time.end]) { const t = object(raw, ["epoch_seconds", "nanoseconds"]); integer(t.epoch_seconds, "epoch", "unsupported_request"); if (typeof t.nanoseconds !== "number" || !Number.isInteger(t.nanoseconds) || t.nanoseconds < 0 || t.nanoseconds > 999999999) reject("unsupported_request"); }
  const out = r as unknown as SliceRequest; if (compare(unix(out.time_scope.start), unix(out.time_scope.end)) >= 0) reject("unsupported_request"); return freeze(out);
}
function safeCode(error: unknown): SliceFailureCode {
  if (typeof error !== "object" || error === null) return "source_failed";
  try { const code = (error as { code?: unknown }).code; return failureCodes.includes(code as SliceFailureCode) ? code as SliceFailureCode : "source_failed"; } catch { return "source_failed"; }
}
function key(record: OwnedPersonalRecord, slot: SliceSlot): string {
  const l = record.lineage as Readonly<Record<string, unknown>>;
  return canonical([slot, record.record_id, l.dataset_id, l.source_id, l.source_revision, l.device, l.installation, l.original_record, l.record_revision]);
}
function boundRecord(record: OwnedPersonalRecord, r: SliceRequest, s: SliceSelector): void {
  const l = record.lineage as Readonly<Record<string, unknown>>, payload = record.payload as Readonly<Record<string, unknown>>;
  const device = l.device as Readonly<Record<string, unknown>>, install = l.installation as Readonly<Record<string, unknown>>;
  if (record.domain !== s.domain || record.payload_kind !== s.payload_kind || l.dataset_id !== r.dataset_id || l.source_id !== s.source_id || l.source_revision !== s.source_revision || l.purpose !== r.purpose
    || device.state !== "known" || device.value !== s.device_id || install.state !== "known" || install.value !== s.installation_id
    || (s.slot !== "location" && payload.statistic !== s.statistic) || (s.slot === "health" && payload.native_profile !== s.profile)) reject("scope_binding_mismatch");
}
function selection(record: OwnedPersonalRecord, r: SliceRequest): "included" | "excluded" | "partial_overlap" {
  const a = unix(r.time_scope.start), b = unix(r.time_scope.end), payload = record.payload as Readonly<Record<string, unknown>>;
  if (record.payload_kind === "usage_aggregate") {
    const bucket = payload.bucket as Readonly<Record<string, unknown>>, start = instant(bucket.start), end = instant(bucket.end);
    if (compare(start, b) >= 0 || compare(end, a) <= 0) return "excluded";
    return compare(start, a) >= 0 && compare(end, b) <= 0 ? "included" : "partial_overlap";
  }
  const time = record.time as Readonly<Record<string, unknown>>, at = instant(time.instant);
  return compare(at, a) >= 0 && compare(at, b) < 0 ? "included" : "excluded";
}
/** One common selected/combined operation; injected adapters alone own source/grant/storage
 * authority. Internal artifact/record ownership never admits a foreign caller object. */
export function createPersonalSliceOperation(dependencies: PersonalSliceDependencies): PersonalSliceOperationProposal {
  const artifacts = new WeakSet<object>();
  return Object.freeze({ run(input: unknown) {
    let closing = false;
    const work = Effect.gen(function* () {
      const r = yield* attempt(() => request(input), "unsupported_request");
      const check = (slot: SliceSelector | null, phase: Parameters<SliceAuthority["check"]>[2]) => {
        const out = dependencies.authority.check(r, slot, phase);
        if (!out.binding_matches) reject("scope_binding_mismatch"); return out;
      };
      const job = yield* attempt(() => check(null, "before_source"), "scope_not_authorized"); if (!job.permitted) return yield* Effect.fail(fail("scope_not_authorized"));
      const coverage: SliceCoverage[] = [], admitted: SliceSelector[] = [];
      for (const s of r.slots) {
        const out = yield* attempt(() => check(s, "before_source"), "scope_not_authorized");
        const status = !out.permitted ? "denied" : out.availability !== "available" ? out.availability : out.coverage;
        if (!out.permitted || out.availability !== "available") {
          if (r.strictness === "strict") return yield* Effect.fail(fail(!out.permitted ? "scope_not_authorized" : "source_required"));
          coverage.push({ slot: s.slot, domain: s.domain, status, reason_codes: [!out.permitted ? "scope_not_authorized" : out.availability === "unknown" ? "source_unknown" : "source_unavailable"] }); continue;
        }
        if (r.require_complete && out.coverage !== "complete") return yield* Effect.fail(fail("coverage_incomplete"));
        admitted.push(s); coverage.push({ slot: s.slot, domain: s.domain, status: out.coverage, reason_codes: out.coverage === "complete" ? [] : ["synthetic_only_no_source_completeness_evidence"] });
      }
      const permitted = (s: SliceSelector | null, phase: Parameters<SliceAuthority["check"]>[2]) => {
        if (s !== null) { const jobCurrent = check(null, phase); if (!jobCurrent.permitted || jobCurrent.availability !== "available") reject("scope_not_authorized"); }
        const out = check(s, phase); if (!out.permitted || out.availability !== "available") reject("scope_not_authorized");
        // Source authority may synchronously change the distinct destination grant.
        if (s !== null) { const jobCurrent = check(null, phase); if (!jobCurrent.permitted || jobCurrent.availability !== "available") reject("scope_not_authorized"); }
        return true;
      };
      let codecPhase: "before_record" | "before_encode" = "before_record";
      let codecSelector: SliceSelector | undefined, codecBindingRejected = false;
      const codec = createPersonalRecordCodec({ authorize(descriptor) {
        const selector = codecSelector;
        const lineage = descriptor.lineage, device = lineage.device as Readonly<Record<string, unknown>>, installation = lineage.installation as Readonly<Record<string, unknown>>;
        if (!selector || descriptor.domain !== selector.domain || descriptor.payload_kind !== selector.payload_kind
          || lineage.dataset_id !== r.dataset_id || lineage.source_id !== selector.source_id || lineage.source_revision !== selector.source_revision || lineage.purpose !== r.purpose
          || device.state !== "known" || device.value !== selector.device_id || installation.state !== "known" || installation.value !== selector.installation_id
          || descriptor.requested_detail.length !== 1 || descriptor.requested_detail[0] !== ({ health: "health_fact", location: "location_exact_point", usage: "app_duration" } as const)[selector.slot]) {
          codecBindingRejected = true; reject("scope_binding_mismatch");
        }
        // Descriptor has no payload profile/statistic: the bound page's profile is checked before
        // decode; full payload profile/statistic is checked by boundRecord after decode. This is
        // a trusted source-adapter precondition, not pre-materialization native profile admission.
        permitted(selector, codecPhase);
        const authority = dependencies.authority.codec_context.authorize(descriptor);
        // Reentrant host callbacks cannot revoke destination/source authority then return old permission.
        permitted(selector, codecPhase);
        return authority;
      } });
      const rows: { slot: SliceSlot; record: OwnedPersonalRecord; encoded: string }[] = [], seen = new Map<string, string>();
      let pageCount = 0, recordCount = 0, rowBytes = 0;
      for (const s of admitted) {
        closing = false;
        yield* Effect.scoped(Effect.gen(function* () {
          yield* attempt(() => permitted(s, "before_source"), "scope_not_authorized");
          const lease = yield* Effect.suspend(() => dependencies.sources.open(r, s));
          for (let ordinal = 0; ; ordinal++) {
            if (++pageCount > 8) return yield* Effect.fail(fail("candidate_limit_exceeded"));
            yield* attempt(() => permitted(s, "before_page"), "scope_not_authorized");
            const page = yield* Effect.suspend(() => lease.readPage(ordinal));
            yield* attempt(() => {
              object(page, ["ordinal", "terminal", "dataset_revision", "snapshot_id", "source_binding", "records_json"], "scope_binding_mismatch");
              if (!Array.isArray(page.records_json) || page.records_json.length > 8 || typeof page.terminal !== "boolean") reject("candidate_limit_exceeded");
              const metadata = canonical({ ordinal: page.ordinal, terminal: page.terminal, dataset_revision: page.dataset_revision, snapshot_id: page.snapshot_id, source_binding: page.source_binding });
              let pageBytes = bytes(metadata, PAGE_LIMIT);
              for (const raw of page.records_json) { if (typeof raw !== "string") reject("invalid_record"); pageBytes += bytes(raw, LIMIT); if (pageBytes > PAGE_LIMIT) reject("candidate_limit_exceeded"); }
              recordCount += page.records_json.length; if (recordCount > 32) reject("candidate_limit_exceeded");
              if (page.ordinal !== ordinal || page.dataset_revision !== r.dataset_revision || page.snapshot_id !== r.snapshot_id || canonical(page.source_binding) !== canonical(s)) reject("scope_binding_mismatch");
            }, "source_failed");
            for (const raw of page.records_json) {
              yield* attempt(() => permitted(s, "before_record"), "scope_not_authorized");
              codecSelector = s; codecBindingRejected = false; codecPhase = "before_record"; const decoded = codec.decode(raw); if (Result.isFailure(decoded)) return yield* Effect.fail(fail(codecBindingRejected ? "scope_binding_mismatch" : decoded.failure.code === "scope_not_authorized" ? "scope_not_authorized" : decoded.failure.code === "candidate_limit_exceeded" ? "candidate_limit_exceeded" : "invalid_record"));
              const record = decoded.success;
              const included = yield* attempt(() => { boundRecord(record, r, s); return selection(record, r); }, "invalid_record");
              if (included === "partial_overlap") { if (r.strictness === "strict") return yield* Effect.fail(fail("aggregate_partial_overlap")); const c = coverage.find((item) => item.slot === s.slot)!; coverage[coverage.indexOf(c)] = { slot: s.slot, domain: s.domain, status: "partial_overlap", reason_codes: ["aggregate_partial_overlap"] }; continue; }
              if (included === "excluded") continue;
              yield* attempt(() => permitted(s, "before_encode"), "scope_not_authorized");
              codecSelector = s; codecBindingRejected = false; codecPhase = "before_encode"; const encoded = codec.encode(record); if (Result.isFailure(encoded)) return yield* Effect.fail(fail(encoded.failure.code === "scope_not_authorized" ? "scope_not_authorized" : "invalid_record"));
              yield* attempt(() => {
                const identity = key(record, s.slot), prior = seen.get(identity);
                if (prior !== undefined && prior !== encoded.success) reject("record_identity_conflict");
                if (prior === undefined) { rowBytes += bytes(encoded.success, LIMIT) + 1; if (rowBytes > OUTPUT_LIMIT) reject("candidate_limit_exceeded"); seen.set(identity, encoded.success); rows.push({ slot: s.slot, record, encoded: encoded.success }); }
              }, "invalid_record");
            }
            if (page.terminal) break;
          }
          closing = true;
        }));
        closing = false;
      }
      // Scope closure above has acknowledged every source before job allocation/materialization.
      yield* attempt(() => { permitted(null, "before_commit"); for (const s of admitted) permitted(s, "before_encode"); }, "scope_not_authorized");
      const artifact = yield* attempt(() => {
        rows.sort((a, b) => slots.indexOf(a.slot) - slots.indexOf(b.slot) || scalarCompare(a.encoded, b.encoded));
        // Reauthorization is synchronous immediately before canonical personal serialization.
        for (const row of rows) { codecSelector = admitted.find((s) => s.slot === row.slot); codecBindingRejected = false; codecPhase = "before_encode"; const encoded = codec.encode(row.record); if (Result.isFailure(encoded)) reject(encoded.failure.code === "scope_not_authorized" ? "scope_not_authorized" : "invalid_record"); if (encoded.success !== row.encoded) reject("record_identity_conflict"); }
        const manifest = { schema: "candidate.personal_slice_manifest", revision: 1, dataset_id: r.dataset_id, dataset_revision: r.dataset_revision, snapshot_id: r.snapshot_id, destination: r.destination,
          time_scope: r.time_scope, selected_sources: admitted, coverage, completeness: coverage.length > 0 && coverage.every((c) => c.status === "complete") ? "complete" : "partial", native_archive_complete: false, record_count: rows.length,
          artifacts: [{ name: "records.ndjson", utf8_bytes: rowBytes, record_count: rows.length }] };
        const manifestText = canonical(manifest); if (bytes(manifestText, OUTPUT_LIMIT) + rowBytes > OUTPUT_LIMIT) reject("candidate_limit_exceeded");
        const value = freeze({ files: [{ name: "manifest.json" as const, utf8: manifestText }, { name: "records.ndjson" as const, utf8: rows.map((row) => row.encoded + "\n").join("") }], records: rows.map((row) => row.record) }) as unknown as OwnedSliceArtifact;
        artifacts.add(value); return value;
      }, "invalid_record");
      const decision = yield* Effect.scoped(Effect.gen(function* () {
        yield* attempt(() => { permitted(null, "before_commit"); for (const s of admitted) permitted(s, "before_commit"); }, "scope_not_authorized");
        const delivery = yield* Effect.suspend(() => dependencies.delivery.open(r));
        const decision = yield* Effect.uninterruptible(Effect.gen(function* () {
          yield* attempt(() => { if (!artifacts.has(artifact)) reject("invalid_record"); permitted(null, "before_commit"); for (const s of admitted) permitted(s, "before_commit"); }, "scope_not_authorized");
          return yield* Effect.suspend(() => delivery.commit(artifact, () => { try { permitted(null, "before_commit"); for (const s of admitted) permitted(s, "before_commit"); return true; } catch { return false; } }));
        }));
        if (!["committed", "definitely_not_committed", "ambiguous"].includes(decision)) return yield* Effect.fail(fail("source_failed"));
        closing = true; return decision;
      }));
      closing = false;
      return Object.freeze({ _tag: "PersonalSliceCompleted" as const, decision, accounted_jobs: 1 as const, cleanup_acknowledged: true as const });
    });
    // Mapping must itself run under interruption so mixed provider/finalizer causes cannot leak.
    return Effect.uninterruptibleMask((restore) => restore(work).pipe(Effect.catchCause((cause) => {
      if (cause.reasons.some((reason) => reason._tag === "Interrupt")) {
        // Use the admitted Effect API to construct fresh fixed causes; no provider reasons,
        // annotations or private Cause representation are forwarded. Explicit finalizer
        // interruption preserves cancellation alongside an unavailable cleanup acknowledgment.
        if (cause.reasons.some((reason) => reason._tag === "Die")) return Effect.fail(fail("cleanup_unacknowledged")).pipe(Effect.ensuring(Effect.interrupt));
        return Effect.interrupt;
      }
      const failed = cause.reasons.find((reason) => reason._tag === "Fail");
      return Effect.fail(fail(closing && cause.reasons.some((reason) => reason._tag === "Die") ? "cleanup_unacknowledged" : failed && failed._tag === "Fail" ? safeCode(failed.error) : "source_failed"));
    })));
  } });
}
