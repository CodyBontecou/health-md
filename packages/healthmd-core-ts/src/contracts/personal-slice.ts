import * as Result from "effect/Result";
import { decodeCanonicalInteger } from "./exact-values.js";

export type PersonalFailureCode = "unsupported_shape" | "invalid_exact_value" | "candidate_limit_exceeded"
  | "scope_not_authorized" | "coordinate_out_of_range" | "native_invalid_accuracy" | "native_invalid_speed"
  | "invalid_bucket" | "duration_outside_bucket" | "clock_inconsistent";
export interface PersonalCodecFailure { readonly _tag: "PersonalCodecFailure"; readonly code: PersonalFailureCode }
type Json = null | boolean | number | string | readonly Json[] | { readonly [key: string]: Json };
export type OwnedPersonalRecord = Readonly<Record<string, Json>> & { readonly __personalRecordBrand: unique symbol };
export interface PersonalAuthorizationDescriptor {
  readonly lineage: Readonly<Record<string, Json>>;
  readonly record_id: string;
  readonly domain: string;
  readonly payload_kind: string;
  readonly boundaries: readonly Json[];
  readonly app_identity: Json;
  readonly claimed_app_class: string | null;
  readonly requested_detail: readonly string[];
}
/** Host-owned catalog/current grants/fences, never an assertion supplied by record JSON. */
export interface TrustedPersonalCodecContext {
  readonly authorize: (descriptor: PersonalAuthorizationDescriptor) => {
    readonly permitted: boolean;
    readonly authority_binding: string;
    readonly frontier_binding: string;
    readonly app_class: "browser" | "non_browser" | "unknown" | null;
    readonly title_permitted: boolean;
  };
}
type Outcome<A> = Result.Result<A, PersonalCodecFailure>;
function failure(code: PersonalFailureCode): PersonalCodecFailure { return Object.freeze({ _tag: "PersonalCodecFailure", code }); }
const rejected = new WeakMap<object, PersonalFailureCode>();
function reject(code: PersonalFailureCode = "unsupported_shape"): never { const marker = Object.freeze({}); rejected.set(marker, code); throw marker; }
type Node = { kind: "string"; start: number; end: number } | { kind: "number"; token: string }
  | { kind: "boolean"; value: boolean } | { kind: "null" } | { kind: "array"; items: Node[] }
  | { kind: "object"; fields: Map<string, Node> };
const RECORD_LIMIT = 65536;
/** Count UTF-8 without a host TextEncoder or a precision/coercion callback. */
function byteLength(text: string): number {
  let size = 0;
  for (let i = 0; i < text.length; i++) {
    const c = text.charCodeAt(i);
    if (c === 0) reject();
    if (c >= 0xd800 && c <= 0xdbff) {
      const next = text.charCodeAt(++i);
      if (!(next >= 0xdc00 && next <= 0xdfff)) reject();
      size += 4;
    } else if (c >= 0xdc00 && c <= 0xdfff) reject();
    else size += c < 0x80 ? 1 : c < 0x800 ? 2 : 3;
    if (size > RECORD_LIMIT) reject("candidate_limit_exceeded");
  }
  return size;
}
/** String tokens stay spans: in particular a title is not decoded before host authority. */
class Parser {
  private position = 0;
  private nodes = 0;
  text = "";
  private white(): void { while (/[ \t\r\n]/.test(this.text[this.position] ?? "x")) this.position++; }
  private string(): Node {
    const start = this.position++;
    let high = false;
    while (this.position < this.text.length) {
      let c = this.text.charCodeAt(this.position++);
      if (c === 34) { if (high) reject(); return { kind: "string", start, end: this.position }; }
      if (c < 32) reject();
      if (c === 92) {
        const escape = this.text[this.position++];
        if (escape === "u") {
          const digits = this.text.slice(this.position, this.position + 4);
          if (!/^[a-fA-F0-9]{4}$/.test(digits)) reject();
          c = Number.parseInt(digits, 16); this.position += 4;
        } else {
          if (!escape || !'"\\/bfnrt'.includes(escape)) reject();
          if (high) reject();
          continue;
        }
      }
      if (c === 0) reject();
      if (high) { if (c < 0xdc00 || c > 0xdfff) reject(); high = false; }
      else if (c >= 0xd800 && c <= 0xdbff) high = true;
      else if (c >= 0xdc00 && c <= 0xdfff) reject();
    }
    return reject();
  }
  private value(depth: number): Node {
    if (depth > 32 || ++this.nodes > 4096) reject("candidate_limit_exceeded");
    this.white();
    const c = this.text[this.position];
    if (c === '"') return this.string();
    if (c === "{") {
      this.position++; this.white(); const fields = new Map<string, Node>();
      if (this.text[this.position] === "}") { this.position++; return { kind: "object", fields }; }
      for (;;) {
        if (this.text[this.position] !== '"') reject();
        const key = this.string(); const name = this.stringValue(key);
        if (fields.has(name)) reject();
        this.white(); if (this.text[this.position++] !== ":") reject();
        fields.set(name, this.value(depth + 1)); this.white();
        const end = this.text[this.position++];
        if (end === "}") break;
        if (end !== ",") reject();
        this.white();
      }
      return { kind: "object", fields };
    }
    if (c === "[") {
      this.position++; this.white(); const items: Node[] = [];
      if (this.text[this.position] === "]") { this.position++; return { kind: "array", items }; }
      for (;;) {
        items.push(this.value(depth + 1)); this.white(); const end = this.text[this.position++];
        if (end === "]") break;
        if (end !== ",") reject();
      }
      return { kind: "array", items };
    }
    for (const [token, node] of [["true", { kind: "boolean", value: true }], ["false", { kind: "boolean", value: false }], ["null", { kind: "null" }]] as const) {
      if (this.text.startsWith(token, this.position)) { this.position += token.length; return node; }
    }
    const start = this.position;
    while (this.position < this.text.length && !/[ \t\r\n,}\]]/.test(this.text[this.position]!)) this.position++;
    const token = this.text.slice(start, this.position);
    if (!/^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$/.test(token)) reject();
    return { kind: "number", token };
  }
  parse(): Node { const node = this.value(0); this.white(); if (this.position !== this.text.length) reject(); return node; }
  stringValue(node: Node): string {
    if (node.kind !== "string") reject();
    // Only this isolated, already scalar-validated primitive string token uses JSON.parse.
    return JSON.parse(this.text.slice(node.start, node.end)) as string;
  }
  materialize(node: Node): Json {
    if (node.kind === "string") return this.stringValue(node);
    if (node.kind === "number") return Number(node.token); // All admitted number nodes were lexically validated integers.
    if (node.kind === "boolean") return node.value;
    if (node.kind === "null") return null;
    if (node.kind === "array") return Object.freeze(node.items.map((n) => this.materialize(n)));
    const value: Record<string, Json> = Object.create(null) as Record<string, Json>;
    for (const [key, field] of node.fields) value[key] = this.materialize(field);
    return Object.freeze(value);
  }
}
type Rational = { numerator: bigint; denominator: bigint };
function compare(a: Rational, b: Rational): number {
  const d = a.numerator * b.denominator - b.numerator * a.denominator; return d < 0n ? -1 : d > 0n ? 1 : 0;
}
function difference(a: Rational, b: Rational): Rational {
  return { numerator: a.numerator * b.denominator - b.numerator * a.denominator, denominator: a.denominator * b.denominator };
}
function integer(value: string, kind: "epoch" | "ordinal" | "signed" | "unsigned"): bigint {
  const out = decodeCanonicalInteger(value, kind); if (Result.isFailure(out)) reject("invalid_exact_value"); return out.success;
}
function binary(bits: string): Rational {
  if (!/^[0-9a-f]{16}$/.test(bits)) reject("invalid_exact_value");
  const raw = BigInt("0x" + bits); const e = Number((raw >> 52n) & 2047n);
  if (e === 2047) reject("invalid_exact_value");
  const fraction = raw & ((1n << 52n) - 1n); const magnitude = e === 0 ? fraction : (1n << 52n) + fraction;
  const shift = e === 0 ? -1074 : e - 1023 - 52;
  const signed = raw >> 63n ? -magnitude : magnitude;
  return shift >= 0 ? { numerator: signed << BigInt(shift), denominator: 1n } : { numerator: signed, denominator: 1n << BigInt(-shift) };
}
const ZERO: Rational = { numerator: 0n, denominator: 1n };
const fixedReasons = new Set(["not_reported", "withheld", "no_title_grant", "detail_excluded", "detail_unadmitted",
  "not_observed", "excluded", "source_policy_unavailable", "native_invalid_accuracy", "native_invalid_speed",
  "denied", "locked", "expired", "retention_loss", "unknown"]);
class Validator {
  parser = new Parser();
  object(node: Node, keys: readonly string[]): Map<string, Node> {
    if (node.kind !== "object" || node.fields.size !== keys.length || keys.some((k) => !node.fields.has(k))) reject(); return node.fields;
  }
  field(fields: Map<string, Node>, key: string): Node { return fields.get(key) ?? reject(); }
  string(node: Node, nonempty = true): string { const value = this.parser.stringValue(node); if (nonempty && value.length === 0) reject(); return value; }
  literal(node: Node, allowed: readonly string[]): string { const s = this.string(node); if (!allowed.includes(s)) reject(); return s; }
  bool(node: Node, required?: boolean): void { if (node.kind !== "boolean" || (required !== undefined && node.value !== required)) reject(); }
  numeric(node: Node, low: number, high: number, maxLength: number, code: PersonalFailureCode = "invalid_exact_value"): number {
    if (node.kind !== "number" || node.token.length > maxLength || !/^(?:0|-?[1-9][0-9]*)$/.test(node.token)) reject(code);
    const exact = BigInt(node.token); if (exact < BigInt(low) || exact > BigInt(high)) reject(code); return Number(exact);
  }
  empty(node: Node): void { if (node.kind !== "array" || node.items.length !== 0) reject(); }
  metadata(node: Node, known: (n: Node) => void = (n) => { this.string(n); }, absent = true): void {
    if (node.kind !== "object") reject(); const state = this.string(this.field(node.fields, "state"));
    if (state === "known") { const f = this.object(node, ["state", "value"]); known(this.field(f, "value")); }
    else if (state === "unknown" || (absent && state === "absent")) {
      const f = this.object(node, ["state", "reason"]); if (!fixedReasons.has(this.string(this.field(f, "reason")))) reject();
    } else reject();
  }
  civil(node: Node): void {
    const s = this.string(node); if (!/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(s)) reject("invalid_exact_value");
    const y = Number(s.slice(0, 4)), m = Number(s.slice(5, 7)), d = Number(s.slice(8));
    const leap = y % 4 === 0 && (y % 100 !== 0 || y % 400 === 0);
    const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    if (y < 1 || m < 1 || m > 12 || d < 1 || d > days[m - 1]!) reject("invalid_exact_value");
  }
  instant(node: Node): Rational {
    if (node.kind !== "object") reject();
    const rep = this.string(this.field(node.fields, "representation"));
    let value: Rational;
    if (rep === "seconds_nanos") {
      const f = this.object(node, ["representation", "epoch", "epoch_seconds", "nanoseconds", "source_resolution", "uncertainty"]);
      this.literal(this.field(f, "epoch"), ["unix"]);
      const sec = integer(this.string(this.field(f, "epoch_seconds")), "epoch");
      const ns = this.numeric(this.field(f, "nanoseconds"), 0, 999999999, 9);
      this.literal(this.field(f, "source_resolution"), ["nanosecond_representation_not_accuracy"]);
      value = { numerator: sec * 1000000000n + BigInt(ns), denominator: 1000000000n };
    } else if (rep === "binary64_epoch_seconds") {
      const f = this.object(node, ["representation", "epoch", "bits", "source_resolution", "uncertainty"]);
      const epoch = this.literal(this.field(f, "epoch"), ["unix", "apple_reference_2001"]);
      value = binary(this.string(this.field(f, "bits")));
      if (epoch === "apple_reference_2001") value = { numerator: value.numerator + 978307200n * value.denominator, denominator: value.denominator };
      this.literal(this.field(f, "source_resolution"), ["binary64_storage"]);
    } else return reject();
    this.metadata(this.field(node.fields, "uncertainty")); return value;
  }
  calendar(node: Node, bucket = false): void {
    const f = this.object(node, ["time_zone", "owner_date", "owner_rule"]);
    this.metadata(this.field(f, "time_zone")); this.metadata(this.field(f, "owner_date"), (n) => this.civil(n));
    if (bucket) this.literal(this.field(f, "owner_rule"), ["synthetic_source_bucket"]); else this.metadata(this.field(f, "owner_rule"));
  }
  scalar(node: Node, unit: string, onlyBinary = false): Rational {
    if (node.kind !== "object") reject(); const rep = this.string(this.field(node.fields, "representation"));
    if (rep === "binary64") {
      const f = this.object(node, ["representation", "bits", "unit"]); this.literal(this.field(f, "unit"), [unit]); return binary(this.string(this.field(f, "bits")));
    }
    if (!onlyBinary && (rep === "signed_integer" || rep === "unsigned_integer")) {
      const f = this.object(node, ["representation", "decimal", "unit"]); this.literal(this.field(f, "unit"), [unit]);
      return { numerator: integer(this.string(this.field(f, "decimal")), rep === "signed_integer" ? "signed" : "unsigned"), denominator: 1n };
    }
    return reject();
  }
  sensor(node: Node, unit: string, negativeCode?: PersonalFailureCode): void {
    if (node.kind !== "object") reject(); const state = this.string(this.field(node.fields, "state"));
    if (state === "absent") { this.object(node, ["state"]); return; }
    if (state === "unavailable" && negativeCode) { const f = this.object(node, ["state", "reason"]); this.literal(this.field(f, "reason"), [negativeCode]); return; }
    const f = this.object(node, ["state", "value"]); if (state !== "known") reject();
    const value = this.scalar(this.field(f, "value"), unit, true); if (negativeCode && compare(value, ZERO) < 0) reject(negativeCode);
  }
  app(node: Node): { identity: Node; appClass: string } {
    const f = this.object(node, ["identity", "identity_kind", "app_class", "display_label"]);
    this.metadata(this.field(f, "identity")); this.literal(this.field(f, "identity_kind"), ["synthetic_application_id"]);
    const appClass = this.literal(this.field(f, "app_class"), ["browser", "non_browser", "unknown"]);
    this.metadata(this.field(f, "display_label")); return { identity: this.field(f, "identity"), appClass };
  }
  validate(root: Node): PersonalAuthorizationDescriptor {
    const f = this.object(root, ["domain", "payload_kind", "payload_revision", "record_id", "lineage", "time", "payload"]);
    this.numeric(this.field(f, "payload_revision"), 1, 1, 1, "unsupported_shape");
    const domain = this.literal(this.field(f, "domain"), ["health", "location", "device_usage"]);
    const kind = this.literal(this.field(f, "payload_kind"), ["health_fact", "location_point", "usage_aggregate", "foreground_app_session"]);
    if (domain !== (kind === "health_fact" ? "health" : kind === "location_point" ? "location" : "device_usage")) reject();
    const id = this.string(this.field(f, "record_id"));
    const lineageNode = this.field(f, "lineage");
    const l = this.object(lineageNode, ["dataset_id", "device", "installation", "source_id", "source_revision", "purpose", "original_record", "record_revision", "acquisition", "source_observation", "integrity_binding"]);
    for (const key of ["dataset_id", "source_id", "source_revision", "purpose"]) this.string(this.field(l, key));
    for (const key of ["device", "installation", "original_record", "source_observation"]) this.metadata(this.field(l, key));
    integer(this.string(this.field(l, "record_revision")), "ordinal");
    this.literal(this.field(l, "acquisition"), ["synthetic_fixture"]); this.literal(this.field(l, "integrity_binding"), ["fixture_only_not_authentication"]);
    const time = this.object(this.field(f, "time"), ["instant", "source_utc_offset_seconds", "calendar", "observed_at", "captured_at", "imported_at", "uploaded_at"]);
    this.instant(this.field(time, "instant")); this.metadata(this.field(time, "source_utc_offset_seconds"), (n) => { this.numeric(n, -86400, 86400, 6); });
    this.calendar(this.field(time, "calendar"));
    for (const key of ["observed_at", "captured_at", "imported_at", "uploaded_at"]) this.metadata(this.field(time, key), (n) => { this.instant(n); });
    const boundaries: Json[] = [this.parser.materialize(this.field(time, "instant"))];
    let appIdentity: Json = null, appClass: string | null = null; const details: string[] = [];
    const p = this.field(f, "payload");
    if (kind === "health_fact") {
      const h = this.object(p, ["semantic_id", "native_semantic_id", "statistic", "value", "native_profile", "extensions"]);
      if (!this.string(this.field(h, "semantic_id")).startsWith("synthetic.health.")) reject();
      this.metadata(this.field(h, "native_semantic_id")); this.literal(this.field(h, "statistic"), ["observation"]);
      this.scalar(this.field(h, "value"), "count"); this.literal(this.field(h, "native_profile"), ["synthetic_only_not_metric_registry_admission"]); this.empty(this.field(h, "extensions"));
      details.push("health_fact");
    } else if (kind === "location_point") {
      const h = this.object(p, ["latitude", "longitude", "horizontal_accuracy", "altitude", "speed", "quality", "recording_session"]);
      for (const [key, bound] of [["latitude", 90n], ["longitude", 180n]] as const) {
        const v = this.scalar(this.field(h, key), "degree", true);
        if (compare(v, { numerator: -bound, denominator: 1n }) < 0 || compare(v, { numerator: bound, denominator: 1n }) > 0) reject("coordinate_out_of_range");
      }
      const accuracy = this.field(h, "horizontal_accuracy");
      if (accuracy.kind === "object" && accuracy.fields.has("state")) {
        const af = this.object(accuracy, ["state", "reason"]);
        this.literal(this.field(af, "state"), ["unavailable"]); this.literal(this.field(af, "reason"), ["native_invalid_accuracy"]);
      }
      else if (compare(this.scalar(accuracy, "meter", true), ZERO) < 0) reject("native_invalid_accuracy");
      this.sensor(this.field(h, "altitude"), "meter"); this.sensor(this.field(h, "speed"), "meter_per_second", "native_invalid_speed");
      const q = this.object(this.field(h, "quality"), ["source_is_outlier", "certainty"]); this.bool(this.field(q, "source_is_outlier")); this.metadata(this.field(q, "certainty"));
      this.metadata(this.field(h, "recording_session")); details.push("location_exact_point");
    } else if (kind === "usage_aggregate") {
      const h = this.object(p, ["app", "bucket", "statistic", "duration", "resolution", "source_device_scope", "observed_session_count", "original_source_precision", "overlap_group", "derived"]);
      const app = this.app(this.field(h, "app")); appIdentity = this.parser.materialize(app.identity); appClass = app.appClass;
      const b = this.object(this.field(h, "bucket"), ["start", "end", "boundaries", "calendar"]);
      const start = this.instant(this.field(b, "start")), end = this.instant(this.field(b, "end"));
      if (compare(start, end) >= 0) reject("invalid_bucket");
      this.literal(this.field(b, "boundaries"), ["half_open"]); this.calendar(this.field(b, "calendar"), true);
      this.literal(this.field(h, "statistic"), ["source_total_duration"]);
      const duration = this.scalar(this.field(h, "duration"), "second", true);
      if (compare(duration, ZERO) < 0) reject("invalid_exact_value");
      if (compare(duration, difference(end, start)) > 0) reject("duration_outside_bucket");
      this.literal(this.field(h, "resolution"), ["hourly_bucket"]); this.literal(this.field(h, "source_device_scope"), ["one_synthetic_device"]);
      this.metadata(this.field(h, "observed_session_count"), (n) => { integer(this.string(n), "ordinal"); });
      this.metadata(this.field(h, "original_source_precision")); this.metadata(this.field(h, "overlap_group")); this.bool(this.field(h, "derived"), false);
      boundaries.push(this.parser.materialize(this.field(b, "start")), this.parser.materialize(this.field(b, "end"))); details.push("app_duration");
    } else {
      const h = this.object(p, ["app", "start", "end", "duration", "duration_basis", "observation_intervals", "title", "device_state"]);
      const app = this.app(this.field(h, "app")); appIdentity = this.parser.materialize(app.identity); appClass = app.appClass;
      const startFields = this.object(this.field(h, "start"), ["instant", "certainty"]), endFields = this.object(this.field(h, "end"), ["instant", "certainty"]);
      const start = this.instant(this.field(startFields, "instant")), end = this.instant(this.field(endFields, "instant"));
      this.literal(this.field(startFields, "certainty"), ["observed"]); this.literal(this.field(endFields, "certainty"), ["observed"]);
      const duration = this.scalar(this.field(h, "duration"), "second", true); this.literal(this.field(h, "duration_basis"), ["synthetic_observation"]);
      if (compare(start, end) > 0 || compare(duration, ZERO) < 0 || compare(duration, difference(end, start)) !== 0) reject("clock_inconsistent");
      this.empty(this.field(h, "observation_intervals")); this.metadata(this.field(h, "device_state"));
      const title = this.field(h, "title"); if (title.kind !== "object") reject(); const state = this.string(this.field(title.fields, "state"));
      if (state === "known" || state === "empty") {
        const tf = this.object(title, ["state", "value"]); const v = this.field(tf, "value"); if (v.kind !== "string") reject();
        // Determine empty from token span without decoding title text.
        const empty = v.end - v.start === 2; if ((state === "empty") !== empty) reject(); details.push("desktop_window_title");
      } else if (["unknown", "not_observed", "withheld", "excluded"].includes(state)) {
        const tf = this.object(title, ["state", "reason"]); if (!fixedReasons.has(this.string(this.field(tf, "reason")))) reject();
      } else reject();
      boundaries.push(this.parser.materialize(this.field(startFields, "instant")), this.parser.materialize(this.field(endFields, "instant"))); details.push("app_duration");
    }
    return Object.freeze({ lineage: this.parser.materialize(lineageNode) as Readonly<Record<string, Json>>, record_id: id, domain, payload_kind: kind,
      boundaries: Object.freeze(boundaries), app_identity: appIdentity, claimed_app_class: appClass, requested_detail: Object.freeze(details) });
  }
}
function scalarOrder(a: string, b: string): number {
  const left = Array.from(a), right = Array.from(b);
  for (let i = 0; i < Math.min(left.length, right.length); i++) {
    const d = left[i]!.codePointAt(0)! - right[i]!.codePointAt(0)!; if (d !== 0) return d;
  }
  return left.length - right.length;
}
function canonical(value: Json): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return "[" + value.map(canonical).join(",") + "]";
  const object = value as Readonly<Record<string, Json>>;
  return "{" + Object.keys(object).sort(scalarOrder).map((k) => JSON.stringify(k) + ":" + canonical(object[k]!)).join(",") + "}";
}
export function createPersonalRecordCodec(context: TrustedPersonalCodecContext): {
  readonly decode: (input: unknown) => Outcome<OwnedPersonalRecord>;
  readonly encode: (input: unknown) => Outcome<string>;
} {
  const records = new WeakMap<object, { descriptor: PersonalAuthorizationDescriptor; json: Json }>();
  function authorize(descriptor: PersonalAuthorizationDescriptor): void {
    try {
      const current = context.authorize(descriptor);
      if (!current.permitted || typeof current.authority_binding !== "string" || !current.authority_binding
        || typeof current.frontier_binding !== "string" || !current.frontier_binding) reject("scope_not_authorized");
      if (descriptor.claimed_app_class !== null && current.app_class !== descriptor.claimed_app_class) reject("scope_not_authorized");
      if (descriptor.requested_detail.includes("desktop_window_title") && (current.app_class !== "non_browser" || !current.title_permitted)) reject("scope_not_authorized");
    } catch { reject("scope_not_authorized"); }
  }
  function run<A>(fn: () => A): Outcome<A> {
    try { return Result.succeed(fn()); } catch (error) { return Result.fail(failure(typeof error === "object" && error !== null ? rejected.get(error) ?? "unsupported_shape" : "unsupported_shape")); }
  }
  return Object.freeze({
    decode(input: unknown): Outcome<OwnedPersonalRecord> {
      return run(() => {
        if (typeof input !== "string") reject();
        // UTF-16 length is a cheap allocation bound before UTF-8 scalar scanning/token work.
        if (input.length > RECORD_LIMIT) reject("candidate_limit_exceeded"); byteLength(input);
        const parser = new Parser(); parser.text = input; const node = parser.parse(); const validator = new Validator(); validator.parser = parser; const descriptor = validator.validate(node);
        authorize(descriptor);
        const json = parser.materialize(node); const record = json as OwnedPersonalRecord;
        records.set(record, { descriptor, json }); return record;
      });
    },
    encode(input: unknown): Outcome<string> {
      return run(() => {
        if ((typeof input !== "object" && typeof input !== "function") || input === null) reject();
        // WeakMap lookup touches neither proxies nor getters, including revoked proxies.
        const entry = records.get(input); if (!entry) reject(); authorize(entry.descriptor);
        const text = canonical(entry.json); byteLength(text); return text;
      });
    },
  });
}
