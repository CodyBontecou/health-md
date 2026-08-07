import {
  SYNTHETIC_OPERATION_VERSION,
  type CanonicalRequestRepresentation,
  type InstructionVariables,
  type NamedWindow,
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

export function createRequestPreview(input: { relationshipId: string; templateId: string; templateRevision: number; builder: RequestBuilder; practiceDisplayName: string }): RequestPreview {
  const issues = validateRequestBuilder(input.builder);
  if (issues.length > 0) throw new RequestValidationError(issues);
  const periodText = input.builder.period.kind === "fixed_dates"
    ? `${input.builder.period.startLocalDate} through before ${input.builder.period.endLocalDateExclusive}; IANA timezone freezes at acceptance`
    : `${input.builder.period.days} completed days; dates and IANA timezone resolve at acceptance`;
  const renderedInstructions = renderCommonInstructions({
    practice_display_name: input.practiceDisplayName,
    care_context_label: input.builder.context.replaceAll("_", " "),
    collection_period_text: periodText,
    schedule_text: input.builder.schedule.type === "all_readings" ? "all available readings" : input.builder.schedule.windows.map(windowText).join("; "),
    submission_cadence_text: input.builder.cadence.type.replaceAll("_", " "),
    requested_values_text: `systolic and diastolic; pulse ${input.builder.pulse.replaceAll("_", " ")}`,
    ...(input.builder.practiceCollectionInstructions === undefined ? {} : { practice_collection_instructions: input.builder.practiceCollectionInstructions }),
    ...(input.builder.practiceContactText === undefined ? {} : { practice_contact_text: input.builder.practiceContactText }),
  });
  const representation: CanonicalRequestRepresentation = {
    schema: SYNTHETIC_OPERATION_VERSION,
    protocolVersion: PRACTICE_PROTOCOL_VERSION,
    instructionVersion: PRACTICE_INSTRUCTION_VERSION,
    relationshipId: input.relationshipId,
    templateId: input.templateId,
    templateRevision: input.templateRevision,
    builder: structuredClone(input.builder),
    renderedInstructions,
  };
  const json = canonicalJson(representation);
  return { representation, canonicalJson: json, canonicalBytes: [...new TextEncoder().encode(json)] };
}

function windowText(window: NamedWindow): string { return `${window.name} ${window.startLocalTime}-${window.endLocalTime}, minimum ${window.minimumCount}`; }

export class RequestValidationError extends Error {
  constructor(readonly issues: readonly ValidationIssue[]) { super("request_validation_failed"); }
}
