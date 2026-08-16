export const PRACTICE_API_VERSION = "practice.synthetic_api.v1" as const;
export const PRACTICE_PROTOCOL_VERSION = "1.0-draft.4" as const;
export const PRACTICE_INSTRUCTION_VERSION = "practice-bp-common/1.0-draft.1" as const;

export type PracticeRuntimeMode = "synthetic";
export type SyntheticRequestState = "issued" | "accepted" | "completed";
export type SyntheticPacketState = "received" | "opened" | "acknowledged";

export interface PracticeMetaResponse {
  apiVersion: typeof PRACTICE_API_VERSION;
  mode: PracticeRuntimeMode;
  protocolVersion: typeof PRACTICE_PROTOCOL_VERSION;
  instructionVersion: typeof PRACTICE_INSTRUCTION_VERSION;
  productionEnabled: false;
  label: "Synthetic demo — no real patient data";
}

export interface SyntheticUser {
  id: string;
  displayName: string;
  role: "practice_admin" | "clinician";
  practiceId: string;
}

export interface SyntheticPractice {
  id: string;
  displayName: string;
}

export interface SyntheticRequestSummary {
  id: string;
  practiceId: string;
  fictionalRelationshipLabel: string;
  context: "pre_visit" | "medication_follow_up" | "recurring_collection";
  state: SyntheticRequestState;
}

export interface SyntheticReading {
  observedAt: string;
  systolicMmHg: number;
  diastolicMmHg: number;
  pulseBeatsPerMinute: number | null;
  sourceDisclosure: "synthetic_apple_health" | "synthetic_health_connect";
}

export interface SyntheticPacketSummary {
  id: string;
  practiceId: string;
  requestId: string;
  fictionalPatientLabel: string;
  state: SyntheticPacketState;
  readings: readonly SyntheticReading[];
  limitations: string;
}

export interface SyntheticCatalogResponse {
  meta: PracticeMetaResponse;
  users: readonly SyntheticUser[];
  practices: readonly SyntheticPractice[];
  requests: readonly SyntheticRequestSummary[];
  packets: readonly SyntheticPacketSummary[];
}

export interface PracticeErrorResponse {
  error: {
    code: "configuration_unavailable" | "not_found" | "method_not_allowed";
    message: string;
  };
}

export const practiceApiPaths = {
  meta: "/api/v1/meta",
  catalog: "/api/v1/catalog",
  operation: "/api/v1/operation",
} as const;

export function assertRelativeApiPath(path: string): void {
  if (!path.startsWith("/") || path.startsWith("//") || path.includes("://") || path.includes("?")) {
    throw new Error("Practice API paths must be static, relative, and query-free");
  }
}
