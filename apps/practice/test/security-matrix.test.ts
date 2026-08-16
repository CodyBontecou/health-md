import { describe, expect, it } from "vitest";
import authorizationPolicy from "../src/contracts/authorization-policy.json";
import { SYNTHETIC_OPERATION_VERSION, operationNames, type OperationEnvelope, type OperationName, type RequestBuilder } from "../src/contracts/clinical";
import { dispatchClinicalOperation } from "../src/http/clinical-api";
import { createRequestPreview } from "../src/synthetic/request-domain";
import { SyntheticClinicalService, type SyntheticFactories } from "../src/synthetic/service";
import { portalRoutes } from "../src/web/routes";

const builder: RequestBuilder = { context: "pre_visit", period: { kind: "fixed_dates", startLocalDate: "2040-01-01", endLocalDateExclusive: "2040-01-08", timezoneRule: "acceptance_time_iana" }, schedule: { type: "all_readings", windows: [] }, cadence: { type: "at_period_end" }, pulse: "preferred" };
const preview = createRequestPreview({ relationshipId: "relationship_unique_a", templateId: "template_default_a", templateRevision: 1, builder, practiceDisplayName: "Fictional Practice A" });

function setup() {
  let sequence = 0;
  const factories: SyntheticFactories = { clock: () => "2040-01-01T00:00:00.000Z", id: kind => `${kind}_matrix_${++sequence}`, token: kind => `${kind}_matrix_${++sequence}_A7vQ9xL2mN4pR6tW8yZ1` };
  const service = new SyntheticClinicalService(factories);
  const auth = (login: "clinician" | "admin" | "other" | "other_admin") => { const challenge = service.signIn(login); return service.verifyMfa(challenge.challengeId, "246810").sessionId; };
  const clinician = auth("clinician"); const admin = auth("admin"); const clinicianB = auth("other"); const adminB = auth("other_admin"); service.relationshipSelect(clinician, "relationship_unique_a");
  return { service, clinician, admin, clinicianB, adminB };
}

function payload(operation: OperationName, foreign = false): Record<string, unknown> {
  const id = (_kind: string, local: string) => foreign ? "relationship_unique_b" : local;
  const operationPreview = foreign ? createRequestPreview({ relationshipId: "relationship_unique_b", templateId: "template_default_b", templateRevision: 1, builder, practiceDisplayName: "Fictional Practice B" }) : preview;
  const values: Partial<Record<OperationName, Record<string, unknown>>> = {
    sign_in: { login: "clinician" }, verify_mfa: { challengeId: "challenge_unknown", code: "246810" }, reauthenticate: { code: "246810" },
    relationship_search: { query: "unique" }, relationship_select: { relationshipId: id("relationship", "relationship_unique_a") },
    template_create: { builder }, template_revise: { templateId: foreign ? "template_default_b" : "template_default_a", expectedRevision: 1, builder }, template_archive: { templateId: foreign ? "template_default_b" : "template_default_a", expectedRevision: 1 },
    request_preview: { templateId: foreign ? "template_default_b" : "template_default_a", expectedTemplateRevision: 1, builder }, request_issue: { preview: operationPreview, idempotencyKey: "matrix-issue" },
    invitation_claim: { token: "invitation_unknown", deviceIanaTimezone: "Etc/UTC" }, invitation_accept: { claimantReceipt: "claimant_unknown", reviewedAcceptanceSha256: "0".repeat(64) }, invitation_revoke: { requestId: foreign ? "request_state_issued_b" : "request_state_issued" }, invitation_expire: { requestId: foreign ? "request_state_issued_b" : "request_state_issued" },
    request_cancel: { requestId: foreign ? "request_state_issued_b" : "request_state_issued", expectedRevision: 1 }, request_renew: { predecessorId: foreign ? "request_state_issued_b" : "request_state_active", preview: operationPreview, idempotencyKey: "matrix-renew" },
    inbox: { filter: { pageSize: 2 } }, packet_load: { packetId: foreign ? "packet_complete_b" : "packet_complete_apple" }, packet_download: { packetId: foreign ? "packet_complete_b" : "packet_complete_apple" },
    packet_acknowledge: { packetId: foreign ? "packet_complete_b" : "packet_complete_apple", expectedRevision: 1, idempotencyKey: "matrix-ack" }, packet_review: { packetId: foreign ? "packet_complete_b" : "packet_complete_apple", expectedRevision: 1, idempotencyKey: "matrix-review" }, packet_passive_event: { packetId: foreign ? "packet_complete_b" : "packet_complete_apple", event: "print" },
    member_role_change: { membershipId: foreign ? "membership_admin_b" : "membership_clinician_a", role: "practice_admin" }, member_offboard: { membershipId: foreign ? "membership_admin_b" : "membership_clinician_a" }, member_revoke_sessions: { membershipId: foreign ? "membership_admin_b" : "membership_clinician_a" }, audit: { cursor: 0, pageSize: 5 },
  };
  return values[operation] ?? {};
}
function envelope(operation: OperationName, foreign = false): OperationEnvelope { return { version: SYNTHETIC_OPERATION_VERSION, operation, payload: payload(operation, foreign) }; }
async function denial(run: () => unknown | Promise<unknown>) { try { await run(); throw new Error("matrix operation unexpectedly succeeded"); } catch (error) { expect((error as { code?: string }).code).toBe("operation_unavailable"); } }
function auditFactCount(service: SyntheticClinicalService): number { return service.auditSnapshotForTest().length + service.auditReadSnapshotForTest().length; }
function auditLengths(service: SyntheticClinicalService): [number, number] { return [service.auditSnapshotForTest().length, service.auditReadSnapshotForTest().length]; }
function auditFactsSince(service: SyntheticClinicalService, [events, reads]: [number, number]) { return [...service.auditSnapshotForTest().slice(events), ...service.auditReadSnapshotForTest().slice(reads)]; }
function expectedSuccessAudit(operation: OperationName, actorCode: string): { action: string; category: string; actorCode: string } {
  const action = operation === "retention" ? "retention_read" : operation === "packet_acknowledge" ? "packet_acknowledged" : operation === "packet_review" ? "packet_reviewed" : operation === "packet_passive_event" ? "packet_print" : operation;
  const category = ["session_bootstrap", "reauthenticate", "session"].includes(operation) ? "authentication" : operation === "logout" || ["invitation_revoke", "member_offboard", "member_revoke_sessions"].includes(operation) ? "revocation" : ["inbox", "packet_load", "packet_download", "packet_passive_event"].includes(operation) ? "access_download" : ["packet_acknowledge", "packet_review"].includes(operation) ? "acknowledgment_review" : ["members", "member_role_change"].includes(operation) ? "role_change" : operation === "retention" || operation === "audit" ? "support_access" : "request";
  return { action, category, actorCode };
}
function expectedDeniedAction(operation: OperationName): string { return operation === "packet_acknowledge" ? "packet_acknowledged" : operation === "packet_review" ? "packet_reviewed" : operation; }
function expectSeededTenantBPayload(service: SyntheticClinicalService, clinicianB: string, adminB: string, operation: OperationName, value: Record<string, unknown>): void {
  const relationshipIds = service.relationshipSearch(clinicianB, "partition").results.map(item => item.id);
  const templateIds = service.templateList(clinicianB).map(item => item.id);
  const requestIds = service.requestList(clinicianB).map(item => item.id);
  const packetIds = service.inbox(clinicianB, {}).items.map(item => item.id);
  const membershipIds = service.members(adminB).map(item => item.membershipId);
  if ("relationshipId" in value) expect(relationshipIds, operation).toContain(value.relationshipId);
  if ("templateId" in value) expect(templateIds, operation).toContain(value.templateId);
  if ("requestId" in value) expect(requestIds, operation).toContain(value.requestId);
  if ("predecessorId" in value) expect(requestIds, operation).toContain(value.predecessorId);
  if ("packetId" in value) expect(packetIds, operation).toContain(value.packetId);
  if ("membershipId" in value) expect(membershipIds, operation).toContain(value.membershipId);
  if ("preview" in value) {
    const foreignPreview = value.preview as typeof preview;
    expect(relationshipIds, operation).toContain(foreignPreview.representation.relationshipId);
    expect(templateIds, operation).toContain(foreignPreview.representation.templateId);
  }
}

describe("machine-traceable route and operation security inventory", () => {
  it("classifies every fixed route and all 34 operations exactly once", () => {
    expect(authorizationPolicy.routes.map(item => item.route).sort()).toEqual([...portalRoutes].sort());
    expect(authorizationPolicy.operations.map(item => item.operation).sort()).toEqual([...operationNames].sort());
    expect(new Set(authorizationPolicy.routes.map(item => item.route)).size).toBe(portalRoutes.length);
    expect(new Set(authorizationPolicy.operations.map(item => item.operation)).size).toBe(operationNames.length);
  });

  it.each(authorizationPolicy.operations.filter(item => item.requiredCapability === "public"))("public operation matrix: $operation executes without a session boundary", async item => {
    const { service } = setup(); const operation = item.operation as OperationName;
    if (operation === "sign_in") { expect(service.signIn("clinician").authState).toBe("mfa_required"); return; }
    if (operation === "verify_mfa") { const challenge = service.signIn("clinician"); expect(service.verifyMfa(challenge.challengeId, "246810").authState).toBe("authenticated"); return; }
    if (operation === "recovery") { expect(service.recovery().authState).toBe("recovery_handoff"); return; }
    try { await dispatchClinicalOperation(service, "", envelope(operation)); } catch (error) { expect((error as { code?: string }).code).toBe("invitation_unavailable"); }
  });

  it.each(authorizationPolicy.operations.filter(item => item.noSessionTest))("operation matrix: $operation denies no session through canonical preauthorization", async item => {
    const { service } = setup(); const before = auditFactCount(service); const operation = item.operation as OperationName;
    await denial(() => service.preauthorizeOperation("missing_session", operation));
    expect(auditFactCount(service), operation).toBe(before + 1); expect(service.auditSnapshotForTest().at(-1)).toMatchObject({ tenantCode: "tenant_unknown", actorCode: "actor_unknown", category: "denied_access", action: operation, outcome: "denied" });
  });

  it.each(authorizationPolicy.operations.filter(item => item.wrongRoleTest))("operation matrix: $operation denies wrong role through canonical preauthorization", async item => {
    const { service, clinician, admin } = setup(); const session = item.authorizedRoles[0] === "clinician" ? admin : clinician; const before = auditFactCount(service);
    const operation = item.operation as OperationName; await denial(() => service.preauthorizeOperation(session, operation));
    expect(auditFactCount(service), operation).toBe(before + 1); expect(service.auditSnapshotForTest().at(-1)).toMatchObject({ tenantCode: "tenant_a", actorCode: session === admin ? "actor_admin" : "actor_clinician", category: "denied_access", action: operation, outcome: "denied" });
  });

  it.each(authorizationPolicy.operations.filter(item => item.requiredCapability !== "public"))("canonical operation policy runtime: $operation preauthorizes every declared role/capability mapping", item => {
    const { service, clinician, admin } = setup();
    for (const role of item.authorizedRoles) expect(() => service.preauthorizeOperation(role === "practice_admin" ? admin : clinician, item.operation as OperationName)).not.toThrow();
  });

  it.each(authorizationPolicy.operations.filter(item => item.requiredCapability !== "public"))("successful PHI-boundary operation matrix: $operation records a success audit fact", async item => {
    const { service, clinician, admin } = setup(); const operation = item.operation as OperationName; const session = item.authorizedRoles[0] === "practice_admin" ? admin : clinician;
    let operationPayload = payload(operation);
    if (operation === "request_renew") {
      const renewalBuilder = structuredClone(builder); renewalBuilder.context = "recurring_collection"; renewalBuilder.period = { kind: "fixed_dates", startLocalDate: "2040-01-08", endLocalDateExclusive: "2040-01-15", timezoneRule: "acceptance_time_iana" }; renewalBuilder.predecessorRequestId = "request_state_active";
      operationPayload = { predecessorId: "request_state_active", preview: createRequestPreview({ relationshipId: "relationship_unique_a", templateId: "template_default_a", templateRevision: 1, builder: renewalBuilder, practiceDisplayName: "Fictional Practice A" }), idempotencyKey: "matrix-renew-success" };
    }
    if (operation === "invitation_revoke" || operation === "invitation_expire") {
      const issued = await service.requestIssue(clinician, preview, `matrix-${operation}`); operationPayload = { requestId: issued.request.id };
    }
    if (operation.startsWith("member_")) service.reauthenticate(admin, "246810");
    const before = auditLengths(service);
    await dispatchClinicalOperation(service, session, { version: SYNTHETIC_OPERATION_VERSION, operation, payload: operationPayload });
    const newFacts = auditFactsSince(service, before); expect(newFacts.length, operation).toBeGreaterThan(0);
    expect(newFacts, operation).toEqual(expect.arrayContaining([expect.objectContaining({ tenantCode: "tenant_a", ...expectedSuccessAudit(operation, session === admin ? "actor_admin" : "actor_clinician"), outcome: "success" })]));
  });

  it.each(authorizationPolicy.operations.filter(item => item.tenantEvidence === "deny_foreign_resource"))("operation matrix: $operation denies an existing foreign tenant resource", async item => {
    const { service, clinician, admin, clinicianB, adminB } = setup(); const session = item.authorizedRoles[0] === "practice_admin" ? admin : clinician; const operation = item.operation as OperationName;
    const foreignPayload = payload(operation, true); expectSeededTenantBPayload(service, clinicianB, adminB, operation, foreignPayload);
    if (item.operation.startsWith("member_")) service.reauthenticate(admin, "246810");
    const before = auditFactCount(service); await denial(() => dispatchClinicalOperation(service, session, { version: SYNTHETIC_OPERATION_VERSION, operation, payload: foreignPayload }));
    expect(auditFactCount(service), operation).toBe(before + 1); expect(service.auditSnapshotForTest().at(-1)).toMatchObject({ tenantCode: "tenant_a", actorCode: session === admin ? "actor_admin" : "actor_clinician", category: "denied_access", action: expectedDeniedAction(operation), outcome: "denied" });
  });

  it("filter matrix excludes seeded tenant-B rows from every canonical filtered-result operation", () => {
    const { service, clinician, admin } = setup();
    expect(service.relationshipSearch(clinician, "partition").results.map(item => item.id)).not.toContain("relationship_unique_b");
    expect(service.templateList(clinician).map(item => item.id)).not.toContain("template_default_b"); expect(service.requestList(clinician).map(item => item.id)).not.toContain("request_state_issued_b");
    expect(service.inbox(clinician, {}).items.map(item => item.id)).not.toContain("packet_complete_b"); expect(service.members(admin).map(item => item.membershipId)).not.toContain("membership_admin_b");
    expect(service.retention(admin).deletion.map(item => item.packetCode)).not.toContain("artifact_complete_b"); expect(service.audit(admin, 0, 50).events.every(item => item.tenantCode === "tenant_a")).toBe(true);
  });
});
