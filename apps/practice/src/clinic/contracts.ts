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
export interface Range { start: string; end: string }
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
  exactKeys(value, ["start", "end"]);
  for (const key of ["start", "end"]) {
    const text = value[key];
    requireClinic(typeof text === "string" && Number.isFinite(Date.parse(text)) && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(text) && new Date(text).toISOString() === text, "invalid_range");
  }
  const start = Date.parse(value.start as string); const end = Date.parse(value.end as string);
  requireClinic(end > start && end <= now && end - start <= 366 * 86_400_000, "invalid_range");
}
