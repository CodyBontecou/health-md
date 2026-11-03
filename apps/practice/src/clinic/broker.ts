import { canonicalJson } from "../synthetic/request-domain";
import { sha256Hex } from "../synthetic/service";
import { CLINIC_CONTRACT, clinicHandoffs, exactKeys, identifier, requireClinic, validateRange,
  type Actor, type ApprovedConnection, type ClinicActor, type PatientActor, type Range,
  type RefreshRequest, type SetupIntent, type SetupReview, type UploadReceipt } from "./contracts";

interface Setup { review: SetupReview; digest: string; accepted?: string }
export interface ClinicFactories {
  clock(): number;
  id(): string;
  /** Server/session authority. Called on every operation, including after hashing. */
  authenticate(actor: Actor): void;
}
const stopped = new Set(["failed", "cancelled", "expired", "revoked"]);
/** Resettable synthetic-only broker; deliberately not mounted as a public HTTP surface. */
export class SyntheticClinicBroker {
  private readonly setups = new Map<string, Setup>();
  private readonly connections = new Map<string, ApprovedConnection>();
  private readonly requests = new Map<string, RefreshRequest>();
  constructor(mode: "synthetic", private readonly factories: ClinicFactories) {
    requireClinic(mode === "synthetic", "configuration_unavailable");
  }
  private auth(actor: Actor, role: Actor["role"]): void {
    this.factories.authenticate(actor); requireClinic(actor.role === role, "unavailable");
  }
  private connection(actor: Actor, id: string): ApprovedConnection {
    this.factories.authenticate(actor); const item = this.connections.get(id);
    requireClinic(item && (actor.role === "clinic" ? item.clinicId === actor.clinicId :
      item.patientId === actor.subjectId && item.deviceId === actor.deviceId), "unavailable");
    return item;
  }
  private request(actor: Actor, id: string): RefreshRequest {
    const item = this.requests.get(id); requireClinic(item, "unavailable");
    const connection = this.connection(actor, item.connection.id);
    if (connection.revoked && ["requested", "running"].includes(item.state)) item.state = "revoked";
    if (["requested", "running"].includes(item.state) && this.factories.clock() >= item.expiresAt) item.state = "expired";
    return item;
  }
  async issueSetup(actor: ClinicActor, input: SetupIntent): Promise<{ review: SetupReview; handoff: string }> {
    this.auth(actor, "clinic"); const authority = canonicalJson(actor); exactKeys(input, ["patientId", "destinationId", "metrics", "schedule"]);
    identifier(input.patientId); identifier(input.destinationId); exactKeys(input.schedule, ["cadence", "hourUtc"]);
    requireClinic(["daily", "weekly"].includes(input.schedule.cadence) && Number.isInteger(input.schedule.hourUtc)
      && input.schedule.hourUtc >= 0 && input.schedule.hourUtc <= 23, "invalid_input");
    // This synthetic adapter has no network/auth delivery. Real destinations require an authenticated binding contract.
    requireClinic(input.destinationId === "destination_synthetic", "unavailable");
    requireClinic(Array.isArray(input.metrics) && input.metrics.length > 0 && input.metrics.length <= 2
      && new Set(input.metrics).size === input.metrics.length
      && input.metrics.every(metric => ["steps", "heart_rate_avg"].includes(metric)), "invalid_metrics");
    requireClinic(this.setups.size < 100, "capacity");
    const review: SetupReview = { version: CLINIC_CONTRACT, setupId: this.factories.id(), clinicId: actor.clinicId,
      patientId: input.patientId, destination: { id: input.destinationId, url: "/synthetic-upload" },
      metrics: [...input.metrics].sort(), schedule: structuredClone(input.schedule), scheduleEnabled: false,
      expiresAt: this.factories.clock() + 15 * 60_000, grantsOSPermission: false, grantsPaidAccess: false };
    const digest = await sha256Hex(canonicalJson(review)); this.auth(actor, "clinic");
    requireClinic(canonicalJson(actor) === authority, "unavailable");
    requireClinic(this.setups.size < 100, "capacity");
    this.setups.set(review.setupId, { review, digest });
    return { review: structuredClone(review), handoff: clinicHandoffs.setup };
  }
  pendingSetups(actor: PatientActor): SetupReview[] {
    this.auth(actor, "patient"); return [...this.setups.values()].filter(item => item.review.patientId === actor.subjectId
      && !item.accepted && item.review.expiresAt > this.factories.clock()).map(item => structuredClone(item.review));
  }
  async reviewSetup(actor: PatientActor, setupId: string): Promise<{ review: SetupReview; digest: string }> {
    this.auth(actor, "patient"); const setup = this.setups.get(setupId);
    requireClinic(setup && setup.review.patientId === actor.subjectId && setup.review.expiresAt > this.factories.clock(), "unavailable");
    return { review: structuredClone(setup.review), digest: setup.digest };
  }
  /** Confirmation must carry the exact digest shown to this authenticated patient. No native permission is granted. */
  acceptSetup(actor: PatientActor, setupId: string, digest: string): ApprovedConnection {
    this.auth(actor, "patient"); const setup = this.setups.get(setupId);
    requireClinic(setup && setup.review.patientId === actor.subjectId && setup.digest === digest, "unavailable");
    if (setup.accepted) return structuredClone(this.connection(actor, setup.accepted));
    requireClinic(setup.review.expiresAt > this.factories.clock(), "expired");
    const connection: ApprovedConnection = { id: this.factories.id(), clinicId: setup.review.clinicId,
      patientId: actor.subjectId, deviceId: actor.deviceId, profileId: this.factories.id(), revision: setup.digest,
      destination: structuredClone(setup.review.destination), metrics: [...setup.review.metrics],
      schedule: structuredClone(setup.review.schedule), scheduleEnabled: false, revoked: false };
    this.connections.set(connection.id, connection); setup.accepted = connection.id; return structuredClone(connection);
  }
  getConnection(actor: PatientActor, id: string): ApprovedConnection { this.auth(actor, "patient"); return structuredClone(this.connection(actor, id)); }
  revoke(actor: PatientActor, connectionId: string): void {
    this.auth(actor, "patient"); const connection = this.connection(actor, connectionId); connection.revoked = true;
    connection.scheduleEnabled = false;
    for (const item of this.requests.values()) if (item.connection.id === connectionId) this.request(actor, item.id);
  }
  enableSchedule(actor: PatientActor, connectionId: string): ApprovedConnection {
    this.auth(actor, "patient"); const item = this.connection(actor, connectionId); requireClinic(!item.revoked, "revoked");
    item.scheduleEnabled = true; return structuredClone(item);
  }
  requestRefresh(actor: ClinicActor, input: { requestId: string; connectionId: string; range: Range }): RefreshRequest {
    this.auth(actor, "clinic"); exactKeys(input, ["requestId", "connectionId", "range"]);
    identifier(input.requestId); identifier(input.connectionId); validateRange(input.range, this.factories.clock());
    const connection = this.connection(actor, input.connectionId); requireClinic(!connection.revoked, "revoked");
    const previous = this.requests.get(input.requestId);
    if (previous) {
      const item = this.request(actor, input.requestId);
      requireClinic(item.connection.id === connection.id && canonicalJson(item.range) === canonicalJson(input.range), "idempotency_conflict");
      return structuredClone(item);
    }
    requireClinic(this.requests.size < 1000, "capacity");
    requireClinic(![...this.requests.values()].some(item => item.connection.id === connection.id
      && ["requested", "running"].includes(this.request(actor, item.id).state)), "request_pending");
    const request: RefreshRequest = { id: input.requestId, connection: structuredClone(connection), range: structuredClone(input.range),
      createdAt: this.factories.clock(), expiresAt: this.factories.clock() + 5 * 60_000, state: "requested" };
    this.requests.set(request.id, request); return structuredClone(request);
  }
  pendingRefreshes(actor: PatientActor): RefreshRequest[] {
    this.auth(actor, "patient"); return [...this.requests.values()].filter(item => item.connection.patientId === actor.subjectId
      && item.connection.deviceId === actor.deviceId && this.request(actor, item.id).state === "requested").map(item => structuredClone(item));
  }
  status(actor: Actor, requestId: string): RefreshRequest { return structuredClone(this.request(actor, requestId)); }
  start(actor: PatientActor, requestId: string): RefreshRequest {
    this.auth(actor, "patient"); const item = this.request(actor, requestId);
    requireClinic(item.state === "requested", "unavailable"); item.state = "running"; item.startedAt = this.factories.clock();
    return structuredClone(item);
  }
  checkRunning(actor: PatientActor, requestId: string): void {
    this.auth(actor, "patient"); requireClinic(this.request(actor, requestId).state === "running", "stopped");
  }
  cancel(actor: Actor, requestId: string): RefreshRequest {
    const item = this.request(actor, requestId);
    if (["requested", "running"].includes(item.state)) item.state = "cancelled";
    return structuredClone(item);
  }
  fail(actor: PatientActor, requestId: string, failure: NonNullable<RefreshRequest["failure"]>): void {
    this.auth(actor, "patient"); const item = this.request(actor, requestId);
    requireClinic(["interrupted", "export_failed", "permission_required", "profile_changed"].includes(failure), "invalid_input");
    if (["requested", "running"].includes(item.state)) { item.state = "failed"; item.failure = failure; }
  }
  uploaded(actor: PatientActor, requestId: string, receipt: UploadReceipt): RefreshRequest {
    this.auth(actor, "patient"); const item = this.request(actor, requestId);
    exactKeys(receipt, ["requestId", "connectionId", "profileId", "revision", "destinationId", "range", "exportId", "uploadedAt"]);
    validateRange(receipt.range, this.factories.clock()); identifier(receipt.exportId);
    requireClinic(item.startedAt !== undefined && receipt.requestId === item.id && receipt.connectionId === item.connection.id
      && receipt.profileId === item.connection.profileId && receipt.revision === item.connection.revision
      && receipt.destinationId === item.connection.destination.id && canonicalJson(receipt.range) === canonicalJson(item.range)
      && Number.isSafeInteger(receipt.uploadedAt) && receipt.uploadedAt >= item.startedAt! && receipt.uploadedAt <= this.factories.clock(), "invalid_receipt");
    if (item.receipt) { requireClinic(canonicalJson(receipt) === canonicalJson(item.receipt), "receipt_conflict"); return structuredClone(item); }
    requireClinic(item.state === "running" || stopped.has(item.state), "unavailable");
    // Preserve late upload evidence after cancellation/expiry; never resurrect remaining work or imply processing.
    item.receipt = structuredClone(receipt); if (item.state === "running") item.state = "uploaded";
    return structuredClone(item);
  }
  processed(actor: ClinicActor, requestId: string, exportId: string): RefreshRequest {
    this.auth(actor, "clinic"); const item = this.request(actor, requestId);
    requireClinic(item.state === "uploaded" || item.state === "processed", "unavailable");
    requireClinic(item.receipt?.exportId === exportId, "invalid_receipt"); item.state = "processed";
    return structuredClone(item);
  }
}
