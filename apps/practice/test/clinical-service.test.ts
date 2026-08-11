import { describe, expect, it } from "vitest";
import { auditCategories, type AuditCategory, type RequestBuilder, type RequestPreview } from "../src/contracts/clinical";
import { createRequestPreview } from "../src/synthetic/request-domain";
import { sha256Hex, SyntheticClinicalService, SyntheticServiceError, type SyntheticFactories } from "../src/synthetic/service";

function harness(lifetime = 60_000) {
  let now = Date.UTC(2040, 0, 1);
  let sequence = 0;
  const factories: SyntheticFactories = {
    clock: () => new Date(now).toISOString(),
    id: kind => `${kind}_${++sequence}`,
    token: kind => `${kind}_${++sequence}_A7vQ9xL2mN4pR6tW8yZ1bC3dE5fG7hJ9`,
  };
  const service = new SyntheticClinicalService(factories, lifetime);
  return { service, advance: (milliseconds: number) => { now += milliseconds; } };
}
function raceHarness() {
  let sequence = 0;
  const pending: Array<{ value: string; resolve: (hash: string) => void }> = [];
  const factories: SyntheticFactories = {
    clock: () => "2040-01-01T00:00:00.000Z",
    id: kind => `${kind}_${++sequence}`,
    token: kind => `${kind}_${++sequence}_A7vQ9xL2mN4pR6tW8yZ1bC3dE5fG7hJ9`,
    hash: value => new Promise(resolve => pending.push({ value, resolve })),
  };
  const service = new SyntheticClinicalService(factories);
  return { service, release: async () => { const item = pending.shift(); if (!item) throw new Error("no pending hash"); item.resolve(await sha256Hex(item.value)); } };
}
function login(service: SyntheticClinicalService, user: "admin" | "clinician" | "clinician_two" | "other" | "other_admin" = "clinician") {
  const challenge = service.signIn(user);
  return service.verifyMfa(challenge.challengeId, "246810");
}
function builder(context: RequestBuilder["context"] = "pre_visit", predecessorRequestId?: string): RequestBuilder {
  return {
    context, period: { kind: "fixed_dates", startLocalDate: predecessorRequestId ? "2040-01-08" : "2040-01-01", endLocalDateExclusive: predecessorRequestId ? "2040-01-15" : "2040-01-08", timezoneRule: "acceptance_time_iana" },
    schedule: { type: "all_readings", windows: [] }, cadence: { type: "at_period_end" }, pulse: "preferred",
    ...(predecessorRequestId === undefined ? {} : { predecessorRequestId }),
  };
}
function preparePreview(service: SyntheticClinicalService, sessionId: string, value = builder()): RequestPreview {
  if (service.sessionSelectionForTest(sessionId) !== "relationship_unique_a") service.relationshipSelect(sessionId, "relationship_unique_a");
  return service.requestPreview(sessionId, "template_default_a", 1, value);
}
function expectCode(run: () => unknown, code: string): void {
  try { run(); throw new Error("expected failure"); } catch (error) { expect(error).toBeInstanceOf(SyntheticServiceError); expect((error as SyntheticServiceError).code).toBe(code); }
}
function collectAuditSequences(service: SyntheticClinicalService, sessionId: string, expectedCount: number, category?: AuditCategory): number[] {
  const sequences: number[] = []; let cursor = 0;
  for (let pageCount = 0; pageCount <= expectedCount; pageCount += 1) {
    const page = service.audit(sessionId, cursor, 1, category);
    sequences.push(...page.events.map(event => event.sequence));
    if (page.nextCursor === null) return sequences;
    expect(page.nextCursor).toBe(page.events.at(-1)?.sequence);
    cursor = page.nextCursor;
  }
  throw new Error(`audit pagination did not terminate for ${category ?? "all"}`);
}

describe("authentication, abuse controls, and server-side step-up", () => {
  it("makes failed, expired, exhausted, and replayed MFA challenges terminal", () => {
    const { service, advance } = harness();
    const failed = service.signIn("clinician"); expectCode(() => service.verifyMfa(failed.challengeId, "000000"), "mfa_failed"); expectCode(() => service.verifyMfa(failed.challengeId, "246810"), "mfa_replay_or_invalid");
    const expired = service.signIn("clinician"); advance(5 * 60_000 + 1); expectCode(() => service.verifyMfa(expired.challengeId, "246810"), "mfa_expired");
    const one = service.signIn("clinician"); expectCode(() => service.verifyMfa(one.challengeId, "bad"), "mfa_failed");
    const two = service.signIn("clinician"); expectCode(() => service.verifyMfa(two.challengeId, "bad"), "mfa_failed");
    const three = service.signIn("clinician"); expectCode(() => service.verifyMfa(three.challengeId, "bad"), "mfa_failed");
    const exhausted = service.signIn("clinician"); expectCode(() => service.verifyMfa(exhausted.challengeId, "bad"), "rate_limited");
  });

  it("rate limits sign-in and derives role/capabilities from the authenticated membership", () => {
    const { service } = harness();
    for (let index = 0; index < 5; index += 1) expectCode(() => service.signIn("unknown"), "authentication_failed");
    expectCode(() => service.signIn("unknown"), "rate_limited");
    const auth = login(harness().service); expect(auth.sessionId).not.toContain("challenge");
  });

  it("derives the minimum practice identity for tenant A and B session results and fails closed for an unknown tenant", () => {
    const { service } = harness(); const tenantA = login(service); const tenantB = login(service, "other");
    expect(service.sessionBootstrap(tenantA.sessionId).session).toMatchObject({ tenantCode: "tenant_a", practiceDisplayName: "Fictional Practice A" });
    expect(service.session(tenantB.sessionId)).toMatchObject({ tenantCode: "tenant_b", practiceDisplayName: "Fictional Practice B" });
    expect(service.session(tenantB.sessionId).practiceDisplayName).not.toBe("Fictional Practice A");
    const memberships = (service as unknown as { memberships: Map<string, { tenantId: string }> }).memberships;
    memberships.get("membership_clinician_a")!.tenantId = "tenant_unknown_fixture";
    expectCode(() => service.sessionBootstrap(tenantA.sessionId), "operation_unavailable");
  });

  it("does not let unknown-login bucket churn reset an active real-identity sign-in limit", () => {
    const { service } = harness();
    for (let index = 0; index < 5; index += 1) expect(service.signIn("clinician").authState).toBe("mfa_required");
    const churnCodes: string[] = [];
    for (let index = 0; index < 300; index += 1) {
      try { service.signIn(`unknown-${index}`); } catch (error) { churnCodes.push((error as { code: string }).code); }
    }
    expect(churnCodes).toContain("authentication_failed");
    expect(churnCodes).toContain("rate_limited");
    expectCode(() => service.signIn("clinician"), "rate_limited");
  });

  it("expires/revokes sessions, clears selection, and never grants changed-role capabilities", () => {
    const { service, advance } = harness(10); const clinician = login(service); service.relationshipSelect(clinician.sessionId, "relationship_unique_a");
    advance(11); expectCode(() => service.session(clinician.sessionId), "session_expired"); expect(service.sessionSelectionForTest(clinician.sessionId)).toBeNull();
    const target = login(service); const admin = login(service, "admin"); service.reauthenticate(admin.sessionId, "246810");
    service.memberRoleChange(admin.sessionId, "membership_clinician_a", "practice_admin");
    expectCode(() => service.session(target.sessionId), "session_revoked");
    const promoted = login(service); expect(service.session(promoted.sessionId).capabilities).toContain("member:manage"); expect(service.session(promoted.sessionId).capabilities).not.toContain("packet:read");
  });

  it("requires, consumes, and expires server-side MFA step-up for every high-risk admin action", () => {
    const { service, advance } = harness(10 * 60_000); const admin = login(service, "admin"); const clinician = login(service);
    expectCode(() => service.memberRevokeSessions(admin.sessionId, "membership_clinician_a"), "reauthentication_required");
    expectCode(() => service.reauthenticate(admin.sessionId, "wrong"), "reauthentication_failed");
    service.reauthenticate(admin.sessionId, "246810"); service.memberRevokeSessions(admin.sessionId, "membership_clinician_a");
    expectCode(() => service.session(clinician.sessionId), "session_revoked");
    expectCode(() => service.memberOffboard(admin.sessionId, "membership_clinician_a"), "reauthentication_required");
    service.reauthenticate(admin.sessionId, "246810"); advance(5 * 60_000 + 1); expectCode(() => service.memberOffboard(admin.sessionId, "membership_clinician_a"), "reauthentication_required");
  });

  it("never reactivates disabled or offboarded memberships through role change", () => {
    const { service } = harness(); const admin = login(service, "admin");
    service.reauthenticate(admin.sessionId, "246810"); expectCode(() => service.memberRoleChange(admin.sessionId, "membership_disabled_a", "practice_admin"), "invalid_transition");
    service.reauthenticate(admin.sessionId, "246810"); service.memberOffboard(admin.sessionId, "membership_clinician_a");
    service.reauthenticate(admin.sessionId, "246810"); expectCode(() => service.memberRoleChange(admin.sessionId, "membership_clinician_a", "practice_admin"), "invalid_transition");
    expect(service.members(admin.sessionId).find(item => item.membershipId === "membership_clinician_a")?.state).toBe("offboarded");
  });

  it("bounds each synthetic audit partition independently", () => {
    const { service } = harness(); const clinician = login(service); login(service, "other");
    const tenantBBefore = service.auditSnapshotForTest("tenant_b").map(event => event.sequence);
    for (let index = 0; index < 1_050; index += 1) service.packetLoad(clinician.sessionId, "packet_complete_apple");
    for (let index = 0; index < 1_050; index += 1) expectCode(() => service.assertCsrf("", ""), "operation_unavailable");
    expect(service.auditSnapshotForTest("tenant_a")).toHaveLength(1_000); expect(service.auditSnapshotForTest("security_unknown")).toHaveLength(1_000);
    expect(service.auditSnapshotForTest("tenant_b").map(event => event.sequence)).toEqual(tenantBBefore);
    expect(tenantBBefore).toEqual([1, 2, 3]);
  });

  it("keeps cross-tenant and role denials generic and health-free in audit", () => {
    const { service } = harness(); const clinician = login(service); const other = login(service, "other"); const admin = login(service, "admin");
    expectCode(() => service.relationshipSelect(clinician.sessionId, "relationship_unique_b"), "operation_unavailable");
    expectCode(() => service.packetLoad(other.sessionId, "packet_complete_apple"), "operation_unavailable");
    expectCode(() => service.members(clinician.sessionId), "operation_unavailable"); expectCode(() => service.packetLoad(admin.sessionId, "packet_complete_apple"), "operation_unavailable");
    const audit = JSON.stringify(service.auditSnapshotForTest());
    for (const prohibited of ["relationship_unique_b", "packet_complete_apple", "systolic", "token"]) expect(audit).not.toContain(prohibited);
  });

  it("derives exact tenant-specific practice instructions and rejects tenant-B previews rendered for A", async () => {
    const { service } = harness();
    const tenantA = login(service); service.relationshipSelect(tenantA.sessionId, "relationship_unique_a");
    const previewA = service.requestPreview(tenantA.sessionId, "template_default_a", 1, builder());
    expect(previewA.representation.renderedInstructions).toContain("Fictional Practice A");
    expect(previewA.representation.renderedInstructions).not.toContain("Fictional Practice B");

    const tenantB = login(service, "other"); service.relationshipSelect(tenantB.sessionId, "relationship_unique_b");
    const previewB = service.requestPreview(tenantB.sessionId, "template_default_b", 1, builder());
    expect(previewB.representation.renderedInstructions).toContain("Fictional Practice B");
    expect(previewB.representation.renderedInstructions).not.toContain("Fictional Practice A");
    await expect(service.requestIssue(tenantB.sessionId, previewB, "tenant-b-correct")).resolves.toHaveProperty("request.representation.renderedInstructions", previewB.representation.renderedInstructions);
    const forgedA = createRequestPreview({ relationshipId: "relationship_unique_b", templateId: "template_default_b", templateRevision: 1, builder: builder(), practiceDisplayName: "Fictional Practice A" });
    await expect(service.requestIssue(tenantB.sessionId, forgedA, "tenant-b-wrong-display")).rejects.toMatchObject({ code: "preview_conflict" });
  });

  it("records the current authenticated admin as each new template revision author", () => {
    const { service } = harness(); const adminA = login(service, "admin"); const adminB = login(service, "other_admin");
    expect(service.templateRevise(adminA.sessionId, "template_default_a", 1, builder()).authorCode).toBe("actor_admin");
    const revisedB = service.templateRevise(adminB.sessionId, "template_default_b", 1, builder());
    expect(revisedB.authorCode).toBe("actor_admin_b");
    expect(revisedB.authorCode).not.toBe("actor_other");
  });

  it("resolves concurrent template revision conflicts and safely reuses only the current immutable revision", async () => {
    const { service } = harness(); const firstAdmin = login(service, "admin"); const secondAdmin = login(service, "admin");
    const revisionTwo = service.templateRevise(firstAdmin.sessionId, "template_default_a", 1, builder());
    expectCode(() => service.templateRevise(secondAdmin.sessionId, "template_default_a", 1, builder()), "stale_revision");
    expect(revisionTwo).toMatchObject({ revision: 2, previousRevision: 1, state: "active" });
    const clinician = login(service); service.relationshipSelect(clinician.sessionId, "relationship_unique_a");
    const currentPreview = service.requestPreview(clinician.sessionId, "template_default_a", 2, revisionTwo.builder);
    const first = await service.requestIssue(clinician.sessionId, currentPreview, "template-reuse-one");
    const second = await service.requestIssue(clinician.sessionId, currentPreview, "template-reuse-two");
    expect([first.request.representation.templateRevision, second.request.representation.templateRevision]).toEqual([2, 2]);
    service.templateArchive(firstAdmin.sessionId, "template_default_a", 2);
    expect(service.requestList(clinician.sessionId).filter(request => [first.request.id, second.request.id].includes(request.id)).every(request => request.representation.templateRevision === 2)).toBe(true);
    expectCode(() => service.requestPreview(clinician.sessionId, "template_default_a", 1, builder()), "operation_unavailable");
  });

  it("rejects predecessor linkage in template create and revise before persistence or success audit", () => {
    const { service } = harness(); const admin = login(service, "admin"); const malicious = builder("recurring_collection", "request_state_active");
    const successCount = () => service.auditSnapshotForTest("tenant_a").filter(event => event.outcome === "success" && ["template_create", "template_revise"].includes(event.action)).length;
    const before = successCount();
    expectCode(() => service.templateCreate(admin.sessionId, malicious), "predecessor_not_allowed");
    expectCode(() => service.templateRevise(admin.sessionId, "template_default_a", 1, malicious), "predecessor_not_allowed");
    expect(successCount()).toBe(before);
    const current = service.templateList(admin.sessionId).find(item => item.id === "template_default_a");
    expect(current).toMatchObject({ revision: 1, state: "active" }); expect(current?.builder).not.toHaveProperty("predecessorRequestId");
    expect(service.templateList(admin.sessionId).some(item => item.builder.predecessorRequestId !== undefined)).toBe(false);
  });

  it("keeps audit-read facts in a separate bounded tenant sink and terminates page-size-one filters", () => {
    const { service } = harness(); const admin = login(service, "admin"); service.retention(admin.sessionId);
    const sourceBefore = service.auditSnapshotForTest("tenant_a");
    for (const category of [undefined, ...auditCategories] as const) {
      const expected = sourceBefore.filter(event => category === undefined || event.category === category).map(event => event.sequence);
      const actual = collectAuditSequences(service, admin.sessionId, expected.length, category);
      expect(actual).toEqual(expected);
      expect(new Set(actual).size).toBe(actual.length);
    }
    expect(service.auditSnapshotForTest("tenant_a")).toEqual(sourceBefore);
    const readFacts = service.auditReadSnapshotForTest("tenant_a");
    expect(readFacts.length).toBeGreaterThan(0);
    expect(readFacts.every(fact => fact.tenantCode === "tenant_a" && fact.category === "support_access" && fact.action === "audit")).toBe(true);
    expect(service.auditReadSnapshotForTest("tenant_b")).toEqual([]);
    const encoded = JSON.stringify(readFacts);
    for (const prohibited of ["systolic", "diastolic", "pulse", "token", "packet_", "request_", "relationship_"]) expect(encoded).not.toContain(prohibited);
  });

  it("paginates the capped audit stream and every category at page size one without gaps, duplicates, or nontermination", () => {
    const { service } = harness(); const admin = login(service, "admin");
    for (let index = 0; index < 1_050; index += 1) service.templateList(admin.sessionId);
    const source = service.auditSnapshotForTest("tenant_a"); expect(source).toHaveLength(1_000);
    for (const category of [undefined, ...auditCategories] as const) {
      const expected = source.filter(event => category === undefined || event.category === category).map(event => event.sequence);
      const actual = collectAuditSequences(service, admin.sessionId, expected.length, category);
      expect(actual).toEqual(expected);
      expect(new Set(actual).size).toBe(actual.length);
    }
    expect(service.auditSnapshotForTest("tenant_a")).toEqual(source);
    expect(service.auditReadSnapshotForTest("tenant_a")).toHaveLength(1_000);
    expect(service.auditReadSnapshotForTest("tenant_b")).toEqual([]);
  });

  it("seeds and filters real tenant-B relationship, template, request, inbox, member, retention, and audit rows", () => {
    const { service } = harness(); const clinicianA = login(service); const clinicianB = login(service, "other"); const adminA = login(service, "admin"); const adminB = login(service, "other_admin");
    expect(service.relationshipSearch(clinicianA.sessionId, "partition").results.map(item => item.id)).toEqual(["relationship_unique_a"]);
    expect(service.relationshipSearch(clinicianB.sessionId, "partition").results.map(item => item.id)).toEqual(["relationship_unique_b"]);
    expect(service.templateList(clinicianA.sessionId).map(item => item.id)).not.toContain("template_default_b"); expect(service.templateList(clinicianB.sessionId).map(item => item.id)).toContain("template_default_b");
    expect(service.requestList(clinicianA.sessionId).map(item => item.id)).not.toContain("request_state_issued_b"); expect(service.requestList(clinicianB.sessionId).map(item => item.id)).toContain("request_state_issued_b");
    expect(service.inbox(clinicianA.sessionId, {}).items.map(item => item.id)).not.toContain("packet_complete_b"); expect(service.inbox(clinicianB.sessionId, {}).items.map(item => item.id)).toEqual(["packet_complete_b"]);
    expect(service.members(adminA.sessionId).map(item => item.membershipId)).not.toContain("membership_admin_b"); expect(service.members(adminB.sessionId).map(item => item.membershipId)).toEqual(expect.arrayContaining(["membership_clinician_b", "membership_admin_b"]));
    expect(service.retention(adminA.sessionId).deletion.map(item => item.packetCode)).not.toContain("artifact_complete_b"); expect(service.retention(adminB.sessionId).deletion.map(item => item.packetCode)).toContain("artifact_complete_b");
    expect(service.audit(adminA.sessionId, 0, 50).events.every(item => item.tenantCode === "tenant_a")).toBe(true); const auditB = service.audit(adminB.sessionId, 0, 50).events; expect(auditB.length).toBeGreaterThan(0); expect(auditB.every(item => item.tenantCode === "tenant_b")).toBe(true);
  });
});

describe("relationships, templates, idempotent issuance, and invitations", () => {
  it("rate limits lookup and represents all search outcomes", () => {
    const { service } = harness(); const auth = login(service);
    expect(service.relationshipSearch(auth.sessionId, "zero").state).toBe("zero"); expect(service.relationshipSearch(auth.sessionId, "unique").state).toBe("unique"); expect(service.relationshipSearch(auth.sessionId, "ambiguous").state).toBe("ambiguous");
    expectCode(() => service.relationshipSearch(auth.sessionId, "inactive"), "rate_limited"); const second = login(service); expect(service.relationshipSearch(second.sessionId, "inactive").state).toBe("inactive"); expectCode(() => service.relationshipSearch(second.sessionId, "denied"), "operation_unavailable");
  });

  it("requires the exact active current template at preview and issuance", async () => {
    const { service } = harness(); const clinician = login(service); const preview = preparePreview(service, clinician.sessionId); const admin = login(service, "admin");
    service.templateArchive(admin.sessionId, "template_default_a", 1);
    await expect(service.requestIssue(clinician.sessionId, preview, "archive-key")).rejects.toMatchObject({ code: "operation_unavailable" });
    expectCode(() => service.requestPreview(clinician.sessionId, "template_default_a", 1, builder()), "operation_unavailable");
  });

  it("preserves an issued request's immutable template revision and canonical representation after archival", async () => {
    const { service } = harness(); const clinician = login(service); const preview = preparePreview(service, clinician.sessionId);
    const issued = await service.requestIssue(clinician.sessionId, preview, "immutable-template-reference");
    const admin = login(service, "admin"); service.templateArchive(admin.sessionId, "template_default_a", 1);
    const persisted = service.requestList(clinician.sessionId).find(request => request.id === issued.request.id);
    expect(persisted).toMatchObject({ representation: { templateId: "template_default_a", templateRevision: 1 }, canonicalJson: issued.request.canonicalJson });
    expect(persisted?.representation).toEqual(issued.request.representation);
    expect(service.templateList(admin.sessionId).find(template => template.id === "template_default_a")).toMatchObject({ revision: 1, state: "archived" });
  });

  it("revalidates template/session after async hashing so archive wins an issue race", async () => {
    const { service, release } = raceHarness(); const clinician = login(service); const preview = preparePreview(service, clinician.sessionId); const pending = service.requestIssue(clinician.sessionId, preview, "archive-race");
    const admin = login(service, "admin"); service.templateArchive(admin.sessionId, "template_default_a", 1); await release();
    await expect(pending).rejects.toMatchObject({ code: "operation_unavailable" }); expect(service.requestList(clinician.sessionId).filter(item => item.id.startsWith("request_") && !item.id.startsWith("request_state_") && !item.id.startsWith("request_fixture"))).toHaveLength(0);
  });

  it("reserves tenant-scoped issuance idempotency before hashing and never redisplays a token", async () => {
    const { service } = harness(); const first = login(service); const second = login(service); const preview = preparePreview(service, first.sessionId); service.relationshipSelect(second.sessionId, "relationship_unique_a");
    const [one, two] = await Promise.all([service.requestIssue(first.sessionId, preview, "shared-key"), service.requestIssue(second.sessionId, preview, "shared-key")]);
    expect(one.request.id).toBe(two.request.id); expect([one.invitation.token, two.invitation.token].filter(Boolean)).toHaveLength(1);
    const replay = await service.requestIssue(second.sessionId, preview, "shared-key"); expect(replay.invitation).toMatchObject({ token: null, displayState: "already_displayed" });
    const otherBuilder = builder(); otherBuilder.pulse = "required";
    const otherPreview = createRequestPreview({ relationshipId: "relationship_unique_a", templateId: "template_default_a", templateRevision: 1, builder: otherBuilder, practiceDisplayName: "Fictional Practice A" });
    await expect(service.requestIssue(first.sessionId, otherPreview, "shared-key")).rejects.toMatchObject({ code: "idempotency_conflict" });
  });

  it("rejects predecessor linkage on ordinary issuance", async () => {
    const { service } = harness(); const auth = login(service); const linked = preparePreview(service, auth.sessionId, builder("recurring_collection", "request_state_active"));
    await expect(service.requestIssue(auth.sessionId, linked, "bad-link")).rejects.toMatchObject({ code: "predecessor_not_allowed" });
  });

  it("records request expiration and enforces immutable request revision on cancellation", async () => {
    const { service } = harness(); const clinician = login(service); const preview = preparePreview(service, clinician.sessionId);
    const expiring = await service.requestIssue(clinician.sessionId, preview, "request-expiration");
    service.invitationExpire(clinician.sessionId, expiring.request.id);
    expect(service.requestList(clinician.sessionId).find(request => request.id === expiring.request.id)).toMatchObject({ revision: 1, lifecycle: "expired", claim: "expired", history: expect.arrayContaining([expect.objectContaining({ type: "expired", revision: 1 })]) });
    const cancellable = await service.requestIssue(clinician.sessionId, preview, "request-revision");
    expectCode(() => service.requestCancel(clinician.sessionId, cancellable.request.id, 2), "stale_revision");
    expect(service.requestList(clinician.sessionId).find(request => request.id === cancellable.request.id)).toMatchObject({ revision: 1, lifecycle: "issued" });
    expect(service.requestCancel(clinician.sessionId, cancellable.request.id, 1)).toMatchObject({ revision: 1, lifecycle: "canceled" });
  });

  it("consumes invitation into a distinct one-time claimant receipt and enforces expiry/cancel/replay", async () => {
    const { service, advance } = harness(); const auth = login(service); const preview = preparePreview(service, auth.sessionId); const issued = await service.requestIssue(auth.sessionId, preview, "invite"); const token = issued.invitation.token!;
    expect(service.invitationHashForTest(issued.request.id)).toBe(await sha256Hex(token));
    const claim = await service.invitationClaim(token, "Etc/UTC"); expect(service.invitationHashForTest(issued.request.id)).toBeUndefined(); expect(service.claimantHashForTest(issued.request.id)).toBe(await sha256Hex(claim.claimantReceipt));
    await expect(service.invitationClaim(token, "Etc/UTC")).rejects.toMatchObject({ code: "invitation_unavailable" }); expect(await service.invitationAccept(claim.claimantReceipt, claim.reviewSha256)).toMatchObject({ claim: "accepted" });
    await expect(service.invitationAccept(claim.claimantReceipt, claim.reviewSha256)).rejects.toMatchObject({ code: "invitation_unavailable" });

    const canceled = await service.requestIssue(auth.sessionId, preview, "cancel"); service.requestCancel(auth.sessionId, canceled.request.id, 1); await expect(service.invitationClaim(canceled.invitation.token!, "Etc/UTC")).rejects.toMatchObject({ code: "invitation_unavailable" });
    const expired = await service.requestIssue(auth.sessionId, preview, "expiry"); advance(15 * 60_000 + 1);
    const refreshed = login(service); expect(service.requestList(refreshed.sessionId).find(request => request.id === expired.request.id)).toMatchObject({ lifecycle: "expired", claim: "expired", history: expect.arrayContaining([expect.objectContaining({ type: "expired", actorCode: "actor_system", revision: 1 })]) });
    await expect(service.invitationClaim(expired.invitation.token!, "Etc/UTC")).rejects.toMatchObject({ code: "invitation_unavailable" }); expect(service.invitationHashForTest(expired.request.id)).toBeUndefined();
    expect(service.auditSnapshotForTest("tenant_a")).toEqual(expect.arrayContaining([expect.objectContaining({ actorCode: "actor_system", action: "invitation_expire", outcome: "success" })]));
  });

  it("expires and consumes an unaccepted claimant receipt", async () => {
    const { service, advance } = harness(30 * 60_000); const auth = login(service); const preview = preparePreview(service, auth.sessionId); const issued = await service.requestIssue(auth.sessionId, preview, "claimant-expiry");
    const claim = await service.invitationClaim(issued.invitation.token!, "Etc/UTC"); advance(5 * 60_000 + 1);
    expect(service.requestList(auth.sessionId).find(request => request.id === issued.request.id)).toMatchObject({ lifecycle: "expired", claim: "expired", history: expect.arrayContaining([expect.objectContaining({ type: "expired", actorCode: "actor_system", revision: 1 })]) });
    await expect(service.invitationAccept(claim.claimantReceipt, claim.reviewSha256)).rejects.toMatchObject({ code: "invitation_unavailable" }); expect(service.claimantHashForTest(issued.request.id)).toBeUndefined();
    expect(service.auditSnapshotForTest("tenant_a")).toEqual(expect.arrayContaining([expect.objectContaining({ actorCode: "actor_system", action: "invitation_expire", outcome: "success" })]));
  });

  it("rate limits per token hash without one token blocking another", async () => {
    const { service } = harness(); const auth = login(service); const preview = preparePreview(service, auth.sessionId); const issued = await service.requestIssue(auth.sessionId, preview, "rate-independent");
    for (let index = 0; index < 5; index += 1) await expect(service.invitationClaim("same_invalid_token", "Etc/UTC")).rejects.toMatchObject({ code: "invitation_unavailable" });
    await expect(service.invitationClaim("same_invalid_token", "Etc/UTC")).rejects.toMatchObject({ code: "rate_limited" });
    await expect(service.invitationClaim(issued.invitation.token!, "Etc/UTC")).resolves.toHaveProperty("claimantReceipt");
  });

  it("keeps renewal pending until successor acceptance and serializes replay/concurrency", async () => {
    const { service } = harness(); const auth = login(service); const recurring = preparePreview(service, auth.sessionId, builder("recurring_collection")); const first = await service.requestIssue(auth.sessionId, recurring, "first");
    const claim = await service.invitationClaim(first.invitation.token!, "Etc/UTC"); await service.invitationAccept(claim.claimantReceipt, claim.reviewSha256);
    const successorPreview = createRequestPreview({ relationshipId: first.request.relationshipId, templateId: "template_default_a", templateRevision: 1, builder: builder("recurring_collection", first.request.id), practiceDisplayName: "Fictional Practice A" });
    const [one, two] = await Promise.all([service.requestRenew(auth.sessionId, first.request.id, successorPreview, "renew"), service.requestRenew(auth.sessionId, first.request.id, successorPreview, "renew")]);
    expect(one.request.id).toBe(two.request.id); expect([one.invitation.token, two.invitation.token].filter(Boolean)).toHaveLength(1);
    const pending = service.requestList(auth.sessionId).find(item => item.id === first.request.id)!; expect(pending.lifecycle).toBe("accepted"); expect(pending.successorRequestId).toBe(one.request.id);
    const successorToken = one.invitation.token ?? two.invitation.token!; const successorClaim = await service.invitationClaim(successorToken, "America/New_York"); await service.invitationAccept(successorClaim.claimantReceipt, successorClaim.reviewSha256);
    expect(service.requestList(auth.sessionId).find(item => item.id === first.request.id)?.lifecycle).toBe("renewed");
    expect((await service.requestRenew(auth.sessionId, first.request.id, successorPreview, "renew")).invitation.token).toBeNull();
    await expect(service.requestRenew(auth.sessionId, first.request.id, successorPreview, "different")).rejects.toMatchObject({ code: "successor_required" });
  });

  it("revalidates predecessor lifecycle after hashing so cancel wins a renew race", async () => {
    const { service, release } = raceHarness(); const auth = login(service); service.relationshipSelect(auth.sessionId, "relationship_unique_a");
    const preview = service.requestPreview(auth.sessionId, "template_default_a", 1, builder("recurring_collection", "request_state_active"));
    const pending = service.requestRenew(auth.sessionId, "request_state_active", preview, "cancel-race"); service.requestCancel(auth.sessionId, "request_state_active", 1); await release();
    await expect(pending).rejects.toMatchObject({ code: "successor_required" }); expect(service.requestList(auth.sessionId).find(item => item.id === "request_state_active")?.successorRequestId).toBeNull();
  });

  it("requires exact predecessor and successor relationship equality", async () => {
    const { service } = harness(); const auth = login(service); service.relationshipSelect(auth.sessionId, "relationship_duplicate_a1");
    const preview = service.requestPreview(auth.sessionId, "template_default_a", 1, builder("recurring_collection", "request_state_active"));
    await expect(service.requestRenew(auth.sessionId, "request_state_active", preview, "wrong-relationship")).rejects.toMatchObject({ code: "successor_required" });
  });
});

describe("packet projections, workflow, retention, and strict filters", () => {
  it("uses a minimum-necessary inbox DTO and validates filters", () => {
    const { service } = harness(); const auth = login(service); const item = service.inbox(auth.sessionId, { requestId: "request_fixture", pageSize: 25 }).items.find(candidate => candidate.id === "packet_complete_apple")!;
    expect(Object.keys(item).sort()).toEqual(["acknowledged", "availability", "context", "coverage", "id", "opened", "receivedAt", "relationshipLabel", "requestId", "requestedPeriod", "reviewed", "revision", "shape", "submittedPeriod", "supersededByPacketId", "supersedesPacketId"].sort());
    expect(item).toMatchObject({ relationshipLabel: "Fictional relationship", requestId: "request_fixture", context: "pre_visit", receivedAt: expect.stringMatching(/^2040-01-09T12:00:\d{2}Z$/), requestedPeriod: "2040-01-01/2040-01-08", submittedPeriod: "2040-01-01/2040-01-08", coverage: "satisfied", supersedesPacketId: "packet_superseded", supersededByPacketId: null, opened: false, acknowledged: false, reviewed: false });
    expect(item).not.toHaveProperty("readings"); expect(item).not.toHaveProperty("disclosures"); expect(item).not.toHaveProperty("limitations");
    expectCode(() => service.inbox(auth.sessionId, { pageSize: 0 }), "invalid_filter"); expectCode(() => service.inbox(auth.sessionId, { cursor: -1 }), "invalid_filter"); expectCode(() => service.inbox(auth.sessionId, { shape: "unknown" } as never), "invalid_filter");
  });

  it("records opened exactly once after the first successful authorized render or download, never denied access", () => {
    const { service } = harness(); const auth = login(service);
    expect(service.inbox(auth.sessionId, { requestId: "request_fixture" }).items.find(item => item.id === "packet_complete_apple")?.opened).toBe(false);
    const downloaded = service.packetDownload(auth.sessionId, "packet_complete_apple"); expect(downloaded.artifact).not.toHaveProperty("opened");
    expect(service.inbox(auth.sessionId, { requestId: "request_fixture" }).items.find(item => item.id === "packet_complete_apple")?.opened).toBe(true);
    expectCode(() => service.packetLoad(auth.sessionId, "packet_quarantined"), "operation_unavailable");
    const loaded = service.packetLoad(auth.sessionId, "packet_complete_apple"); expect(loaded.opened).toMatchObject({ type: "opened", actorCode: "actor_clinician", revision: 1 });
    expect(loaded.history.filter(fact => fact.type === "opened")).toHaveLength(1);
    expect(service.packetLoad(auth.sessionId, "packet_complete_apple").history.filter(fact => fact.type === "opened")).toHaveLength(1);
    expect(service.packetDownload(auth.sessionId, "packet_complete_apple").artifact).not.toHaveProperty("opened");
  });

  it("derives context from owned requests and filters and sorts before stable pagination", () => {
    const { service } = harness(); const auth = login(service); const other = login(service, "other");
    expect(service.inbox(auth.sessionId, { context: "medication_follow_up" }).items.map(item => item.id)).toEqual(["packet_partial_android"]);
    expect(service.inbox(auth.sessionId, { context: "recurring_collection" }).items.map(item => item.id)).toEqual(["packet_empty_apple"]);
    expect(service.inbox(auth.sessionId, { requestId: "request_state_issued_b" }).items).toEqual([]);
    expect(service.inbox(other.sessionId, { context: "pre_visit" }).items.map(item => item.id)).toEqual(["packet_complete_b"]);
    const ascendingItems = service.inbox(auth.sessionId, { sort: "received_asc", pageSize: 25 }).items;
    const descendingItems = service.inbox(auth.sessionId, { sort: "received_desc", pageSize: 25 }).items;
    const ascending = ascendingItems.map(item => item.id); const descending = descendingItems.map(item => item.id);
    expect(ascending.at(-1)).toBe("packet_offset_chronology"); expect(descending[0]).toBe("packet_offset_chronology");
    const utcDateItems = service.inbox(auth.sessionId, { receivedFromUtcDate: "2040-01-09", receivedToExclusiveUtcDate: "2040-01-10", pageSize: 25 }).items;
    expect(utcDateItems.find(item => item.id === "packet_offset_chronology")?.receivedAt).toBe("2040-01-08T23:30:00-14:00");
    expect(service.inbox(auth.sessionId, { receivedFromUtcDate: "2040-01-08", receivedToExclusiveUtcDate: "2040-01-09", pageSize: 25 }).items.map(item => item.id)).not.toContain("packet_offset_chronology");
    expect(new Set(ascendingItems.map(item => item.receivedAt)).size).toBe(ascendingItems.length);
    for (const item of ascendingItems) { expect(item.requestedPeriod).toBe(item.submittedPeriod); expect(Date.parse(item.receivedAt)).toBeGreaterThan(Date.parse(`${item.submittedPeriod.split("/")[1]}T00:00:00Z`)); }
    const admin = login(service, "admin"); const deletionByCode = new Map(service.retention(admin.sessionId).deletion.map(item => [item.packetCode, item]));
    for (const item of ascendingItems) expect(deletionByCode.get(item.id.replace(/^packet_/, "artifact_"))?.receivedAt).toBe(item.receivedAt);
    expect(descending).toEqual([...ascending].reverse()); expect(descending).not.toEqual(ascending);

    const packetMap = (service as unknown as { packets: Map<string, { receivedAt: string }> }).packets;
    packetMap.get("packet_complete_apple")!.receivedAt = "2040-01-09T11:59:59Z"; packetMap.get("packet_manual_android")!.receivedAt = "2040-01-09T11:59:59Z";
    const ascendingWithTie = service.inbox(auth.sessionId, { sort: "received_asc", pageSize: 25 }).items.map(item => item.id);
    const descendingWithTie = service.inbox(auth.sessionId, { sort: "received_desc", pageSize: 25 }).items.map(item => item.id);
    expect(ascendingWithTie.slice(0, 2)).toEqual(["packet_complete_apple", "packet_manual_android"]);
    expect(descendingWithTie).toEqual([...ascendingWithTie].reverse());
    expect(descendingWithTie.slice(-2)).toEqual(["packet_manual_android", "packet_complete_apple"]);
    const first = service.inbox(auth.sessionId, { sort: "received_asc", pageSize: 3 }); const second = service.inbox(auth.sessionId, { sort: "received_asc", cursor: first.nextCursor!, pageSize: 3 });
    expect(new Set([...first.items, ...second.items].map(item => item.id)).size).toBe(6);
    expect(service.inbox(auth.sessionId, { supersession: "superseded" }).items.map(item => item.id)).toEqual(["packet_superseded"]);
    expect(service.inbox(auth.sessionId, { supersession: "superseding" }).items.map(item => item.id)).toEqual(["packet_complete_apple"]);
    expect(service.inbox(auth.sessionId, { acknowledged: true }).items).toEqual([]); expect(service.inbox(auth.sessionId, { acknowledged: false }).items.length).toBeGreaterThan(0);
    expect(service.inbox(auth.sessionId, { reviewed: true }).items).toEqual([]); expect(service.inbox(auth.sessionId, { reviewed: false }).items.length).toBeGreaterThan(0);
    packetMap.get("packet_offset_chronology")!.receivedAt = "not-a-finite-timestamp";
    expectCode(() => service.inbox(auth.sessionId, {}), "operation_unavailable");
  });

  it("keeps immutable artifact download bytes stable across mutable workflow actions", () => {
    const { service } = harness(); const auth = login(service); const before = service.packetDownload(auth.sessionId, "packet_complete_apple").canonicalJson;
    service.packetPassiveEvent(auth.sessionId, "packet_complete_apple", "scroll"); service.packetReview(auth.sessionId, "packet_complete_apple", 1, "review"); service.packetAcknowledge(auth.sessionId, "packet_complete_apple", 1, "ack");
    const after = service.packetDownload(auth.sessionId, "packet_complete_apple").canonicalJson; expect(after).toBe(before); expect(after).not.toContain("acknowledged"); expect(after).not.toContain("opened");
  });

  it("centralizes availability denial and returns only a passive no-op receipt", () => {
    const { service } = harness(); const auth = login(service);
    expect(service.packetPassiveEvent(auth.sessionId, "packet_complete_apple", "dwell")).toEqual({ recorded: false, event: "dwell" });
    for (const operation of [
      () => service.packetLoad(auth.sessionId, "packet_quarantined"),
      () => service.packetDownload(auth.sessionId, "packet_quarantined"),
      () => service.packetPassiveEvent(auth.sessionId, "packet_quarantined", "print"),
      () => service.packetAcknowledge(auth.sessionId, "packet_quarantined", 1, "ack"),
      () => service.packetReview(auth.sessionId, "packet_quarantined", 1, "review"),
    ]) expectCode(operation, "operation_unavailable");
  });

  it("only explicit acknowledgment changes the synthetic retention schedule", () => {
    const { service } = harness(); const clinician = login(service); const admin = login(service, "admin");
    const initial = service.retention(admin.sessionId).deletion.find(item => item.packetCode === "artifact_complete_apple")!;
    expect(initial).toMatchObject({ state: "scheduled", trigger: "unacknowledged_max", receivedAt: "2040-01-09T12:00:59Z", unacknowledgedDeleteAt: "2040-04-08T12:00:59.000Z", scheduledDeleteAt: "2040-04-08T12:00:59.000Z" });
    const deadline = initial.scheduledDeleteAt;
    service.packetLoad(clinician.sessionId, "packet_complete_apple"); service.packetPassiveEvent(clinician.sessionId, "packet_complete_apple", "print"); service.packetReview(clinician.sessionId, "packet_complete_apple", 1, "review");
    expect(service.retention(admin.sessionId).deletion.find(item => item.packetCode === "artifact_complete_apple")?.scheduledDeleteAt).toBe(deadline);
    service.packetAcknowledge(clinician.sessionId, "packet_complete_apple", 1, "ack"); const acknowledged = service.retention(admin.sessionId).deletion.find(item => item.packetCode === "artifact_complete_apple")!;
    expect(acknowledged).toMatchObject({ state: "scheduled", trigger: "explicit_acknowledgment" }); expect(acknowledged.scheduledDeleteAt).toBe("2040-01-31T00:00:00.000Z");
    const receipts = service.retention(admin.sessionId).deletion;
    expect(receipts.find(item => item.packetCode === "artifact_deleted")).toMatchObject({ state: "purged", unacknowledgedDeleteAt: null, scheduledDeleteAt: null, trigger: "purged" });
    expect(receipts.find(item => item.packetCode === "artifact_revoked")).toMatchObject({ state: "scheduled", unacknowledgedDeleteAt: null, scheduledDeleteAt: "2040-01-09T12:00:51Z", trigger: "revocation" });
    expect(receipts.find(item => item.state === "held")?.legalHoldReceipt).toBe("synthetic_policy_receipt_hold"); expect(service.retention(admin.sessionId).policy.legalApproval).toBe(false);
  });

  it("audits retention reads and passive access truthfully and records workflow conflicts as denied", () => {
    const { service } = harness(); const clinician = login(service); const admin = login(service, "admin");
    service.retention(admin.sessionId); service.packetPassiveEvent(clinician.sessionId, "packet_complete_apple", "dwell"); service.packetPassiveEvent(clinician.sessionId, "packet_complete_apple", "scroll"); service.packetPassiveEvent(clinician.sessionId, "packet_complete_apple", "print");
    expectCode(() => service.packetAcknowledge(clinician.sessionId, "packet_complete_apple", 2, "stale"), "stale_revision");
    service.packetAcknowledge(clinician.sessionId, "packet_complete_apple", 1, "shared"); expectCode(() => service.packetAcknowledge(clinician.sessionId, "packet_partial_android", 1, "shared"), "idempotency_conflict");
    const events = service.auditSnapshotForTest("tenant_a");
    expect(events).toEqual(expect.arrayContaining([
      expect.objectContaining({ category: "support_access", action: "retention_read", outcome: "success" }),
      expect.objectContaining({ category: "access_download", action: "packet_dwell", outcome: "success" }),
      expect.objectContaining({ category: "denied_access", action: "packet_acknowledged_stale_revision", outcome: "denied" }),
      expect.objectContaining({ category: "denied_access", action: "packet_acknowledged_idempotency_conflict", outcome: "denied" }),
    ]));
    expect(events.some(event => event.category === "purge" && event.action === "retention")).toBe(false);
  });

  it("supports independent same-tenant clinician sessions and action-scoped idempotency", () => {
    const { service } = harness(); const first = login(service); const second = login(service, "clinician_two"); const admin = login(service, "admin");
    const acknowledged = service.packetAcknowledge(first.sessionId, "packet_complete_apple", 1, "same-key");
    const deadlineAfterAcknowledgment = service.retention(admin.sessionId).deletion.find(item => item.packetCode === "artifact_complete_apple")?.scheduledDeleteAt;
    const reviewed = service.packetReview(second.sessionId, "packet_complete_apple", 1, "same-key");
    expect(reviewed.reviewed?.actorCode).toBe("actor_clinician_two"); expect(reviewed.acknowledged).toEqual(acknowledged.acknowledged);
    const replay = service.packetAcknowledge(first.sessionId, "packet_complete_apple", 1, "same-key");
    expect(replay.acknowledged).toEqual(acknowledged.acknowledged); expect(replay.reviewed).toEqual(reviewed.reviewed);
    expect(replay.history.filter(fact => fact.type === "acknowledged")).toHaveLength(1); expect(replay.history.filter(fact => fact.type === "reviewed")).toHaveLength(1);
    expect(service.retention(admin.sessionId).deletion.find(item => item.packetCode === "artifact_complete_apple")?.scheduledDeleteAt).toBe(deadlineAfterAcknowledgment);
    const workflowEvents = service.auditSnapshotForTest("tenant_a").filter(event => event.category === "acknowledgment_review");
    expect(workflowEvents.filter(event => event.action === "packet_acknowledged")).toHaveLength(1); expect(workflowEvents.filter(event => event.action === "packet_reviewed")).toHaveLength(1);
  });

  it("strictly rejects invalid audit pagination/category and redacts values", () => {
    const { service } = harness(); const admin = login(service, "admin");
    expectCode(() => service.audit(admin.sessionId, -1, 20), "invalid_filter"); expectCode(() => service.audit(admin.sessionId, 0, 51), "invalid_filter"); expectCode(() => service.audit(admin.sessionId, 0, 20, "bad" as never), "invalid_filter");
    const encoded = JSON.stringify(service.audit(admin.sessionId, 0, 50).events); for (const prohibited of ["systolic", "diastolic", "pulseBeats", "token", "packet_complete", "actor_other"]) expect(encoded).not.toContain(prohibited);
  });
});
