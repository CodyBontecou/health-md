import type {
  PracticeMetaResponse,
  SyntheticCatalogResponse,
  SyntheticPacketSummary,
  SyntheticPractice,
  SyntheticRequestSummary,
  SyntheticUser,
} from "../contracts/api";
import {
  PRACTICE_API_VERSION,
  PRACTICE_INSTRUCTION_VERSION,
  PRACTICE_PROTOCOL_VERSION,
} from "../contracts/api";

export const syntheticMeta: PracticeMetaResponse = Object.freeze({
  apiVersion: PRACTICE_API_VERSION,
  mode: "synthetic",
  protocolVersion: PRACTICE_PROTOCOL_VERSION,
  instructionVersion: PRACTICE_INSTRUCTION_VERSION,
  productionEnabled: false,
  label: "Synthetic demo — no real patient data",
});

export const syntheticPractices: readonly SyntheticPractice[] = Object.freeze([
  Object.freeze({ id: "practice_synthetic_a", displayName: "Fictional Practice A" }),
  Object.freeze({ id: "practice_synthetic_b", displayName: "Fictional Practice B" }),
]);

export const syntheticUsers: readonly SyntheticUser[] = Object.freeze([
  Object.freeze({
    id: "user_synthetic_admin",
    displayName: "Avery Admin (fictional)",
    role: "practice_admin",
    practiceId: "practice_synthetic_a",
  }),
  Object.freeze({
    id: "user_synthetic_clinician",
    displayName: "Casey Clinician (fictional)",
    role: "clinician",
    practiceId: "practice_synthetic_a",
  }),
]);

export const syntheticRequests: readonly SyntheticRequestSummary[] = Object.freeze([
  Object.freeze({
    id: "request_synthetic_previsit",
    practiceId: "practice_synthetic_a",
    fictionalRelationshipLabel: "Avery Fiction — synthetic relationship",
    context: "pre_visit",
    state: "accepted",
  }),
  Object.freeze({
    id: "request_synthetic_recurring",
    practiceId: "practice_synthetic_a",
    fictionalRelationshipLabel: "Morgan Example — synthetic relationship",
    context: "recurring_collection",
    state: "issued",
  }),
  Object.freeze({
    id: "request_synthetic_android",
    practiceId: "practice_synthetic_b",
    fictionalRelationshipLabel: "Jordan Example — synthetic relationship",
    context: "medication_follow_up",
    state: "completed",
  }),
]);

const hostileFictionalLabel = "Taylor <img src=x onerror=alert(1)> Fiction";

export const syntheticPackets: readonly SyntheticPacketSummary[] = Object.freeze([
  Object.freeze({
    id: "packet_synthetic_apple",
    practiceId: "practice_synthetic_a",
    requestId: "request_synthetic_previsit",
    fictionalPatientLabel: hostileFictionalLabel,
    state: "received",
    readings: Object.freeze([
      Object.freeze({
        observedAt: "2040-01-15T08:00:00-05:00",
        systolicMmHg: 118,
        diastolicMmHg: 76,
        pulseBeatsPerMinute: 68,
        sourceDisclosure: "synthetic_apple_health" as const,
      }),
      Object.freeze({
        observedAt: "2040-01-15T20:00:00-05:00",
        systolicMmHg: 121,
        diastolicMmHg: 78,
        pulseBeatsPerMinute: null,
        sourceDisclosure: "synthetic_apple_health" as const,
      }),
    ]),
    limitations: "Fictional values for interface testing only; not for clinical use.",
  }),
  Object.freeze({
    id: "packet_synthetic_android",
    practiceId: "practice_synthetic_b",
    requestId: "request_synthetic_android",
    fictionalPatientLabel: "Jordan Example (fictional)",
    state: "opened",
    readings: Object.freeze([
      Object.freeze({
        observedAt: "2040-02-20T09:15:00+01:00",
        systolicMmHg: 116,
        diastolicMmHg: 74,
        pulseBeatsPerMinute: 65,
        sourceDisclosure: "synthetic_health_connect" as const,
      }),
    ]),
    limitations: "Fictional values for interface testing only; not for clinical use.",
  }),
]);

export const syntheticCatalog: SyntheticCatalogResponse = Object.freeze({
  meta: syntheticMeta,
  users: syntheticUsers,
  practices: syntheticPractices,
  requests: syntheticRequests,
  packets: syntheticPackets,
});
