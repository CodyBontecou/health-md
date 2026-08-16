// @vitest-environment jsdom
import { cleanup, render, screen, waitFor, within } from "@testing-library/react";
import "@testing-library/jest-dom/vitest";
import userEvent from "@testing-library/user-event";
import axe from "axe-core";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { OperationName, PacketRecord, RequestBuilder, RequestRecord, RequestTemplateRevision } from "../src/contracts/clinical";
import { SYNTHETIC_OPERATION_VERSION } from "../src/contracts/clinical";
import { createAcceptanceReview, createRequestPreview } from "../src/synthetic/request-domain";
import { App, RootErrorBoundary } from "../src/web/App";
import type { OperationClient } from "../src/web/api-client";

const clinicianSession = { role: "clinician" as const, capabilities: ["relationship:search", "request:write", "packet:read", "packet:download", "packet:acknowledge", "packet:review"] as const, tenantCode: "tenant_a", practiceDisplayName: "Fictional Practice A" };
const adminSession = { role: "practice_admin" as const, capabilities: ["template:manage", "member:manage", "retention:manage", "audit:read"] as const, tenantCode: "tenant_a", practiceDisplayName: "Fictional Practice A" };
const builder: RequestBuilder = { context: "pre_visit", period: { kind: "fixed_dates", startLocalDate: "2040-01-01", endLocalDateExclusive: "2040-01-08", timezoneRule: "acceptance_time_iana" }, schedule: { type: "all_readings", windows: [] }, cadence: { type: "at_period_end" }, pulse: "preferred" };
const preview = createRequestPreview({ relationshipId: "relationship_unique_a", templateId: "template_default_a", templateRevision: 1, builder, practiceDisplayName: "Fictional Practice A" });
const acceptanceReview = createAcceptanceReview({ representation: preview.representation, requestRepresentationSha256: "1".repeat(64), practiceDisplayName: "Fictional Practice A", deviceIanaTimezone: "Etc/UTC" });
const acceptanceReviewSha256 = "2".repeat(64);
const request: RequestRecord = { id: "request_memory", tenantId: "tenant_a", relationshipId: "relationship_unique_a", revision: 1, lifecycle: "issued", delivery: "not_attempted", claim: "available", submission: "none", representation: preview.representation, canonicalJson: preview.canonicalJson, predecessorRequestId: null, successorRequestId: null, acceptance: null, history: [] };
const packet: PacketRecord = { id: "packet_memory", tenantId: "tenant_a", requestId: "request_memory", relationshipLabel: "Taylor <script> Fictional", revision: 1, shape: "complete", availability: "available", receivedAt: "2040-01-09T12:00:00Z", requestedPeriod: "2040-01-01/2040-01-08", submittedPeriod: "2040-01-01/2040-01-08", timezone: "Etc/UTC", coverage: "satisfied", readings: [
  { key: "one", observedAt: "2040-01-02T08:00:00Z", systolicMmHg: 118, diastolicMmHg: 76, pulseBeatsPerMinute: 68, source: "apple_health", manual: "not_marked_manual", pulseAssociation: "patient_confirmed_same_source_nearby", windowName: null },
  { key: "two", observedAt: "2040-01-03T08:00:00Z", systolicMmHg: 121, diastolicMmHg: 78, pulseBeatsPerMinute: null, source: "apple_health", manual: "manual", pulseAssociation: "none", windowName: null },
], disclosures: ["Apple Health synthetic provenance", "Manual records remain included"], limitations: "Synthetic source availability can be incomplete.", supersedesPacketId: null, supersededByPacketId: null, opened: { type: "opened", actorCode: "actor_clinician", at: "2040-01-09T12:01:00Z", revision: 1 }, acknowledged: null, reviewed: null, history: [{ type: "opened", actorCode: "actor_clinician", at: "2040-01-09T12:01:00Z", revision: 1 }] };

function fakeClient(overrides: Partial<Record<OperationName, unknown | ((payload: Record<string, unknown>) => unknown)>> = {}): OperationClient & { invoke: ReturnType<typeof vi.fn>; clear: ReturnType<typeof vi.fn> } {
  const defaults: Partial<Record<OperationName, unknown | ((payload: Record<string, unknown>) => unknown)>> = {
    sign_in: { authState: "mfa_required", challengeId: "challenge_memory" }, verify_mfa: { authState: "authenticated" }, session_bootstrap: clinicianSession, logout: { authState: "signed_out" },
    relationship_search: { state: "unique", results: [{ id: "relationship_unique_a", label: "Avery Fiction — synthetic", state: "active", nameProvenance: "patient_confirmed", dobProvenance: "patient_confirmed", practiceReferenceProvenance: "practice_supplied" }] }, relationship_select: { selected: true },
    request_list: [request], template_list: [{ id: "template_default_a", tenantId: "tenant_a", revision: 1, state: "active", builder, authorCode: "actor_admin", modifiedAt: "2040-01-01T00:00:00Z", previousRevision: null } satisfies RequestTemplateRevision], request_preview: preview, request_issue: { request, invitation: { requestId: request.id, token: "invitation_synthetic_memory_only", genericText: "A synthetic document request is available.", displayState: "available_once" } }, invitation_claim: { claimantReceipt: "claimant_memory", expiresAt: "2040-01-01T00:05:00Z", review: acceptanceReview, reviewSha256: acceptanceReviewSha256 }, invitation_accept: { claim: "accepted" }, invitation_revoke: { revoked: true },
    inbox: { items: [{ id: packet.id, relationshipLabel: packet.relationshipLabel, requestId: packet.requestId, revision: 1, shape: "complete", availability: "available", receivedAt: packet.receivedAt, requestedPeriod: packet.requestedPeriod, submittedPeriod: packet.submittedPeriod, coverage: "satisfied", supersedesPacketId: null, supersededByPacketId: null, opened: false, acknowledged: false, reviewed: false }], nextCursor: null },
    packet_load: packet, packet_download: { filename: "practice-document.json", canonicalJson: JSON.stringify({ schema: "practice.synthetic.packet/1.0-draft.2" }) }, packet_acknowledge: { ...packet, acknowledged: { type: "acknowledged", actorCode: "actor_clinician", at: "2040-01-09T12:02:00Z", revision: 1 } }, packet_review: { ...packet, reviewed: { type: "reviewed", actorCode: "actor_clinician", at: "2040-01-09T12:03:00Z", revision: 1 } },
    members: [{ membershipId: "membership_clinician", actorCode: "actor_clinician", role: "clinician", state: "active", sessionsRevokedAt: null }], reauthenticate: { authState: "authenticated" }, member_revoke_sessions: { membershipId: "membership_clinician", actorCode: "actor_clinician", role: "clinician", state: "active", sessionsRevokedAt: "2040-01-09T12:04:00Z" }, member_role_change: { membershipId: "membership_clinician", actorCode: "actor_clinician", role: "practice_admin", state: "role_changed", sessionsRevokedAt: "2040-01-09T12:04:00Z" }, member_offboard: { membershipId: "membership_clinician", actorCode: "actor_clinician", role: "clinician", state: "offboarded", sessionsRevokedAt: "2040-01-09T12:04:00Z" },
    retention: { policy: { version: "practice.synthetic.retention/1.0-draft.1", status: "authoritative_synthetic_draft_only", acknowledgedDays: 30, unacknowledgedDays: 90, backupTargetDays: 35, legalApproval: false }, deletion: [] }, audit: { events: [], nextCursor: null },
  };
  const values = { ...defaults, ...overrides };
  const invoke = vi.fn(async (operation: OperationName, payload: Record<string, unknown> = {}) => { const value = values[operation]; if (value instanceof Error) throw value; return typeof value === "function" ? (value as (payload: Record<string, unknown>) => unknown)(payload) : value; });
  return { invoke, clear: vi.fn((): void => undefined) } as unknown as OperationClient & { invoke: ReturnType<typeof vi.fn>; clear: ReturnType<typeof vi.fn> };
}

function assertLifecycleFacts(lifecycle: string, claim: string): void {
  const table = screen.getByRole("table", { name: "Separate lifecycle facts" });
  const cells = [...table.querySelectorAll("tbody th, tbody td")].map(cell => cell.textContent);
  expect(cells).toEqual([lifecycle, "delivered", claim, "none", "None", "None"]);
}

function ThrowingChild(): never { throw new Error("fictional-sensitive-detail"); }

const originalCreateObjectURL = URL.createObjectURL;
const originalRevokeObjectURL = URL.revokeObjectURL;
beforeEach(() => { history.replaceState(null, "", "/sign-in"); vi.stubGlobal("scrollTo", vi.fn()); });
afterEach(() => { cleanup(); Object.defineProperty(URL, "createObjectURL", { configurable: true, value: originalCreateObjectURL }); Object.defineProperty(URL, "revokeObjectURL", { configurable: true, value: originalRevokeObjectURL }); vi.unstubAllGlobals(); });

describe("portal flows", () => {
  it("renders a generic root fallback without error details or console logging", () => {
    const error = vi.spyOn(console, "error").mockImplementation(() => undefined); const warn = vi.spyOn(console, "warn").mockImplementation(() => undefined); const log = vi.spyOn(console, "log").mockImplementation(() => undefined);
    render(<RootErrorBoundary><ThrowingChild /></RootErrorBoundary>, { onCaughtError: () => undefined });
    const fallback = screen.getByRole("alert"); expect(within(fallback).getByRole("heading", { name: "Portal unavailable" })).toBeVisible();
    expect(fallback).toHaveTextContent("No clinical details disclosed"); expect(fallback).toHaveTextContent("The requested content is not available."); expect(fallback).not.toHaveTextContent("fictional-sensitive-detail");
    expect(error).not.toHaveBeenCalled(); expect(warn).not.toHaveBeenCalled(); expect(log).not.toHaveBeenCalled();
  });

  it("signs in with fictional MFA, uses generic title, role navigation, history, and no storage", async () => {
    const user = userEvent.setup(); const client = fakeClient(); const storage = vi.spyOn(Storage.prototype, "setItem");
    render(<App initialPath="/sign-in" client={client} />);
    await user.click(screen.getByRole("button", { name: "Continue to MFA" }));
    expect(location.pathname).toBe("/verify");
    await user.click(screen.getByRole("button", { name: "Verify synthetic account" }));
    expect(await screen.findByRole("heading", { name: "Practice portal overview" })).toBeVisible();
    expect(document.title).toBe("Health.md Practice");
    expect(screen.getByRole("link", { name: "Packet inbox" })).toBeVisible();
    expect(screen.queryByRole("link", { name: "Members" })).toBeNull();
    expect(storage).not.toHaveBeenCalled();
    history.pushState(null, "", "/portal/inbox"); window.dispatchEvent(new PopStateEvent("popstate"));
    expect(await screen.findByRole("heading", { name: "Packet inbox" })).toBeVisible();
    expect(location.search).toBe("");
  });

  it("renders role-aware admin navigation without clinical packet access", () => {
    render(<App initialPath="/portal" client={fakeClient()} initialSession={adminSession} />);
    expect(screen.getByRole("link", { name: "Members" })).toBeVisible();
    expect(screen.queryByRole("link", { name: "Packet inbox" })).toBeNull();
  });

  it("requires explicit relationship selection and never auto-selects ambiguous results", async () => {
    const user = userEvent.setup(); const client = fakeClient({ relationship_search: { state: "ambiguous", results: [
      { id: "one", label: "Duplicate Fiction One", state: "active", nameProvenance: "patient_confirmed", dobProvenance: "patient_confirmed", practiceReferenceProvenance: "practice_supplied" },
      { id: "two", label: "Duplicate Fiction Two", state: "active", nameProvenance: "patient_confirmed", dobProvenance: "patient_confirmed", practiceReferenceProvenance: "practice_supplied" },
    ] } });
    render(<App initialPath="/portal/relationships" client={client} initialSession={clinicianSession} />);
    await user.click(screen.getByRole("button", { name: "Search relationships" }));
    expect(await screen.findByText("Multiple possible relationships")).toBeVisible();
    expect(screen.getAllByRole("button", { name: "Select this relationship" })).toHaveLength(2);
    expect(client.invoke).not.toHaveBeenCalledWith("relationship_select", expect.anything());
  });

  it("shows exact blocking request validation and never issues unresolved relative semantics", async () => {
    const user = userEvent.setup(); const client = fakeClient();
    render(<App initialPath="/portal/relationships" client={client} initialSession={clinicianSession} />);
    await user.click(screen.getByRole("button", { name: "Search relationships" }));
    await user.click(await screen.findByRole("button", { name: "Select this relationship" }));
    await user.click(screen.getByRole("link", { name: "Requests" }));
    await user.click(await screen.findByRole("button", { name: "Start new request" }));
    await user.click(screen.getByRole("radio", { name: "Constrained customization" }));
    await user.click(screen.getByRole("radio", { name: /Relative completed days/ }));
    await user.click(screen.getByRole("button", { name: "Validate and preview" }));
    const alert = screen.getByRole("alert");
    expect(alert).toHaveTextContent("relative_days_invalid");
    expect(alert).toHaveTextContent("relative_acceptance_unresolved");
    expect(client.invoke).not.toHaveBeenCalledWith("request_preview", expect.anything());
    expect(client.invoke).not.toHaveBeenCalledWith("request_issue", expect.anything());
  });

  it("keeps preview equal to issue input and clears a one-time invitation secret after claim", async () => {
    const user = userEvent.setup(); const client = fakeClient();
    render(<App initialPath="/portal/relationships" client={client} initialSession={clinicianSession} />);
    await user.click(screen.getByRole("button", { name: "Search relationships" })); await user.click(await screen.findByRole("button", { name: "Select this relationship" }));
    await user.click(screen.getByRole("link", { name: "Requests" })); await user.click(await screen.findByRole("button", { name: "Start new request" }));
    await user.click(screen.getByRole("button", { name: "Validate and preview" }));
    expect(await screen.findByText("Exact patient-facing instruction text")).toBeVisible();
    expect(document.querySelector(".plain-text-preview pre")?.textContent).toBe(preview.representation.renderedInstructions);
    await user.click(screen.getByRole("button", { name: "Issue this exact preview" }));
    expect(await screen.findByText("invitation_synthetic_memory_only")).toBeVisible();
    const previewCall = client.invoke.mock.calls.find(call => call[0] === "request_preview");
    const issueCall = client.invoke.mock.calls.find(call => call[0] === "request_issue");
    expect(issueCall?.[1].preview).toBe(preview);
    expect(previewCall?.[1].builder).toEqual(builder);
    await user.click(screen.getByRole("button", { name: "Synthetic claim" }));
    expect(screen.queryByText("invitation_synthetic_memory_only")).toBeNull();
    expect(await screen.findByText(/Original one-time token cleared/)).toBeVisible();
    await user.click(screen.getByRole("button", { name: "Accept these exact instructions" }));
    expect(await screen.findByText(/Claimant receipt cleared/)).toBeVisible();
    expect(client.invoke).toHaveBeenCalledWith("invitation_accept", { claimantReceipt: "claimant_memory", reviewedAcceptanceSha256: acceptanceReviewSha256 });
  });

  it("renders exact independent delivery, claim, and submission lifecycle facts through claim and acceptance", async () => {
    let phase: "issued" | "claimed" | "accepted" = "issued";
    const lifecycleRequest = () => ({ ...request, lifecycle: phase, delivery: "delivered" as const, claim: phase === "issued" ? "available" as const : phase, submission: "none" as const });
    const client = fakeClient({
      request_issue: () => ({ request: lifecycleRequest(), invitation: { requestId: request.id, token: "invitation_synthetic_memory_only", genericText: "A synthetic document request is available.", displayState: "available_once" } }),
      invitation_claim: () => { phase = "claimed"; return { claimantReceipt: "claimant_memory", expiresAt: "2040-01-01T00:05:00Z", review: acceptanceReview, reviewSha256: acceptanceReviewSha256 }; },
      invitation_accept: () => { phase = "accepted"; return { claim: "accepted" }; },
      request_list: () => [lifecycleRequest()],
    });
    const user = userEvent.setup(); render(<App initialPath="/portal/relationships" client={client} initialSession={clinicianSession} />);
    await user.click(screen.getByRole("button", { name: "Search relationships" })); await user.click(await screen.findByRole("button", { name: "Select this relationship" })); await user.click(screen.getByRole("link", { name: "Requests" })); await user.click(await screen.findByRole("button", { name: "Start new request" })); await user.click(screen.getByRole("button", { name: "Validate and preview" })); await user.click(await screen.findByRole("button", { name: "Issue this exact preview" }));
    expect(screen.getByText("Synthetic notification delivery is not implemented.", { exact: false })).toBeVisible();
    expect(within(screen.getByRole("table", { name: "Separate lifecycle facts" })).getAllByRole("columnheader").map(cell => cell.textContent)).toEqual(["Lifecycle", "Delivery", "Claim", "Submission", "Predecessor", "Successor"]); assertLifecycleFacts("issued", "available");
    await user.click(screen.getByRole("button", { name: "Synthetic claim" })); await screen.findByText(/Original one-time token cleared/); assertLifecycleFacts("claimed", "claimed");
    await user.click(screen.getByRole("button", { name: "Accept these exact instructions" })); await screen.findByText(/Claimant receipt cleared/); assertLifecycleFacts("accepted", "accepted");
  });

  it("renders every report reading and disclosure, has chart alternative, and keeps print/download separate from acknowledgment", async () => {
    const user = userEvent.setup(); const client = fakeClient(); const createUrl = vi.fn((_blob: Blob) => "blob:memory"); const revoke = vi.fn();
    Object.defineProperty(URL, "createObjectURL", { configurable: true, value: createUrl }); Object.defineProperty(URL, "revokeObjectURL", { configurable: true, value: revoke });
    let anchorDownload = ""; let anchorHref = "";
    vi.spyOn(HTMLAnchorElement.prototype, "click").mockImplementation(function (this: HTMLAnchorElement) { anchorDownload = this.download; anchorHref = this.href; }); vi.stubGlobal("print", vi.fn());
    const { container } = render(<App initialPath="/portal/inbox" client={client} initialSession={clinicianSession} />);
    await user.click(await screen.findByRole("button", { name: "Open report" }));
    expect(await screen.findByText("Complete reading table — 2 of 2 rows visible")).toBeVisible();
    expect(screen.getByText("118 mmHg")).toBeVisible(); expect(screen.getByText("121 mmHg")).toBeVisible();
    expect(screen.getByText("Manual records remain included")).toBeVisible(); expect(screen.getByText("Synthetic source availability can be incomplete.")).toBeVisible();
    const provenance = screen.getByRole("table", { name: "Document provenance and exact periods" });
    expect(within(provenance).getByText("Taylor <script> Fictional")).toBeVisible(); expect(within(provenance).getAllByText("2040-01-01/2040-01-08")).toHaveLength(2); expect(within(provenance).getByText("Etc/UTC")).toBeVisible(); expect(within(provenance).getByText("patient confirmed / practice supplied")).toBeVisible();
    expect(screen.getByText(/Coverage: satisfied/)).toBeVisible(); expect(screen.getByText("patient confirmed same source nearby")).toBeVisible(); expect(screen.getByText("No associated pulse")).toBeVisible();
    expect(screen.getByText("Immutable synthetic document · revision 1")).toBeVisible();
    expect(screen.getByRole("img", { name: /Neutral systolic trend/ })).toBeVisible();
    expect(container.querySelector("#trend-description")?.textContent).toContain("118 millimeters of mercury");
    expect(container.querySelector("script")).toBeNull();
    await user.click(screen.getByRole("button", { name: "Print" }));
    await user.click(screen.getByRole("button", { name: "Download canonical JSON" }));
    expect(client.invoke).not.toHaveBeenCalledWith("packet_acknowledge", expect.anything());
    expect(client.invoke).not.toHaveBeenCalledWith("packet_review", expect.anything());
    expect(createUrl).toHaveBeenCalledOnce(); const blob = createUrl.mock.calls[0]?.[0] as Blob; expect(blob.type).toBe("application/json"); expect(blob.size).toBe(new TextEncoder().encode(JSON.stringify({ schema: "practice.synthetic.packet/1.0-draft.2" })).byteLength); expect(anchorDownload).toBe("practice-document.json"); expect(anchorHref).toContain("blob:memory"); expect(revoke).toHaveBeenCalledWith("blob:memory");
    await user.click(screen.getByRole("button", { name: "Acknowledge receipt" }));
    await user.click(within(screen.getByRole("dialog")).getByRole("button", { name: "Acknowledge receipt" }));
    expect(await screen.findByText("Explicit receipt acknowledgment recorded.")).toBeVisible();
    expect(client.invoke).toHaveBeenCalledWith("packet_acknowledge", expect.objectContaining({ expectedRevision: 1 }));
    expect(client.invoke).not.toHaveBeenCalledWith("packet_review", expect.anything());
    expect((await axe.run(container, { rules: { "color-contrast": { enabled: false } } })).violations).toEqual([]);
  });

  it("requires admin step-up before session revocation and clears protected state on logout", async () => {
    const user = userEvent.setup(); const client = fakeClient();
    render(<App initialPath="/portal/admin/members" client={client} initialSession={adminSession} />);
    await user.click(await screen.findByRole("button", { name: "Revoke sessions" }));
    expect(screen.getByRole("dialog")).toBeVisible();
    await user.click(screen.getByRole("button", { name: "Verify and confirm" }));
    await screen.findByText(/Step-up succeeded/);
    const reauthOrder = client.invoke.mock.invocationCallOrder[client.invoke.mock.calls.findIndex(call => call[0] === "reauthenticate")];
    const revokeOrder = client.invoke.mock.invocationCallOrder[client.invoke.mock.calls.findIndex(call => call[0] === "member_revoke_sessions")];
    expect(reauthOrder).toBeLessThan(revokeOrder ?? 0);
    await user.click(screen.getByRole("button", { name: "Sign out" }));
    expect(await screen.findByRole("heading", { name: "Signed out" })).toBeVisible();
    expect(client.clear).toHaveBeenCalled();
    history.pushState(null, "", "/portal/admin/members"); window.dispatchEvent(new PopStateEvent("popstate"));
    expect(screen.queryByText("actor_clinician")).toBeNull();
  });

  it.each([["Change role", "member_role_change"], ["Offboard", "member_offboard"]] as const)("reauthenticates before admin action %s and then bootstraps truth", async (button, operation) => {
    const api = fakeClient(); const user = userEvent.setup(); render(<App initialPath="/portal/admin/members" client={api} initialSession={adminSession} />); await user.click(await screen.findByRole("button", { name: button })); await user.click(screen.getByRole("button", { name: "Verify and confirm" })); await waitFor(() => expect(api.invoke).toHaveBeenCalledWith(operation, expect.objectContaining({ membershipId: "membership_clinician" }))); expect(api.invoke).toHaveBeenCalledWith("session_bootstrap", {});
  });

  it("uses only the static same-origin operation endpoint in client envelopes", async () => {
    const calls: Array<[RequestInfo | URL, RequestInit | undefined]> = [];
    const { createSyntheticOperationClient } = await import("../src/web/api-client");
    const fetcher = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => { calls.push([input, init]); return new Response(JSON.stringify({ version: SYNTHETIC_OPERATION_VERSION, ok: true, data: {} }), { status: 200 }); }) as unknown as typeof fetch;
    await createSyntheticOperationClient(fetcher).invoke("sign_in", { login: "clinician" });
    expect(calls[0]?.[0]).toBe("/api/v1/operation");
    expect(calls[0]?.[1]?.method).toBe("POST");
    expect(String(calls[0]?.[1]?.body)).not.toContain("?");
  });
});
