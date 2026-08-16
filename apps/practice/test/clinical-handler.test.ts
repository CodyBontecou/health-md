import { describe, expect, it } from "vitest";
import { operationNames, SYNTHETIC_OPERATION_VERSION, validationErrorCodes, type OperationEnvelope, type RequestBuilder, type RequestPreview } from "../src/contracts/clinical";
import { dispatchClinicalOperation, handleClinicalOperation, syntheticClinicalService } from "../src/http/clinical-api";
import worker, { type PracticeWorkerEnv } from "../src/worker";
import { canonicalJson, validateRequestBuilder } from "../src/synthetic/request-domain";
import { SyntheticClinicalService, type SyntheticFactories } from "../src/synthetic/service";

function setup() {
  let sequence = 0;
  const factories: SyntheticFactories = {
    clock: () => "2040-01-01T00:00:00.000Z",
    id: kind => `${kind}_${++sequence}`,
    token: kind => `${kind}_${++sequence}_A7vQ9xL2mN4pR6tW8yZ1bC3dE5fG7hJ9`,
  };
  return new SyntheticClinicalService(factories);
}
function request(body: unknown, options: { origin?: string | null; cookie?: string; contentType?: string; method?: string } = {}): Request {
  const headers = new Headers();
  if (options.origin !== null) headers.set("Origin", options.origin ?? "https://practice.invalid");
  if (options.cookie) headers.set("Cookie", options.cookie);
  headers.set("Content-Type", options.contentType ?? "application/json");
  return new Request("https://practice.invalid/api/v1/operation", { method: options.method ?? "POST", headers, ...(options.method === "GET" ? {} : { body: JSON.stringify(body) }) });
}
function envelope(operation: string, payload: Record<string, unknown> = {}, csrfToken?: string) { return { version: SYNTHETIC_OPERATION_VERSION, operation, payload, ...(csrfToken === undefined ? {} : { csrfToken }) }; }
async function authenticate(service: SyntheticClinicalService, login = "clinician") {
  const signIn = await handleClinicalOperation(request(envelope("sign_in", { login })), service);
  const challenge = (await signIn.json() as { data: { challengeId: string } }).data.challengeId;
  const verified = await handleClinicalOperation(request(envelope("verify_mfa", { challengeId: challenge, code: "246810" }), { cookie: "__Host-practice_synthetic_session=attacker_fixed" }), service);
  const setCookie = verified.headers.get("Set-Cookie")!;
  return { cookie: setCookie.split(";", 1)[0]!, csrf: (await verified.json() as { csrfToken: string }).csrfToken, setCookie };
}
async function invoke(service: SyntheticClinicalService, auth: { cookie: string; csrf: string }, operation: string, payload: Record<string, unknown> = {}) {
  return handleClinicalOperation(request(envelope(operation, payload, auth.csrf), { cookie: auth.cookie }), service);
}
function builder(context: RequestBuilder["context"] = "pre_visit"): RequestBuilder {
  return { context, period: { kind: "fixed_dates", startLocalDate: "2040-01-01", endLocalDateExclusive: "2040-01-08", timezoneRule: "acceptance_time_iana" }, schedule: { type: "all_readings", windows: [] }, cadence: { type: "at_period_end" }, pulse: "preferred" };
}
function workerEnv(): PracticeWorkerEnv {
  return { PRACTICE_RUNTIME_MODE: "synthetic", ASSETS: { fetch: async () => new Response("asset"), connect: () => { throw new Error("not used"); } } as unknown as Fetcher };
}
async function workerOperation(operation: string, payload: Record<string, unknown> = {}, cookie?: string, csrfToken?: string): Promise<Response> {
  const headers = new Headers({ Origin: "https://practice.invalid", "Content-Type": "application/json" }); if (cookie) headers.set("Cookie", cookie);
  return worker.fetch(new Request("https://practice.invalid/api/v1/operation", { method: "POST", headers, body: JSON.stringify(envelope(operation, payload, csrfToken)) }), workerEnv());
}

describe("static same-origin synthetic operation handler", () => {
  it("keeps explicit dispatch parity with all 34 versioned operations", async () => {
    const service = setup();
    for (const operation of operationNames) {
      try { await dispatchClinicalOperation(service, "missing_session", { version: SYNTHETIC_OPERATION_VERSION, operation, payload: {} } as OperationEnvelope); }
      catch (error) { expect(error).toBeInstanceOf(Error); expect((error as { code?: string }).code).not.toBe("unknown_operation"); }
    }
    expect(operationNames).toHaveLength(34);
  });

  it("sets a fixation-safe HttpOnly Secure Strict cookie and memory-only CSRF", async () => {
    const service = setup(); const auth = await authenticate(service);
    expect(auth.setCookie).toContain("__Host-practice_synthetic_session=session_"); expect(auth.setCookie).not.toContain("attacker_fixed");
    expect(auth.setCookie).toContain("HttpOnly"); expect(auth.setCookie).toContain("Secure"); expect(auth.setCookie).toContain("SameSite=Strict");
    const session = await invoke(service, auth, "session"); expect(session.status).toBe(200); expect(await session.json()).toMatchObject({ data: { role: "clinician", tenantCode: "tenant_a", practiceDisplayName: "Fictional Practice A" } });
    expect(session.headers.get("Cache-Control")).toBe("no-store"); expect(session.headers.get("Access-Control-Allow-Origin")).toBeNull();
  });

  it("bootstraps a rotated CSRF token through the real Worker singleton after refresh", async () => {
    syntheticClinicalService.reset();
    const signIn = await workerOperation("sign_in", { login: "clinician" }); const challengeId = (await signIn.json() as { data: { challengeId: string } }).data.challengeId;
    const verified = await workerOperation("verify_mfa", { challengeId, code: "246810" }); const cookie = verified.headers.get("Set-Cookie")!.split(";", 1)[0]!; const originalCsrf = (await verified.json() as { csrfToken: string }).csrfToken;
    expect((await workerOperation("session_bootstrap")).status).toBe(404);
    const bootstrap = await workerOperation("session_bootstrap", {}, cookie); expect(bootstrap.status).toBe(200); const bootstrapBody = await bootstrap.json() as { csrfToken: string; data: { role: string; tenantCode: string; practiceDisplayName: string } };
    expect(bootstrapBody.data).toMatchObject({ role: "clinician", tenantCode: "tenant_a", practiceDisplayName: "Fictional Practice A" }); expect(bootstrapBody.csrfToken).not.toBe(originalCsrf);
    expect((await workerOperation("session", {}, cookie, originalCsrf)).status).toBe(404);
    expect((await workerOperation("session", {}, cookie, bootstrapBody.csrfToken)).status).toBe(200);
  });

  it.each([
    ["missing origin", { origin: null }, 403, "origin_denied"], ["cross origin", { origin: "https://other.invalid" }, 403, "origin_denied"],
    ["wrong content", { contentType: "text/plain" }, 415, "content_type_required"], ["wrong method", { method: "GET" }, 405, "method_not_allowed"],
  ])("rejects %s", async (_label, options, status, code) => {
    const response = await handleClinicalOperation(request(envelope("sign_in", { login: "clinician" }), options), setup());
    expect(response.status).toBe(status); expect(await response.json()).toMatchObject({ error: { code, message: "The requested operation is unavailable" } });
  });

  it("stream-bounds and cancels oversized bodies before unbounded allocation", async () => {
    let canceled = false;
    const body = new ReadableStream<Uint8Array>({ start(controller) { controller.enqueue(new Uint8Array(10_000)); controller.enqueue(new Uint8Array(10_000)); }, cancel() { canceled = true; } });
    const oversized = new Request("https://practice.invalid/api/v1/operation", { method: "POST", headers: { Origin: "https://practice.invalid", "Content-Type": "application/json" }, body, duplex: "half" } as RequestInit & { duplex: "half" });
    const response = await handleClinicalOperation(oversized, setup()); expect(response.status).toBe(413); expect(canceled).toBe(true);
  });

  it("rejects unknown fields, operations, malformed filters, categories, and extra no-payload data", async () => {
    const service = setup();
    expect((await handleClinicalOperation(request(envelope("read_anything")), service)).status).toBe(404);
    expect((await handleClinicalOperation(request({ ...envelope("sign_in", { login: "clinician" }), tenantId: "tenant_b" }), service)).status).toBe(400);
    const auth = await authenticate(service);
    expect((await invoke(service, auth, "session", { extra: true })).status).toBe(400);
    expect((await invoke(service, auth, "relationship_select", { relationshipId: "relationship_unique_a" })).status).toBe(200);
    expect((await invoke(service, auth, "inbox", { filter: { pageSize: 0 } })).status).toBe(400);
    expect((await invoke(service, auth, "inbox", { filter: { shape: "invented" } })).status).toBe(400);
    for (const filter of [{ context: "invented" }, { acknowledged: "false" }, { receivedFromUtcDate: "2040-02-31" }, { receivedFromUtcDate: "2040-02-02", receivedToExclusiveUtcDate: "2040-02-01" }, { supersession: "old" }, { sort: "newest" }, { extra: true }]) expect((await invoke(service, auth, "inbox", { filter })).status).toBe(400);
    const invalidDate = builder(); if (invalidDate.period.kind === "fixed_dates") invalidDate.period.startLocalDate = "2040-02-31";
    expect((await invoke(service, auth, "request_preview", { templateId: "template_default_a", expectedTemplateRevision: 1, builder: invalidDate })).status).toBe(422);
    const strayCadence = builder(); strayCadence.cadence = { type: "daily", everyNDays: 2 };
    expect((await invoke(service, auth, "request_preview", { templateId: "template_default_a", expectedTemplateRevision: 1, builder: strayCadence })).status).toBe(422);
    const missingN = builder(); missingN.cadence = { type: "every_n_days" };
    expect((await invoke(service, auth, "request_preview", { templateId: "template_default_a", expectedTemplateRevision: 1, builder: missingN })).status).toBe(422);
    const fractionalN = builder(); fractionalN.cadence = { type: "every_n_days", everyNDays: 1.5 };
    expect((await invoke(service, auth, "request_preview", { templateId: "template_default_a", expectedTemplateRevision: 1, builder: fractionalN })).status).toBe(422);
    const admin = await authenticate(service, "admin"); expect((await invoke(service, admin, "audit", { category: "invented" })).status).toBe(400);
    expect((await invoke(service, admin, "audit", { cursor: -1 })).status).toBe(400);
  });

  it("keeps client and server validation matrices identical across dates, DST windows, counts, recurrence, cadence, pulse, and renewal", async () => {
    const service = setup(); const auth = await authenticate(service); expect((await invoke(service, auth, "relationship_select", { relationshipId: "relationship_unique_a" })).status).toBe(200);
    const fixed = () => builder();
    const matrix: Array<[string, RequestBuilder, string[]]> = [];
    const unknownContext = fixed(); unknownContext.context = "unknown" as never; matrix.push(["context", unknownContext, ["unknown_context"]]);
    const emptyContext = fixed(); emptyContext.context = "" as never; matrix.push(["empty context", emptyContext, ["unknown_context"]]);
    const boundary = fixed(); if (boundary.period.kind === "fixed_dates") boundary.period.endLocalDateExclusive = boundary.period.startLocalDate; matrix.push(["boundary dates", boundary, ["fixed_period_invalid"]]);
    const relativeDays = fixed(); relativeDays.period = { kind: "relative_completed_days", days: 0, timezoneRule: "acceptance_time_iana" }; matrix.push(["relative days", relativeDays, ["relative_days_invalid", "relative_acceptance_unresolved"]]);
    const timezone = fixed(); timezone.period.timezoneRule = "floating" as never; matrix.push(["timezone", timezone, ["timezone_rule_invalid"]]);
    const overlapping = fixed(); overlapping.schedule = { type: "custom_windows", windows: [{ name: "First", startLocalTime: "08:00", endLocalTime: "10:00", minimumCount: 1 }, { name: "Second", startLocalTime: "09:00", endLocalTime: "11:00", minimumCount: 1 }] }; matrix.push(["DST overlap", overlapping, ["window_overlap", "dst_materialization_unresolved"]]);
    const unsupportedSchedule = fixed(); unsupportedSchedule.schedule = { type: "unsupported" as never, windows: [] }; matrix.push(["schedule", unsupportedSchedule, ["unsupported_schedule"]]);
    const emptySchedule = fixed(); emptySchedule.schedule = { type: "" as never, windows: [] }; matrix.push(["empty schedule", emptySchedule, ["unsupported_schedule"]]);
    const cardinality = fixed(); cardinality.schedule = { type: "once_daily", windows: [] }; matrix.push(["cardinality", cardinality, ["window_cardinality_invalid"]]);
    const windowName = fixed(); windowName.schedule = { type: "custom_windows", windows: [{ name: "Bad!", startLocalTime: "08:00", endLocalTime: "09:00", minimumCount: 1 }] }; matrix.push(["window name", windowName, ["window_name_invalid", "dst_materialization_unresolved"]]);
    const emptyWindowName = fixed(); emptyWindowName.schedule = { type: "custom_windows", windows: [{ name: "", startLocalTime: "08:00", endLocalTime: "09:00", minimumCount: 1 }] }; matrix.push(["empty window name", emptyWindowName, ["window_name_invalid", "dst_materialization_unresolved"]]);
    const windowTime = fixed(); windowTime.schedule = { type: "custom_windows", windows: [{ name: "Time", startLocalTime: "25:00", endLocalTime: "09:00", minimumCount: 1 }] }; matrix.push(["window time", windowTime, ["window_time_invalid", "dst_materialization_unresolved"]]);
    const emptyWindowTime = fixed(); emptyWindowTime.schedule = { type: "custom_windows", windows: [{ name: "Time", startLocalTime: "", endLocalTime: "09:00", minimumCount: 1 }] }; matrix.push(["empty window time", emptyWindowTime, ["window_time_invalid", "dst_materialization_unresolved"]]);
    const count = fixed(); count.schedule = { type: "custom_windows", windows: [{ name: "Count", startLocalTime: "08:00", endLocalTime: "09:00", minimumCount: 0 }] }; matrix.push(["count", count, ["window_count_invalid", "dst_materialization_unresolved"]]);
    const overnight = fixed(); overnight.schedule = { type: "custom_windows", windows: [{ name: "Night", startLocalTime: "10:00", endLocalTime: "09:00", minimumCount: 1 }] }; matrix.push(["overnight", overnight, ["overnight_window_unresolved", "dst_materialization_unresolved"]]);
    const touching = fixed(); touching.schedule = { type: "custom_windows", windows: [{ name: "First", startLocalTime: "08:00", endLocalTime: "09:00", minimumCount: 1 }, { name: "Second", startLocalTime: "09:00", endLocalTime: "10:00", minimumCount: 1 }] }; matrix.push(["touching", touching, ["touching_window_unresolved", "dst_materialization_unresolved"]]);
    const recurrence = builder("recurring_collection"); recurrence.period = { kind: "relative_completed_days", days: 7, timezoneRule: "acceptance_time_iana" }; matrix.push(["recurrence", recurrence, ["finite_fixed_bounds_required", "relative_acceptance_unresolved"]]);
    const unsupportedCadence = fixed(); unsupportedCadence.cadence = { type: "unsupported" as never }; matrix.push(["unsupported cadence", unsupportedCadence, ["unsupported_cadence"]]);
    const emptyCadence = fixed(); emptyCadence.cadence = { type: "" as never }; matrix.push(["empty cadence", emptyCadence, ["unsupported_cadence"]]);
    const cadence = fixed(); cadence.cadence = { type: "every_n_days", everyNDays: 0 }; matrix.push(["cadence", cadence, ["every_n_days_invalid", "cadence_anchor_unresolved"]]);
    const pulse = fixed(); pulse.pulse = "sometimes" as never; matrix.push(["pulse", pulse, ["unsupported_pulse_policy"]]);
    const emptyPulse = fixed(); emptyPulse.pulse = "" as never; matrix.push(["empty pulse", emptyPulse, ["unsupported_pulse_policy"]]);
    const emptyText = fixed(); emptyText.practiceCollectionInstructions = ""; matrix.push(["empty text", emptyText, ["text_too_long"]]);
    const html = fixed(); html.practiceCollectionInstructions = "Use <b>unsafe</b> text"; matrix.push(["HTML", html, ["html_not_allowed"]]);
    const markdown = fixed(); markdown.practiceCollectionInstructions = "Use **unsafe** text"; matrix.push(["Markdown", markdown, ["markdown_not_allowed"]]);
    const link = fixed(); link.practiceContactText = "Visit https://practice.invalid"; matrix.push(["link", link, ["link_not_allowed"]]);
    const variable = fixed(); variable.practiceCollectionInstructions = "Use {{unknown}}"; matrix.push(["variable", variable, ["undeclared_variable"]]);
    const longText = fixed(); longText.practiceCollectionInstructions = "x".repeat(501); matrix.push(["text length", longText, ["text_too_long"]]);
    const renewal = fixed(); renewal.predecessorRequestId = "request_state_active"; matrix.push(["renewal", renewal, []]);
    const covered = new Set<string>();
    for (const [name, draft, expectedCodes] of matrix) {
      const clientCodes = validateRequestBuilder(draft).map(issue => issue.code).sort(); expectedCodes.forEach(code => expect(clientCodes, name).toContain(code)); clientCodes.forEach(code => covered.add(code));
      const response = await invoke(service, auth, "request_preview", { templateId: "template_default_a", expectedTemplateRevision: 1, builder: draft });
      if (clientCodes.length === 0) expect(response.status, name).toBe(200);
      else { expect(response.status, name).toBe(422); const body = await response.json() as { error: { issues: Array<{ code: string }> } }; expect(body.error.issues.map(issue => issue.code).sort(), name).toEqual(clientCodes); }
    }
    expect([...covered].sort()).toEqual([...validationErrorCodes].sort());
  });

  it("requires CSRF and ignores browser attempts to provide tenant/role", async () => {
    const service = setup(); const auth = await authenticate(service);
    expect((await handleClinicalOperation(request(envelope("session"), { cookie: auth.cookie }), service)).status).toBe(404);
    expect(service.auditSnapshotForTest("tenant_a").at(-1)).toMatchObject({ tenantCode: "tenant_a", actorCode: "actor_clinician", category: "denied_access", action: "csrf", outcome: "denied" });
    expect((await invoke(service, auth, "session", { tenantId: "tenant_b", role: "practice_admin" })).status).toBe(400);
    const denied = await invoke(service, auth, "relationship_select", { relationshipId: "relationship_unique_b" }); expect(denied.status).toBe(404);
    expect(await denied.json()).toEqual({ error: { code: "operation_unavailable", message: "The requested operation is unavailable" } });
  });

  it("renders and validates tenant-B previews only with the authenticated tenant-B practice name", async () => {
    const service = setup(); const auth = await authenticate(service, "other");
    const bootstrap = await invoke(service, auth, "session_bootstrap");
    const bootstrapBody = await bootstrap.json() as { csrfToken: string; data: { tenantCode: string; practiceDisplayName: string } };
    expect(bootstrapBody).toMatchObject({ data: { tenantCode: "tenant_b", practiceDisplayName: "Fictional Practice B" } }); auth.csrf = bootstrapBody.csrfToken;
    expect((await invoke(service, auth, "relationship_select", { relationshipId: "relationship_unique_b" })).status).toBe(200);
    const previewResponse = await invoke(service, auth, "request_preview", { templateId: "template_default_b", expectedTemplateRevision: 1, builder: builder() });
    expect(previewResponse.status).toBe(200);
    const preview = (await previewResponse.json() as { data: RequestPreview }).data;
    expect(preview.representation.renderedInstructions).toContain("Fictional Practice B");
    expect(preview.representation.renderedInstructions).not.toContain("Fictional Practice A");
    expect((await invoke(service, auth, "request_issue", { preview, idempotencyKey: "handler-tenant-b" })).status).toBe(200);
    const forged = structuredClone(preview); forged.representation.renderedInstructions = forged.representation.renderedInstructions.replace("Fictional Practice B", "Fictional Practice A");
    const forgedJson = canonicalJson(forged.representation);
    forged.canonicalJson = forgedJson; forged.canonicalBytes = [...new TextEncoder().encode(forgedJson)];
    const rejected = await invoke(service, auth, "request_issue", { preview: forged, idempotencyKey: "handler-tenant-b-forged-a" });
    expect(rejected.status).toBe(409); expect(await rejected.json()).toMatchObject({ error: { code: "preview_conflict" } });
  });

  it("rejects malformed request previews at the HTTP boundary with invalid_body", async () => {
    const service = setup(); const auth = await authenticate(service); await invoke(service, auth, "relationship_select", { relationshipId: "relationship_unique_a" });
    const response = await invoke(service, auth, "request_preview", { templateId: "template_default_a", expectedTemplateRevision: 1, builder: builder() });
    const valid = (await response.json() as { data: RequestPreview }).data;
    const mutations: Array<(value: Record<string, any>) => void> = [
      value => { delete value.representation.schema; }, value => { value.representation.schema = "wrong"; },
      value => { delete value.representation.protocolVersion; }, value => { value.representation.protocolVersion = "wrong"; },
      value => { delete value.representation.instructionVersion; }, value => { value.representation.instructionVersion = "wrong"; },
      value => { value.representation.relationshipId = ""; }, value => { value.representation.templateId = 7; },
      value => { value.representation.templateRevision = 0; }, value => { value.representation.templateRevision = Number.MAX_SAFE_INTEGER + 1; },
      value => { delete value.representation.renderedInstructions; }, value => { value.canonicalJson = 7; },
      value => { value.canonicalBytes = []; }, value => { value.canonicalBytes = [256]; }, value => { value.representation.extra = true; },
    ];
    for (const mutate of mutations) {
      const malformed = structuredClone(valid) as unknown as Record<string, any>; mutate(malformed);
      const rejected = await invoke(service, auth, "request_issue", { preview: malformed, idempotencyKey: `malformed-${mutations.indexOf(mutate)}` });
      expect(rejected.status).toBe(400); expect(await rejected.json()).toEqual({ error: { code: "invalid_body", message: "The requested operation is unavailable" } });
    }
  });

  it("exercises relationship, template/request preview, issuance, claim, and acceptance handlers", async () => {
    const service = setup(); const auth = await authenticate(service);
    expect((await invoke(service, auth, "relationship_search", { query: "unique" })).status).toBe(200);
    expect((await invoke(service, auth, "relationship_select", { relationshipId: "relationship_unique_a" })).status).toBe(200);
    const previewResponse = await invoke(service, auth, "request_preview", { templateId: "template_default_a", expectedTemplateRevision: 1, builder: builder() });
    const preview = (await previewResponse.json() as { data: unknown }).data;
    const issueResponse = await invoke(service, auth, "request_issue", { preview, idempotencyKey: "handler-issue" }); expect(issueResponse.status).toBe(200);
    const issued = (await issueResponse.json() as { data: { invitation: { token: string } } }).data;
    const claimResponse = await handleClinicalOperation(request(envelope("invitation_claim", { token: issued.invitation.token, deviceIanaTimezone: "America/New_York" })), service); expect(claimResponse.status).toBe(200);
    const claim = (await claimResponse.json() as { data: { claimantReceipt: string; reviewSha256: string } }).data;
    expect((await handleClinicalOperation(request(envelope("invitation_accept", { claimantReceipt: claim.claimantReceipt, reviewedAcceptanceSha256: claim.reviewSha256 })), service)).status).toBe(200);
  });

  it("exercises inbox/load/download/workflow/passive handlers with generic unavailable denial", async () => {
    const service = setup(); const auth = await authenticate(service);
    const inbox = await invoke(service, auth, "inbox", { filter: { requestId: "request_fixture", context: "pre_visit", sort: "received_asc", pageSize: 25 } }); const item = (await inbox.json() as { data: { items: Array<Record<string, unknown>> } }).data.items.find(row => row.id === "packet_complete_apple")!;
    expect(item).not.toHaveProperty("readings"); expect(item).toMatchObject({ context: "pre_visit", opened: false });
    expect((await invoke(service, auth, "packet_download", { packetId: "packet_complete_apple" })).status).toBe(200);
    const afterDownload = await invoke(service, auth, "inbox", { filter: { requestId: "request_fixture", pageSize: 25 } }); expect((await afterDownload.json() as { data: { items: Array<Record<string, unknown>> } }).data.items.find(row => row.id === "packet_complete_apple")).toMatchObject({ opened: true });
    const loaded = await invoke(service, auth, "packet_load", { packetId: "packet_complete_apple" }); expect(loaded.status).toBe(200); expect(await loaded.json()).toMatchObject({ data: { opened: { actorCode: "actor_clinician", revision: 1 }, history: [{ type: "opened" }] } });
    expect(await (await invoke(service, auth, "packet_passive_event", { packetId: "packet_complete_apple", event: "scroll" })).json()).toMatchObject({ data: { recorded: false } });
    expect((await invoke(service, auth, "packet_acknowledge", { packetId: "packet_quarantined", expectedRevision: 1, idempotencyKey: "x" })).status).toBe(404);
  });

  it("returns authoritative workflow facts from an idempotent HTTP replay", async () => {
    const service = setup(); const clinicianA = await authenticate(service); const clinicianB = await authenticate(service, "clinician_two");
    const acknowledged = await invoke(service, clinicianA, "packet_acknowledge", { packetId: "packet_complete_apple", expectedRevision: 1, idempotencyKey: "handler-replay" });
    expect(acknowledged.status).toBe(200);
    const reviewed = await invoke(service, clinicianB, "packet_review", { packetId: "packet_complete_apple", expectedRevision: 1, idempotencyKey: "handler-review" });
    expect(reviewed.status).toBe(200);
    const replay = await invoke(service, clinicianA, "packet_acknowledge", { packetId: "packet_complete_apple", expectedRevision: 1, idempotencyKey: "handler-replay" });
    expect(await replay.json()).toMatchObject({ data: { acknowledged: { actorCode: "actor_clinician" }, reviewed: { actorCode: "actor_clinician_two" } } });
  });

  it("exercises template create, list, revise, and archive handlers", async () => {
    const service = setup(); const admin = await authenticate(service, "admin"); const clinician = await authenticate(service);
    expect((await invoke(service, admin, "template_list")).status).toBe(200);
    expect((await invoke(service, clinician, "template_list")).status).toBe(200);
    const createdResponse = await invoke(service, admin, "template_create", { builder: builder() }); expect(createdResponse.status).toBe(200);
    const created = (await createdResponse.json() as { data: { id: string; revision: number } }).data;
    expect((await invoke(service, admin, "template_revise", { templateId: created.id, expectedRevision: 1, builder: builder() })).status).toBe(200);
    expect((await invoke(service, admin, "template_archive", { templateId: created.id, expectedRevision: 2 })).status).toBe(200);
  });

  it("rejects malicious predecessor fields from template create and revise handlers", async () => {
    const service = setup(); const admin = await authenticate(service, "admin"); const malicious = { ...builder("recurring_collection"), predecessorRequestId: "request_state_active" };
    for (const [operation, payload] of [
      ["template_create", { builder: malicious }],
      ["template_revise", { templateId: "template_default_a", expectedRevision: 1, builder: malicious }],
    ] as const) {
      const response = await invoke(service, admin, operation, payload); expect(response.status).toBe(422); expect(await response.json()).toMatchObject({ error: { code: "predecessor_not_allowed" } });
    }
    const listed = await invoke(service, admin, "template_list"); const templates = (await listed.json() as { data: Array<{ id: string; revision: number; builder: RequestBuilder }> }).data;
    expect(templates.find(item => item.id === "template_default_a")?.revision).toBe(1); expect(templates.some(item => item.builder.predecessorRequestId !== undefined)).toBe(false);
  });

  it("uses reauthenticate rather than caller booleans for admin changes and revokes promoted sessions", async () => {
    const service = setup(); const admin = await authenticate(service, "admin"); const clinician = await authenticate(service);
    expect((await invoke(service, admin, "member_role_change", { membershipId: "membership_clinician_a", role: "practice_admin", reauthenticated: true })).status).toBe(400);
    expect((await invoke(service, admin, "member_role_change", { membershipId: "membership_clinician_a", role: "practice_admin" })).status).toBe(401);
    expect((await invoke(service, admin, "reauthenticate", { code: "246810" })).status).toBe(200);
    expect((await invoke(service, admin, "member_role_change", { membershipId: "membership_clinician_a", role: "practice_admin" })).status).toBe(200);
    const revoked = await invoke(service, clinician, "session"); expect(revoked.status).toBe(401); expect(await revoked.json()).toEqual({ error: { code: "session_revoked", message: "The requested operation is unavailable" } }); expect(revoked.headers.get("Set-Cookie")).toContain("Max-Age=0");
    expect((await invoke(service, admin, "retention")).status).toBe(200); expect((await invoke(service, admin, "audit", { cursor: 0, pageSize: 5 })).status).toBe(200);
  });

  it("clears terminal expired and revoked cookies with identical secure attributes", async () => {
    let now = Date.UTC(2040, 0, 1); let sequence = 0;
    const service = new SyntheticClinicalService({ clock: () => new Date(now).toISOString(), id: kind => `${kind}_terminal_${++sequence}`, token: kind => `${kind}_terminal_${++sequence}_A7vQ9xL2mN4pR6tW8yZ1` }, 10);
    const expiredAuth = await authenticate(service); now += 11;
    const expired = await invoke(service, expiredAuth, "session"); expect(expired.status).toBe(401); expect(await expired.json()).toMatchObject({ error: { code: "session_expired" } });
    const expiredCookie = expired.headers.get("Set-Cookie")!; for (const attribute of ["__Host-practice_synthetic_session=", "Path=/", "HttpOnly", "Secure", "SameSite=Strict", "Max-Age=0"]) expect(expiredCookie).toContain(attribute);
    now -= 11; const clinician = await authenticate(service); const admin = await authenticate(service, "admin"); await invoke(service, admin, "reauthenticate", { code: "246810" }); await invoke(service, admin, "member_role_change", { membershipId: "membership_clinician_a", role: "practice_admin" });
    const revoked = await invoke(service, clinician, "session"); expect(revoked.status).toBe(401); expect(await revoked.json()).toEqual({ error: { code: "session_revoked", message: "The requested operation is unavailable" } });
    expect(revoked.headers.get("Set-Cookie")).toBe(expiredCookie);
  });

  it("clears cookie/session state on logout", async () => {
    const service = setup(); const auth = await authenticate(service); const logout = await invoke(service, auth, "logout");
    expect(logout.status).toBe(200); expect(logout.headers.get("Set-Cookie")).toContain("Max-Age=0"); expect(await logout.text()).not.toContain("return");
  });
});
