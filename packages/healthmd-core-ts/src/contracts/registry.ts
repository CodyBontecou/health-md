import * as Schema from "effect/Schema";
import * as Result from "effect/Result";

export const registryExpectedSha256 = "56def644baa3d81e0c6c2eda3733bfdd7ceee6554ca9ec609da80356c6578c99";
export interface RegistryFailure { readonly _tag: "RegistryFailure"; readonly code: "invalid_registry" | "unsupported_registry_version" | "unsupported_registry_profile"; }
export type RegistryResult<A> = Result.Result<A, RegistryFailure>;
const fail = (code: RegistryFailure["code"]): RegistryResult<never> => Result.fail(Object.freeze({ _tag: "RegistryFailure", code }));
const S = Schema.String;
const U = Schema.Number;
const strings = Schema.Array(S);
const optionalString = Schema.optionalKey(Schema.NullOr(S));
const optionalBool = Schema.optionalKey(Schema.NullOr(Schema.Boolean));
const AppleOutput = Schema.Struct({ key: S, unit: S, daily_aggregation: S, rollup: S });
const Binding = Schema.Struct({
  status: S, ordinal: Schema.optionalKey(Schema.NullOr(U)), selection_id: optionalString,
  label_key: optionalString, reference_name: optionalString, category_id: optionalString,
  unit: optionalString, kind: optionalString, source_aggregation: optionalString,
  archive_only: optionalBool, default_enabled: optionalBool, availability_key: optionalString,
  source_selector: optionalString, authorization_key: optionalString,
  outputs: Schema.optionalKey(Schema.Array(AppleOutput)), related_semantic_ids: Schema.optionalKey(strings),
  reason_key: optionalString, picker_visibility: optionalString,
});
const Metric = Schema.Struct({ semantic_id: S, reference_name: S, capability_id: S, equivalence: S, apple: Binding, android: Binding });
const Category = Schema.Struct({ platform: S, category_id: S, label_key: S, ordinal: U });
const Output = Schema.Struct({
  selection_id: optionalString, selection_ids: Schema.optionalKey(strings), surface: S, key: S,
  unit: Schema.optionalKey(S), daily_aggregation: Schema.optionalKey(S), rollup: Schema.optionalKey(S),
  alias_kind: Schema.optionalKey(S), platform_native: Schema.optionalKey(Schema.Boolean),
  condition: Schema.optionalKey(S), enabled_by_default: Schema.optionalKey(Schema.Boolean),
});
const Profile = Schema.Struct({
  id: S, public_profile_id: S, public_schema: S, public_schema_version: U, profile_revision: U,
  platform: S, ordered_selection_ids: strings, outputs: Schema.Array(Output), unavailable_selection_ids: strings,
});
const Unavailable = Schema.Struct({ selection_id: S, label_key: S, category_id: S, reference_name: S, reason: S, reason_key: S });
const RegistryShape = Schema.Struct({
  schema: S, schema_version: U, registry_version: U, known_capability_ids: strings,
  available_capability_ids_by_platform: Schema.Struct({ apple: strings, android: strings }),
  categories: Schema.Array(Category), metrics: Schema.Array(Metric), profiles: Schema.Array(Profile),
  legacy_unavailable: Schema.Struct({ android: Schema.Array(Unavailable) }),
});
type Registry = Schema.Schema.Type<typeof RegistryShape>;
type MetricRow = Schema.Schema.Type<typeof Metric>;
type BindingRow = Schema.Schema.Type<typeof Binding>;
type ProfileRow = Schema.Schema.Type<typeof Profile>;
type OutputRow = Schema.Schema.Type<typeof Output>;
type Platform = "apple" | "android";
const decode = Schema.decodeUnknownResult(RegistryShape, { onExcessProperty: "error" });
function requireValid(value: unknown): asserts value { if (!value) throw new Error("invalid_registry"); }
function present<A>(value: A | null | undefined): A { requireValid(value != null); return value; }
const u32 = (value: number): boolean => Number.isInteger(value) && value >= 0 && value <= 4294967295;
function unique(values: readonly string[]): Set<string> {
  const result = new Set(values); requireValid(result.size === values.length && !result.has("")); return result;
}
function outputSelectors(value: OutputRow): readonly string[] {
  const many = value.selection_ids ?? [];
  if (value.selection_id != null) { requireValid(value.selection_id !== "" && many.length === 0); return [value.selection_id]; }
  requireValid(many.length > 0 && many.every((id) => id !== "")); return many;
}
function outputDefaults(value: OutputRow) {
  return { selection_ids: outputSelectors(value), surface: value.surface, key: value.key,
    unit: value.unit ?? "", daily_aggregation: value.daily_aggregation ?? "", rollup: value.rollup ?? "",
    alias_kind: value.alias_kind ?? "none", platform_native: value.platform_native ?? false,
    condition: value.condition ?? "default", enabled_by_default: value.enabled_by_default ?? true };
}
function platformSelections(value: Registry, platform: Platform, ids: Set<string>): Map<string, MetricRow> {
  const selections = new Map<string, MetricRow>(); const ordinals = new Set<number>();
  const aggregations = platform === "apple" ? ["cumulative", "discreteAvg", "discreteMin", "discreteMax", "mostRecent", "duration", "count"] : ["sum", "average", "minimum", "maximum", "latest", "record_projection"];
  for (const metric of value.metrics) {
    const binding = metric[platform];
    requireValid(binding.ordinal == null || u32(binding.ordinal));
    requireValid(binding.status === "backed" || binding.status === "unavailable");
    if (binding.status === "unavailable") {
      requireValid(binding.selection_id == null && binding.ordinal == null && ["hidden", "listed"].includes(present(binding.picker_visibility)) && present(binding.reason_key) !== "");
      continue;
    }
    const id = present(binding.selection_id); const ordinal = present(binding.ordinal);
    requireValid(!selections.has(id) && !ordinals.has(ordinal) && present(binding.label_key) !== "" && present(binding.category_id) !== "");
    present(binding.unit);
    requireValid(aggregations.includes(present(binding.source_aggregation)) && present(binding.availability_key) !== "");
    present(binding.default_enabled);
    requireValid((binding.related_semantic_ids ?? []).every((related) => related !== metric.semantic_id && ids.has(related)));
    if (platform === "apple") {
      requireValid(present(binding.kind) !== "" && present(binding.source_selector) !== "" && present(binding.authorization_key) !== "");
      const archive = present(binding.archive_only); requireValid(archive ? (binding.outputs ?? []).length === 0 : (binding.outputs ?? []).length > 0);
    }
    selections.set(id, metric); ordinals.add(ordinal);
  }
  requireValid([...ordinals].every((ordinal) => ordinal < selections.size) && ordinals.size === selections.size);
  return selections;
}
function validate(value: Registry): void {
  requireValid(value.schema === "healthmd.metric_registry" && value.schema_version === 1 && value.registry_version === 1 && value.profiles.length === 3 && value.known_capability_ids.length > 0);
  const capabilities = unique(value.known_capability_ids); const ids = unique(value.metrics.map((m) => m.semantic_id));
  const available = { apple: unique(value.available_capability_ids_by_platform.apple), android: unique(value.available_capability_ids_by_platform.android) };
  for (const platform of ["apple", "android"] as const) {
    requireValid([...available[platform]].every((id) => capabilities.has(id)));
    requireValid(value.metrics.every((m) => capabilities.has(m.capability_id) && (m[platform].status !== "backed" || available[platform].has(m.capability_id))));
  }
  const next = { apple: 0, android: 0 }; const categories = new Set<string>();
  for (const c of value.categories) {
    requireValid(c.platform === "apple" || c.platform === "android"); const key = JSON.stringify([c.platform, c.category_id]);
    requireValid(c.category_id !== "" && c.label_key !== "" && !categories.has(key) && u32(c.ordinal) && c.ordinal === next[c.platform]);
    categories.add(key); next[c.platform]++;
  }
  requireValid(next.apple === 21 && next.android === 12);
  const selections = { apple: platformSelections(value, "apple", ids), android: platformSelections(value, "android", ids) };
  requireValid(selections.apple.size === 230 && selections.android.size === 106);
  const profiles = unique(value.profiles.map((p) => p.id));
  requireValid(["apple_health_data_v8", "android_frozen_v4", "android_analytical_v5"].every((id) => profiles.has(id)));
  for (const p of value.profiles) {
    requireValid(p.platform === "apple" || p.platform === "android"); const selected = selections[p.platform];
    requireValid(p.public_profile_id !== "" && p.public_schema === "healthmd.health_data" && u32(p.public_schema_version) && u32(p.profile_revision) && p.profile_revision > 0 && p.ordered_selection_ids.length === selected.size);
    requireValid(p.ordered_selection_ids.every((id, ordinal) => selected.get(id)?.[p.platform as Platform].ordinal === ordinal));
    const unavailable = unique(p.unavailable_selection_ids);
    requireValid((p.platform !== "apple" || unavailable.size === 0) && [...unavailable].every((id) => !selected.has(id)));
    const paths = new Set<string>();
    for (const raw of p.outputs) {
      const o = outputDefaults(raw); const key = JSON.stringify([o.surface, o.key]);
      requireValid(o.surface !== "" && o.key !== "" && !paths.has(key) && o.selection_ids.every((id) => selected.has(id)));
      requireValid(["none", "legacy_android"].includes(o.alias_kind) && ["default", "legacy_alias_opt_in", "android_native_opt_in"].includes(o.condition));
      requireValid(o.alias_kind !== "legacy_android" || (o.condition === "legacy_alias_opt_in" && !o.enabled_by_default));
      requireValid(o.condition !== "default" || o.enabled_by_default);
      if (p.platform === "apple") requireValid(o.unit !== "" && o.daily_aggregation !== "" && o.rollup !== "" && !o.platform_native && o.alias_kind === "none");
      paths.add(key);
    }
  }
  const unavailable = unique(value.legacy_unavailable.android.map((m) => m.selection_id));
  requireValid(unavailable.size === 102 && [...unavailable].every((id) => !selections.android.has(id)));
  requireValid(value.legacy_unavailable.android.every((m) => [m.label_key, m.category_id, m.reference_name, m.reason, m.reason_key].every((s) => s !== "")));
}
function project(value: Registry, profile: ProfileRow) {
  const platform = profile.platform as Platform; const byId = new Map<string, { metric: MetricRow; binding: BindingRow }>();
  for (const metric of value.metrics) { const binding = metric[platform]; if (binding.status === "backed") byId.set(present(binding.selection_id), { metric, binding }); }
  const unavailable = new Map(value.legacy_unavailable.android.map((m) => [m.selection_id, m]));
  return {
    registry_version: value.registry_version, registry_sha256: registryExpectedSha256, profile_id: profile.id,
    public_profile_id: profile.public_profile_id, public_schema: profile.public_schema,
    public_schema_version: profile.public_schema_version, profile_revision: profile.profile_revision,
    categories: value.categories.filter((c) => c.platform === platform).map(({ category_id, label_key, ordinal }) => ({ category_id, label_key, ordinal })),
    metrics: profile.ordered_selection_ids.map((selection_id) => {
      const { metric: m, binding: b } = present(byId.get(selection_id));
      return { semantic_id: m.semantic_id, selection_id, label_key: present(b.label_key), reference_name: b.reference_name ?? m.reference_name,
        category_id: present(b.category_id), unit: present(b.unit), kind: b.kind ?? "summary", source_aggregation: present(b.source_aggregation),
        default_enabled: present(b.default_enabled), archive_only: b.archive_only ?? false, availability_key: present(b.availability_key),
        authorization_key: b.authorization_key ?? "native", capability_id: m.capability_id, source_selector: b.source_selector ?? selection_id,
        related_semantic_ids: b.related_semantic_ids ?? [], ordinal: present(b.ordinal) };
    }),
    unavailable_metrics: profile.unavailable_selection_ids.map((selection_id) => { const m = present(unavailable.get(selection_id)); return { selection_id, category_id: m.category_id, label_key: m.label_key, reason_key: m.reason_key }; }),
    outputs: profile.outputs.map((o, ordinal) => ({ ...outputDefaults(o), ordinal })),
  };
}
export type RegistrySnapshot = ReturnType<typeof project>;
export interface RegistryReader {
  readonly authority: { readonly expected_sha256: string; readonly byte_binding: "requires_reviewed_host_binding" };
  readonly profileIds: readonly string[];
  readonly semanticRows: readonly MetricRow[];
  readonly snapshot: (profileId: string, expectedVersion?: number) => RegistryResult<RegistrySnapshot>;
  readonly selection: (profileId: string, selectionId: string) => RegistryResult<{ readonly state: "backed"; readonly metric: RegistrySnapshot["metrics"][number] } | { readonly state: "unavailable"; readonly metric: RegistrySnapshot["unavailable_metrics"][number] } | { readonly state: "unsupported" }>;
}
function freezeDeep<A>(value: A): A {
  if (typeof value === "object" && value !== null) { for (const child of Object.values(value)) freezeDeep(child); Object.freeze(value); } return value;
}
function validUnicode(value: string): boolean {
  // Iteration combines valid pairs; any remaining surrogate is malformed Unicode.
  for (const character of value) { const point = character.codePointAt(0)!; if (point >= 0xd800 && point <= 0xdfff) return false; }
  return true;
}
function sorted(value: unknown, depth = 0, budget = { nodes: 100000 }): unknown {
  requireValid(depth <= 32 && --budget.nodes >= 0);
  if (typeof value === "string") requireValid(validUnicode(value));
  if (Array.isArray(value)) return value.map((child: unknown) => sorted(child, depth + 1, budget));
  if (typeof value === "object" && value !== null) {
    return Object.fromEntries(Object.entries(value).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0).map(([key, child]) => { requireValid(validUnicode(key)); return [key, sorted(child, depth + 1, budget)]; }));
  }
  return value;
}
function utf8Size(text: string): number {
  let size = 0;
  for (const character of text) { const point = character.codePointAt(0)!; size += point <= 127 ? 1 : point <= 2047 ? 2 : point <= 65535 ? 3 : 4; }
  return size;
}
/** Reviewed static text only. The caller's build must bind exact bytes to expected_sha256.
 * This structural reader performs no hash verification and has no supplied-digest parameter.
 * Local 1MiB/32-depth/100000-node admission budgets are candidate safeguards, not a public revision.
 * Snapshots carry the expected authority pin under that precondition; they do not authenticate input.
 */
export function readReviewedRegistry(text: unknown, expectedVersion = 1): RegistryResult<RegistryReader> {
  if (expectedVersion !== 1) return fail("unsupported_registry_version");
  try {
    requireValid(typeof text === "string" && text.length <= 1048576 && validUnicode(text) && utf8Size(text) <= 1048576);
    const raw: unknown = JSON.parse(text); const canonical = sorted(raw);
    requireValid(JSON.stringify(canonical, null, 2) + "\n" === text);
    const decoded = decode(raw); if (Result.isFailure(decoded)) return fail("invalid_registry");
    const value = decoded.success; validate(value); freezeDeep(value);
    const snapshots = new Map<string, RegistrySnapshot>();
    const snapshot: RegistryReader["snapshot"] = (id, version = 1) => {
      if (version !== 1) return fail("unsupported_registry_version");
      const profile = value.profiles.find((p) => p.id === id); if (!profile) return fail("unsupported_registry_profile");
      try {
        if (!snapshots.has(id)) snapshots.set(id, freezeDeep(project(value, profile)));
        return Result.succeed(snapshots.get(id)!);
      } catch { return fail("invalid_registry"); }
    };
    const selection: RegistryReader["selection"] = (profileId, selectionId) => Result.map(snapshot(profileId), (s) => {
      const metric = s.metrics.find((m) => m.selection_id === selectionId); if (metric) return Object.freeze({ state: "backed" as const, metric });
      const missing = s.unavailable_metrics.find((m) => m.selection_id === selectionId); return missing ? Object.freeze({ state: "unavailable" as const, metric: missing }) : Object.freeze({ state: "unsupported" as const });
    });
    return Result.succeed(Object.freeze({ authority: Object.freeze({ expected_sha256: registryExpectedSha256, byte_binding: "requires_reviewed_host_binding" as const }), profileIds: Object.freeze(value.profiles.map((p) => p.id)), semanticRows: value.metrics, snapshot, selection }));
  } catch { return fail("invalid_registry"); }
}
