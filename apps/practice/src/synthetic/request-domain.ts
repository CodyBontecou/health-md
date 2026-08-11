import {
  SYNTHETIC_ACCEPTANCE_REVIEW_VERSION,
  SYNTHETIC_OPERATION_VERSION,
  type AcceptanceReview,
  type CanonicalRequestRepresentation,
  type InstructionVariables,
  type MaterializedCollectionPeriod,
  type NamedWindow,
  type PracticeInstructionVariantRef,
  type RequestBuilder,
  type RequestPreview,
  type ValidationIssue,
} from "../contracts/clinical";
import { PRACTICE_INSTRUCTION_VERSION, PRACTICE_PROTOCOL_VERSION } from "../contracts/api";

const DATE = /^\d{4}-\d{2}-\d{2}$/;
const TIME = /^(?:[01]\d|2[0-3]):[0-5]\d$/;
const NAME = /^[\p{L}\p{N}][\p{L}\p{N} _-]{0,39}$/u;
const forbiddenMarkup = /<[^>]*>|&(?:#\d+|#x[\da-f]+|[a-z]+);/i;
const forbiddenMarkdown = /(?:\[[^\]]+\]\([^)]*\)|\[[^\]]+\]\[[^\]]*\]|(?:^|\s)[*_`]\S|(?:^|\n)\s*(?:[#>]\s|[-+*]\s+|\d+[.)]\s+|`{3,}|~{3,}|\[[^\]]+\]:\s*\S)|(?:^|\n)[^\n]+\n\s*(?:={3,}|-{3,})\s*(?:\n|$))/m;
const forbiddenLink = /\b(?:https?:\/\/|mailto:|www\.)/i;
const undeclaredVariable = /{{\s*[^}]+\s*}}/;

function issue(code: ValidationIssue["code"], field: string): ValidationIssue { return { code, field }; }
function realDate(value: string): boolean {
  if (!DATE.test(value)) return false;
  const [year, month, day] = value.split("-").map(Number);
  if (year === undefined || month === undefined || day === undefined) return false;
  const parsed = new Date(Date.UTC(year, month - 1, day));
  return parsed.getUTCFullYear() === year && parsed.getUTCMonth() === month - 1 && parsed.getUTCDate() === day;
}
function timeValue(value: string): number { const [h = "0", m = "0"] = value.split(":"); return Number(h) * 60 + Number(m); }

interface ZonedParts { year: number; month: number; day: number; hour: number; minute: number; second: number }
function formatter(timeZone: string): Intl.DateTimeFormat {
  return new Intl.DateTimeFormat("en-CA", { timeZone, calendar: "gregory", numberingSystem: "latn", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit", hourCycle: "h23" });
}
function zonedParts(epoch: number, timeZone: string): ZonedParts {
  const values = Object.fromEntries(formatter(timeZone).formatToParts(new Date(epoch)).filter(part => part.type !== "literal").map(part => [part.type, Number(part.value)]));
  const parts = { year: values.year, month: values.month, day: values.day, hour: values.hour, minute: values.minute, second: values.second };
  if (Object.values(parts).some(value => !Number.isFinite(value))) throw new AcceptanceMaterializationError();
  return parts as ZonedParts;
}
function sameParts(actual: ZonedParts, expected: ZonedParts): boolean {
  return actual.year === expected.year && actual.month === expected.month && actual.day === expected.day && actual.hour === expected.hour && actual.minute === expected.minute && actual.second === expected.second;
}

export function canonicalIanaTimezone(value: string): string {
  if (typeof value !== "string" || value.length < 1 || value.length > 128 || !/^(?:UTC|Etc\/UTC|[A-Za-z0-9._+-]+(?:\/[A-Za-z0-9._+-]+)+)$/.test(value)) throw new AcceptanceMaterializationError();
  try {
    const canonical = new Intl.DateTimeFormat("en", { timeZone: value }).resolvedOptions().timeZone;
    if (!canonical || canonical.length > 128) throw new AcceptanceMaterializationError();
    return canonical;
  } catch { throw new AcceptanceMaterializationError(); }
}

function localMidnightUtc(localDate: string, timeZone: string): string {
  if (!realDate(localDate)) throw new AcceptanceMaterializationError();
  const [year = 0, month = 0, day = 0] = localDate.split("-").map(Number);
  const nominal = Date.UTC(year, month - 1, day);
  const expected: ZonedParts = { year, month, day, hour: 0, minute: 0, second: 0 };
  const offsets = new Set<number>();
  for (const sample of [nominal - 36 * 3_600_000, nominal, nominal + 36 * 3_600_000]) {
    const parts = zonedParts(sample, timeZone);
    offsets.add(Date.UTC(parts.year, parts.month - 1, parts.day, parts.hour, parts.minute, parts.second) - sample);
  }
  const candidates = [...offsets].map(offset => nominal - offset).filter(candidate => sameParts(zonedParts(candidate, timeZone), expected));
  const unique = [...new Set(candidates)];
  const candidate = unique[0];
  if (unique.length !== 1 || candidate === undefined) throw new AcceptanceMaterializationError();
  return new Date(candidate).toISOString();
}

export function materializeCollectionPeriod(builder: RequestBuilder, deviceIanaTimezone: string): MaterializedCollectionPeriod {
  const timezone = canonicalIanaTimezone(deviceIanaTimezone);
  if (builder.period.kind !== "fixed_dates" || !realDate(builder.period.startLocalDate) || !realDate(builder.period.endLocalDateExclusive) || builder.period.startLocalDate >= builder.period.endLocalDateExclusive) throw new AcceptanceMaterializationError();
  const startUtcInclusive = localMidnightUtc(builder.period.startLocalDate, timezone);
  const endUtcExclusive = localMidnightUtc(builder.period.endLocalDateExclusive, timezone);
  if (Date.parse(startUtcInclusive) >= Date.parse(endUtcExclusive)) throw new AcceptanceMaterializationError();
  return Object.freeze({ deviceIanaTimezone: timezone, startLocalDate: builder.period.startLocalDate, endLocalDateExclusive: builder.period.endLocalDateExclusive, startUtcInclusive, endUtcExclusive });
}

export function formatObservationInTimezone(observedAt: string, deviceIanaTimezone: string): string {
  const instant = Date.parse(observedAt); const timezone = canonicalIanaTimezone(deviceIanaTimezone);
  if (!Number.isFinite(instant)) throw new AcceptanceMaterializationError();
  const parts = zonedParts(instant, timezone);
  const two = (value: number) => String(value).padStart(2, "0");
  return `${String(parts.year).padStart(4, "0")}-${two(parts.month)}-${two(parts.day)} ${two(parts.hour)}:${two(parts.minute)}:${two(parts.second)} ${timezone}`;
}

function validateText(value: string | undefined, field: string, issues: ValidationIssue[]): void {
  if (value === undefined) return;
  if (value.length < 1 || value.length > 500) issues.push(issue("text_too_long", field));
  if (forbiddenMarkup.test(value)) issues.push(issue("html_not_allowed", field));
  if (forbiddenMarkdown.test(value)) issues.push(issue("markdown_not_allowed", field));
  if (forbiddenLink.test(value)) issues.push(issue("link_not_allowed", field));
  if (undeclaredVariable.test(value)) issues.push(issue("undeclared_variable", field));
}

function validateWindows(builder: RequestBuilder, issues: ValidationIssue[]): void {
  const windows = builder.schedule.windows;
  const expected = builder.schedule.type === "all_readings" ? 0 : builder.schedule.type === "once_daily" ? 1 : builder.schedule.type === "morning_evening" ? 2 : null;
  if ((expected !== null && windows.length !== expected) || (builder.schedule.type === "custom_windows" && windows.length < 1)) {
    issues.push(issue("window_cardinality_invalid", "schedule.windows"));
  }
  const normalizedNames = new Set<string>();
  const ranges: Array<{ start: number; end: number }> = [];
  for (const [index, window] of windows.entries()) {
    const prefix = `schedule.windows.${index}`;
    const key = window.name.toLocaleLowerCase("en-US");
    if (!NAME.test(window.name) || normalizedNames.has(key)) issues.push(issue("window_name_invalid", `${prefix}.name`));
    normalizedNames.add(key);
    if (!TIME.test(window.startLocalTime) || !TIME.test(window.endLocalTime)) {
      issues.push(issue("window_time_invalid", prefix));
      continue;
    }
    if (!Number.isSafeInteger(window.minimumCount) || window.minimumCount <= 0) issues.push(issue("window_count_invalid", `${prefix}.minimumCount`));
    const start = timeValue(window.startLocalTime);
    const end = timeValue(window.endLocalTime);
    if (end <= start) issues.push(issue("overnight_window_unresolved", prefix));
    else ranges.push({ start, end });
  }
  ranges.sort((a, b) => a.start - b.start);
  for (let index = 1; index < ranges.length; index += 1) {
    const previous = ranges[index - 1];
    const current = ranges[index];
    if (!previous || !current) continue;
    if (current.start < previous.end) issues.push(issue("window_overlap", "schedule.windows"));
    if (current.start === previous.end) issues.push(issue("touching_window_unresolved", "schedule.windows"));
  }
}

export function validateRequestBuilder(builder: RequestBuilder): readonly ValidationIssue[] {
  const issues: ValidationIssue[] = [];
  if (!["pre_visit", "medication_follow_up", "recurring_collection"].includes(builder.context)) issues.push(issue("unknown_context", "context"));
  if (builder.period.kind === "fixed_dates") {
    if (!realDate(builder.period.startLocalDate) || !realDate(builder.period.endLocalDateExclusive) || builder.period.startLocalDate >= builder.period.endLocalDateExclusive) {
      issues.push(issue("fixed_period_invalid", "period"));
    }
  } else if (!Number.isSafeInteger(builder.period.days) || builder.period.days <= 0) {
    issues.push(issue("relative_days_invalid", "period.days"));
  }
  if ((builder.context === "medication_follow_up" || builder.context === "recurring_collection") && builder.period.kind !== "fixed_dates") {
    issues.push(issue("finite_fixed_bounds_required", "period"));
  }
  if (builder.period.timezoneRule !== "acceptance_time_iana") issues.push(issue("timezone_rule_invalid", "period.timezoneRule"));
  if (!["all_readings", "once_daily", "morning_evening", "custom_windows"].includes(builder.schedule.type)) issues.push(issue("unsupported_schedule", "schedule.type"));
  if (!["at_period_end", "daily", "weekly", "every_n_days", "patient_initiated"].includes(builder.cadence.type)) issues.push(issue("unsupported_cadence", "cadence.type"));
  validateWindows(builder, issues);
  if (builder.cadence.type === "every_n_days" && (!Number.isSafeInteger(builder.cadence.everyNDays) || (builder.cadence.everyNDays ?? 0) <= 0) || builder.cadence.type !== "every_n_days" && builder.cadence.everyNDays !== undefined) {
    issues.push(issue("every_n_days_invalid", "cadence.everyNDays"));
  }
  if (!["required", "preferred", "not_requested"].includes(builder.pulse)) issues.push(issue("unsupported_pulse_policy", "pulse"));
  validateText(builder.practiceCollectionInstructions, "practiceCollectionInstructions", issues);
  validateText(builder.practiceContactText, "practiceContactText", issues);

  // The draft intentionally has no cross-language materialization oracle yet.
  if (builder.period.kind === "relative_completed_days") issues.push(issue("relative_acceptance_unresolved", "period"));
  if (builder.schedule.windows.length > 0) issues.push(issue("dst_materialization_unresolved", "schedule.windows"));
  if (["daily", "weekly", "every_n_days"].includes(builder.cadence.type)) issues.push(issue("cadence_anchor_unresolved", "cadence"));
  return Object.freeze(issues);
}

function assertPlainBoundedVariables(variables: InstructionVariables): void {
  const declared = new Set([
    "practice_display_name", "care_context_label", "collection_period_text", "schedule_text",
    "submission_cadence_text", "requested_values_text", "practice_collection_instructions", "practice_contact_text",
  ]);
  for (const [name, value] of Object.entries(variables)) {
    if (!declared.has(name)) throw new Error("undeclared_variable");
    if (typeof value !== "string" || value.length < 1 || value.length > 500) throw new Error("text_too_long");
    if (forbiddenMarkup.test(value)) throw new Error("html_not_allowed");
    if (forbiddenMarkdown.test(value)) throw new Error("markdown_not_allowed");
    if (forbiddenLink.test(value)) throw new Error("link_not_allowed");
    if (undeclaredVariable.test(value)) throw new Error("undeclared_variable");
  }
}

export function renderCommonInstructions(variables: InstructionVariables): string {
  assertPlainBoundedVariables(variables);
  const paragraphs = [
    `Blood-pressure document request from ${variables.practice_display_name}`,
    `Your practice requested a ${variables.care_context_label} blood-pressure document.`,
    `Collection period: ${variables.collection_period_text}`,
    `Requested schedule: ${variables.schedule_text}`,
    `Submission schedule: ${variables.submission_cadence_text}`,
    `Requested values: ${variables.requested_values_text}`,
    "Health.md reads eligible blood-pressure and heart-rate records from Apple Health or Health Connect. Health.md Practice does not let you enter or change measurement values. Records marked as manually entered by the source can be included and will be labeled in the document.",
  ];
  if (variables.practice_collection_instructions) paragraphs.push(`Instructions from your practice: ${variables.practice_collection_instructions}`);
  paragraphs.push(
    "Review the requested dates, timezone, schedule, identity, readings, sources, and any proposed pulse associations before submitting. If a source value is wrong, correct it in the app or health source that recorded it and generate a new document.",
    "Health.md Practice exchanges a document. It does not continuously monitor your readings, provide medical advice or emergency alerts, or promise that a clinician will respond within a particular time.",
    "If you need medical help or have a time-sensitive concern, use the contact and emergency channels provided by your practice or local emergency services. Do not rely on this document submission for urgent help.",
  );
  if (variables.practice_contact_text) paragraphs.push(`Practice contact direction: ${variables.practice_contact_text}`);
  return paragraphs.join("\n\n");
}

export function canonicalJson(value: unknown): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  return `{${Object.entries(value as Record<string, unknown>).sort(([a], [b]) => a.localeCompare(b)).map(([key, entry]) => `${JSON.stringify(key)}:${canonicalJson(entry)}`).join(",")}}`;
}

function instructionVariables(builder: RequestBuilder, practiceDisplayName: string, collectionPeriodText: string): InstructionVariables {
  return {
    practice_display_name: practiceDisplayName,
    care_context_label: builder.context.replaceAll("_", " "),
    collection_period_text: collectionPeriodText,
    schedule_text: builder.schedule.type === "all_readings" ? "all available readings" : builder.schedule.windows.map(windowText).join("; "),
    submission_cadence_text: builder.cadence.type.replaceAll("_", " "),
    requested_values_text: `systolic and diastolic; pulse ${builder.pulse.replaceAll("_", " ")}`,
    ...(builder.practiceCollectionInstructions === undefined ? {} : { practice_collection_instructions: builder.practiceCollectionInstructions }),
    ...(builder.practiceContactText === undefined ? {} : { practice_contact_text: builder.practiceContactText }),
  };
}

const SHA256_INITIAL = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19] as const;
const SHA256_ROUND = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
] as const;
function rotateRight(value: number, bits: number): number { return (value >>> bits) | (value << (32 - bits)); }
function sha256HexSync(value: string): string {
  const input = new TextEncoder().encode(value); const paddedLength = Math.ceil((input.length + 9) / 64) * 64; const bytes = new Uint8Array(paddedLength); bytes.set(input); bytes[input.length] = 0x80;
  const view = new DataView(bytes.buffer); const bitLength = input.length * 8; view.setUint32(paddedLength - 8, Math.floor(bitLength / 0x1_0000_0000)); view.setUint32(paddedLength - 4, bitLength >>> 0);
  const hash = Uint32Array.from(SHA256_INITIAL); const words = new Uint32Array(64);
  for (let offset = 0; offset < paddedLength; offset += 64) {
    for (let index = 0; index < 16; index += 1) words[index] = view.getUint32(offset + index * 4);
    for (let index = 16; index < 64; index += 1) {
      const before15 = words[index - 15]!; const before2 = words[index - 2]!;
      const sigma0 = rotateRight(before15, 7) ^ rotateRight(before15, 18) ^ (before15 >>> 3); const sigma1 = rotateRight(before2, 17) ^ rotateRight(before2, 19) ^ (before2 >>> 10);
      words[index] = (words[index - 16]! + sigma0 + words[index - 7]! + sigma1) >>> 0;
    }
    let a = hash[0]!; let b = hash[1]!; let c = hash[2]!; let d = hash[3]!; let e = hash[4]!; let f = hash[5]!; let g = hash[6]!; let h = hash[7]!;
    for (let index = 0; index < 64; index += 1) {
      const sum1 = rotateRight(e, 6) ^ rotateRight(e, 11) ^ rotateRight(e, 25); const choose = (e & f) ^ (~e & g); const temp1 = (h + sum1 + choose + SHA256_ROUND[index]! + words[index]!) >>> 0;
      const sum0 = rotateRight(a, 2) ^ rotateRight(a, 13) ^ rotateRight(a, 22); const majority = (a & b) ^ (a & c) ^ (b & c); const temp2 = (sum0 + majority) >>> 0;
      h = g; g = f; f = e; e = (d + temp1) >>> 0; d = c; c = b; b = a; a = (temp1 + temp2) >>> 0;
    }
    hash[0] = (hash[0]! + a) >>> 0; hash[1] = (hash[1]! + b) >>> 0; hash[2] = (hash[2]! + c) >>> 0; hash[3] = (hash[3]! + d) >>> 0;
    hash[4] = (hash[4]! + e) >>> 0; hash[5] = (hash[5]! + f) >>> 0; hash[6] = (hash[6]! + g) >>> 0; hash[7] = (hash[7]! + h) >>> 0;
  }
  return [...hash].map(part => part.toString(16).padStart(8, "0")).join("");
}
function practiceVariant(input: { templateId: string; templateRevision: number; builder: RequestBuilder }): PracticeInstructionVariantRef | null {
  if (input.builder.practiceCollectionInstructions === undefined && input.builder.practiceContactText === undefined) return null;
  const exactParagraphs = canonicalJson({
    commonInstructionVersion: PRACTICE_INSTRUCTION_VERSION,
    practiceCollectionInstructions: input.builder.practiceCollectionInstructions ?? null,
    practiceContactText: input.builder.practiceContactText ?? null,
  });
  return Object.freeze({ id: `${input.templateId}.synthetic-draft`, version: `${input.templateRevision}.sha256-${sha256HexSync(exactParagraphs)}`, approvalStatus: "synthetic_draft" });
}

export function createRequestPreview(input: { relationshipId: string; templateId: string; templateRevision: number; builder: RequestBuilder; practiceDisplayName: string }): RequestPreview {
  const issues = validateRequestBuilder(input.builder);
  if (issues.length > 0) throw new RequestValidationError(issues);
  const periodText = input.builder.period.kind === "fixed_dates"
    ? `${input.builder.period.startLocalDate} through before ${input.builder.period.endLocalDateExclusive}; IANA timezone freezes at acceptance`
    : `${input.builder.period.days} completed days; dates and IANA timezone resolve at acceptance`;
  const renderedInstructions = renderCommonInstructions(instructionVariables(input.builder, input.practiceDisplayName, periodText));
  const representation: CanonicalRequestRepresentation = {
    schema: SYNTHETIC_OPERATION_VERSION,
    protocolVersion: PRACTICE_PROTOCOL_VERSION,
    instructionVersion: PRACTICE_INSTRUCTION_VERSION,
    practiceVariant: practiceVariant(input),
    relationshipId: input.relationshipId,
    templateId: input.templateId,
    templateRevision: input.templateRevision,
    builder: structuredClone(input.builder),
    renderedInstructions,
  };
  const json = canonicalJson(representation);
  return { representation, canonicalJson: json, canonicalBytes: [...new TextEncoder().encode(json)] };
}

export function createAcceptanceReview(input: { representation: CanonicalRequestRepresentation; requestRepresentationSha256: string; practiceDisplayName: string; deviceIanaTimezone: string }): AcceptanceReview {
  if (!/^[a-f0-9]{64}$/.test(input.requestRepresentationSha256)) throw new AcceptanceMaterializationError();
  const materializedPeriod = materializeCollectionPeriod(input.representation.builder, input.deviceIanaTimezone);
  const periodText = `${materializedPeriod.startLocalDate} through before ${materializedPeriod.endLocalDateExclusive} in ${materializedPeriod.deviceIanaTimezone}`;
  return Object.freeze({
    schema: SYNTHETIC_ACCEPTANCE_REVIEW_VERSION,
    requestRepresentationSha256: input.requestRepresentationSha256,
    instructionVersion: input.representation.instructionVersion,
    practiceVariant: input.representation.practiceVariant === null ? null : Object.freeze(structuredClone(input.representation.practiceVariant)),
    materializedPeriod,
    renderedInstructions: renderCommonInstructions(instructionVariables(input.representation.builder, input.practiceDisplayName, periodText)),
  });
}

function windowText(window: NamedWindow): string { return `${window.name} ${window.startLocalTime}-${window.endLocalTime}, minimum ${window.minimumCount}`; }

export class RequestValidationError extends Error {
  constructor(readonly issues: readonly ValidationIssue[]) { super("request_validation_failed"); }
}
export class AcceptanceMaterializationError extends Error {
  constructor() { super("acceptance_materialization_unavailable"); }
}
