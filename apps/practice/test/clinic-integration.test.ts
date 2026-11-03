import { describe, expect, it, vi } from "vitest";
import { ClinicAccessPolicy, SyntheticClinicLicenses } from "../src/clinic/access";
import { SyntheticClinicBroker } from "../src/clinic/broker";
import { CLINIC_CONTRACT, clinicHandoffs, parseClinicHandoff, type ApprovedConnection, type ClinicActor,
  type PatientActor, type Range, type SetupIntent, type UploadReceipt } from "../src/clinic/contracts";
import { PatientClinicExports, SyntheticExportJournal, type ApprovedExportAdapter } from "../src/clinic/foreground-exports";

const clinic: ClinicActor = { role: "clinic", subjectId: "clinician_synthetic", clinicId: "clinic_synthetic" };
const patient: PatientActor = { role: "patient", subjectId: "patient_synthetic", deviceId: "phone_synthetic" };
const range: Range = { start: "2026-11-01T00:00:00.000Z", end: "2026-11-02T00:00:00.000Z" };
const setup: SetupIntent = { patientId: patient.subjectId, destinationId: "destination_synthetic", metrics: ["steps"],
  schedule: { cadence: "daily", hourUtc: 12 } };
async function fixture() {
  let now = Date.parse("2026-11-03T00:00:00.000Z"); let serial = 0; let authenticated = true;
  const broker = new SyntheticClinicBroker("synthetic", { clock: () => now, id: () => `synthetic_${++serial}`,
    authenticate: () => { if (!authenticated) throw new Error("unauthorized"); } });
  const issued = await broker.issueSetup(clinic, setup);
  const preview = await broker.reviewSetup(patient, issued.review.setupId);
  const connection = broker.acceptSetup(patient, issued.review.setupId, preview.digest);
  let local = structuredClone(connection); let foreground = true; let permission = true; let consumer = false;
  const licenses = new SyntheticClinicLicenses(clinic.clinicId, 20, now + 365 * 86_400_000, () => now, () => consumer);
  licenses.assign(connection);
  const policy = new ClinicAccessPolicy(licenses, () => now, "synthetic");
  const journal = new SyntheticExportJournal();
  const exporter = vi.fn<ApprovedExportAdapter["exportApproved"]>(async (request, check) => {
    check(); return { requestId: request.id, connectionId: connection.id, profileId: connection.profileId,
      revision: connection.revision, destinationId: connection.destination.id, range: request.range,
      exportId: `export_${request.id}`, uploadedAt: now };
  });
  const adapter: ApprovedExportAdapter = { foreground: () => foreground, healthDataAvailable: () => permission,
    currentConnection: () => local, exportApproved: exporter };
  const runner = new PatientClinicExports(broker, policy, adapter, journal);
  const request = (requestId = "refresh_synthetic") => broker.requestRefresh(clinic, { requestId, connectionId: connection.id, range });
  return { broker, issued, preview, connection, licenses, policy, journal, adapter, exporter, runner, request,
    clock: () => now, advance: (ms: number) => { now += ms; }, logout: () => { authenticated = false; },
    setLocal: (value: ApprovedConnection) => { local = value; }, setForeground: (value: boolean) => { foreground = value; },
    setPermission: (value: boolean) => { permission = value; }, setConsumer: () => { consumer = true; } };
}

describe("patient-confirmed clinic setup", () => {
  it("uses navigation-only QR/link, authenticated inbox and exact review before creating a disabled schedule", async () => {
    const f = await fixture();
    expect(f.issued.handoff).toBe(clinicHandoffs.setup);
    expect(parseClinicHandoff(f.issued.handoff)).toBe("setup");
    expect(f.preview.review).toMatchObject({ version: CLINIC_CONTRACT, metrics: ["steps"],
      destination: { url: "/synthetic-upload" }, scheduleEnabled: false,
      grantsOSPermission: false, grantsPaidAccess: false });
    expect(f.connection.scheduleEnabled).toBe(false);
    expect(f.broker.acceptSetup(patient, f.issued.review.setupId, f.preview.digest)).toEqual(f.connection);
    expect(f.broker.pendingSetups(patient)).toEqual([]);
    expect(f.broker.enableSchedule(patient, f.connection.id).scheduleEnabled).toBe(true);
  });
  it.each(["?token=synthetic", "#setup_synthetic", "/patient_synthetic", "?entitled=true", "?endpoint=synthetic"])("rejects URL context %s", suffix => {
    expect(parseClinicHandoff(clinicHandoffs.setup + suffix)).toBeNull();
  });
  it("isolates patients, devices and exact review digests", async () => {
    const f = await fixture();
    expect(f.broker.pendingSetups({ ...patient, subjectId: "other_synthetic" })).toEqual([]);
    await expect(f.broker.reviewSetup({ ...patient, subjectId: "other_synthetic" }, f.issued.review.setupId)).rejects.toThrow("unavailable");
    expect(() => f.broker.acceptSetup(patient, f.issued.review.setupId, "changed")).toThrow("unavailable");
    expect(() => f.broker.acceptSetup({ ...patient, deviceId: "other_synthetic" }, f.issued.review.setupId, f.preview.digest)).toThrow("unavailable");
    f.preview.review.destination.url = "https://other.invalid/upload";
    expect(f.broker.getConnection(patient, f.connection.id).destination.url).toBe("/synthetic-upload");
  });
  it("expires reviews, rejects credential/entitlement input and refuses unknown destinations/metrics", async () => {
    const f = await fixture(); const issued = await f.broker.issueSetup(clinic, setup);
    const review = await f.broker.reviewSetup(patient, issued.review.setupId); f.advance(15 * 60_000);
    expect(() => f.broker.acceptSetup(patient, issued.review.setupId, review.digest)).toThrow("expired");
    for (const field of ["token", "headers", "entitlement", "permission", "endpoint"]) {
      await expect(f.broker.issueSetup(clinic, { ...setup, [field]: "synthetic" })).rejects.toThrow("invalid_input");
    }
    await expect(f.broker.issueSetup(clinic, { ...setup, destinationId: "other_synthetic" })).rejects.toThrow("unavailable");
    await expect(f.broker.issueSetup(clinic, { ...setup, metrics: ["invented_metric"] })).rejects.toThrow("invalid_metrics");
    await expect(f.broker.issueSetup(clinic, { ...setup, schedule: { cadence: "daily", hourUtc: 24 } })).rejects.toThrow("invalid_input");
  });
  it("reauthorizes issuance after asynchronous hashing and has no production mode", async () => {
    const f = await fixture(); const issuing = f.broker.issueSetup(clinic, setup); f.logout();
    await expect(issuing).rejects.toThrow("unauthorized");
    expect(() => new SyntheticClinicBroker("production" as "synthetic", {} as never)).toThrow("configuration_unavailable");
  });
});

describe("clinic-paid entitlement seam", () => {
  it("gates policy-dependent access and preserves consumer access independently of clinic seats", async () => {
    const f = await fixture();
    expect(new ClinicAccessPolicy(f.licenses, f.clock).evaluate(f.connection)).toBe("store_decision_required");
    expect(f.policy.evaluate(f.connection)).toBe("clinic");
    f.licenses.revoke(f.connection.id); expect(f.policy.evaluate(f.connection)).toBe("entitlement_required");
    f.setConsumer(); expect(new ClinicAccessPolicy(f.licenses, f.clock).evaluate(f.connection)).toBe("consumer");
    expect(f.policy.evaluate({ ...f.connection, clinicId: "other_synthetic" })).toBe("consumer");
  });
  it("bounds twenty fictional seats, counts patients once and supports revocation/reassignment/expiry", async () => {
    const f = await fixture();
    for (let index = 1; index < 20; index++) f.licenses.assign({ ...f.connection, id: `connection_${index}`, patientId: `patient_${index}` });
    f.licenses.assign({ ...f.connection, id: "same_patient_profile" });
    expect(() => f.licenses.assign({ ...f.connection, id: "extra", patientId: "extra" })).toThrow("capacity");
    f.licenses.revoke("connection_1"); f.licenses.assign({ ...f.connection, id: "extra", patientId: "extra" });
    expect(() => f.licenses.assign({ ...f.connection, clinicId: "other_synthetic" })).toThrow("unavailable");
    expect(f.policy.evaluate({ ...f.connection, id: "unapproved_profile" })).toBe("entitlement_required");
    f.advance(365 * 86_400_000); expect(f.policy.evaluate(f.connection)).toBe("entitlement_required");
  });
});

describe("foreground clinic refresh", () => {
  it("exports frozen approved scope once, correlates upload receipt and requires explicit clinic processing", async () => {
    const f = await fixture(); const request = f.request();
    expect(request.state).toBe("requested"); expect(f.broker.pendingRefreshes(patient)).toHaveLength(1);
    const uploaded = await f.runner.run(patient, request.id); expect(uploaded.state).toBe("uploaded");
    expect(f.exporter).toHaveBeenCalledExactlyOnceWith(expect.objectContaining({ connection: f.connection, range }), expect.any(Function));
    expect(await f.runner.run(patient, request.id)).toEqual(uploaded); expect(f.exporter).toHaveBeenCalledTimes(1);
    expect(() => f.broker.processed(clinic, request.id, "wrong")).toThrow("invalid_receipt");
    expect(f.broker.processed(clinic, request.id, uploaded.receipt!.exportId).state).toBe("processed");
  });
  it("binds idempotency to clinic, profile and exact date scope; forbids destination overrides", async () => {
    const f = await fixture(); const request = f.request(); expect(f.request()).toEqual(request);
    expect(() => f.broker.requestRefresh({ ...clinic, clinicId: "other_synthetic" }, { requestId: request.id, connectionId: f.connection.id, range })).toThrow("unavailable");
    expect(() => f.broker.status({ ...patient, deviceId: "other_synthetic" }, request.id)).toThrow("unavailable");
    expect(() => f.broker.requestRefresh(clinic, { requestId: request.id, connectionId: f.connection.id,
      range: { ...range, start: "2026-10-31T00:00:00.000Z" } })).toThrow("idempotency_conflict");
    expect(() => f.broker.requestRefresh(clinic, { requestId: "another", connectionId: f.connection.id, range })).toThrow("request_pending");
    expect(() => f.broker.requestRefresh(clinic, { requestId: "another", connectionId: f.connection.id, range, destinationId: "other" } as never)).toThrow("invalid_input");
  });
  it.each(["foreground", "permission", "profile", "entitlement"])("keeps request pending until %s gate is resolved", async gate => {
    const f = await fixture(); const request = f.request();
    if (gate === "foreground") f.setForeground(false);
    if (gate === "permission") f.setPermission(false);
    if (gate === "profile") f.setLocal({ ...f.connection, profileId: "other_synthetic" });
    if (gate === "entitlement") f.licenses.revoke(f.connection.id);
    await expect(f.runner.run(patient, request.id)).rejects.toThrow();
    expect(f.exporter).not.toHaveBeenCalled(); expect(f.broker.status(clinic, request.id).state).toBe("requested");
  });
  it.each(["cancel", "revoke", "expire", "logout", "permission", "entitlement", "profile", "foreground"])("checks %s again before publication", async event => {
    const f = await fixture(); const request = f.request();
    f.exporter.mockImplementation(async (_request, check) => {
      if (event === "cancel") f.broker.cancel(clinic, request.id);
      if (event === "revoke") f.broker.revoke(patient, f.connection.id);
      if (event === "expire") f.advance(300_000);
      if (event === "permission") f.setPermission(false);
      if (event === "entitlement") f.licenses.revoke(f.connection.id);
      if (event === "profile") f.setLocal({ ...f.connection, revision: "changed" });
      if (event === "foreground") f.setForeground(false);
      if (event === "logout") f.logout();
      check(); throw new Error("must not publish");
    });
    if (event === "logout") await expect(f.runner.run(patient, request.id)).rejects.toThrow("unauthorized");
    else expect((await f.runner.run(patient, request.id)).receipt).toBeUndefined();
    expect(f.exporter).toHaveBeenCalledTimes(1);
  });
  it("replays persisted receipt after acknowledgment loss without another export", async () => {
    const f = await fixture(); const request = f.request();
    const ack = vi.spyOn(f.broker, "uploaded"); ack.mockImplementationOnce(() => { throw new Error("offline"); });
    await expect(f.runner.run(patient, request.id)).rejects.toThrow("offline");
    const restarted = new PatientClinicExports(f.broker, f.policy, f.adapter, f.journal);
    expect((await restarted.run(patient, request.id)).state).toBe("uploaded"); expect(f.exporter).toHaveBeenCalledTimes(1);
  });
  it("does not re-export an interrupted or concurrent request", async () => {
    const f = await fixture(); const request = f.request();
    let release!: (value: UploadReceipt) => void;
    f.exporter.mockImplementation(() => new Promise(resolve => { release = resolve; }));
    const running = f.runner.run(patient, request.id);
    await expect(f.runner.run(patient, request.id)).rejects.toThrow("already_running");
    const restarted = new PatientClinicExports(f.broker, f.policy, f.adapter, f.journal);
    expect((await restarted.run(patient, request.id)).state).toBe("failed");
    release({ requestId: request.id, connectionId: f.connection.id, profileId: f.connection.profileId,
      revision: f.connection.revision, destinationId: f.connection.destination.id, range, exportId: "export_synthetic", uploadedAt: f.clock() });
    expect((await running).state).toBe("failed"); expect(f.exporter).toHaveBeenCalledTimes(1);
  });
  it("retains a late upload receipt after cancellation without reviving work", async () => {
    const f = await fixture(); const request = f.request();
    const original = f.exporter.getMockImplementation()!;
    f.exporter.mockImplementation(async (...args) => { const receipt = await original(...args); f.broker.cancel(clinic, request.id); return receipt; });
    const outcome = await f.runner.run(patient, request.id);
    expect(outcome.state).toBe("cancelled"); expect(outcome.receipt?.requestId).toBe(request.id);
    expect(() => f.broker.processed(clinic, request.id, outcome.receipt!.exportId)).toThrow("unavailable");
  });
  it("rejects uncorrelated or conflicting receipts and invalid ranges", async () => {
    const f = await fixture(); const request = f.request(); const result = await f.runner.run(patient, request.id);
    for (const patch of [{ destinationId: "other" }, { profileId: "other" }, { requestId: "other" }, { revision: "other" },
      { range: { ...range, start: "2026-10-31T00:00:00.000Z" } }, { uploadedAt: f.clock() + 1 }]) {
      expect(() => f.broker.uploaded(patient, request.id, { ...result.receipt!, ...patch })).toThrow("invalid_receipt");
    }
    expect(() => f.broker.uploaded(patient, request.id, { ...result.receipt!, exportId: "changed" })).toThrow("receipt_conflict");
    for (const invalidRange of [{ ...range, end: range.start }, { ...range, end: "2026-11-04T00:00:00.000Z" },
      { ...range, start: "2026-02-30T00:00:00.000Z" }]) {
      expect(() => f.broker.requestRefresh(clinic, { requestId: "invalid", connectionId: f.connection.id, range: invalidRange })).toThrow();
    }
  });
});

describe("clinic authority and terminal-state regressions", () => {
  it("does not accept an upload for a request that never started", async () => {
    const f = await fixture(); const request = f.request(); f.broker.cancel(clinic, request.id);
    expect(() => f.broker.uploaded(patient, request.id, { requestId: request.id, connectionId: f.connection.id,
      profileId: f.connection.profileId, revision: f.connection.revision, destinationId: f.connection.destination.id,
      range, exportId: "export_synthetic", uploadedAt: f.clock() })).toThrow("invalid_receipt");
    expect(() => f.broker.getConnection(clinic as unknown as PatientActor, f.connection.id)).toThrow("unavailable");
  });
  it("expires untouched requests and requires a new ID after a terminal failure", async () => {
    const f = await fixture(); const request = f.request(); f.advance(300_000);
    expect((await f.runner.run(patient, request.id)).state).toBe("expired");
    expect(f.request().state).toBe("expired"); expect(f.exporter).not.toHaveBeenCalled();
    const renewed = f.request("fresh_synthetic"); expect((await f.runner.run(patient, renewed.id)).state).toBe("uploaded");
  });
  it("consent revocation stops pending exports while consumer purchases remain independent", async () => {
    const f = await fixture(); const request = f.request(); f.setConsumer(); f.broker.revoke(patient, f.connection.id);
    expect(f.policy.evaluate(f.connection)).toBe("consumer");
    expect((await f.runner.run(patient, request.id)).state).toBe("revoked"); expect(f.exporter).not.toHaveBeenCalled();
    expect(() => f.broker.enableSchedule(patient, f.connection.id)).toThrow("revoked");
    expect(() => f.request("another_synthetic")).toThrow("revoked");
  });
  it("reauthenticates status, acknowledgment, schedule, cancellation and review operations", async () => {
    const f = await fixture(); const request = f.request(); const result = await f.runner.run(patient, request.id); f.logout();
    for (const operation of [() => f.broker.status(clinic, request.id), () => f.broker.cancel(patient, request.id),
      () => f.broker.uploaded(patient, request.id, result.receipt!), () => f.broker.pendingSetups(patient),
      () => f.broker.enableSchedule(patient, f.connection.id), () => f.broker.revoke(patient, f.connection.id)]) {
      expect(operation).toThrow("unauthorized");
    }
  });
});

describe("review and lifecycle stability", () => {
  it("rejects an authority change during review hashing", async () => {
    const f = await fixture(); const actor = { ...clinic }; const issuing = f.broker.issueSetup(actor, setup);
    actor.clinicId = "other_synthetic"; await expect(issuing).rejects.toThrow("unavailable");
  });
  it("keeps terminal cancellation stable when consent is later revoked", async () => {
    const f = await fixture(); const request = f.request(); f.broker.cancel(clinic, request.id);
    f.broker.revoke(patient, f.connection.id); expect(f.broker.status(clinic, request.id).state).toBe("cancelled");
  });
  it("uses a new ID for a fresh export of the same approved interval", async () => {
    const f = await fixture(); await f.runner.run(patient, f.request().id);
    const second = f.request("second_synthetic"); expect((await f.runner.run(patient, second.id)).state).toBe("uploaded");
    expect(f.exporter).toHaveBeenCalledTimes(2);
  });
});
