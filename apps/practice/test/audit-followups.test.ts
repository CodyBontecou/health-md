import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import type { RequestBuilder } from "../src/contracts/clinical";
import { AcceptanceMaterializationError, canonicalJson, createAcceptanceReview, createRequestPreview, formatObservationInTimezone, materializeCollectionPeriod } from "../src/synthetic/request-domain";
import { sha256Hex, SyntheticClinicalService, type SyntheticFactories } from "../src/synthetic/service";

function builder(start = "2040-01-01", end = "2040-01-08", predecessorRequestId?: string): RequestBuilder {
  return { context: predecessorRequestId ? "recurring_collection" : "pre_visit", period: { kind: "fixed_dates", startLocalDate: start, endLocalDateExclusive: end, timezoneRule: "acceptance_time_iana" }, schedule: { type: "all_readings", windows: [] }, cadence: { type: "at_period_end" }, pulse: "preferred", ...(predecessorRequestId ? { predecessorRequestId } : {}) };
}
function harness() {
  let now = Date.UTC(2040, 0, 1); let sequence = 0;
  const factories: SyntheticFactories = { clock: () => new Date(now).toISOString(), id: kind => `${kind}_followup_${++sequence}`, token: kind => `${kind}_followup_${++sequence}_A7vQ9xL2mN4pR6tW8yZ1` };
  const service = new SyntheticClinicalService(factories);
  const login = (user: "clinician" | "clinician_two" | "admin" = "clinician") => { const challenge = service.signIn(user); return service.verifyMfa(challenge.challengeId, "246810"); };
  return { service, login, advance: (milliseconds: number) => { now += milliseconds; } };
}
function selectedPreview(service: SyntheticClinicalService, sessionId: string, value = builder()) {
  service.relationshipSelect(sessionId, "relationship_unique_a");
  return service.requestPreview(sessionId, "template_default_a", 1, value);
}
function raceHarness() {
  let sequence = 0; const pending: Array<{ value: string; resolve: (hash: string) => void }> = [];
  const service = new SyntheticClinicalService({ clock: () => "2040-01-01T00:00:00.000Z", id: kind => `${kind}_replay_${++sequence}`, token: kind => `${kind}_replay_${++sequence}_A7vQ9xL2mN4pR6tW8yZ1`, hash: value => new Promise(resolveHash => pending.push({ value, resolve: resolveHash })) });
  const login = (user: "clinician" | "clinician_two" | "admin") => { const challenge = service.signIn(user); return service.verifyMfa(challenge.challengeId, "246810"); };
  const release = async () => { const item = pending.shift(); if (!item) throw new Error("no pending hash"); item.resolve(await sha256Hex(item.value)); };
  return { service, login, release };
}
function claimantExpiryRaceHarness() {
  let now = Date.UTC(2040, 0, 1); let sequence = 0; let delayClaimant = false; let pending: { value: string; resolve: (hash: string) => void } | null = null;
  const service = new SyntheticClinicalService({
    clock: () => new Date(now).toISOString(), id: kind => `${kind}_expiry_race_${++sequence}`, token: kind => `${kind}_expiry_race_${++sequence}_A7vQ9xL2mN4pR6tW8yZ1`,
    hash: value => delayClaimant && value.startsWith("claimant_") ? new Promise(resolveHash => { pending = { value, resolve: resolveHash }; }) : sha256Hex(value),
  });
  return {
    service,
    delayNextClaimantHash: () => { delayClaimant = true; },
    advance: (milliseconds: number) => { now += milliseconds; },
    release: async () => { const item = pending as { value: string; resolve: (hash: string) => void } | null; if (!item) throw new Error("no pending claimant hash"); delayClaimant = false; item.resolve(await sha256Hex(item.value)); pending = null; },
  };
}

describe("acceptance materialization and fixed-timezone presentation", () => {
  it("matches the versioned exact common-instruction golden bytes", async () => {
    const preview = createRequestPreview({ relationshipId: "relationship_unique_a", templateId: "template_default_a", templateRevision: 1, builder: builder(), practiceDisplayName: "Fictional Practice A" });
    const golden = (await readFile(resolve(import.meta.dirname, "../fixtures/common-instructions.practice-bp-common-1.0-draft.1.txt"), "utf8")).trimEnd();
    expect(preview.representation.instructionVersion).toBe("practice-bp-common/1.0-draft.1");
    expect(preview.representation.renderedInstructions).toBe(golden);
  });

  it("materializes each local midnight independently across daylight-saving changes", () => {
    const spring = materializeCollectionPeriod(builder("2040-03-11", "2040-03-12"), "America/New_York");
    expect(spring).toMatchObject({ deviceIanaTimezone: "America/New_York", startUtcInclusive: "2040-03-11T05:00:00.000Z", endUtcExclusive: "2040-03-12T04:00:00.000Z" });
    expect(Date.parse(spring.endUtcExclusive) - Date.parse(spring.startUtcInclusive)).toBe(23 * 3_600_000);
    const fall = materializeCollectionPeriod(builder("2040-11-04", "2040-11-05"), "America/New_York");
    expect(Date.parse(fall.endUtcExclusive) - Date.parse(fall.startUtcInclusive)).toBe(25 * 3_600_000);
  });

  it("rejects offset-like and unknown zones and formats observations only in the packet zone", () => {
    for (const zone of ["GMT+05:00", "+05:00", "unknown", "Not/AZone"]) expect(() => materializeCollectionPeriod(builder(), zone)).toThrow(AcceptanceMaterializationError);
    expect(formatObservationInTimezone("2040-01-02T01:00:00Z", "America/Los_Angeles")).toBe("2040-01-01 17:00:00 America/Los_Angeles");
  });

  it("binds an exact acceptance review to canonical request bytes, versions, variant, timezone, dates, and UTC bounds", async () => {
    const value = builder(); value.practiceCollectionInstructions = "Use the fictional practice's approved synthetic draft wording.";
    const preview = createRequestPreview({ relationshipId: "relationship_unique_a", templateId: "template_default_a", templateRevision: 1, builder: value, practiceDisplayName: "Fictional Practice A" });
    const exactVariantBytes = canonicalJson({ commonInstructionVersion: "practice-bp-common/1.0-draft.1", practiceCollectionInstructions: value.practiceCollectionInstructions, practiceContactText: null });
    expect(preview.representation.practiceVariant).toEqual({ id: "template_default_a.synthetic-draft", version: `1.sha256-${await sha256Hex(exactVariantBytes)}`, approvalStatus: "synthetic_draft" });
    const changed = structuredClone(value); changed.practiceCollectionInstructions = "Use different exact synthetic draft wording.";
    expect(createRequestPreview({ relationshipId: "relationship_unique_a", templateId: "template_default_a", templateRevision: 1, builder: changed, practiceDisplayName: "Fictional Practice A" }).representation.practiceVariant?.version).not.toBe(preview.representation.practiceVariant?.version);
    const requestRepresentationSha256 = await sha256Hex(preview.canonicalJson);
    const review = createAcceptanceReview({ representation: preview.representation, requestRepresentationSha256, practiceDisplayName: "Fictional Practice A", deviceIanaTimezone: "America/New_York" });
    expect(review.renderedInstructions).toContain("2040-01-01 through before 2040-01-08 in America/New_York");
    expect(review.requestRepresentationSha256).toBe(requestRepresentationSha256);
    expect(await sha256Hex(canonicalJson(review))).toMatch(/^[a-f0-9]{64}$/);
  });
});

describe("acceptance, renewal, replay, and immutable packet service invariants", () => {
  it("does not consume a claim on a mismatched review digest and persists exact accepted facts once", async () => {
    const { service, login } = harness(); const auth = login(); const preview = selectedPreview(service, auth.sessionId); const issued = await service.requestIssue(auth.sessionId, preview, "acceptance-binding");
    await expect(service.invitationClaim(issued.invitation.token!, "GMT+05:00")).rejects.toMatchObject({ code: "acceptance_materialization_unavailable" });
    const claim = await service.invitationClaim(issued.invitation.token!, "America/New_York");
    await expect(service.invitationAccept(claim.claimantReceipt, "0".repeat(64))).rejects.toMatchObject({ code: "acceptance_review_mismatch" });
    const accepted = await service.invitationAccept(claim.claimantReceipt, claim.reviewSha256);
    expect(accepted.acceptance).toMatchObject({ reviewSha256: claim.reviewSha256, review: { requestRepresentationSha256: claim.review.requestRepresentationSha256, materializedPeriod: { deviceIanaTimezone: "America/New_York", startLocalDate: "2040-01-01", endLocalDateExclusive: "2040-01-08" } } });
    expect(service.requestList(auth.sessionId).find(item => item.id === issued.request.id)?.acceptance).toEqual(accepted.acceptance);
  });

  it("rejects unchanged, local-date-overlapping, and UTC-overlapping successor periods and accepts safe exact bounds", async () => {
    const { service, login } = harness(); const auth = login(); const firstPreview = selectedPreview(service, auth.sessionId, { ...builder(), context: "recurring_collection" }); const first = await service.requestIssue(auth.sessionId, firstPreview, "renew-period-first");
    const claim = await service.invitationClaim(first.invitation.token!, "America/Los_Angeles"); await service.invitationAccept(claim.claimantReceipt, claim.reviewSha256);
    const invalidPreview = createRequestPreview({ relationshipId: first.request.relationshipId, templateId: "template_default_a", templateRevision: 1, builder: builder("2040-01-01", "2040-01-08", first.request.id), practiceDisplayName: "Fictional Practice A" });
    await expect(service.requestRenew(auth.sessionId, first.request.id, invalidPreview, "renew-period-invalid")).rejects.toMatchObject({ code: "successor_period_invalid" });
    const validPreview = createRequestPreview({ relationshipId: first.request.relationshipId, templateId: "template_default_a", templateRevision: 1, builder: builder("2040-01-08", "2040-01-15", first.request.id), practiceDisplayName: "Fictional Practice A" });
    const successor = await service.requestRenew(auth.sessionId, first.request.id, validPreview, "renew-period-valid");
    await expect(service.invitationClaim(successor.invitation.token!, "America/New_York")).rejects.toMatchObject({ code: "successor_period_invalid" });
    const safeClaim = await service.invitationClaim(successor.invitation.token!, "America/Los_Angeles"); await expect(service.invitationAccept(safeClaim.claimantReceipt, safeClaim.reviewSha256)).resolves.toHaveProperty("claim", "accepted");
  });

  it("rejects a claimant receipt that expires while its asynchronous hash is pending", async () => {
    const { service, delayNextClaimantHash, advance, release } = claimantExpiryRaceHarness(); const challenge = service.signIn("clinician"); const auth = service.verifyMfa(challenge.challengeId, "246810"); const preview = selectedPreview(service, auth.sessionId); const issued = await service.requestIssue(auth.sessionId, preview, "accept-expiry-race");
    const claim = await service.invitationClaim(issued.invitation.token!, "UTC"); delayNextClaimantHash(); const acceptance = service.invitationAccept(claim.claimantReceipt, claim.reviewSha256); advance(5 * 60_000 + 1); await release();
    await expect(acceptance).rejects.toMatchObject({ code: "invitation_unavailable" });
    expect(service.requestList(auth.sessionId).find(item => item.id === issued.request.id)).toMatchObject({ lifecycle: "expired", claim: "expired", acceptance: null });
  });

  it("reauthorizes a coalesced issuance follower after awaiting the committed result", async () => {
    const { service, login, release } = raceHarness(); const primary = login("clinician"); const follower = login("clinician_two"); const admin = login("admin");
    const preview = selectedPreview(service, primary.sessionId); service.relationshipSelect(follower.sessionId, "relationship_unique_a");
    const first = service.requestIssue(primary.sessionId, preview, "coalesced-revocation"); const second = service.requestIssue(follower.sessionId, preview, "coalesced-revocation");
    service.reauthenticate(admin.sessionId, "246810"); service.memberRevokeSessions(admin.sessionId, "membership_clinician_a2"); await release();
    await expect(first).resolves.toHaveProperty("request.relationshipId", "relationship_unique_a");
    await expect(second).rejects.toMatchObject({ code: "session_revoked" });
  });

  it("prunes expired attacker-controlled public rate buckets before admitting a valid invitation", async () => {
    const { service, login, advance } = harness(); const auth = login(); const preview = selectedPreview(service, auth.sessionId); const issued = await service.requestIssue(auth.sessionId, preview, "bucket-recovery");
    for (let wave = 0; wave < 3; wave += 1) {
      for (let index = 0; index < 85; index += 1) await expect(service.invitationClaim(`invalid_${wave}_${index}`, "UTC")).rejects.toMatchObject({ code: "invitation_unavailable" });
      advance(60_001);
    }
    await expect(service.invitationClaim(issued.invitation.token!, "UTC")).resolves.toHaveProperty("reviewSha256");
  });

  it("keeps immutable packet bytes free of mutable reverse supersession and records download as opened", () => {
    const { service, login } = harness(); const auth = login(); const before = service.packetDownload(auth.sessionId, "packet_superseded");
    expect(before.artifact).toMatchObject({ schema: "practice.synthetic.packet/1.0-draft.2", supersedesPacketId: null });
    expect(before.artifact).not.toHaveProperty("supersededByPacketId"); expect(before.artifact).not.toHaveProperty("opened");
    const packets = (service as unknown as { packets: Map<string, { supersededByPacketId: string | null }> }).packets; packets.get("packet_superseded")!.supersededByPacketId = "packet_newer_projection";
    expect(service.packetDownload(auth.sessionId, "packet_superseded").canonicalJson).toBe(before.canonicalJson);
    expect(service.inbox(auth.sessionId, { requestId: "request_fixture" }).items.find(item => item.id === "packet_superseded")?.opened).toBe(true);
  });
});
