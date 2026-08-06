import { auditCategories, careContexts, inboxReceivedSorts, inboxSupersessionStates, operationNames, packetAvailabilityStates, packetShapes, SYNTHETIC_OPERATION_VERSION, type AuditCategory, type InboxFilter, type OperationEnvelope, type OperationResponse, type RequestBuilder, type RequestPreview, type Role } from "../contracts/clinical";
import { PRACTICE_INSTRUCTION_VERSION, PRACTICE_PROTOCOL_VERSION } from "../contracts/api";
import { operationPolicy } from "../contracts/authorization";
import { jsonResponse } from "./security";
import { RequestValidationError } from "../synthetic/request-domain";
import { SyntheticClinicalService, SyntheticServiceError, type SyntheticFactories } from "../synthetic/service";

const MAX_BODY_BYTES = 16_384;
const COOKIE_NAME = "__Host-practice_synthetic_session";

function defaultFactories(): SyntheticFactories {
  const randomToken = (kind: string): string => {
    const bytes = crypto.getRandomValues(new Uint8Array(32));
    return `${kind}_synthetic_${[...bytes].map(byte => byte.toString(16).padStart(2, "0")).join("")}`;
  };
  return {
    clock: () => new Date().toISOString(),
    id: kind => `${kind}_synthetic_${crypto.randomUUID()}`,
    token: kind => randomToken(kind),
  };
}

export const syntheticClinicalService = new SyntheticClinicalService(defaultFactories());

function clearSessionCookie(response: Response): Response {
  response.headers.append("Set-Cookie", `${COOKIE_NAME}=; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=0`);
  return response;
}
function error(code: string, status: number): Response {
  const response = jsonResponse({ error: { code, message: "The requested operation is unavailable" } }, { status });
  return code === "session_expired" || code === "session_revoked" ? clearSessionCookie(response) : response;
}
function ok(data: unknown, csrfToken?: string): Response {
  const body: OperationResponse = { version: SYNTHETIC_OPERATION_VERSION, ok: true, data, ...(csrfToken === undefined ? {} : { csrfToken }) };
  return jsonResponse(body);
}
function keys(value: Record<string, unknown>, allowed: readonly string[]): void {
  if (Object.keys(value).some(key => !allowed.includes(key))) throw new SyntheticServiceError("invalid_body");
}
function payload(envelope: OperationEnvelope, allowed: readonly string[]): Record<string, unknown> {
  const value = envelope.payload ?? {}; keys(value, allowed); return value;
}
function string(value: unknown): string { if (typeof value !== "string" || value.length < 1 || value.length > 8_192) throw new SyntheticServiceError("invalid_body"); return value; }
function builderString(value: unknown): string { if (typeof value !== "string" || value.length > 8_192) throw new SyntheticServiceError("invalid_body"); return value; }
function number(value: unknown): number { if (typeof value !== "number" || !Number.isSafeInteger(value)) throw new SyntheticServiceError("invalid_body"); return value; }
function finiteNumber(value: unknown): number { if (typeof value !== "number" || !Number.isFinite(value)) throw new SyntheticServiceError("invalid_body"); return value; }
function record(value: unknown): Record<string, unknown> { if (!value || typeof value !== "object" || Array.isArray(value)) throw new SyntheticServiceError("invalid_body"); return value as Record<string, unknown>; }
function localDate(value: unknown): string { const text = string(value); const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text); if (!match) throw new SyntheticServiceError("invalid_body"); const year = Number(match[1]); const month = Number(match[2]); const day = Number(match[3]); const parsed = new Date(Date.UTC(year, month - 1, day)); if (parsed.getUTCFullYear() !== year || parsed.getUTCMonth() !== month - 1 || parsed.getUTCDate() !== day) throw new SyntheticServiceError("invalid_body"); return text; }
function utcDate(value: unknown): string { return localDate(value); }
function builder(value: unknown): RequestBuilder {
  const input = record(value); keys(input, ["context", "period", "schedule", "cadence", "pulse", "practiceCollectionInstructions", "practiceContactText", "predecessorRequestId"]);
  const period = record(input.period); const periodKind = string(period.kind);
  if (periodKind === "fixed_dates") { keys(period, ["kind", "startLocalDate", "endLocalDateExclusive", "timezoneRule"]); builderString(period.startLocalDate); builderString(period.endLocalDateExclusive); builderString(period.timezoneRule); }
  else if (periodKind === "relative_completed_days") { keys(period, ["kind", "days", "timezoneRule"]); finiteNumber(period.days); builderString(period.timezoneRule); }
  else throw new SyntheticServiceError("invalid_body");
  const schedule = record(input.schedule); keys(schedule, ["type", "windows"]);
  if (!Array.isArray(schedule.windows) || schedule.windows.length > 16) throw new SyntheticServiceError("invalid_body");
  for (const item of schedule.windows) { const window = record(item); keys(window, ["name", "startLocalTime", "endLocalTime", "minimumCount"]); builderString(window.name); builderString(window.startLocalTime); builderString(window.endLocalTime); finiteNumber(window.minimumCount); }
  const cadence = record(input.cadence); builderString(cadence.type); keys(cadence, ["type", "everyNDays"]);
  if (cadence.everyNDays !== undefined) finiteNumber(cadence.everyNDays);
  builderString(input.context); builderString(schedule.type); builderString(input.pulse);
  if (input.practiceCollectionInstructions !== undefined) builderString(input.practiceCollectionInstructions);
  if (input.practiceContactText !== undefined) builderString(input.practiceContactText);
  if (input.predecessorRequestId !== undefined) string(input.predecessorRequestId);
  return input as unknown as RequestBuilder;
}
function preview(value: unknown): RequestPreview {
  const input = record(value); keys(input, ["representation", "canonicalJson", "canonicalBytes"]);
  const representation = record(input.representation);
  keys(representation, ["schema", "protocolVersion", "instructionVersion", "relationshipId", "templateId", "templateRevision", "builder", "renderedInstructions"]);
  if (representation.schema !== SYNTHETIC_OPERATION_VERSION || representation.protocolVersion !== PRACTICE_PROTOCOL_VERSION || representation.instructionVersion !== PRACTICE_INSTRUCTION_VERSION) throw new SyntheticServiceError("invalid_body");
  string(representation.relationshipId); string(representation.templateId);
  const templateRevision = number(representation.templateRevision); if (templateRevision < 1) throw new SyntheticServiceError("invalid_body");
  builder(representation.builder); string(representation.renderedInstructions); string(input.canonicalJson);
  if (!Array.isArray(input.canonicalBytes) || input.canonicalBytes.length < 1 || input.canonicalBytes.length > MAX_BODY_BYTES || input.canonicalBytes.some(byte => typeof byte !== "number" || !Number.isInteger(byte) || byte < 0 || byte > 255)) throw new SyntheticServiceError("invalid_body");
  return input as unknown as RequestPreview;
}
function inboxFilter(value: unknown): InboxFilter {
  if (value === undefined) return {};
  const input = record(value); keys(input, ["shape", "availability", "context", "requestId", "receivedFromUtcDate", "receivedToExclusiveUtcDate", "acknowledged", "reviewed", "supersession", "sort", "cursor", "pageSize"]);
  const output: InboxFilter = {};
  if (input.shape !== undefined) { const shape = string(input.shape); if (!packetShapes.includes(shape as never)) throw new SyntheticServiceError("invalid_filter"); output.shape = shape as NonNullable<InboxFilter["shape"]>; }
  if (input.availability !== undefined) { const availability = string(input.availability); if (!packetAvailabilityStates.includes(availability as never)) throw new SyntheticServiceError("invalid_filter"); output.availability = availability as NonNullable<InboxFilter["availability"]>; }
  if (input.context !== undefined) { const context = string(input.context); if (!careContexts.includes(context as never)) throw new SyntheticServiceError("invalid_filter"); output.context = context as NonNullable<InboxFilter["context"]>; }
  if (input.requestId !== undefined) output.requestId = string(input.requestId);
  if (input.receivedFromUtcDate !== undefined) output.receivedFromUtcDate = utcDate(input.receivedFromUtcDate);
  if (input.receivedToExclusiveUtcDate !== undefined) output.receivedToExclusiveUtcDate = utcDate(input.receivedToExclusiveUtcDate);
  if (output.receivedFromUtcDate && output.receivedToExclusiveUtcDate && output.receivedFromUtcDate >= output.receivedToExclusiveUtcDate) throw new SyntheticServiceError("invalid_filter");
  for (const field of ["acknowledged", "reviewed"] as const) { if (input[field] !== undefined) { if (typeof input[field] !== "boolean") throw new SyntheticServiceError("invalid_filter"); output[field] = input[field]; } }
  if (input.supersession !== undefined) { const supersession = string(input.supersession); if (!inboxSupersessionStates.includes(supersession as never)) throw new SyntheticServiceError("invalid_filter"); output.supersession = supersession as NonNullable<InboxFilter["supersession"]>; }
  if (input.sort !== undefined) { const sort = string(input.sort); if (!inboxReceivedSorts.includes(sort as never)) throw new SyntheticServiceError("invalid_filter"); output.sort = sort as NonNullable<InboxFilter["sort"]>; }
  if (input.cursor !== undefined) { const cursor = number(input.cursor); if (cursor < 0) throw new SyntheticServiceError("invalid_filter"); output.cursor = cursor; }
  if (input.pageSize !== undefined) { const pageSize = number(input.pageSize); if (pageSize < 1 || pageSize > 25) throw new SyntheticServiceError("invalid_filter"); output.pageSize = pageSize; }
  return output;
}
function auditCategory(value: unknown): AuditCategory | undefined {
  if (value === undefined) return undefined;
  const category = string(value);
  if (!auditCategories.includes(category as AuditCategory)) throw new SyntheticServiceError("invalid_filter");
  return category as AuditCategory;
}
function noPayload(envelope: OperationEnvelope): void { payload(envelope, []); }
function sessionCookie(request: Request): string {
  const cookie = request.headers.get("Cookie") ?? "";
  for (const part of cookie.split(";")) { const [name, ...rest] = part.trim().split("="); if (name === COOKIE_NAME) return rest.join("="); }
  return "";
}

async function parseEnvelope(request: Request): Promise<OperationEnvelope> {
  if (request.headers.get("Content-Type")?.split(";", 1)[0]?.trim().toLowerCase() !== "application/json") throw new SyntheticServiceError("content_type_required", 415);
  const declaredLength = Number(request.headers.get("Content-Length") ?? "0");
  if (declaredLength > MAX_BODY_BYTES) throw new SyntheticServiceError("body_too_large", 413);
  if (!request.body) throw new SyntheticServiceError("invalid_json");
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = []; let length = 0;
  while (true) {
    const result = await reader.read();
    if (result.done) break;
    length += result.value.byteLength;
    if (length > MAX_BODY_BYTES) { await reader.cancel(); throw new SyntheticServiceError("body_too_large", 413); }
    chunks.push(result.value);
  }
  const bytes = new Uint8Array(length); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  let parsed: unknown;
  try { parsed = JSON.parse(new TextDecoder().decode(bytes)); } catch { throw new SyntheticServiceError("invalid_json"); }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new SyntheticServiceError("invalid_body");
  const record = parsed as Record<string, unknown>; keys(record, ["version", "operation", "csrfToken", "payload"]);
  if (record.version !== SYNTHETIC_OPERATION_VERSION || typeof record.operation !== "string" || !operationNames.includes(record.operation as never)) throw new SyntheticServiceError("unknown_operation", 404);
  if (record.payload !== undefined && (!record.payload || typeof record.payload !== "object" || Array.isArray(record.payload))) throw new SyntheticServiceError("invalid_body");
  if (record.csrfToken !== undefined && typeof record.csrfToken !== "string") throw new SyntheticServiceError("invalid_body");
  return record as unknown as OperationEnvelope;
}

export async function handleClinicalOperation(request: Request, service = syntheticClinicalService): Promise<Response> {
  try {
    if (request.method !== "POST") return error("method_not_allowed", 405);
    const url = new URL(request.url);
    if (request.headers.get("Origin") !== url.origin) return error("origin_denied", 403);
    const envelope = await parseEnvelope(request);
    const sessionId = sessionCookie(request);
    const policy = operationPolicy(envelope.operation);
    service.preauthorizeOperation(sessionId, envelope.operation);
    if (policy.csrfRequired) service.assertCsrf(sessionId, envelope.csrfToken);
    const response = await dispatchClinicalOperation(service, sessionId, envelope);
    if (envelope.operation === "verify_mfa") {
      const result = response as { sessionId: string; csrfToken: string };
      const resultResponse = ok({ authState: "authenticated" }, result.csrfToken);
      resultResponse.headers.append("Set-Cookie", `${COOKIE_NAME}=${result.sessionId}; Path=/; HttpOnly; Secure; SameSite=Strict`);
      return resultResponse;
    }
    if (envelope.operation === "session_bootstrap") {
      const result = response as ReturnType<SyntheticClinicalService["sessionBootstrap"]>;
      return ok(result.session, result.csrfToken);
    }
    if (envelope.operation === "logout") {
      return clearSessionCookie(ok(response));
    }
    return ok(response);
  } catch (caught) {
    if (caught instanceof RequestValidationError) return jsonResponse({ error: { code: "request_validation_failed", message: "The requested operation is unavailable", issues: caught.issues } }, { status: 422 });
    if (caught instanceof SyntheticServiceError) return error(caught.code, caught.status);
    return error("operation_unavailable", 500);
  }
}

export async function dispatchClinicalOperation(service: SyntheticClinicalService, sessionId: string, envelope: OperationEnvelope): Promise<unknown> {
  const operation = envelope.operation;
  if (operation === "sign_in") { const p = payload(envelope, ["login"]); return service.signIn(string(p.login)); }
  if (operation === "verify_mfa") { const p = payload(envelope, ["challengeId", "code"]); return service.verifyMfa(string(p.challengeId), string(p.code)); }
  if (operation === "session_bootstrap") { noPayload(envelope); return service.sessionBootstrap(sessionId); }
  if (operation === "reauthenticate") { const p = payload(envelope, ["code"]); return service.reauthenticate(sessionId, string(p.code)); }
  if (operation === "recovery") { noPayload(envelope); return service.recovery(); }
  if (operation === "session") { noPayload(envelope); return service.session(sessionId); }
  if (operation === "logout") { noPayload(envelope); service.logout(sessionId); return { authState: "signed_out" }; }
  if (operation === "relationship_search") { const p = payload(envelope, ["query"]); return service.relationshipSearch(sessionId, string(p.query)); }
  if (operation === "relationship_select") { const p = payload(envelope, ["relationshipId"]); service.relationshipSelect(sessionId, string(p.relationshipId)); return { selected: true }; }
  if (operation === "template_list") { noPayload(envelope); return service.templateList(sessionId); }
  if (operation === "template_create") { const p = payload(envelope, ["builder"]); return service.templateCreate(sessionId, builder(p.builder)); }
  if (operation === "template_revise") { const p = payload(envelope, ["templateId", "expectedRevision", "builder"]); return service.templateRevise(sessionId, string(p.templateId), number(p.expectedRevision), builder(p.builder)); }
  if (operation === "template_archive") { const p = payload(envelope, ["templateId", "expectedRevision"]); return service.templateArchive(sessionId, string(p.templateId), number(p.expectedRevision)); }
  if (operation === "request_list") { noPayload(envelope); return service.requestList(sessionId); }
  if (operation === "request_preview") { const p = payload(envelope, ["templateId", "expectedTemplateRevision", "builder"]); return service.requestPreview(sessionId, string(p.templateId), number(p.expectedTemplateRevision), builder(p.builder)); }
  if (operation === "request_issue") { const p = payload(envelope, ["preview", "idempotencyKey"]); return service.requestIssue(sessionId, preview(p.preview), string(p.idempotencyKey)); }
  if (operation === "invitation_claim") { const p = payload(envelope, ["token"]); return service.invitationClaim(string(p.token)); }
  if (operation === "invitation_accept") { const p = payload(envelope, ["claimantReceipt"]); return service.invitationAccept(string(p.claimantReceipt)); }
  if (operation === "invitation_revoke") { const p = payload(envelope, ["requestId"]); service.invitationRevoke(sessionId, string(p.requestId)); return { revoked: true }; }
  if (operation === "invitation_expire") { const p = payload(envelope, ["requestId"]); service.invitationExpire(sessionId, string(p.requestId)); return { expired: true }; }
  if (operation === "request_cancel") { const p = payload(envelope, ["requestId", "expectedRevision"]); return service.requestCancel(sessionId, string(p.requestId), number(p.expectedRevision)); }
  if (operation === "request_renew") { const p = payload(envelope, ["predecessorId", "preview", "idempotencyKey"]); return service.requestRenew(sessionId, string(p.predecessorId), preview(p.preview), string(p.idempotencyKey)); }
  if (operation === "inbox") { const p = payload(envelope, ["filter"]); return service.inbox(sessionId, inboxFilter(p.filter)); }
  if (operation === "packet_load") { const p = payload(envelope, ["packetId"]); return service.packetLoad(sessionId, string(p.packetId)); }
  if (operation === "packet_download") { const p = payload(envelope, ["packetId"]); return service.packetDownload(sessionId, string(p.packetId)); }
  if (operation === "packet_acknowledge") { const p = payload(envelope, ["packetId", "expectedRevision", "idempotencyKey"]); return service.packetAcknowledge(sessionId, string(p.packetId), number(p.expectedRevision), string(p.idempotencyKey)); }
  if (operation === "packet_review") { const p = payload(envelope, ["packetId", "expectedRevision", "idempotencyKey"]); return service.packetReview(sessionId, string(p.packetId), number(p.expectedRevision), string(p.idempotencyKey)); }
  if (operation === "packet_passive_event") { const p = payload(envelope, ["packetId", "event"]); const event = string(p.event); if (event !== "dwell" && event !== "scroll" && event !== "print") throw new SyntheticServiceError("invalid_body"); return service.packetPassiveEvent(sessionId, string(p.packetId), event); }
  if (operation === "members") { noPayload(envelope); return service.members(sessionId); }
  if (operation === "member_role_change") { const p = payload(envelope, ["membershipId", "role"]); const role = string(p.role); if (role !== "practice_admin" && role !== "clinician") throw new SyntheticServiceError("invalid_body"); return service.memberRoleChange(sessionId, string(p.membershipId), role as Role); }
  if (operation === "member_offboard") { const p = payload(envelope, ["membershipId"]); return service.memberOffboard(sessionId, string(p.membershipId)); }
  if (operation === "member_revoke_sessions") { const p = payload(envelope, ["membershipId"]); return service.memberRevokeSessions(sessionId, string(p.membershipId)); }
  if (operation === "retention") { noPayload(envelope); return service.retention(sessionId); }
  if (operation === "audit") { const p = payload(envelope, ["cursor", "pageSize", "category"]); const cursor = p.cursor === undefined ? 0 : number(p.cursor); const pageSize = p.pageSize === undefined ? 20 : number(p.pageSize); if (cursor < 0 || pageSize < 1 || pageSize > 50) throw new SyntheticServiceError("invalid_filter"); return service.audit(sessionId, cursor, pageSize, auditCategory(p.category)); }
  throw new SyntheticServiceError("unknown_operation", 404);
}
