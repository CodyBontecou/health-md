import type { ApprovedConnection } from "./contracts";

export interface VerifiedClinicGrant {
  patientId: string;
  clinicId: string;
  connectionId: string;
  expiresAt: number;
  revoked: boolean;
}
/** Inject trusted provider lookups, never URL/QR/imported flags. No production provider is installed. */
export interface ClinicAccessProvider {
  consumerAllowsExport(patientId: string): boolean;
  verifiedGrant(patientId: string, connectionId: string): VerifiedClinicGrant | null;
}
export type ClinicAccess = "consumer" | "clinic" | "store_decision_required" | "entitlement_required";
export class ClinicAccessPolicy {
  constructor(private readonly provider: ClinicAccessProvider, private readonly clock: () => number,
    private readonly route: "disabled" | "synthetic" = "disabled") {}
  evaluate(connection: ApprovedConnection): ClinicAccess {
    if (this.provider.consumerAllowsExport(connection.patientId)) return "consumer";
    if (this.route !== "synthetic") return "store_decision_required";
    const grant = this.provider.verifiedGrant(connection.patientId, connection.id);
    return grant && !grant.revoked && grant.patientId === connection.patientId && grant.clinicId === connection.clinicId
      && grant.connectionId === connection.id && grant.expiresAt > this.clock() ? "clinic" : "entitlement_required";
  }
}

/** Explicitly provisioned fictional seats for integration tests. No billing or production entitlement activation. */
export class SyntheticClinicLicenses implements ClinicAccessProvider {
  private readonly grants = new Map<string, VerifiedClinicGrant>();
  constructor(private readonly clinicId: string, private readonly seats: number, private readonly expiresAt: number,
    private readonly clock: () => number, private readonly consumer: (patientId: string) => boolean = () => false) {
    if (!Number.isSafeInteger(seats) || seats < 0 || seats > 1000 || !Number.isSafeInteger(expiresAt)) throw new Error("invalid_capacity");
  }
  consumerAllowsExport(patientId: string): boolean { return this.consumer(patientId); }
  verifiedGrant(patientId: string, connectionId: string): VerifiedClinicGrant | null {
    const value = this.grants.get(connectionId); return value?.patientId === patientId ? structuredClone(value) : null;
  }
  assign(connection: ApprovedConnection): void {
    if (connection.clinicId !== this.clinicId || connection.revoked || this.expiresAt <= this.clock()) throw new Error("unavailable");
    const existing = this.grants.get(connection.id);
    if (existing && !existing.revoked) return;
    // Capacity is per patient, even if a patient has more than one approved profile.
    const assigned = new Set([...this.grants.values()].filter(item => !item.revoked && item.expiresAt > this.clock()).map(item => item.patientId));
    if (!assigned.has(connection.patientId) && assigned.size >= this.seats) throw new Error("capacity");
    this.grants.set(connection.id, { patientId: connection.patientId, clinicId: this.clinicId,
      connectionId: connection.id, expiresAt: this.expiresAt, revoked: false });
  }
  revoke(connectionId: string): void { const grant = this.grants.get(connectionId); if (grant) grant.revoked = true; }
}
