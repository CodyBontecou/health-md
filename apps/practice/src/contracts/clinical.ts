import { PRACTICE_INSTRUCTION_VERSION, PRACTICE_PROTOCOL_VERSION } from "./api";

export const SYNTHETIC_OPERATION_VERSION = "practice.synthetic.operation/1.0-draft.1" as const;
export const SYNTHETIC_RETENTION_POLICY_VERSION = "practice.synthetic.retention/1.0-draft.1" as const;

export const roles = ["practice_admin", "clinician"] as const;
export type Role = (typeof roles)[number];
export const capabilities = [
  "relationship:search", "request:write", "template:manage", "packet:read",
  "packet:download", "packet:acknowledge", "packet:review", "member:manage",
  "retention:manage", "audit:read",
] as const;
export type Capability = (typeof capabilities)[number];

export const authStates = [
  "signed_out", "primary_verified", "mfa_required", "authenticated", "idle_warning",
  "reauthentication_required", "recovery_handoff", "expired", "revoked", "denied",
  "identity_unavailable", "authenticated_reduced",
] as const;
export type AuthState = (typeof authStates)[number];
export const mfaStates = ["required", "verified", "failed", "expired", "exhausted", "replayed"] as const;
export type MfaState = (typeof mfaStates)[number];
export const recoveryStates = ["not_requested", "handoff_required"] as const;
export type RecoveryState = (typeof recoveryStates)[number];
export const membershipStates = ["active", "disabled", "offboarded", "role_changed"] as const;
export type MembershipState = (typeof membershipStates)[number];
export const sessionStates = ["active", "expired", "revoked"] as const;
export type SessionState = (typeof sessionStates)[number];

export const relationshipProvenance = ["practice_supplied", "patient_confirmed", "unverified"] as const;
export type RelationshipProvenance = (typeof relationshipProvenance)[number];
export const relationshipSearchStates = ["zero", "unique", "ambiguous", "inactive", "denied"] as const;
export type RelationshipSearchState = (typeof relationshipSearchStates)[number];

export const careContexts = ["pre_visit", "medication_follow_up", "recurring_collection"] as const;
export type CareContext = (typeof careContexts)[number];
export type CollectionPeriod =
  | { kind: "fixed_dates"; startLocalDate: string; endLocalDateExclusive: string; timezoneRule: "acceptance_time_iana" }
  | { kind: "relative_completed_days"; days: number; timezoneRule: "acceptance_time_iana" };
export const scheduleTypes = ["all_readings", "once_daily", "morning_evening", "custom_windows"] as const;
export type ScheduleType = (typeof scheduleTypes)[number];
export interface NamedWindow { name: string; startLocalTime: string; endLocalTime: string; minimumCount: number }
export interface CollectionSchedule { type: ScheduleType; windows: readonly NamedWindow[] }
export const cadenceTypes = ["at_period_end", "daily", "weekly", "every_n_days", "patient_initiated"] as const;
export type CadenceType = (typeof cadenceTypes)[number];
export interface SubmissionCadence { type: CadenceType; everyNDays?: number }
export const pulsePolicies = ["required", "preferred", "not_requested"] as const;
export type PulsePolicy = (typeof pulsePolicies)[number];

export interface RequestBuilder {
  context: CareContext;
  period: CollectionPeriod;
  schedule: CollectionSchedule;
  cadence: SubmissionCadence;
  pulse: PulsePolicy;
  practiceCollectionInstructions?: string;
  practiceContactText?: string;
  predecessorRequestId?: string;
}

export const validationErrorCodes = [
  "unknown_context", "fixed_period_invalid", "relative_days_invalid", "finite_fixed_bounds_required", "timezone_rule_invalid",
  "unsupported_schedule", "unsupported_cadence", "window_name_invalid", "window_time_invalid", "window_count_invalid", "window_overlap",
  "window_cardinality_invalid", "every_n_days_invalid", "unsupported_pulse_policy",
  "html_not_allowed", "markdown_not_allowed", "link_not_allowed", "undeclared_variable", "text_too_long",
  "relative_acceptance_unresolved", "dst_materialization_unresolved", "cadence_anchor_unresolved",
  "overnight_window_unresolved", "touching_window_unresolved",
] as const;
export type ValidationErrorCode = (typeof validationErrorCodes)[number];
export interface ValidationIssue { code: ValidationErrorCode; field: string }

export interface InstructionVariables {
  practice_display_name: string;
  care_context_label: string;
  collection_period_text: string;
  schedule_text: string;
  submission_cadence_text: string;
  requested_values_text: string;
  practice_collection_instructions?: string;
  practice_contact_text?: string;
}

export interface CanonicalRequestRepresentation {
  schema: typeof SYNTHETIC_OPERATION_VERSION;
  protocolVersion: typeof PRACTICE_PROTOCOL_VERSION;
  instructionVersion: typeof PRACTICE_INSTRUCTION_VERSION;
  relationshipId: string;
  templateId: string;
  templateRevision: number;
  builder: RequestBuilder;
  renderedInstructions: string;
}
export interface RequestPreview { representation: CanonicalRequestRepresentation; canonicalJson: string; canonicalBytes: number[] }

export const templateStates = ["draft", "active", "superseded", "archived"] as const;
export type TemplateState = (typeof templateStates)[number];
export interface RequestTemplateRevision {
  id: string; tenantId: string; revision: number; state: TemplateState; builder: RequestBuilder;
  authorCode: string; modifiedAt: string; previousRevision: number | null;
}

export const requestLifecycleStates = [
  "created", "issued", "claimed", "accepted", "active", "completed", "expired",
  "canceled", "superseded", "renewed",
] as const;
export type RequestLifecycleState = (typeof requestLifecycleStates)[number];
export const deliveryStates = ["not_attempted", "delivered", "failed"] as const;
export type DeliveryState = (typeof deliveryStates)[number];
export const claimStates = ["available", "claimed", "accepted", "expired", "revoked"] as const;
export type ClaimState = (typeof claimStates)[number];
export const submissionStates = ["none", "partial", "complete"] as const;
export type SubmissionState = (typeof submissionStates)[number];
export interface RequestRecord {
  id: string; tenantId: string; relationshipId: string; revision: number; lifecycle: RequestLifecycleState;
  delivery: DeliveryState; claim: ClaimState; submission: SubmissionState; representation: CanonicalRequestRepresentation;
  canonicalJson: string; predecessorRequestId: string | null; successorRequestId: string | null;
  history: readonly HistoryFact[];
}
export interface InvitationDisplay { requestId: string; token: string | null; genericText: string; displayState: "available_once" | "already_displayed" }
export interface ClaimantReceipt { requestId: string; claimantReceipt: string; expiresAt: string }

export const packetShapes = ["complete", "partial", "empty", "manual_source", "missing_pulse"] as const;
export type PacketShape = (typeof packetShapes)[number];
export const packetAvailabilityStates = ["available", "quarantined", "superseded", "rejected", "revoked", "deleted", "expired", "inaccessible"] as const;
export type PacketAvailabilityState = (typeof packetAvailabilityStates)[number];
export const platforms = ["apple_health", "health_connect"] as const;
export type Platform = (typeof platforms)[number];
export const coverageStates = ["satisfied", "underfilled", "no_qualifying_reading_found", "indeterminate_due_to_partial_capture"] as const;
export type CoverageState = (typeof coverageStates)[number];
export const manualDisclosures = ["manual", "not_marked_manual", "automatic_or_device_recorded", "unknown"] as const;
export type ManualDisclosure = (typeof manualDisclosures)[number];
export const pulseAssociations = ["source_declared", "patient_confirmed_same_source_nearby", "none"] as const;
export type PulseAssociation = (typeof pulseAssociations)[number];
export interface PacketReading { key: string; observedAt: string; systolicMmHg: number; diastolicMmHg: number; pulseBeatsPerMinute: number | null; source: Platform; manual: ManualDisclosure; pulseAssociation: PulseAssociation; windowName: string | null }
export interface PacketRecord {
  id: string; tenantId: string; requestId: string; relationshipLabel: string; revision: number; shape: PacketShape;
  availability: PacketAvailabilityState; receivedAt: string; requestedPeriod: string; submittedPeriod: string;
  timezone: string; coverage: CoverageState; readings: readonly PacketReading[]; disclosures: readonly string[];
  limitations: string; supersedesPacketId: string | null; supersededByPacketId: string | null;
  opened: HistoryFact | null; acknowledged: HistoryFact | null; reviewed: HistoryFact | null; history: readonly HistoryFact[];
}
export const inboxSupersessionStates = ["current", "superseded", "superseding"] as const;
export type InboxSupersession = (typeof inboxSupersessionStates)[number];
export const inboxReceivedSorts = ["received_desc", "received_asc"] as const;
export type InboxReceivedSort = (typeof inboxReceivedSorts)[number];
export interface InboxFilter {
  shape?: PacketShape; availability?: PacketAvailabilityState; context?: CareContext; requestId?: string;
  receivedFromUtcDate?: string; receivedToExclusiveUtcDate?: string; acknowledged?: boolean; reviewed?: boolean;
  supersession?: InboxSupersession; sort?: InboxReceivedSort; cursor?: number; pageSize?: number;
}
export interface InboxPacketSummary {
  id: string; relationshipLabel: string; requestId: string; context: CareContext; revision: number; shape: PacketShape;
  availability: PacketAvailabilityState; receivedAt: string; requestedPeriod: string; submittedPeriod: string;
  coverage: CoverageState; supersedesPacketId: string | null; supersededByPacketId: string | null;
  opened: boolean; acknowledged: boolean; reviewed: boolean;
}
export interface PacketArtifact {
  schema: "practice.synthetic.packet/1.0-draft.1"; id: string; requestId: string; relationshipLabel: string;
  revision: number; shape: PacketShape; receivedAt: string; requestedPeriod: string; submittedPeriod: string;
  timezone: string; coverage: CoverageState; readings: readonly PacketReading[]; disclosures: readonly string[];
  limitations: string; supersedesPacketId: string | null; supersededByPacketId: string | null;
}

export interface HistoryFact { type: string; actorCode: string; at: string; revision: number }
export const auditCategories = ["authentication", "request", "upload", "access_download", "acknowledgment_review", "role_change", "denied_access", "support_access", "revocation", "purge"] as const;
export type AuditCategory = (typeof auditCategories)[number];
export interface AuditEvent { sequence: number; tenantCode: string; actorCode: string; category: AuditCategory; action: string; outcome: "success" | "denied"; at: string }
export interface MembershipView { membershipId: string; actorCode: string; role: Role; state: MembershipState; sessionsRevokedAt: string | null }
export interface RetentionPolicyReceipt { version: typeof SYNTHETIC_RETENTION_POLICY_VERSION; status: "authoritative_synthetic_draft_only"; acknowledgedDays: 30; unacknowledgedDays: 90; backupTargetDays: 35; legalApproval: false }
export interface DeletionProgress {
  packetCode: string; revision: number; state: "not_scheduled" | "scheduled" | "held" | "purged";
  receivedAt: string; unacknowledgedDeleteAt: string | null; scheduledDeleteAt: string | null;
  trigger: "unacknowledged_max" | "explicit_acknowledgment" | "revocation" | "legal_hold" | "purged";
  legalHoldReceipt: string | null;
}

export const operationNames = [
  "sign_in", "verify_mfa", "session_bootstrap", "reauthenticate", "recovery", "session", "logout", "relationship_search", "relationship_select",
  "template_list", "template_create", "template_revise", "template_archive", "request_list", "request_preview", "request_issue",
  "invitation_claim", "invitation_accept", "invitation_revoke", "invitation_expire", "request_cancel", "request_renew", "inbox", "packet_load", "packet_download",
  "packet_acknowledge", "packet_review", "packet_passive_event", "members", "member_role_change", "member_offboard",
  "member_revoke_sessions", "retention", "audit",
] as const;
export type OperationName = (typeof operationNames)[number];

export interface OperationEnvelope { version: typeof SYNTHETIC_OPERATION_VERSION; operation: OperationName; csrfToken?: string; payload?: Record<string, unknown> }
export interface OperationResponse { version: typeof SYNTHETIC_OPERATION_VERSION; ok: true; csrfToken?: string; data: unknown }
export interface ClinicalErrorResponse { error: { code: string; message: "The requested operation is unavailable" } }
