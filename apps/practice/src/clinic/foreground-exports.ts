import { canonicalJson } from "../synthetic/request-domain";
import { ClinicAccessPolicy } from "./access";
import { SyntheticClinicBroker } from "./broker";
import { ClinicError, requireClinic, type ApprovedConnection, type PatientActor, type RefreshRequest, type UploadReceipt } from "./contracts";

export type JournalEntry = { action: "executing" } | { action: "uploaded"; receipt: UploadReceipt }
  | { action: "failed"; failure: NonNullable<RefreshRequest["failure"]> };
/** Native adapter must persist synchronously/transactionally before export starts. Memory implementation is synthetic only. */
export interface ExportJournal {
  get(key: string): JournalEntry | undefined;
  put(key: string, value: JournalEntry): void;
}
export class SyntheticExportJournal implements ExportJournal {
  private readonly entries = new Map<string, JournalEntry>();
  get(key: string): JournalEntry | undefined { const value = this.entries.get(key); return value && structuredClone(value); }
  put(key: string, value: JournalEntry): void { this.entries.set(key, structuredClone(value)); }
}
export interface ApprovedExportAdapter {
  foreground(actor: PatientActor): boolean;
  /** Local saved profile/destination snapshot, loaded afresh. Includes no credential or permission grant. */
  currentConnection(id: string): ApprovedConnection | null;
  healthDataAvailable(): boolean;
  /** Delegate to the existing exporter, with frozen profile/range and destination-bound secure auth.
   * Call check before capture and EVERY publication/retry. It throws after foreground, consent,
   * permissions, entitlement, profile, cancellation or expiry changes. Never force wearable sync. */
  exportApproved(request: RefreshRequest, check: () => void): Promise<UploadReceipt>;
}
/** Foreground-only patient handoff. No APNs, background guarantee or alternate export renderer. */
export class PatientClinicExports {
  private readonly active = new Set<string>();
  constructor(private readonly broker: SyntheticClinicBroker, private readonly access: ClinicAccessPolicy,
    private readonly adapter: ApprovedExportAdapter, private readonly journal: ExportJournal) {}
  async run(actor: PatientActor, requestId: string): Promise<RefreshRequest> {
    const request = this.broker.status(actor, requestId);
    const key = JSON.stringify([actor.subjectId, actor.deviceId, requestId]);
    requireClinic(!this.active.has(key), "already_running"); this.active.add(key);
    try {
      const previous = this.journal.get(key);
      // A restarted runtime cannot know whether an executing export uploaded bytes. Never repeat it.
      if (previous?.action === "executing") {
        this.broker.fail(actor, requestId, "interrupted"); return this.broker.status(actor, requestId);
      }
      // Acknowledgment retry never recaptures or uploads health data, even after expiry/revocation.
      if (previous?.action === "uploaded") return this.broker.uploaded(actor, requestId, previous.receipt);
      if (previous?.action === "failed") {
        this.broker.fail(actor, requestId, previous.failure); return this.broker.status(actor, requestId);
      }
      if (request.state !== "requested") return request;
      const checkLocal = (): void => {
        requireClinic(this.adapter.foreground(actor), "foreground_required");
        const approved = this.broker.getConnection(actor, request.connection.id);
        requireClinic(!approved.revoked, "revoked");
        const local = this.adapter.currentConnection(approved.id);
        requireClinic(local && canonicalJson(local) === canonicalJson(approved)
          && approved.revision === request.connection.revision, "profile_changed");
        requireClinic(this.adapter.healthDataAvailable(), "permission_required");
        const entitlement = this.access.evaluate(approved);
        requireClinic(entitlement === "consumer" || entitlement === "clinic", entitlement);
      };
      // Blocked gates remain requested, allowing the patient to resolve them before the request expires.
      checkLocal();
      this.journal.put(key, { action: "executing" });
      const started = this.broker.start(actor, requestId);
      const check = (): void => { checkLocal(); this.broker.checkRunning(actor, requestId); };
      let receipt: UploadReceipt;
      try {
        check(); receipt = await this.adapter.exportApproved(started, check);
      } catch (error) {
        const code = error instanceof ClinicError ? error.code : "export_failed";
        const failure = code === "permission_required" || code === "profile_changed" ? code : "export_failed";
        this.journal.put(key, { action: "failed", failure }); this.broker.fail(actor, requestId, failure);
        return this.broker.status(actor, requestId);
      }
      // Persist success BEFORE network acknowledgment. An acknowledgment error must never overwrite it.
      this.journal.put(key, { action: "uploaded", receipt });
      return this.broker.uploaded(actor, requestId, receipt);
    } finally { this.active.delete(key); }
  }
}
