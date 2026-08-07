import type {
  AuditCategory, AuditEvent, Capability, ClaimState, ClaimantReceipt, DeletionProgress, HistoryFact,
  InboxFilter, InboxPacketSummary, MembershipState, MembershipView, PacketArtifact, PacketRecord, RequestBuilder,
  RequestPreview, RequestRecord, RequestTemplateRevision, RetentionPolicyReceipt, Role,
} from "../contracts/clinical";
import { auditCategories, careContexts, inboxReceivedSorts, inboxSupersessionStates, packetAvailabilityStates, packetShapes, SYNTHETIC_RETENTION_POLICY_VERSION } from "../contracts/clinical";
import { canonicalRoleCapabilities, operationPolicy, roleSatisfiesPolicy } from "../contracts/authorization";
import type { OperationName } from "../contracts/clinical";
import { canonicalJson, createRequestPreview } from "./request-domain";

export interface SyntheticFactories {
  clock: () => string;
  id: (kind: "challenge" | "session" | "template" | "request" | "receipt") => string;
  token: (kind: "csrf" | "invitation" | "claimant") => string;
  hash?: (value: string) => Promise<string>;
}

interface Membership { membershipId: string; userId: string; tenantId: string; actorCode: string; role: Role; state: MembershipState; sessionsRevokedAt: string | null }
interface User { id: string; login: string; membershipIds: string[] }
interface Challenge { id: string; userId: string; state: "required" | "verified" | "failed" | "expired" | "exhausted" | "replayed"; attempts: number; expiresAt: number; terminalAt: number | null }
interface Session { id: string; userId: string; membershipId: string; csrfToken: string; state: "active" | "expired" | "revoked"; expiresAt: number; selectedRelationshipId: string | null; roleAtAuthentication: Role; stepUpExpiresAt: number | null }
interface Relationship { id: string; tenantId: string; label: string; state: "active" | "inactive"; nameProvenance: "patient_confirmed"; dobProvenance: "patient_confirmed"; practiceReferenceProvenance: "practice_supplied" }
interface InvitationState { requestId: string; tokenHash: string | null; claimantHash: string | null; claim: ClaimState; expiresAt: number; claimantExpiresAt: number | null }
interface Reservation { fingerprint: string; promise: Promise<RequestRecord> }
type RequestIssueResult = { request: RequestRecord; invitation: { requestId: string; token: string | null; genericText: string; displayState: "available_once" | "already_displayed" } };

const roleCapabilities = canonicalRoleCapabilities;
const CLAIMABLE_LIFECYCLES = new Set(["issued"]);
const ACCEPTABLE_LIFECYCLES = new Set(["claimed"]);
const CANCELLATION_TERMINAL = new Set(["completed", "canceled", "expired", "renewed", "superseded"]);
const PACKET_ACCESSIBLE = new Set(["available", "superseded"]);
const MAX_AUDIT_EVENTS = 1_000;
const MAX_CHALLENGES = 256;
const MAX_RATE_BUCKETS = 256;
const SIGN_IN_COARSE_MAXIMUM = 512;
const RATE_WINDOW_MS = 60_000;
const CHALLENGE_MS = 5 * 60_000;
const STEP_UP_MS = 5 * 60_000;
const INVITATION_MS = 15 * 60_000;
const CLAIMANT_MS = 5 * 60_000;
const SYNTHETIC_PRACTICE_DISPLAY_NAMES = Object.freeze({
  tenant_a: "Fictional Practice A",
  tenant_b: "Fictional Practice B",
} satisfies Record<string, string>);

function practiceDisplayName(tenantId: string): string {
  const displayName = SYNTHETIC_PRACTICE_DISPLAY_NAMES[tenantId as keyof typeof SYNTHETIC_PRACTICE_DISPLAY_NAMES];
  if (!displayName) throw new SyntheticServiceError("operation_unavailable", 404);
  return displayName;
}

export class SyntheticServiceError extends Error {
  constructor(readonly code: string, readonly status = 400) { super(code); }
}

function clone<T>(value: T): T { return structuredClone(value); }
function immutableHistory(history: readonly HistoryFact[], fact: HistoryFact): readonly HistoryFact[] { return Object.freeze([...history.map(clone), Object.freeze(clone(fact))]); }
function addDays(iso: string, days: number): string { return new Date(Date.parse(iso) + days * 86_400_000).toISOString(); }
function assertTemplateBuilder(builder: RequestBuilder): void { if (builder.predecessorRequestId !== undefined) throw new SyntheticServiceError("predecessor_not_allowed", 422); }
function receivedEpoch(receivedAt: string): number { const epoch = Date.parse(receivedAt); if (!Number.isFinite(epoch)) throw new SyntheticServiceError("operation_unavailable", 500); return epoch; }
function realUtcDate(value: string): boolean { const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value); if (!match) return false; const year = Number(match[1]); const month = Number(match[2]); const day = Number(match[3]); const parsed = new Date(Date.UTC(year, month - 1, day)); return parsed.getUTCFullYear() === year && parsed.getUTCMonth() === month - 1 && parsed.getUTCDate() === day; }
function defaultBuilder(context: RequestBuilder["context"] = "pre_visit"): RequestBuilder {
  return {
    context,
    period: { kind: "fixed_dates", startLocalDate: "2040-01-01", endLocalDateExclusive: "2040-01-08", timezoneRule: "acceptance_time_iana" },
    schedule: { type: "all_readings", windows: [] }, cadence: { type: "at_period_end" }, pulse: "preferred",
  };
}

function packetFixtures(): PacketRecord[] {
  const base = {
    tenantId: "tenant_a", requestId: "request_fixture", relationshipLabel: "Fictional relationship", revision: 1,
    availability: "available" as const, receivedAt: "2040-01-09T12:00:00Z", requestedPeriod: "2040-01-01/2040-01-08",
    submittedPeriod: "2040-01-01/2040-01-08", timezone: "Etc/UTC", limitations: "Synthetic document; source availability can be incomplete.",
    supersedesPacketId: null, supersededByPacketId: null, opened: null, acknowledged: null, reviewed: null, history: [] as readonly HistoryFact[],
  };
  const reading = (key: string, source: "apple_health" | "health_connect", manual: "manual" | "not_marked_manual", pulse: number | null) => ({
    key, observedAt: `2040-01-0${Math.min(9, key.length)}T08:00:00Z`, systolicMmHg: 118, diastolicMmHg: 76,
    pulseBeatsPerMinute: pulse, source, manual, pulseAssociation: pulse === null ? "none" as const : "patient_confirmed_same_source_nearby" as const, windowName: null,
  });
  const packets = [
    { ...base, id: "packet_complete_apple", shape: "complete", coverage: "satisfied", readings: [reading("a", "apple_health", "not_marked_manual", 68), reading("aa", "apple_health", "not_marked_manual", 70)], disclosures: ["Apple Health synthetic provenance", "Complete reading list"], supersedesPacketId: "packet_superseded" },
    { ...base, id: "packet_superseded", shape: "complete", availability: "superseded", coverage: "satisfied", readings: [reading("old", "apple_health", "not_marked_manual", 68)], disclosures: ["Apple Health synthetic provenance", "Immutable superseded revision"], supersededByPacketId: "packet_complete_apple" },
    { ...base, id: "packet_partial_android", requestId: "request_fixture_medication", shape: "partial", coverage: "indeterminate_due_to_partial_capture", readings: [reading("b", "health_connect", "not_marked_manual", 65)], disclosures: ["Health Connect synthetic provenance", "Partial source capture"] },
    { ...base, id: "packet_empty_apple", requestId: "request_fixture_recurring", shape: "empty", coverage: "no_qualifying_reading_found", readings: [], disclosures: ["Apple Health synthetic provenance", "Empty source result does not prove no readings"] },
    { ...base, id: "packet_manual_android", shape: "manual_source", coverage: "underfilled", readings: [reading("c", "health_connect", "manual", 64)], disclosures: ["Health Connect synthetic provenance", "Source marked manual"] },
    { ...base, id: "packet_missing_pulse", shape: "missing_pulse", coverage: "satisfied", readings: [reading("d", "apple_health", "not_marked_manual", null)], disclosures: ["Apple Health synthetic provenance", "No associated pulse available"] },
    { ...base, id: "packet_quarantined", shape: "partial", availability: "quarantined", coverage: "indeterminate_due_to_partial_capture", readings: [], disclosures: ["Malformed synthetic artifact quarantined"] },
    { ...base, id: "packet_complete_b", tenantId: "tenant_b", requestId: "request_state_issued_b", relationshipLabel: "Other Tenant Fiction", shape: "complete", coverage: "satisfied", readings: [reading("tenantb", "health_connect", "not_marked_manual", 66)], disclosures: ["Other tenant synthetic fixture"] },
    ...(["rejected", "revoked", "deleted", "expired", "inaccessible"] as const).map(availability => ({ ...base, id: `packet_${availability}`, shape: "partial" as const, availability, coverage: "indeterminate_due_to_partial_capture" as const, readings: [], disclosures: [`Synthetic artifact ${availability}`] })),
    { ...base, id: "packet_offset_chronology", receivedAt: "2040-01-08T23:30:00-14:00", shape: "partial", coverage: "underfilled", readings: [reading("offset", "health_connect", "not_marked_manual", 67)], disclosures: ["Offset-form synthetic chronology fixture"] },
  ];
  let tenantASequence = 0;
  return packets.map(packet => packet.tenantId === "tenant_a" && packet.id !== "packet_offset_chronology"
    ? { ...packet, receivedAt: `2040-01-09T12:00:${String(59 - tenantASequence++).padStart(2, "0")}Z` }
    : packet) as PacketRecord[];
}

export class SyntheticClinicalService {
  private users = new Map<string, User>();
  private memberships = new Map<string, Membership>();
  private challenges = new Map<string, Challenge>();
  private sessions = new Map<string, Session>();
  private relationships = new Map<string, Relationship>();
  private templates = new Map<string, RequestTemplateRevision[]>();
  private requests = new Map<string, RequestRecord>();
  private invitations = new Map<string, InvitationState>();
  private packets = new Map<string, PacketRecord>();
  private issueReservations = new Map<string, Reservation>();
  private renewalReservations = new Map<string, Reservation>();
  private workflowIdempotency = new Map<string, { fingerprint: string }>();
  private rateBuckets = new Map<string, number[]>();
  private searchTimes = new Map<string, number[]>();
  private auditPartitions = new Map<string, { sequence: number; events: AuditEvent[] }>();
  private auditReadPartitions = new Map<string, { sequence: number; facts: AuditEvent[] }>();
  private deletions = new Map<string, DeletionProgress>();

  constructor(private readonly factories: SyntheticFactories, private readonly sessionLifetimeMs = 30 * 60_000) { this.reset(); }

  reset(): void {
    this.users.clear(); this.memberships.clear(); this.challenges.clear(); this.sessions.clear(); this.relationships.clear(); this.templates.clear();
    this.requests.clear(); this.invitations.clear(); this.packets.clear(); this.issueReservations.clear(); this.renewalReservations.clear();
    this.workflowIdempotency.clear(); this.rateBuckets.clear(); this.searchTimes.clear(); this.auditPartitions.clear(); this.auditReadPartitions.clear();
    this.deletions.clear();
    const memberships: Membership[] = [
      { membershipId: "membership_admin_a", userId: "user_admin", tenantId: "tenant_a", actorCode: "actor_admin", role: "practice_admin", state: "active", sessionsRevokedAt: null },
      { membershipId: "membership_clinician_a", userId: "user_clinician", tenantId: "tenant_a", actorCode: "actor_clinician", role: "clinician", state: "active", sessionsRevokedAt: null },
      { membershipId: "membership_clinician_a2", userId: "user_clinician_two", tenantId: "tenant_a", actorCode: "actor_clinician_two", role: "clinician", state: "active", sessionsRevokedAt: null },
      { membershipId: "membership_clinician_b", userId: "user_other", tenantId: "tenant_b", actorCode: "actor_other", role: "clinician", state: "active", sessionsRevokedAt: null },
      { membershipId: "membership_admin_b", userId: "user_admin_b", tenantId: "tenant_b", actorCode: "actor_admin_b", role: "practice_admin", state: "active", sessionsRevokedAt: null },
      { membershipId: "membership_disabled_a", userId: "user_disabled", tenantId: "tenant_a", actorCode: "actor_disabled", role: "clinician", state: "disabled", sessionsRevokedAt: null },
    ];
    memberships.forEach(item => this.memberships.set(item.membershipId, item));
    [
      { id: "user_admin", login: "admin", membershipIds: ["membership_admin_a"] },
      { id: "user_clinician", login: "clinician", membershipIds: ["membership_clinician_a"] },
      { id: "user_clinician_two", login: "clinician_two", membershipIds: ["membership_clinician_a2"] },
      { id: "user_other", login: "other", membershipIds: ["membership_clinician_b"] },
      { id: "user_admin_b", login: "other_admin", membershipIds: ["membership_admin_b"] },
      { id: "user_disabled", login: "disabled", membershipIds: ["membership_disabled_a"] },
    ].forEach(item => this.users.set(item.id, item));
    for (const relationship of [
      { id: "relationship_unique_a", tenantId: "tenant_a", label: "Avery Fiction — synthetic", state: "active", nameProvenance: "patient_confirmed", dobProvenance: "patient_confirmed", practiceReferenceProvenance: "practice_supplied" },
      { id: "relationship_duplicate_a1", tenantId: "tenant_a", label: "Duplicate Fiction One", state: "active", nameProvenance: "patient_confirmed", dobProvenance: "patient_confirmed", practiceReferenceProvenance: "practice_supplied" },
      { id: "relationship_duplicate_a2", tenantId: "tenant_a", label: "Duplicate Fiction Two", state: "active", nameProvenance: "patient_confirmed", dobProvenance: "patient_confirmed", practiceReferenceProvenance: "practice_supplied" },
      { id: "relationship_inactive_a", tenantId: "tenant_a", label: "Inactive Fiction", state: "inactive", nameProvenance: "patient_confirmed", dobProvenance: "patient_confirmed", practiceReferenceProvenance: "practice_supplied" },
      { id: "relationship_unique_b", tenantId: "tenant_b", label: "Other Tenant Fiction", state: "active", nameProvenance: "patient_confirmed", dobProvenance: "patient_confirmed", practiceReferenceProvenance: "practice_supplied" },
    ] satisfies Relationship[]) this.relationships.set(relationship.id, relationship);
    this.templates.set("template_default_a", [{ id: "template_default_a", tenantId: "tenant_a", revision: 1, state: "active", builder: defaultBuilder("pre_visit"), authorCode: "actor_admin", modifiedAt: this.factories.clock(), previousRevision: null }]);
    this.templates.set("template_synthetic_medication_a", [{ id: "template_synthetic_medication_a", tenantId: "tenant_a", revision: 1, state: "active", builder: defaultBuilder("medication_follow_up"), authorCode: "actor_admin", modifiedAt: this.factories.clock(), previousRevision: null }]);
    this.templates.set("template_synthetic_recurring_a", [{ id: "template_synthetic_recurring_a", tenantId: "tenant_a", revision: 1, state: "active", builder: defaultBuilder("recurring_collection"), authorCode: "actor_admin", modifiedAt: this.factories.clock(), previousRevision: null }]);
    this.templates.set("template_draft_a", [{ id: "template_draft_a", tenantId: "tenant_a", revision: 1, state: "draft", builder: defaultBuilder(), authorCode: "actor_admin", modifiedAt: this.factories.clock(), previousRevision: null }]);
    this.templates.set("template_default_b", [{ id: "template_default_b", tenantId: "tenant_b", revision: 1, state: "active", builder: defaultBuilder(), authorCode: "actor_other", modifiedAt: this.factories.clock(), previousRevision: null }]);
    const lifecyclePreview = createRequestPreview({ relationshipId: "relationship_unique_a", templateId: "template_default_a", templateRevision: 1, builder: defaultBuilder("recurring_collection"), practiceDisplayName: practiceDisplayName("tenant_a") });
    for (const [index, lifecycle] of (["created", "issued", "claimed", "accepted", "active", "completed", "expired", "canceled", "superseded", "renewed"] as const).entries()) {
      const claim = lifecycle === "claimed" ? "claimed" : ["accepted", "active", "completed", "superseded", "renewed"].includes(lifecycle) ? "accepted" : lifecycle === "expired" ? "expired" : "available";
      const submission = lifecycle === "completed" ? "complete" : lifecycle === "active" ? "partial" : "none";
      const request: RequestRecord = { id: `request_state_${lifecycle}`, tenantId: "tenant_a", relationshipId: "relationship_unique_a", revision: 1, lifecycle, delivery: index % 2 === 0 ? "delivered" : "not_attempted", claim, submission, representation: clone(lifecyclePreview.representation), canonicalJson: lifecyclePreview.canonicalJson, predecessorRequestId: lifecycle === "renewed" ? "request_state_superseded" : null, successorRequestId: lifecycle === "superseded" ? "request_state_renewed" : null, history: [this.fact("actor_fixture", lifecycle, 1)] };
      this.requests.set(request.id, request);
    }
    for (const [id, templateId, context] of [
      ["request_fixture", "template_default_a", "pre_visit"],
      ["request_fixture_medication", "template_synthetic_medication_a", "medication_follow_up"],
      ["request_fixture_recurring", "template_synthetic_recurring_a", "recurring_collection"],
    ] as const) {
      const fixturePreview = createRequestPreview({ relationshipId: "relationship_unique_a", templateId, templateRevision: 1, builder: defaultBuilder(context), practiceDisplayName: practiceDisplayName("tenant_a") });
      this.requests.set(id, { id, tenantId: "tenant_a", relationshipId: "relationship_unique_a", revision: 1, lifecycle: "completed", delivery: "delivered", claim: "accepted", submission: "complete", representation: clone(fixturePreview.representation), canonicalJson: fixturePreview.canonicalJson, predecessorRequestId: null, successorRequestId: null, history: [this.fact("actor_fixture", "completed", 1)] });
    }
    const tenantBPreview = createRequestPreview({ relationshipId: "relationship_unique_b", templateId: "template_default_b", templateRevision: 1, builder: defaultBuilder(), practiceDisplayName: practiceDisplayName("tenant_b") });
    this.requests.set("request_state_issued_b", { id: "request_state_issued_b", tenantId: "tenant_b", relationshipId: "relationship_unique_b", revision: 1, lifecycle: "issued", delivery: "delivered", claim: "available", submission: "none", representation: clone(tenantBPreview.representation), canonicalJson: tenantBPreview.canonicalJson, predecessorRequestId: null, successorRequestId: null, history: [this.fact("actor_other", "issued", 1)] });
    for (const packet of packetFixtures()) {
      this.packets.set(packet.id, packet);
      const packetCode = packet.id.replace(/^packet_/, "artifact_");
      const ordinaryDeleteAt = addDays(packet.receivedAt, 90);
      const deletion: DeletionProgress = packet.availability === "deleted"
        ? { packetCode, revision: packet.revision, state: "purged", receivedAt: packet.receivedAt, unacknowledgedDeleteAt: null, scheduledDeleteAt: null, trigger: "purged", legalHoldReceipt: null }
        : packet.availability === "revoked"
          ? { packetCode, revision: packet.revision, state: "scheduled", receivedAt: packet.receivedAt, unacknowledgedDeleteAt: null, scheduledDeleteAt: packet.receivedAt, trigger: "revocation", legalHoldReceipt: null }
          : { packetCode, revision: packet.revision, state: "scheduled", receivedAt: packet.receivedAt, unacknowledgedDeleteAt: ordinaryDeleteAt, scheduledDeleteAt: ordinaryDeleteAt, trigger: "unacknowledged_max", legalHoldReceipt: null };
      this.deletions.set(`${packet.tenantId}:${packet.id}:${packet.revision}`, deletion);
    }
    this.deletions.set("tenant_a:legal_hold:1", { packetCode: "artifact_legal_hold", revision: 1, state: "held", receivedAt: "2040-01-09T12:00:00Z", unacknowledgedDeleteAt: "2040-04-08T12:00:00Z", scheduledDeleteAt: null, trigger: "legal_hold", legalHoldReceipt: "synthetic_policy_receipt_hold" });
    this.appendAudit("tenant_b", "actor_other", "request", "tenant_b_seed", "success");
  }

  signIn(login: string): { authState: "mfa_required"; challengeId: string } {
    this.cleanup(); this.rateLimit("signin:coarse", SIGN_IN_COARSE_MAXIMUM, RATE_WINDOW_MS); this.rateLimit(`signin:${login}`, 5, RATE_WINDOW_MS);
    const user = [...this.users.values()].find(candidate => candidate.login === login);
    const membership = user ? this.memberships.get(user.membershipIds[0] ?? "") : undefined;
    if (!user || !membership || !["active", "role_changed"].includes(membership.state)) { this.appendAudit("tenant_unknown", "actor_unknown", "authentication", "sign_in", "denied"); throw new SyntheticServiceError("authentication_failed", 401); }
    const id = this.factories.id("challenge");
    this.challenges.set(id, { id, userId: user.id, state: "required", attempts: 0, expiresAt: this.nowMs() + CHALLENGE_MS, terminalAt: null });
    this.trimChallenges(); this.appendAudit(membership.tenantId, membership.actorCode, "authentication", "sign_in", "success");
    return { authState: "mfa_required", challengeId: id };
  }

  verifyMfa(challengeId: string, code: string): { authState: "authenticated"; sessionId: string; csrfToken: string } {
    this.cleanup(); const challenge = this.challenges.get(challengeId); const now = this.nowMs();
    if (!challenge || challenge.state !== "required") { if (challenge) challenge.state = "replayed"; this.appendAudit("tenant_unknown", "actor_unknown", "authentication", "mfa_verify", "denied"); throw new SyntheticServiceError("mfa_replay_or_invalid", 401); }
    const user = this.users.get(challenge.userId); const membership = user ? this.memberships.get(user.membershipIds[0] ?? "") : undefined;
    if (now >= challenge.expiresAt) { challenge.state = "expired"; challenge.terminalAt = now; this.appendAudit(membership?.tenantId ?? "tenant_unknown", membership?.actorCode ?? "actor_unknown", "authentication", "mfa_verify", "denied"); throw new SyntheticServiceError("mfa_expired", 401); }
    try { this.rateLimit(`mfa:${challenge.userId}`, 3, 60_000); } catch (error) { challenge.state = "exhausted"; challenge.terminalAt = now; throw error; }
    challenge.attempts += 1;
    if (!user || !membership || !["active", "role_changed"].includes(membership.state) || code !== "246810") { challenge.state = "failed"; challenge.terminalAt = now; this.appendAudit(membership?.tenantId ?? "tenant_unknown", membership?.actorCode ?? "actor_unknown", "authentication", "mfa_verify", "denied"); throw new SyntheticServiceError("mfa_failed", 401); }
    challenge.state = "verified"; challenge.terminalAt = now;
    const sessionId = this.factories.id("session"); const csrfToken = this.factories.token("csrf");
    this.sessions.set(sessionId, { id: sessionId, userId: user.id, membershipId: membership.membershipId, csrfToken, state: "active", expiresAt: now + this.sessionLifetimeMs, selectedRelationshipId: null, roleAtAuthentication: membership.role, stepUpExpiresAt: null });
    this.appendAudit(membership.tenantId, membership.actorCode, "authentication", "mfa_verify", "success"); return { authState: "authenticated", sessionId, csrfToken };
  }

  sessionBootstrap(sessionId: string): { session: { authState: "authenticated"; role: Role; capabilities: readonly Capability[]; tenantCode: string; practiceDisplayName: string }; csrfToken: string } {
    const context = this.authorize(sessionId, undefined, "authentication", "session_bootstrap");
    const displayName = practiceDisplayName(context.membership.tenantId);
    context.session.csrfToken = this.factories.token("csrf");
    this.appendAudit(context.membership.tenantId, context.membership.actorCode, "authentication", "session_bootstrap", "success");
    return { session: { authState: "authenticated", role: context.membership.role, capabilities: roleCapabilities[context.session.roleAtAuthentication], tenantCode: context.membership.tenantId, practiceDisplayName: displayName }, csrfToken: context.session.csrfToken };
  }

  reauthenticate(sessionId: string, code: string): { authState: "authenticated"; stepUpExpiresAt: string } {
    const context = this.authorize(sessionId, undefined, "authentication", "reauthenticate");
    this.rateLimit(`reauth:${sessionId}`, 3, 60_000);
    if (code !== "246810") { context.session.stepUpExpiresAt = null; this.appendAudit(context.membership.tenantId, context.membership.actorCode, "authentication", "reauthenticate", "denied"); throw new SyntheticServiceError("reauthentication_failed", 401); }
    context.session.stepUpExpiresAt = this.nowMs() + STEP_UP_MS; this.appendAudit(context.membership.tenantId, context.membership.actorCode, "authentication", "reauthenticate", "success");
    return { authState: "authenticated", stepUpExpiresAt: new Date(context.session.stepUpExpiresAt).toISOString() };
  }

  recovery(): { authState: "recovery_handoff"; recovery: "handoff_required" } { return { authState: "recovery_handoff", recovery: "handoff_required" }; }
  preauthorizeOperation(sessionId: string, operation: OperationName): void {
    const policy = operationPolicy(operation);
    if (policy.requiredCapability === "public") return;
    const context = this.authorize(sessionId, undefined, "denied_access", operation);
    const capabilities = roleCapabilities[context.session.roleAtAuthentication];
    if (!roleSatisfiesPolicy(context.session.roleAtAuthentication, capabilities, policy)) this.deny(context, operation);
  }
  session(sessionId: string): { authState: "authenticated"; role: Role; capabilities: readonly Capability[]; tenantCode: string; practiceDisplayName: string } { const context = this.authorize(sessionId, undefined, "authentication", "session"); this.appendAudit(context.membership.tenantId, context.membership.actorCode, "authentication", "session", "success"); return { authState: "authenticated", role: context.membership.role, capabilities: roleCapabilities[context.membership.role], tenantCode: context.membership.tenantId, practiceDisplayName: practiceDisplayName(context.membership.tenantId) }; }
  logout(sessionId: string): void { const session = this.sessions.get(sessionId); if (session) { session.state = "revoked"; session.selectedRelationshipId = null; session.stepUpExpiresAt = null; const membership = this.memberships.get(session.membershipId); this.appendAudit(membership?.tenantId ?? "tenant_unknown", membership?.actorCode ?? "actor_unknown", "revocation", "logout", "success"); } }
  assertCsrf(sessionId: string, token: string | undefined): void { const session = this.sessions.get(sessionId); if (!session || !token || token !== session.csrfToken) { const membership = session ? this.memberships.get(session.membershipId) : undefined; this.appendAudit(membership?.tenantId ?? "tenant_unknown", membership?.actorCode ?? "actor_unknown", "denied_access", "csrf", "denied"); throw new SyntheticServiceError("operation_unavailable", 404); } }

  relationshipSearch(sessionId: string, query: string): { state: "zero" | "unique" | "ambiguous" | "inactive"; results: readonly Omit<Relationship, "tenantId">[] } {
    const context = this.authorize(sessionId, "relationship:search", "request", "relationship_search"); const now = this.nowMs(); const times = (this.searchTimes.get(sessionId) ?? []).filter(time => now - time < 60_000);
    if (times.length >= 3) { this.appendAudit(context.membership.tenantId, context.membership.actorCode, "denied_access", "relationship_search_rate", "denied"); throw new SyntheticServiceError("rate_limited", 429); }
    times.push(now); this.searchTimes.set(sessionId, times);
    if (query === "denied") return this.deny(context, "relationship_search");
    const ids = query === "unique" ? ["relationship_unique_a"] : query === "ambiguous" ? ["relationship_duplicate_a1", "relationship_duplicate_a2"] : query === "inactive" ? ["relationship_inactive_a"] : query === "partition" ? ["relationship_unique_a", "relationship_unique_b"] : [];
    const results = ids.map(id => this.relationships.get(id)).filter((item): item is Relationship => item?.tenantId === context.membership.tenantId).map(({ tenantId: _tenantId, ...item }) => clone(item));
    const state = results.length === 0 ? "zero" : results.length > 1 ? "ambiguous" : results[0]?.state === "inactive" ? "inactive" : "unique";
    this.appendAudit(context.membership.tenantId, context.membership.actorCode, "request", "relationship_search", "success"); return { state, results };
  }
  relationshipSelect(sessionId: string, relationshipId: string): void { const context = this.authorize(sessionId, "relationship:search", "request", "relationship_select"); const relationship = this.relationships.get(relationshipId); if (!relationship || relationship.tenantId !== context.membership.tenantId || relationship.state !== "active") return this.deny(context, "relationship_select"); context.session.selectedRelationshipId = relationship.id; this.appendAudit(context.membership.tenantId, context.membership.actorCode, "request", "relationship_select", "success"); }

  templateList(sessionId: string): readonly RequestTemplateRevision[] { const context = this.authorize(sessionId, undefined, "request", "template_list"); if (!roleCapabilities[context.session.roleAtAuthentication].some(capability => capability === "template:manage" || capability === "request:write")) return this.deny(context, "template_list"); const result = [...this.templates.values()].flat().filter(item => item.tenantId === context.membership.tenantId).map(clone); this.appendAudit(context.membership.tenantId, context.membership.actorCode, "request", "template_list", "success"); return result; }
  templateCreate(sessionId: string, builder: RequestBuilder): RequestTemplateRevision { const context = this.authorize(sessionId, "template:manage", "request", "template_create"); assertTemplateBuilder(builder); createRequestPreview({ relationshipId: "validation_only", templateId: "validation_only", templateRevision: 1, builder, practiceDisplayName: practiceDisplayName(context.membership.tenantId) }); const id = this.factories.id("template"); const revision: RequestTemplateRevision = { id, tenantId: context.membership.tenantId, revision: 1, state: "active", builder: clone(builder), authorCode: context.membership.actorCode, modifiedAt: this.factories.clock(), previousRevision: null }; this.templates.set(id, [revision]); this.appendAudit(context.membership.tenantId, context.membership.actorCode, "request", "template_create", "success"); return clone(revision); }
  templateRevise(sessionId: string, id: string, expectedRevision: number, builder: RequestBuilder): RequestTemplateRevision { const context = this.authorize(sessionId, "template:manage", "request", "template_revise"); assertTemplateBuilder(builder); const revisions = this.templates.get(id); const current = revisions?.at(-1); if (!revisions || !current || current.tenantId !== context.membership.tenantId) return this.deny(context, "template_revise"); if (current.revision !== expectedRevision || current.state !== "active") throw new SyntheticServiceError("stale_revision", 409); createRequestPreview({ relationshipId: "validation_only", templateId: id, templateRevision: expectedRevision + 1, builder, practiceDisplayName: practiceDisplayName(context.membership.tenantId) }); current.state = "superseded"; const revision: RequestTemplateRevision = { ...clone(current), revision: current.revision + 1, state: "active", builder: clone(builder), authorCode: context.membership.actorCode, modifiedAt: this.factories.clock(), previousRevision: current.revision }; revisions.push(revision); this.appendAudit(context.membership.tenantId, context.membership.actorCode, "request", "template_revise", "success"); return clone(revision); }
  templateArchive(sessionId: string, id: string, expectedRevision: number): RequestTemplateRevision { const context = this.authorize(sessionId, "template:manage", "request", "template_archive"); const current = this.templates.get(id)?.at(-1); if (!current || current.tenantId !== context.membership.tenantId) return this.deny(context, "template_archive"); if (current.revision !== expectedRevision || current.state !== "active") throw new SyntheticServiceError("stale_revision", 409); current.state = "archived"; this.appendAudit(context.membership.tenantId, context.membership.actorCode, "request", "template_archive", "success"); return clone(current); }

  requestList(sessionId: string): readonly RequestRecord[] { const context = this.authorize(sessionId, "request:write", "request", "request_list"); const result = [...this.requests.values()].filter(item => item.tenantId === context.membership.tenantId).map(clone); this.appendAudit(context.membership.tenantId, context.membership.actorCode, "request", "request_list", "success"); return result; }
  requestPreview(sessionId: string, templateId: string, expectedTemplateRevision: number, builder: RequestBuilder): RequestPreview { const context = this.authorize(sessionId, "request:write", "request", "request_preview"); if (!context.session.selectedRelationshipId) throw new SyntheticServiceError("selection_required", 409); const template = this.activeCurrentTemplate(context.membership.tenantId, templateId, expectedTemplateRevision); if (!template) return this.deny(context, "request_preview"); const preview = createRequestPreview({ relationshipId: context.session.selectedRelationshipId, templateId, templateRevision: expectedTemplateRevision, builder, practiceDisplayName: practiceDisplayName(context.membership.tenantId) }); this.appendAudit(context.membership.tenantId, context.membership.actorCode, "request", "request_preview", "success"); return clone(preview); }

  async requestIssue(sessionId: string, preview: RequestPreview, idempotencyKey: string): Promise<RequestIssueResult> {
    const initial = this.authorize(sessionId, "request:write", "request", "request_issue");
    const key = `${initial.membership.tenantId}:issue:${idempotencyKey}`; const fingerprint = preview.canonicalJson; const prior = this.issueReservations.get(key);
    if (prior) { if (prior.fingerprint !== fingerprint) throw new SyntheticServiceError("idempotency_conflict", 409); return this.replayedIssue(await prior.promise); }
    const token = this.factories.token("invitation");
    const promise = (async (): Promise<RequestRecord> => {
      const tokenHash = await this.hash(token);
      const commit = this.authorize(sessionId, "request:write", "request", "request_issue");
      this.validatePreview(commit, preview, "request_issue");
      if (preview.representation.builder.predecessorRequestId !== undefined) throw new SyntheticServiceError("predecessor_not_allowed", 422);
      return this.createIssuedRequest(commit, preview, tokenHash, null);
    })();
    this.issueReservations.set(key, { fingerprint, promise });
    try { const request = await promise; this.appendAudit(initial.membership.tenantId, initial.membership.actorCode, "request", "request_issue", "success"); return { request: clone(request), invitation: this.displayInvitation(request.id, token) }; }
    catch (error) { this.issueReservations.delete(key); throw error; }
  }

  async invitationClaim(token: string): Promise<ClaimantReceipt> {
    this.rateLimit("invitation:claim:coarse", 100, 60_000); const now = this.nowMs(); const hash = await this.hash(token); this.rateLimit(`invitation:claim:${hash}`, 5, 60_000);
    const invitation = [...this.invitations.values()].find(item => item.tokenHash === hash); const request = invitation ? this.requests.get(invitation.requestId) : undefined;
    if (invitation && request && now >= invitation.expiresAt) { this.expireInvitationByClock(invitation, request); throw new SyntheticServiceError("invitation_unavailable", 404); }
    if (!invitation || !request || invitation.claim !== "available" || !CLAIMABLE_LIFECYCLES.has(request.lifecycle)) throw new SyntheticServiceError("invitation_unavailable", 404);
    const claimantReceipt = this.factories.token("claimant"); invitation.tokenHash = null; invitation.claimantHash = await this.hash(claimantReceipt); invitation.claimantExpiresAt = now + CLAIMANT_MS; invitation.claim = "claimed";
    request.claim = "claimed"; request.lifecycle = "claimed"; request.history = immutableHistory(request.history, this.fact("actor_patient", "claimed", request.revision)); this.appendAudit(request.tenantId, "actor_patient", "request", "invitation_claim", "success");
    return { requestId: request.id, claimantReceipt, expiresAt: new Date(invitation.claimantExpiresAt).toISOString() };
  }

  async invitationAccept(claimantReceipt: string): Promise<{ requestId: string; claim: "accepted" }> {
    this.rateLimit("invitation:accept:coarse", 100, 60_000); const now = this.nowMs(); const hash = await this.hash(claimantReceipt); this.rateLimit(`invitation:accept:${hash}`, 5, 60_000);
    const invitation = [...this.invitations.values()].find(item => item.claimantHash === hash); const request = invitation ? this.requests.get(invitation.requestId) : undefined;
    if (invitation && request && invitation.claimantExpiresAt !== null && now >= invitation.claimantExpiresAt) { this.expireInvitationByClock(invitation, request); throw new SyntheticServiceError("invitation_unavailable", 404); }
    if (!invitation || !request || invitation.claim !== "claimed" || invitation.claimantExpiresAt === null || !ACCEPTABLE_LIFECYCLES.has(request.lifecycle)) throw new SyntheticServiceError("invitation_unavailable", 404);
    const predecessor = request.predecessorRequestId ? this.requests.get(request.predecessorRequestId) : undefined;
    if (request.predecessorRequestId && (!predecessor || predecessor.tenantId !== request.tenantId || predecessor.relationshipId !== request.relationshipId || predecessor.successorRequestId !== request.id || !["accepted", "active", "expired"].includes(predecessor.lifecycle))) throw new SyntheticServiceError("invitation_unavailable", 404);
    invitation.claimantHash = null; invitation.claimantExpiresAt = null; invitation.claim = "accepted"; request.claim = "accepted"; request.lifecycle = "accepted";
    request.history = immutableHistory(request.history, this.fact("actor_patient", "accepted", request.revision));
    if (predecessor) { predecessor.lifecycle = "renewed"; predecessor.history = immutableHistory(predecessor.history, this.fact("actor_patient", "renewed", predecessor.revision)); }
    this.appendAudit(request.tenantId, "actor_patient", "request", "invitation_accept", "success"); return { requestId: request.id, claim: "accepted" };
  }

  invitationRevoke(sessionId: string, requestId: string): void { const context = this.authorize(sessionId, "request:write", "revocation", "invitation_revoke"); const request = this.ownedRequest(context, requestId, "invitation_revoke"); const invitation = this.invitations.get(requestId); if (!invitation || !["available", "claimed"].includes(invitation.claim)) throw new SyntheticServiceError("invalid_transition", 409); this.consumeInvitation(invitation, "revoked"); request.claim = "revoked"; this.appendAudit(context.membership.tenantId, context.membership.actorCode, "revocation", "invitation_revoke", "success"); }
  invitationExpire(sessionId: string, requestId: string): void { const context = this.authorize(sessionId, "request:write", "request", "invitation_expire"); const request = this.ownedRequest(context, requestId, "invitation_expire"); const invitation = this.invitations.get(requestId); if (!invitation || !["available", "claimed"].includes(invitation.claim)) throw new SyntheticServiceError("invalid_transition", 409); this.consumeInvitation(invitation, "expired"); request.claim = "expired"; request.lifecycle = "expired"; request.history = immutableHistory(request.history, this.fact(context.membership.actorCode, "expired", request.revision)); this.appendAudit(context.membership.tenantId, context.membership.actorCode, "request", "invitation_expire", "success"); }
  requestCancel(sessionId: string, requestId: string, expectedRevision: number): RequestRecord {
    const context = this.authorize(sessionId, "request:write", "request", "request_cancel"); const request = this.ownedRequest(context, requestId, "request_cancel");
    if (request.revision !== expectedRevision) throw new SyntheticServiceError("stale_revision", 409);
    if (CANCELLATION_TERMINAL.has(request.lifecycle)) throw new SyntheticServiceError("invalid_transition", 409);
    request.lifecycle = "canceled"; const invitation = this.invitations.get(request.id); if (invitation) this.consumeInvitation(invitation, "revoked"); request.claim = "revoked";
    request.history = immutableHistory(request.history, this.fact(context.membership.actorCode, "canceled", request.revision));
    if (request.predecessorRequestId) { const predecessor = this.requests.get(request.predecessorRequestId); if (predecessor?.successorRequestId === request.id && predecessor.lifecycle !== "renewed") predecessor.successorRequestId = null; }
    if (request.successorRequestId) { const successor = this.requests.get(request.successorRequestId); if (successor && !CANCELLATION_TERMINAL.has(successor.lifecycle)) { successor.lifecycle = "canceled"; successor.claim = "revoked"; const successorInvitation = this.invitations.get(successor.id); if (successorInvitation) this.consumeInvitation(successorInvitation, "revoked"); successor.history = immutableHistory(successor.history, this.fact(context.membership.actorCode, "canceled_with_predecessor", successor.revision)); } }
    this.appendAudit(context.membership.tenantId, context.membership.actorCode, "request", "request_cancel", "success"); return clone(request);
  }

  async requestRenew(sessionId: string, predecessorId: string, preview: RequestPreview, idempotencyKey: string): Promise<RequestIssueResult> {
    const initial = this.authorize(sessionId, "request:write", "request", "request_renew");
    const fingerprint = `${predecessorId}:${preview.canonicalJson}`; const key = `${initial.membership.tenantId}:renew:${idempotencyKey}`; const prior = this.renewalReservations.get(key);
    if (prior) { if (prior.fingerprint !== fingerprint) throw new SyntheticServiceError("idempotency_conflict", 409); return this.replayedIssue(await prior.promise); }
    const token = this.factories.token("invitation");
    const promise = (async (): Promise<RequestRecord> => {
      const tokenHash = await this.hash(token);
      const commit = this.authorize(sessionId, "request:write", "request", "request_renew");
      this.validatePreview(commit, preview, "request_renew");
      const predecessor = this.ownedRequest(commit, predecessorId, "request_renew");
      if (predecessor.relationshipId !== preview.representation.relationshipId || predecessor.representation.builder.context !== "recurring_collection" || !["accepted", "active", "expired"].includes(predecessor.lifecycle) || preview.representation.builder.predecessorRequestId !== predecessorId || predecessor.successorRequestId) throw new SyntheticServiceError("successor_required", 409);
      const successor = this.createIssuedRequest(commit, preview, tokenHash, predecessorId);
      predecessor.successorRequestId = successor.id;
      return successor;
    })();
    this.renewalReservations.set(key, { fingerprint, promise });
    try { const successor = await promise; this.appendAudit(initial.membership.tenantId, initial.membership.actorCode, "request", "request_renew", "success"); return { request: clone(successor), invitation: this.displayInvitation(successor.id, token) }; }
    catch (error) { this.renewalReservations.delete(key); throw error; }
  }

  inbox(sessionId: string, filter: InboxFilter): { items: readonly InboxPacketSummary[]; nextCursor: number | null } {
    const auth = this.authorize(sessionId, "packet:read", "access_download", "inbox"); this.validateInboxFilter(filter); const cursor = filter.cursor ?? 0; const pageSize = filter.pageSize ?? 10;
    const rows = [...this.packets.values()].flatMap(packet => {
      if (packet.tenantId !== auth.membership.tenantId) return [];
      const request = this.requests.get(packet.requestId);
      if (!request || request.tenantId !== auth.membership.tenantId) return this.deny(auth, "inbox_request_ownership");
      const context = request.representation.builder.context; const epoch = receivedEpoch(packet.receivedAt); const receivedUtcDate = new Date(epoch).toISOString().slice(0, 10);
      const supersessionMatches = !filter.supersession
        || filter.supersession === "superseded" && (packet.availability === "superseded" || packet.supersededByPacketId !== null)
        || filter.supersession === "superseding" && packet.supersedesPacketId !== null
        || filter.supersession === "current" && packet.availability !== "superseded" && packet.supersededByPacketId === null;
      return (!filter.shape || packet.shape === filter.shape) && (!filter.availability || packet.availability === filter.availability)
        && (!filter.context || context === filter.context) && (!filter.requestId || packet.requestId === filter.requestId)
        && (!filter.receivedFromUtcDate || receivedUtcDate >= filter.receivedFromUtcDate) && (!filter.receivedToExclusiveUtcDate || receivedUtcDate < filter.receivedToExclusiveUtcDate)
        && (filter.acknowledged === undefined || (packet.acknowledged !== null) === filter.acknowledged) && (filter.reviewed === undefined || (packet.reviewed !== null) === filter.reviewed)
        && supersessionMatches ? [{ packet, context, epoch }] : [];
    });
    const direction = filter.sort === "received_asc" ? 1 : -1;
    rows.sort((a, b) => direction * (a.epoch - b.epoch || a.packet.id.localeCompare(b.packet.id)));
    const items = rows.slice(cursor, cursor + pageSize).map(({ packet, context }) => this.inboxSummary(packet, context)); this.appendAudit(auth.membership.tenantId, auth.membership.actorCode, "access_download", "inbox", "success"); return { items, nextCursor: cursor + pageSize < rows.length ? cursor + pageSize : null };
  }
  packetLoad(sessionId: string, packetId: string): PacketRecord {
    const { context, packet } = this.authorizedPacketAccess(sessionId, packetId, "packet:read", "packet_load");
    if (!packet.opened) { const fact = this.fact(context.membership.actorCode, "opened", packet.revision); packet.opened = fact; packet.history = immutableHistory(packet.history, fact); }
    this.appendAudit(context.membership.tenantId, context.membership.actorCode, "access_download", "packet_load", "success"); return clone(packet);
  }
  packetDownload(sessionId: string, packetId: string): { filename: "practice-document.json"; canonicalJson: string; artifact: PacketArtifact } {
    const { context, packet } = this.authorizedPacketAccess(sessionId, packetId, "packet:download", "packet_download"); const artifact = this.packetArtifact(packet);
    this.appendAudit(context.membership.tenantId, context.membership.actorCode, "access_download", "packet_download", "success"); return { filename: "practice-document.json", canonicalJson: canonicalJson(artifact), artifact };
  }
  packetAcknowledge(sessionId: string, packetId: string, expectedRevision: number, idempotencyKey: string): PacketRecord { const result = this.packetWorkflow(sessionId, packetId, expectedRevision, idempotencyKey, "packet:acknowledge", "acknowledged"); const progress = this.deletions.get(`${result.tenantId}:${result.id}:${result.revision}`); if (progress && progress.state !== "held" && progress.trigger !== "explicit_acknowledgment") { progress.state = "scheduled"; progress.scheduledDeleteAt = addDays(this.factories.clock(), 30); progress.trigger = "explicit_acknowledgment"; } return result; }
  packetReview(sessionId: string, packetId: string, expectedRevision: number, idempotencyKey: string): PacketRecord { return this.packetWorkflow(sessionId, packetId, expectedRevision, idempotencyKey, "packet:review", "reviewed"); }
  packetPassiveEvent(sessionId: string, packetId: string, event: "dwell" | "scroll" | "print"): { recorded: false; event: "dwell" | "scroll" | "print" } { const context = this.authorize(sessionId, "packet:read", "access_download", "packet_passive_event"); if (!["dwell", "scroll", "print"].includes(event)) throw new SyntheticServiceError("unknown_event", 400); this.availablePacket(context, packetId, "packet_passive_event"); this.appendAudit(context.membership.tenantId, context.membership.actorCode, "access_download", `packet_${event}`, "success"); return { recorded: false, event }; }

  members(sessionId: string): readonly MembershipView[] { const context = this.authorize(sessionId, "member:manage", "role_change", "members"); const result = [...this.memberships.values()].filter(item => item.tenantId === context.membership.tenantId).map(({ membershipId, actorCode, role, state, sessionsRevokedAt }) => ({ membershipId, actorCode, role, state, sessionsRevokedAt })); this.appendAudit(context.membership.tenantId, context.membership.actorCode, "role_change", "members", "success"); return clone(result); }
  memberRoleChange(sessionId: string, membershipId: string, role: Role): MembershipView { const context = this.authorize(sessionId, "member:manage", "role_change", "member_role_change"); this.consumeStepUp(context.session); const membership = this.ownedMembership(context, membershipId, "member_role_change"); if (membership.state !== "active" && membership.state !== "role_changed") throw new SyntheticServiceError("invalid_transition", 409); membership.role = role; membership.state = "role_changed"; this.revokeMembershipSessions(membership); this.appendAudit(context.membership.tenantId, context.membership.actorCode, "role_change", "member_role_change", "success"); return clone(membership); }
  memberOffboard(sessionId: string, membershipId: string): MembershipView { const context = this.authorize(sessionId, "member:manage", "revocation", "member_offboard"); this.consumeStepUp(context.session); const membership = this.ownedMembership(context, membershipId, "member_offboard"); membership.state = "offboarded"; this.revokeMembershipSessions(membership); this.appendAudit(context.membership.tenantId, context.membership.actorCode, "revocation", "member_offboard", "success"); return clone(membership); }
  memberRevokeSessions(sessionId: string, membershipId: string): MembershipView { const context = this.authorize(sessionId, "member:manage", "revocation", "member_revoke_sessions"); this.consumeStepUp(context.session); const membership = this.ownedMembership(context, membershipId, "member_revoke_sessions"); this.revokeMembershipSessions(membership); this.appendAudit(context.membership.tenantId, context.membership.actorCode, "revocation", "member_revoke_sessions", "success"); return clone(membership); }

  retention(sessionId: string): { policy: RetentionPolicyReceipt; deletion: readonly DeletionProgress[] } { const context = this.authorize(sessionId, "retention:manage", "support_access", "retention_read"); const policy: RetentionPolicyReceipt = { version: SYNTHETIC_RETENTION_POLICY_VERSION, status: "authoritative_synthetic_draft_only", acknowledgedDays: 30, unacknowledgedDays: 90, backupTargetDays: 35, legalApproval: false }; this.appendAudit(context.membership.tenantId, context.membership.actorCode, "support_access", "retention_read", "success"); return { policy, deletion: [...this.deletions.entries()].filter(([key]) => key.startsWith(`${context.membership.tenantId}:`)).map(([, value]) => clone(value)) }; }
  audit(sessionId: string, cursor = 0, pageSize = 20, category?: AuditCategory): { events: readonly AuditEvent[]; nextCursor: number | null } {
    const context = this.authorize(sessionId, "audit:read", "support_access", "audit");
    if (!Number.isSafeInteger(cursor) || cursor < 0 || !Number.isSafeInteger(pageSize) || pageSize < 1 || pageSize > 50 || (category !== undefined && !auditCategories.includes(category))) throw new SyntheticServiceError("invalid_filter", 400);
    // Successful reads are self-audited in a separate bounded control-plane sink. Reading a
    // page therefore cannot append to, evict from, or shift the bounded event stream it paginates.
    const matching = (this.auditPartitions.get(context.membership.tenantId)?.events ?? [])
      .filter(event => event.sequence > cursor && (!category || event.category === category));
    const events = matching.slice(0, pageSize).map(clone);
    const nextCursor = matching.length > events.length ? events.at(-1)?.sequence ?? null : null;
    this.appendAuditReadFact(context.membership.tenantId, context.membership.actorCode);
    return { events, nextCursor };
  }

  invitationHashForTest(requestId: string): string | undefined { return this.invitations.get(requestId)?.tokenHash ?? undefined; }
  claimantHashForTest(requestId: string): string | undefined { return this.invitations.get(requestId)?.claimantHash ?? undefined; }
  auditSnapshotForTest(partition?: string): readonly AuditEvent[] { if (partition) return clone(this.auditPartitions.get(partition)?.events ?? []); return clone([...this.auditPartitions.values()].flatMap(value => value.events)); }
  auditReadSnapshotForTest(partition?: string): readonly AuditEvent[] { if (partition) return clone(this.auditReadPartitions.get(partition)?.facts ?? []); return clone([...this.auditReadPartitions.values()].flatMap(value => value.facts)); }
  sessionSelectionForTest(sessionId: string): string | null | undefined { return this.sessions.get(sessionId)?.selectedRelationshipId; }

  private validatePreview(context: { session: Session; membership: Membership }, preview: RequestPreview, action: "request_issue" | "request_renew"): void {
    if (!context.session.selectedRelationshipId || preview.representation.relationshipId !== context.session.selectedRelationshipId) return this.deny(context, action);
    if (preview.canonicalJson !== canonicalJson(preview.representation) || new TextDecoder().decode(Uint8Array.from(preview.canonicalBytes)) !== preview.canonicalJson) throw new SyntheticServiceError("preview_conflict", 409);
    const template = this.activeCurrentTemplate(context.membership.tenantId, preview.representation.templateId, preview.representation.templateRevision); if (!template) return this.deny(context, action);
    const authoritative = createRequestPreview({ relationshipId: context.session.selectedRelationshipId, templateId: template.id, templateRevision: template.revision, builder: preview.representation.builder, practiceDisplayName: practiceDisplayName(context.membership.tenantId) }); if (authoritative.canonicalJson !== preview.canonicalJson) throw new SyntheticServiceError("preview_conflict", 409);
  }
  private activeCurrentTemplate(tenantId: string, templateId: string, revision: number): RequestTemplateRevision | undefined { const current = this.templates.get(templateId)?.at(-1); return current?.tenantId === tenantId && current.revision === revision && current.state === "active" ? current : undefined; }
  private createIssuedRequest(context: { session: Session; membership: Membership }, preview: RequestPreview, tokenHash: string, predecessorId: string | null): RequestRecord { const requestId = this.factories.id("request"); const request: RequestRecord = { id: requestId, tenantId: context.membership.tenantId, relationshipId: context.session.selectedRelationshipId!, revision: 1, lifecycle: "issued", delivery: "not_attempted", claim: "available", submission: "none", representation: clone(preview.representation), canonicalJson: preview.canonicalJson, predecessorRequestId: predecessorId, successorRequestId: null, history: [this.fact(context.membership.actorCode, "issued", 1)] }; this.requests.set(requestId, request); this.invitations.set(requestId, { requestId, tokenHash, claimantHash: null, claim: "available", expiresAt: this.nowMs() + INVITATION_MS, claimantExpiresAt: null }); return request; }
  private displayInvitation(requestId: string, token: string): RequestIssueResult["invitation"] { return { requestId, token, genericText: "A synthetic Health.md Practice document request is available.", displayState: "available_once" }; }
  private replayedIssue(request: RequestRecord): RequestIssueResult { return { request: clone(request), invitation: { requestId: request.id, token: null, genericText: "A synthetic Health.md Practice document request is available.", displayState: "already_displayed" } }; }
  private consumeInvitation(invitation: InvitationState, claim: "revoked" | "expired"): void { invitation.tokenHash = null; invitation.claimantHash = null; invitation.claimantExpiresAt = null; invitation.claim = claim; }
  private expireInvitationByClock(invitation: InvitationState, request: RequestRecord): void { this.consumeInvitation(invitation, "expired"); if (CANCELLATION_TERMINAL.has(request.lifecycle)) return; request.claim = "expired"; request.lifecycle = "expired"; const fact = this.fact("actor_system", "expired", request.revision); request.history = immutableHistory(request.history, fact); this.appendAudit(request.tenantId, "actor_system", "request", "invitation_expire", "success"); }
  private inboxSummary(packet: PacketRecord, context: RequestBuilder["context"]): InboxPacketSummary { return { id: packet.id, relationshipLabel: packet.relationshipLabel, requestId: packet.requestId, context, revision: packet.revision, shape: packet.shape, availability: packet.availability, receivedAt: packet.receivedAt, requestedPeriod: packet.requestedPeriod, submittedPeriod: packet.submittedPeriod, coverage: packet.coverage, supersedesPacketId: packet.supersedesPacketId, supersededByPacketId: packet.supersededByPacketId, opened: packet.opened !== null, acknowledged: packet.acknowledged !== null, reviewed: packet.reviewed !== null }; }
  private packetArtifact(packet: PacketRecord): PacketArtifact { return { schema: "practice.synthetic.packet/1.0-draft.1", id: packet.id, requestId: packet.requestId, relationshipLabel: packet.relationshipLabel, revision: packet.revision, shape: packet.shape, receivedAt: packet.receivedAt, requestedPeriod: packet.requestedPeriod, submittedPeriod: packet.submittedPeriod, timezone: packet.timezone, coverage: packet.coverage, readings: clone(packet.readings), disclosures: clone(packet.disclosures), limitations: packet.limitations, supersedesPacketId: packet.supersedesPacketId, supersededByPacketId: packet.supersededByPacketId }; }
  private authorizedPacketAccess(sessionId: string, packetId: string, capability: Capability, action: string): { context: { session: Session; membership: Membership }; packet: PacketRecord } { const context = this.authorize(sessionId, capability, "access_download", action); return { context, packet: this.availablePacket(context, packetId, action) }; }
  private packetWorkflow(sessionId: string, packetId: string, revision: number, keyValue: string, capability: Capability, field: "acknowledged" | "reviewed"): PacketRecord { const context = this.authorize(sessionId, capability, "acknowledgment_review", `packet_${field}`); const packet = this.availablePacket(context, packetId, `packet_${field}`); if (packet.revision !== revision) { this.appendAudit(context.membership.tenantId, context.membership.actorCode, "denied_access", `packet_${field}_stale_revision`, "denied"); throw new SyntheticServiceError("stale_revision", 409); } const key = `${context.membership.tenantId}:${field}:${keyValue}`; const fingerprint = `${packetId}:${revision}`; const prior = this.workflowIdempotency.get(key); if (prior) { if (prior.fingerprint !== fingerprint) { this.appendAudit(context.membership.tenantId, context.membership.actorCode, "denied_access", `packet_${field}_idempotency_conflict`, "denied"); throw new SyntheticServiceError("idempotency_conflict", 409); } return clone(packet); } if (!packet[field]) { const fact = this.fact(context.membership.actorCode, field, revision); packet[field] = fact; packet.history = immutableHistory(packet.history, fact); } this.workflowIdempotency.set(key, { fingerprint }); this.appendAudit(context.membership.tenantId, context.membership.actorCode, "acknowledgment_review", `packet_${field}`, "success"); return clone(packet); }
  private availablePacket(context: { session: Session; membership: Membership }, id: string, action: string): PacketRecord { const packet = this.ownedPacket(context, id, action); if (!PACKET_ACCESSIBLE.has(packet.availability)) return this.deny(context, action); return packet; }
  private validateInboxFilter(filter: InboxFilter): void { const allowed = ["shape", "availability", "context", "requestId", "receivedFromUtcDate", "receivedToExclusiveUtcDate", "acknowledged", "reviewed", "supersession", "sort", "cursor", "pageSize"]; if (!filter || typeof filter !== "object" || Object.keys(filter).some(key => !allowed.includes(key))) throw new SyntheticServiceError("invalid_filter"); if (filter.shape !== undefined && !packetShapes.includes(filter.shape)) throw new SyntheticServiceError("invalid_filter"); if (filter.availability !== undefined && !packetAvailabilityStates.includes(filter.availability)) throw new SyntheticServiceError("invalid_filter"); if (filter.context !== undefined && !careContexts.includes(filter.context)) throw new SyntheticServiceError("invalid_filter"); if (filter.requestId !== undefined && (typeof filter.requestId !== "string" || filter.requestId.length < 1 || filter.requestId.length > 128)) throw new SyntheticServiceError("invalid_filter"); if (filter.receivedFromUtcDate !== undefined && !realUtcDate(filter.receivedFromUtcDate) || filter.receivedToExclusiveUtcDate !== undefined && !realUtcDate(filter.receivedToExclusiveUtcDate) || filter.receivedFromUtcDate && filter.receivedToExclusiveUtcDate && filter.receivedFromUtcDate >= filter.receivedToExclusiveUtcDate) throw new SyntheticServiceError("invalid_filter"); if (filter.acknowledged !== undefined && typeof filter.acknowledged !== "boolean" || filter.reviewed !== undefined && typeof filter.reviewed !== "boolean") throw new SyntheticServiceError("invalid_filter"); if (filter.supersession !== undefined && !inboxSupersessionStates.includes(filter.supersession) || filter.sort !== undefined && !inboxReceivedSorts.includes(filter.sort)) throw new SyntheticServiceError("invalid_filter"); if (filter.cursor !== undefined && (!Number.isSafeInteger(filter.cursor) || filter.cursor < 0)) throw new SyntheticServiceError("invalid_filter"); if (filter.pageSize !== undefined && (!Number.isSafeInteger(filter.pageSize) || filter.pageSize < 1 || filter.pageSize > 25)) throw new SyntheticServiceError("invalid_filter"); }
  private authorize(sessionId: string, capability: Capability | undefined, _category: AuditCategory, action: string): { session: Session; membership: Membership } {
    this.cleanup(); const session = this.sessions.get(sessionId); const membership = session ? this.memberships.get(session.membershipId) : undefined;
    if (!session || !membership) { this.appendAudit("tenant_unknown", "actor_unknown", "denied_access", action, "denied"); throw new SyntheticServiceError("operation_unavailable", 404); }
    if (session.state === "expired" || this.nowMs() >= session.expiresAt) { session.state = "expired"; session.selectedRelationshipId = null; session.stepUpExpiresAt = null; this.appendAudit(membership.tenantId, membership.actorCode, "authentication", "session_expired", "denied"); throw new SyntheticServiceError("session_expired", 401); }
    if (session.state === "revoked" || membership.role !== session.roleAtAuthentication) { session.state = "revoked"; session.selectedRelationshipId = null; session.stepUpExpiresAt = null; this.appendAudit(membership.tenantId, membership.actorCode, "revocation", "session_revoked", "denied"); throw new SyntheticServiceError("session_revoked", 401); }
    if (session.state !== "active" || membership.state === "disabled" || membership.state === "offboarded") { session.selectedRelationshipId = null; session.stepUpExpiresAt = null; this.appendAudit("tenant_unknown", "actor_unknown", "denied_access", action, "denied"); throw new SyntheticServiceError("operation_unavailable", 404); }
    if (capability && !roleCapabilities[session.roleAtAuthentication].includes(capability)) return this.deny({ membership }, action); return { session, membership };
  }
  private consumeStepUp(session: Session): void { const now = this.nowMs(); if (session.stepUpExpiresAt === null || now >= session.stepUpExpiresAt) { session.stepUpExpiresAt = null; throw new SyntheticServiceError("reauthentication_required", 401); } session.stepUpExpiresAt = null; }
  private ownedMembership(context: { membership: Membership }, id: string, action: string): Membership { const item = this.memberships.get(id); if (!item || item.tenantId !== context.membership.tenantId) return this.deny(context, action); return item; }
  private ownedRequest(context: { membership: Membership }, id: string, action: string): RequestRecord { const item = this.requests.get(id); if (!item || item.tenantId !== context.membership.tenantId) return this.deny(context, action); return item; }
  private ownedPacket(context: { membership: Membership }, id: string, action: string): PacketRecord { const item = this.packets.get(id); if (!item || item.tenantId !== context.membership.tenantId) return this.deny(context, action); return item; }
  private deny(context: { membership: Membership }, action: string): never { this.appendAudit(context.membership.tenantId, context.membership.actorCode, "denied_access", action, "denied"); throw new SyntheticServiceError("operation_unavailable", 404); }
  private fact(actorCode: string, type: string, revision: number): HistoryFact { return { type, actorCode, at: this.factories.clock(), revision }; }
  private revokeMembershipSessions(membership: Membership): void { membership.sessionsRevokedAt = this.factories.clock(); for (const session of this.sessions.values()) if (session.membershipId === membership.membershipId) { session.state = "revoked"; session.selectedRelationshipId = null; session.stepUpExpiresAt = null; } }
  private rateLimit(key: string, maximum: number, windowMs: number): void {
    const now = this.nowMs(); const existing = this.rateBuckets.get(key); const values = (existing ?? []).filter(value => now - value < windowMs);
    if (values.length >= maximum) throw new SyntheticServiceError("rate_limited", 429);
    if (!existing && this.rateBuckets.size >= MAX_RATE_BUCKETS) throw new SyntheticServiceError("rate_limited", 429);
    values.push(now); this.rateBuckets.set(key, values);
  }
  private cleanup(): void { const now = this.nowMs(); for (const [id, challenge] of this.challenges) if ((challenge.terminalAt !== null && now - challenge.terminalAt > CHALLENGE_MS) || now - challenge.expiresAt > CHALLENGE_MS) this.challenges.delete(id); for (const [key, values] of this.rateBuckets) { const current = values.filter(value => now - value < RATE_WINDOW_MS); if (current.length === 0) this.rateBuckets.delete(key); else this.rateBuckets.set(key, current); } for (const invitation of this.invitations.values()) { const request = this.requests.get(invitation.requestId); if (!request) continue; const tokenExpired = invitation.claim === "available" && now >= invitation.expiresAt; const claimantExpired = invitation.claim === "claimed" && invitation.claimantExpiresAt !== null && now >= invitation.claimantExpiresAt; if (tokenExpired || claimantExpired) this.expireInvitationByClock(invitation, request); } }
  private trimChallenges(): void { while (this.challenges.size > MAX_CHALLENGES) this.challenges.delete(this.challenges.keys().next().value as string); }
  private appendAudit(tenantCode: string, actorCode: string, category: AuditCategory, action: string, outcome: "success" | "denied"): void { const key = tenantCode === "tenant_unknown" ? "security_unknown" : tenantCode; const partition = this.auditPartitions.get(key) ?? { sequence: 0, events: [] }; partition.sequence += 1; partition.events.push(Object.freeze({ sequence: partition.sequence, tenantCode, actorCode, category, action, outcome, at: this.factories.clock() })); if (partition.events.length > MAX_AUDIT_EVENTS) partition.events.splice(0, partition.events.length - MAX_AUDIT_EVENTS); this.auditPartitions.set(key, partition); }
  private appendAuditReadFact(tenantCode: string, actorCode: string): void { const partition = this.auditReadPartitions.get(tenantCode) ?? { sequence: 0, facts: [] }; partition.sequence += 1; partition.facts.push(Object.freeze({ sequence: partition.sequence, tenantCode, actorCode, category: "support_access", action: "audit", outcome: "success", at: this.factories.clock() })); if (partition.facts.length > MAX_AUDIT_EVENTS) partition.facts.splice(0, partition.facts.length - MAX_AUDIT_EVENTS); this.auditReadPartitions.set(tenantCode, partition); }
  private hash(value: string): Promise<string> { return this.factories.hash ? this.factories.hash(value) : sha256Hex(value); }
  private nowMs(): number { return Date.parse(this.factories.clock()); }
}

export async function sha256Hex(value: string): Promise<string> { const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)); return [...new Uint8Array(digest)].map(byte => byte.toString(16).padStart(2, "0")).join(""); }
