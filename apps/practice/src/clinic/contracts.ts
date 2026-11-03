/** Internal synthetic integration contract. This is not Shared Setup or a shipped mobile API. */
export const CLINIC_CONTRACT = "healthmd.clinic.synthetic.v1" as const;
export const clinicHandoffs = {
  setup: "healthmd://clinic/setup",
  refresh: "healthmd://clinic/refresh",
} as const;

/** QR encodes only this navigation hint. Authenticated inbox lookup supplies all context. */
export function parseClinicHandoff(value: string): keyof typeof clinicHandoffs | null {
  for (const kind of ["setup", "refresh"] as const) if (value === clinicHandoffs[kind]) return kind;
  return null;
}
export class ClinicError extends Error {
  constructor(readonly code: string) { super(code); }
}
export function requireClinic(condition: unknown, code: string): asserts condition {
  if (!condition) throw new ClinicError(code);
}
export type ClinicActor = { role: "clinic"; subjectId: string; clinicId: string };
export type PatientActor = { role: "patient"; subjectId: string; deviceId: string };
export type Actor = ClinicActor | PatientActor;
export interface Range {
  start: string; end: string;
  /** Explicit reviewed owner-day scope; never an implicit rounding of timestamps. */
  ownerDayZone?: string;
}
export interface SetupIntent {
  patientId: string;
  destinationId: string;
  metrics: string[];
  schedule: { cadence: "daily" | "weekly"; hourUtc: number };
}
export interface SetupReview {
  version: typeof CLINIC_CONTRACT;
  setupId: string;
  clinicId: string;
  patientId: string;
  destination: { id: string; url: string };
  metrics: string[];
  schedule: SetupIntent["schedule"];
  scheduleEnabled: false;
  expiresAt: number;
  grantsOSPermission: false;
  grantsPaidAccess: false;
}
export interface ApprovedConnection {
  id: string;
  clinicId: string;
  patientId: string;
  deviceId: string;
  profileId: string;
  revision: string;
  destination: { id: string; url: string };
  metrics: string[];
  schedule: SetupIntent["schedule"];
  scheduleEnabled: boolean;
  revoked: boolean;
}
export type RefreshState = "requested" | "running" | "uploaded" | "processed" | "failed" | "cancelled" | "expired" | "revoked";
export interface UploadReceipt {
  requestId: string;
  connectionId: string;
  profileId: string;
  revision: string;
  destinationId: string;
  range: Range;
  exportId: string;
  uploadedAt: number;
}
export interface RefreshRequest {
  id: string;
  connection: ApprovedConnection;
  range: Range;
  createdAt: number;
  expiresAt: number;
  state: RefreshState;
  startedAt?: number;
  receipt?: UploadReceipt;
  failure?: "interrupted" | "export_failed" | "permission_required" | "profile_changed";
}
export function identifier(value: unknown): asserts value is string {
  requireClinic(typeof value === "string" && /^[a-zA-Z0-9_-]{1,100}$/.test(value), "invalid_input");
}
export function exactKeys(value: unknown, keys: readonly string[]): asserts value is Record<string, unknown> {
  requireClinic(value && typeof value === "object" && !Array.isArray(value), "invalid_input");
  requireClinic(Object.keys(value).every(key => keys.includes(key)), "invalid_input");
}
export function validateRange(value: unknown, now: number): asserts value is Range {
  exactKeys(value, ["start", "end", "ownerDayZone"]);
  for (const key of ["start", "end"]) {
    const text = value[key];
    requireClinic(typeof text === "string" && Number.isFinite(Date.parse(text)) && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(text) && new Date(text).toISOString() === text, "invalid_range");
  }
  const start = Date.parse(value.start as string); const end = Date.parse(value.end as string);
  requireClinic(end > start && start <= now, "invalid_range");
  if ("ownerDayZone" in value) {
    requireClinic(validOwnerDays(start, end, value.ownerDayZone, now), "invalid_range");
  } else requireClinic(end <= now && end - start <= 366 * 86_400_000, "invalid_range");
}
function validOwnerDays(start: number, end: number, zone: unknown, now: number): boolean {
  if (typeof zone !== "string" || zone.length === 0 || zone.length > 100) return false;
  try {
    const format = new Intl.DateTimeFormat("en-CA", { timeZone: zone, year: "numeric", month: "2-digit", day: "2-digit",
      hour: "2-digit", minute: "2-digit", second: "2-digit", fractionalSecondDigits: 3, hourCycle: "h23" });
    const fields = (time: number) => Object.fromEntries(format.formatToParts(time).map(part => [part.type, part.value]));
    const day = (f: Record<string, string>) => Date.UTC(Number(f.year), Number(f.month) - 1, Number(f.day)) / 86_400_000;
    const midnight = (f: Record<string, string>) => f.hour === "00" && f.minute === "00" && f.second === "00" && f.fractionalSecond === "000";
    const first = fields(start); const last = fields(end); const count = day(last) - day(first);
    return midnight(first) && midnight(last) && count >= 1 && count <= 366 && day(last) <= day(fields(now)) + 1;
  } catch { return false; }
}
