// @vitest-environment jsdom
import { cleanup, render, screen, waitFor, within } from "@testing-library/react";
import "@testing-library/jest-dom/vitest";
import userEvent from "@testing-library/user-event";
import axe from "axe-core";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Capability, OperationName, PacketRecord, RequestBuilder, RequestRecord, RequestTemplateRevision } from "../src/contracts/clinical";
import { createRequestPreview } from "../src/synthetic/request-domain";
import { App } from "../src/web/App";
import { PracticeClientError, type OperationClient } from "../src/web/api-client";

const capabilities = ["relationship:search", "request:write", "packet:read", "packet:download", "packet:acknowledge", "packet:review"] as const satisfies readonly Capability[];
const session = { role: "clinician" as const, capabilities, tenantCode: "tenant_a", practiceDisplayName: "Fictional Practice A" };
const admin = { role: "practice_admin" as const, capabilities: ["template:manage", "member:manage", "retention:manage", "audit:read"] as const, tenantCode: "tenant_a", practiceDisplayName: "Fictional Practice A" };
const builder: RequestBuilder = { context: "pre_visit", period: { kind: "fixed_dates", startLocalDate: "2040-01-01", endLocalDateExclusive: "2040-01-08", timezoneRule: "acceptance_time_iana" }, schedule: { type: "all_readings", windows: [] }, cadence: { type: "at_period_end" }, pulse: "preferred" };
const relationship = { id: "relationship_unique_a", label: "Avery Fiction — synthetic", state: "active", nameProvenance: "patient_confirmed", dobProvenance: "patient_confirmed", practiceReferenceProvenance: "practice_supplied" };
const template = (revision = 1): RequestTemplateRevision => ({ id: "template_active", tenantId: "tenant_a", revision, state: "active", builder, authorCode: "actor_admin", modifiedAt: "2040-01-01T00:00:00Z", previousRevision: revision - 1 || null });
const preview = (revision = 1) => createRequestPreview({ relationshipId: relationship.id, templateId: "template_active", templateRevision: revision, builder, practiceDisplayName: "Fictional Practice A" });
const request = (revision = 1): RequestRecord => ({ id: "request_selected", tenantId: "tenant_a", relationshipId: relationship.id, revision, lifecycle: "issued", delivery: "not_attempted", claim: "available", submission: "none", representation: preview().representation, canonicalJson: preview().canonicalJson, predecessorRequestId: null, successorRequestId: null, acceptance: null, history: [] });
const packet: PacketRecord = { id: "packet_selected", tenantId: "tenant_a", requestId: "request_selected", relationshipLabel: "Fictional relationship", revision: 1, shape: "complete", availability: "available", receivedAt: "2040-01-09T12:00:00Z", requestedPeriod: "2040-01-01/2040-01-08", submittedPeriod: "2040-01-01/2040-01-08", timezone: "Etc/UTC", coverage: "satisfied", readings: [], disclosures: ["Synthetic disclosure"], limitations: "Synthetic limitation", supersedesPacketId: null, supersededByPacketId: null, opened: null, acknowledged: null, reviewed: null, history: [] };

function client(values: Partial<Record<OperationName, unknown | ((payload: Record<string, unknown>) => unknown)>> = {}): OperationClient & { invoke: ReturnType<typeof vi.fn>; clear: ReturnType<typeof vi.fn> } {
  const defaults: Partial<Record<OperationName, unknown | ((payload: Record<string, unknown>) => unknown)>> = {
    session_bootstrap: session, relationship_search: { state: "unique", results: [relationship] }, relationship_select: { selected: true }, template_list: [template()], request_list: [], request_preview: preview(),
    inbox: { items: [{ id: packet.id, relationshipLabel: packet.relationshipLabel, requestId: packet.requestId, revision: 1, shape: "complete", availability: "available", receivedAt: packet.receivedAt, requestedPeriod: packet.requestedPeriod, submittedPeriod: packet.submittedPeriod, coverage: "satisfied", supersedesPacketId: null, supersededByPacketId: null, opened: false, acknowledged: false, reviewed: false }], nextCursor: null }, packet_load: packet,
    audit: { events: [], nextCursor: null }, logout: { authState: "signed_out" }, members: [], retention: { policy: { version: "practice.synthetic.retention/1.0-draft.1", status: "authoritative_synthetic_draft_only", acknowledgedDays: 30, unacknowledgedDays: 90, backupTargetDays: 35, legalApproval: false }, deletion: [] },
  };
  const all = { ...defaults, ...values };
  const invoke = vi.fn(async (operation: OperationName, payload: Record<string, unknown> = {}) => { const value = all[operation]; if (value instanceof Error) throw value; return typeof value === "function" ? (value as (payload: Record<string, unknown>) => unknown)(payload) : value; });
  return { invoke, clear: vi.fn(() => undefined) } as unknown as OperationClient & { invoke: ReturnType<typeof vi.fn>; clear: ReturnType<typeof vi.fn> };
}

async function selectRelationshipAndOpenBuilder(user: ReturnType<typeof userEvent.setup>, api: ReturnType<typeof client>): Promise<void> {
  render(<App initialPath="/portal/relationships" client={api} initialSession={session} />);
  await user.click(screen.getByRole("button", { name: "Search relationships" })); await user.click(await screen.findByRole("button", { name: "Select this relationship" }));
  await user.click(screen.getByRole("link", { name: "Requests" })); await user.click(await screen.findByRole("button", { name: "Start new request" }));
  await screen.findByRole("heading", { name: "Build a synthetic request" });
}

beforeEach(() => { history.replaceState(null, "", "/sign-in"); vi.stubGlobal("requestAnimationFrame", (callback: FrameRequestCallback) => { callback(0); return 1; }); });
afterEach(() => { cleanup(); vi.unstubAllGlobals(); });

describe("review fixes", () => {
  it.each([
    ["/recovery", "Account recovery handoff"], ["/access-denied", "Access denied"], ["/session-expired", "Session expired"], ["/unavailable", "Portal unavailable"],
  ])("renders and axe-checks public state %s", async (path, heading) => {
    const { container } = render(<App initialPath={path} client={client()} />); expect(screen.getByRole("heading", { name: heading })).toBeVisible(); expect((await axe.run(container, { rules: { "color-contrast": { enabled: false } } })).violations).toEqual([]);
  });

  it.each([
    ["/portal/relationships", session, "Find a synthetic relationship"], ["/portal/requests", session, "Clinician request list"], ["/portal/inbox", session, "Packet inbox"], ["/portal/templates", admin, "Request templates"], ["/portal/admin/members", admin, "Practice members"], ["/portal/admin/retention", admin, "Retention and deletion progress"], ["/portal/admin/audit", admin, "Audit events"],
  ] as const)("axe-checks major UI family %s", async (path, roleSession, heading) => {
    const { container } = render(<App initialPath={path} client={client()} initialSession={roleSession} />); await screen.findByRole("heading", { name: heading }); await waitFor(() => expect(container.querySelector('[role="status"]')).toBeTruthy()); expect((await axe.run(container, { rules: { "color-contrast": { enabled: false } } })).violations).toEqual([]);
  });

  it("scrubs initial search and fragment and focuses main after navigation", async () => {
    history.replaceState(null, "", "/portal?relationship=forbidden#secret"); render(<App client={client()} initialSession={session} />);
    expect(location.pathname).toBe("/portal"); expect(location.search).toBe(""); expect(location.hash).toBe(""); expect(screen.getByRole("main")).toHaveFocus();
  });

  it("fails closed immediately on a server-terminal session error without a logout retry or content restoration", async () => {
    const api = client({ inbox: new PracticeClientError("session_expired", 401) }); const user = userEvent.setup(); render(<App initialPath="/portal/inbox" client={api} initialSession={session} />);
    expect(await screen.findByRole("heading", { name: "Session expired" })).toBeVisible(); expect(api.clear).toHaveBeenCalled(); expect(api.invoke).not.toHaveBeenCalledWith("logout"); expect(location.pathname).toBe("/session-expired");
    await user.click(screen.getByLabelText("Health.md Practice synthetic portal home")); expect(screen.getByRole("heading", { name: "Clinician sign in" })).toBeVisible();
    history.back(); window.dispatchEvent(new PopStateEvent("popstate")); expect(screen.queryByRole("heading", { name: "Practice portal overview" })).toBeNull();
  });

  it("direct authenticated session-expired route clears memory and revokes server session before safe home navigation", async () => {
    const api = client(); const user = userEvent.setup(); render(<App initialPath="/session-expired" client={api} initialSession={session} />);
    expect(screen.getByRole("heading", { name: "Session expired" })).toBeVisible();
    await waitFor(() => expect(api.invoke).toHaveBeenCalledWith("logout")); expect(api.clear).toHaveBeenCalled();
    expect(api.invoke.mock.invocationCallOrder[0]).toBeLessThan(api.clear.mock.invocationCallOrder[0]!);
    await user.click(screen.getByLabelText("Health.md Practice synthetic portal home"));
    expect(screen.getByRole("heading", { name: "Clinician sign in" })).toBeVisible(); expect(location.pathname).toBe("/sign-in");
  });

  it("back navigation to session-expired cannot restore protected session or selections", async () => {
    const api = client(); render(<App initialPath="/portal" client={api} initialSession={session} />);
    history.pushState(null, "", "/session-expired"); window.dispatchEvent(new PopStateEvent("popstate"));
    expect(await screen.findByRole("heading", { name: "Session expired" })).toBeVisible(); await waitFor(() => expect(api.invoke).toHaveBeenCalledWith("logout"));
    history.back(); window.dispatchEvent(new PopStateEvent("popstate"));
    await waitFor(() => expect(location.pathname).not.toBe("/portal")); expect(screen.queryByRole("heading", { name: "Practice portal overview" })).toBeNull();
  });

  it("clears and rebootstraps protected state on persisted pageshow", async () => {
    const api = client(); render(<App initialPath="/portal" client={api} initialSession={session} />);
    const event = new Event("pageshow") as PageTransitionEvent; Object.defineProperty(event, "persisted", { value: true }); window.dispatchEvent(event);
    await waitFor(() => expect(api.invoke).toHaveBeenCalledWith("session_bootstrap")); expect(api.clear).toHaveBeenCalled();
  });

  it.each([["zero", "No matching relationships"], ["inactive", "Inactive relationship"]])("renders relationship %s state", async (state, expected) => {
    const api = client({ relationship_search: { state, results: state === "zero" ? [] : [{ ...relationship, state: "inactive" }] } }); const user = userEvent.setup(); render(<App initialPath="/portal/relationships" client={api} initialSession={session} />); await user.click(screen.getByRole("button", { name: "Search relationships" })); expect(await screen.findByText(expected)).toBeVisible(); expect(api.invoke).not.toHaveBeenCalledWith("relationship_select", expect.anything());
  });

  it("renders generic relationship denial without selecting", async () => {
    const api = client({ relationship_search: new PracticeClientError("operation_unavailable", 404) }); const user = userEvent.setup(); render(<App initialPath="/portal/relationships" client={api} initialSession={session} />); await user.click(screen.getByRole("button", { name: "Search relationships" })); expect(await screen.findByText("Search unavailable")).toBeVisible(); expect(screen.getByText(/Stable code: operation_unavailable/)).toBeVisible(); expect(api.invoke).not.toHaveBeenCalledWith("relationship_select", expect.anything());
  });

  it("creates, revises, archives, validates, and reports template UI errors", async () => {
    const created = template(1); const revised = { ...template(2), previousRevision: 1 }; const archived = { ...revised, state: "archived" as const }; const api = client({ template_create: created, template_revise: revised, template_archive: archived }); const user = userEvent.setup();
    render(<App initialPath="/portal/templates" client={api} initialSession={admin} />); await user.click(screen.getByRole("button", { name: "Create synthetic template" })); expect(await screen.findByRole("heading", { name: "Create template" })).toBeVisible(); await user.click(screen.getByRole("radio", { name: /Relative completed days/ })); await user.click(screen.getByRole("button", { name: "Create active template" })); expect(await screen.findByText(/relative_acceptance_unresolved/)).toBeVisible(); expect(api.invoke).not.toHaveBeenCalledWith("template_create", expect.anything()); cleanup();
    render(<App initialPath="/portal/templates" client={api} initialSession={admin} />); await user.click(await screen.findByRole("button", { name: "Open" })); await user.click(screen.getByRole("link", { name: "Revise template" })); await user.click(screen.getByRole("radio", { name: "not requested" })); await user.click(screen.getByRole("button", { name: "Create immutable revision" })); expect(api.invoke).toHaveBeenCalledWith("template_revise", expect.objectContaining({ templateId: "template_active", expectedRevision: 1, builder: expect.objectContaining({ pulse: "not_requested" }) })); await user.click(await screen.findByRole("button", { name: "Archive revision" })); await user.click(within(screen.getByRole("dialog")).getByRole("button", { name: "Archive" })); await waitFor(() => expect(api.invoke).toHaveBeenCalledWith("template_archive", { templateId: "template_active", expectedRevision: 2 })); cleanup();
    const failed = client({ template_list: new PracticeClientError("operation_failed", 503) }); render(<App initialPath="/portal/templates" client={failed} initialSession={admin} />); expect(await screen.findByText("Templates unavailable")).toBeVisible();
  });

  it("blocks drafts without an active template and freezes the current server revision", async () => {
    const user = userEvent.setup(); const blocked = client({ template_list: [] }); await selectRelationshipAndOpenBuilder(user, blocked); expect(screen.getByText("No active request template")).toBeVisible(); expect(screen.getByRole("button", { name: "Validate and preview" })).toBeDisabled(); cleanup();
    const current = client({ template_list: [template(7)], request_preview: preview(7) }); await selectRelationshipAndOpenBuilder(userEvent.setup(), current); await userEvent.setup().click(screen.getByRole("button", { name: "Validate and preview" })); expect(current.invoke).toHaveBeenCalledWith("request_preview", expect.objectContaining({ templateId: "template_active", expectedTemplateRevision: 7 }));
  });

  it("clones exact selected presets and bounds custom-window add/remove controls", async () => {
    const templates = (["pre_visit", "medication_follow_up", "recurring_collection"] as const).map((context, index) => ({
      ...template(), id: `template_${context}`,
      builder: { ...structuredClone(builder), context, period: { kind: "fixed_dates" as const, startLocalDate: `2040-0${index + 1}-01`, endLocalDateExclusive: `2040-0${index + 1}-08`, timezoneRule: "acceptance_time_iana" as const } },
    }));
    for (const selected of templates) {
      const api = client({ template_list: templates, request_preview: (payload: Record<string, unknown>) => createRequestPreview({ relationshipId: relationship.id, templateId: selected.id, templateRevision: 1, builder: payload.builder as RequestBuilder, practiceDisplayName: "Fictional Practice A" }) }); const user = userEvent.setup(); await selectRelationshipAndOpenBuilder(user, api); await user.selectOptions(screen.getByLabelText("Active template revision"), selected.id); expect(screen.getByRole("region", { name: "Exact read-only preset summary" })).toHaveTextContent(selected.builder.period.startLocalDate); await user.click(screen.getByRole("button", { name: "Validate and preview" })); expect(api.invoke).toHaveBeenCalledWith("request_preview", { templateId: selected.id, expectedTemplateRevision: 1, builder: selected.builder }); cleanup();
    }
    const api = client(); const user = userEvent.setup(); await selectRelationshipAndOpenBuilder(user, api); await user.click(screen.getByRole("radio", { name: "Constrained customization" })); await user.selectOptions(screen.getByLabelText("Collection schedule"), "custom_windows"); const add = screen.getByRole("button", { name: "Add custom window" }); for (let index = 1; index < 16; index += 1) await user.click(add); expect(add).toBeDisabled(); expect(screen.getAllByText(/Named window/)).toHaveLength(16); await user.click(screen.getByRole("button", { name: "Remove window 16" })); expect(add).toBeEnabled(); expect(add).toHaveFocus(); expect(screen.getByText("Custom window removed. 15 of 16 windows.")).toBeInTheDocument(); expect(screen.getAllByText(/Named window/)).toHaveLength(15); await user.click(screen.getByRole("button", { name: "Validate and preview" })); expect(api.invoke).not.toHaveBeenCalledWith("request_preview", expect.anything()); expect(await screen.findByText(/dst_materialization_unresolved/)).toBeVisible();
  });

  it("cancels a selected request and starts successors only from an explicit recurring selection", async () => {
    const recurringBuilder = { ...builder, context: "recurring_collection" as const }; const recurringPreview = createRequestPreview({ relationshipId: relationship.id, templateId: "template_active", templateRevision: 1, builder: recurringBuilder, practiceDisplayName: "Fictional Practice A" }); const recurring = { ...request(), representation: recurringPreview.representation, canonicalJson: recurringPreview.canonicalJson, lifecycle: "active" as const }; const canceled = { ...recurring, lifecycle: "canceled" as const };
    const cancelApi = client({ request_list: [recurring], request_cancel: canceled }); const user = userEvent.setup(); render(<App initialPath="/portal/relationships" client={cancelApi} initialSession={session} />); await user.click(screen.getByRole("button", { name: "Search relationships" })); await user.click(await screen.findByRole("button", { name: "Select this relationship" })); await user.click(screen.getByRole("link", { name: "Requests" })); await user.click(await screen.findByRole("button", { name: "Open" })); await user.click(screen.getByRole("button", { name: "Cancel request" })); expect(await screen.findByText("canceled")).toBeVisible(); cleanup();
    const successorApi = client({ request_list: [recurring], request_preview: recurringPreview }); const successorUser = userEvent.setup(); render(<App initialPath="/portal/relationships" client={successorApi} initialSession={session} />); await successorUser.click(screen.getByRole("button", { name: "Search relationships" })); await successorUser.click(await screen.findByRole("button", { name: "Select this relationship" })); await successorUser.click(screen.getByRole("link", { name: "Requests" })); await successorUser.click(await screen.findByRole("button", { name: "Open" })); await successorUser.click(screen.getByRole("button", { name: "Start explicit successor" })); await screen.findByText(/Frozen template intent/); await successorUser.type(screen.getByLabelText("Inclusive start date"), "2040-01-08"); await successorUser.type(screen.getByLabelText("Exclusive end date"), "2040-01-15"); await successorUser.click(screen.getByRole("button", { name: "Validate and preview" })); expect(successorApi.invoke).toHaveBeenCalledWith("request_preview", expect.objectContaining({ builder: expect.objectContaining({ predecessorRequestId: "request_selected", context: "recurring_collection" }) }));
  });

  it("strips a malicious template predecessor from nominal new-request dispatch", async () => {
    const maliciousTemplate = { ...template(), builder: { ...builder, context: "recurring_collection" as const, predecessorRequestId: "request_state_active" } };
    const api = client({
      template_list: [maliciousTemplate],
      request_preview: (payload: Record<string, unknown>) => createRequestPreview({ relationshipId: relationship.id, templateId: maliciousTemplate.id, templateRevision: 1, builder: payload.builder as RequestBuilder, practiceDisplayName: "Fictional Practice A" }),
      request_issue: (payload: Record<string, unknown>) => {
        const issuedPreview = payload.preview as ReturnType<typeof preview>;
        return { request: { ...request(), representation: issuedPreview.representation, canonicalJson: issuedPreview.canonicalJson }, invitation: { requestId: "request_selected", token: "nominal_secret", genericText: "Synthetic claim", displayState: "available_once" } };
      },
      request_renew: new Error("nominal dispatch must not renew"),
    });
    const user = userEvent.setup(); await selectRelationshipAndOpenBuilder(user, api); await user.click(screen.getByRole("button", { name: "Validate and preview" }));
    expect(api.invoke).toHaveBeenCalledWith("request_preview", expect.objectContaining({ builder: expect.not.objectContaining({ predecessorRequestId: expect.anything() }) }));
    await user.click(await screen.findByRole("button", { name: "Issue this exact preview" }));
    expect(api.invoke).toHaveBeenCalledWith("request_issue", expect.objectContaining({ preview: expect.objectContaining({ representation: expect.objectContaining({ builder: expect.not.objectContaining({ predecessorRequestId: expect.anything() }) }) }) }));
    expect(api.invoke).not.toHaveBeenCalledWith("request_renew", expect.anything());
  });

  it("preserves explicit successor intent across inactive-template replacement and builder-mode switches", async () => {
    const recurringBuilder = { ...builder, context: "recurring_collection" as const };
    const oldPreview = createRequestPreview({ relationshipId: relationship.id, templateId: "template_inactive_old", templateRevision: 1, builder: recurringBuilder, practiceDisplayName: "Fictional Practice A" });
    const predecessor = { ...request(), lifecycle: "active" as const, representation: oldPreview.representation, canonicalJson: oldPreview.canonicalJson };
    const replacement = { ...template(), id: "template_active_replacement", builder: recurringBuilder };
    let successorPreview = oldPreview;
    const api = client({
      request_list: [predecessor], template_list: [{ ...template(), id: "template_inactive_old", state: "archived" as const, builder: recurringBuilder }, replacement],
      request_preview: (payload: Record<string, unknown>) => {
        successorPreview = createRequestPreview({ relationshipId: relationship.id, templateId: replacement.id, templateRevision: 1, builder: payload.builder as RequestBuilder, practiceDisplayName: "Fictional Practice A" }); return successorPreview;
      },
      request_renew: { request: { ...predecessor, id: "request_successor", representation: successorPreview.representation, canonicalJson: successorPreview.canonicalJson, predecessorRequestId: predecessor.id }, invitation: { requestId: "request_successor", token: "successor_secret", genericText: "Synthetic successor", displayState: "available_once" } },
    });
    const user = userEvent.setup(); render(<App initialPath="/portal/relationships" client={api} initialSession={session} />);
    await user.click(screen.getByRole("button", { name: "Search relationships" })); await user.click(await screen.findByRole("button", { name: "Select this relationship" })); await user.click(screen.getByRole("link", { name: "Requests" })); await user.click(await screen.findByRole("button", { name: "Open" })); await user.click(screen.getByRole("button", { name: "Start explicit successor" }));
    expect(await screen.findByText(/remains bound to predecessor/)).toHaveTextContent(predecessor.id);
    await user.selectOptions(screen.getByLabelText("Active template revision"), replacement.id); await user.click(screen.getByRole("radio", { name: "Constrained customization" })); await user.click(screen.getByRole("radio", { name: "Use preset unchanged" }));
    expect(screen.getByText(/remains bound to predecessor/)).toHaveTextContent(predecessor.id);
    await user.click(screen.getByRole("button", { name: "Validate and preview" }));
    expect(api.invoke).toHaveBeenCalledWith("request_preview", expect.objectContaining({ templateId: replacement.id, builder: expect.objectContaining({ predecessorRequestId: predecessor.id }) }));
    await user.click(await screen.findByRole("button", { name: "Issue this exact preview" }));
    expect(api.invoke).toHaveBeenCalledWith("request_renew", expect.objectContaining({ predecessorId: predecessor.id, preview: expect.objectContaining({ representation: expect.objectContaining({ builder: expect.objectContaining({ predecessorRequestId: predecessor.id }) }) }) }));
    expect(api.invoke).not.toHaveBeenCalledWith("request_issue", expect.anything());
  });

  it("reuses one unique preview key for an exact retry and never hard-codes it", async () => {
    const keys: string[] = []; let attempts = 0; const api = client({ request_issue: (payload: Record<string, unknown>) => { keys.push(String(payload.idempotencyKey)); attempts += 1; if (attempts === 1) throw new PracticeClientError("operation_failed", 503); return { request: request(), invitation: { requestId: "request_selected", token: "route_secret", genericText: "Synthetic claim", displayState: "available_once" } }; } }); const user = userEvent.setup(); await selectRelationshipAndOpenBuilder(user, api); await user.click(screen.getByRole("button", { name: "Validate and preview" })); await user.click(await screen.findByRole("button", { name: "Issue this exact preview" })); await screen.findByText(/operation_failed/); await user.click(screen.getByRole("button", { name: "Issue this exact preview" })); expect(keys).toHaveLength(2); expect(keys[0]).toBe(keys[1]); expect(keys[0]).toMatch(/^intent-[0-9a-f]{32}$/);
  });

  it.each([
    ["Revoke invitation", "invitation_revoke", "Invitation revoked and secret cleared."], ["Expire invitation", "invitation_expire", "Invitation expired and secret cleared."], ["Cancel request", "request_cancel", "Request canceled; invitation secret cleared."],
  ] as const)("handles invitation action %s with truthful clearing", async (button, operation, expected) => {
    const transitioned = { ...request(), lifecycle: operation === "request_cancel" ? "canceled" as const : request().lifecycle, claim: operation === "invitation_revoke" ? "revoked" as const : operation === "invitation_expire" ? "expired" as const : request().claim };
    const overrides: Partial<Record<OperationName, unknown>> = { request_issue: { request: request(), invitation: { requestId: "request_selected", token: "route_secret", genericText: "Synthetic claim", displayState: "available_once" } }, request_list: [transitioned], [operation]: operation === "request_cancel" ? transitioned : { changed: true } };
    const api = client(overrides); const user = userEvent.setup(); await selectRelationshipAndOpenBuilder(user, api); await user.click(screen.getByRole("button", { name: "Validate and preview" })); await user.click(await screen.findByRole("button", { name: "Issue this exact preview" })); await user.click(await screen.findByRole("button", { name: button })); expect(await screen.findByText(expected)).toBeVisible(); expect(screen.queryByText("route_secret")).toBeNull(); expect(api.invoke).toHaveBeenCalledWith(operation, expect.anything());
  });

  it("destroys the route-only invitation on pagehide and cannot redisplay it", async () => {
    const api = client({ request_issue: { request: request(), invitation: { requestId: "request_selected", token: "route_secret", genericText: "Synthetic claim", displayState: "available_once" } } }); const user = userEvent.setup(); await selectRelationshipAndOpenBuilder(user, api); await user.click(screen.getByRole("button", { name: "Validate and preview" })); await user.click(await screen.findByRole("button", { name: "Issue this exact preview" })); expect(await screen.findByText("route_secret")).toBeVisible(); window.dispatchEvent(new Event("pagehide")); expect(await screen.findByText("One-time invitation selection expired")).toBeVisible(); expect(screen.queryByText("route_secret")).toBeNull();
  });

  it("handles inbox filters, empty, error, and cursor pagination in body memory", async () => {
    const api = client({ inbox: (payload: Record<string, unknown>) => { const filter = payload.filter as { cursor: number; shape?: string }; return { items: filter.cursor === 0 ? [{ id: packet.id, relationshipLabel: packet.relationshipLabel, requestId: packet.requestId, revision: 1, shape: "complete", availability: "available", receivedAt: packet.receivedAt, requestedPeriod: packet.requestedPeriod, submittedPeriod: packet.submittedPeriod, coverage: "satisfied", supersedesPacketId: null, supersededByPacketId: null, opened: false, acknowledged: false, reviewed: false }] : [], nextCursor: filter.cursor === 0 ? 5 : null }; } }); const user = userEvent.setup(); render(<App initialPath="/portal/inbox" client={api} initialSession={session} />); await screen.findByRole("button", { name: "Open report" }); const callsAfterInitialLoad = api.invoke.mock.calls.length; await user.selectOptions(screen.getByLabelText("Document shape"), "complete"); await user.type(screen.getByLabelText("Opaque request code"), "request_code"); await user.type(screen.getByLabelText("Received from UTC date"), "2040-01-09"); await user.type(screen.getByLabelText("Received to exclusive UTC date"), "2040-01-10"); await user.selectOptions(screen.getByLabelText("Acknowledged"), "yes"); await user.selectOptions(screen.getByLabelText("Reviewed"), "no"); await user.selectOptions(screen.getByLabelText("Supersession"), "superseded"); expect(api.invoke).toHaveBeenCalledTimes(callsAfterInitialLoad); await user.click(screen.getByRole("button", { name: "Apply filters" })); await waitFor(() => expect(api.invoke).toHaveBeenCalledTimes(callsAfterInitialLoad + 1)); expect(api.invoke).toHaveBeenLastCalledWith("inbox", { filter: expect.objectContaining({ shape: "complete", requestId: "request_code", receivedFromUtcDate: "2040-01-09", receivedToExclusiveUtcDate: "2040-01-10", acknowledged: true, reviewed: false, supersession: "superseded", cursor: 0 }) }); await user.click(screen.getByRole("button", { name: "Next page" })); expect(await screen.findByText("No matching packets")).toBeVisible(); expect(api.invoke).toHaveBeenCalledWith("inbox", { filter: expect.objectContaining({ cursor: 5 }) }); cleanup();
    render(<App initialPath="/portal/inbox" client={client({ inbox: { items: [], nextCursor: null } })} initialSession={session} />); expect(await screen.findByText("No matching packets")).toBeVisible(); cleanup();
    render(<App initialPath="/portal/inbox" client={client({ inbox: new PracticeClientError("temporary_failure", 503) })} initialSession={session} />); expect(await screen.findByText("Inbox unavailable")).toBeVisible();
  });

  it("axe-checks inbox loading, empty, denied, generic-error, paginated, superseded, and unavailable states", async () => {
    const scenarios = [
      [client({ inbox: () => new Promise(() => undefined) }), "Loading inbox"],
      [client({ inbox: { items: [], nextCursor: null } }), "No matching packets"],
      [client({ inbox: new PracticeClientError("operation_unavailable", 404) }), "Inbox access unavailable"],
      [client({ inbox: new PracticeClientError("temporary_failure", 503) }), "Inbox unavailable"],
    ] as const;
    for (const [api, title] of scenarios) {
      const { container } = render(<App initialPath="/portal/inbox" client={api} initialSession={session} />); expect(await screen.findByText(title)).toBeVisible(); expect((await axe.run(container, { rules: { "color-contrast": { enabled: false } } })).violations).toEqual([]); cleanup();
    }
    const states = ["available", "superseded", "quarantined", "rejected", "revoked", "deleted", "expired", "inaccessible"] as const;
    const items = states.map((availability, index) => ({ id: `packet-${availability}`, relationshipLabel: `Relationship ${index}`, requestId: `request-${index}`, context: "pre_visit" as const, revision: 1, shape: "complete" as const, availability, receivedAt: packet.receivedAt, requestedPeriod: packet.requestedPeriod, submittedPeriod: packet.submittedPeriod, coverage: "satisfied" as const, supersedesPacketId: null, supersededByPacketId: availability === "superseded" ? "newer" : null, opened: false, acknowledged: false, reviewed: false }));
    const { container } = render(<App initialPath="/portal/inbox" client={client({ inbox: { items, nextCursor: 5 } })} initialSession={session} />); const table = await screen.findByRole("region", { name: "Synthetic packet metadata" }); expect(screen.getByRole("button", { name: "Next page" })).toBeEnabled(); expect(within(table).getAllByRole("button", { name: "Open report" })).toHaveLength(2);
    for (const availability of states.slice(2)) { const row = within(table).getByText(availability, { selector: ".status-badge span" }).closest("tr")!; expect(within(row).queryByRole("button")).toBeNull(); expect(row).toHaveTextContent(`${availability} — unavailable, not actionable`); }
    expect((await axe.run(container, { rules: { "color-contrast": { enabled: false } } })).violations).toEqual([]);
  });

  it("renders purged and prompt-revocation retention receipts truthfully in admin rows", async () => {
    const deletion = [
      { packetCode: "artifact_deleted", revision: 1, state: "purged", receivedAt: "2040-01-09T12:00:00Z", unacknowledgedDeleteAt: null, scheduledDeleteAt: null, trigger: "purged", legalHoldReceipt: null },
      { packetCode: "artifact_revoked", revision: 1, state: "scheduled", receivedAt: "2040-01-09T12:00:00Z", unacknowledgedDeleteAt: null, scheduledDeleteAt: "2040-01-09T12:00:00Z", trigger: "revocation", legalHoldReceipt: null },
    ];
    render(<App initialPath="/portal/admin/retention" client={client({ retention: { policy: { version: "practice.synthetic.retention/1.0-draft.1", status: "authoritative_synthetic_draft_only", acknowledgedDays: 30, unacknowledgedDays: 90, backupTargetDays: 35, legalApproval: false }, deletion } })} initialSession={admin} />);
    const table = await screen.findByRole("region", { name: "Synthetic deletion and legal hold progress" });
    const deletedRow = within(table).getByText("artifact_deleted").closest("tr")!; expect(deletedRow).toHaveTextContent("purged"); expect(deletedRow).toHaveTextContent("Not scheduled"); expect(deletedRow).not.toHaveTextContent("2040-04");
    const revokedRow = within(table).getByText("artifact_revoked").closest("tr")!; expect(revokedRow).toHaveTextContent("revocation"); expect(revokedRow).toHaveTextContent("2040-01-09T12:00:00Z"); expect(revokedRow).not.toHaveTextContent("2040-04");
  });

  it("portals a full-App dialog and makes every background body subtree inert and aria-hidden", async () => {
    const api = client(); const user = userEvent.setup(); const nestedHost = document.createElement("div"); const appMount = document.createElement("div"); nestedHost.setAttribute("aria-hidden", "false"); nestedHost.appendChild(appMount); document.body.appendChild(nestedHost);
    render(<App initialPath="/portal/inbox" client={api} initialSession={session} />, { container: appMount });
    await user.click(await screen.findByRole("button", { name: "Open report" })); await user.click(screen.getByRole("button", { name: "Acknowledge receipt" }));
    const dialog = screen.getByRole("dialog"); const portal = dialog.closest("[data-modal-portal]")!; expect(portal.parentElement).toBe(document.body);
    expect(nestedHost).toHaveAttribute("aria-hidden", "true"); expect(nestedHost).toHaveAttribute("inert");
    for (const selector of ["header", "nav", "main", "footer"]) { const subtree = appMount.querySelector(selector); expect(subtree).not.toBeNull(); expect(subtree?.closest("body > *")).toBe(nestedHost); }
    await user.click(within(dialog).getByRole("button", { name: "Keep current state" }));
    expect(nestedHost).toHaveAttribute("aria-hidden", "false"); expect(nestedHost).not.toHaveAttribute("inert"); nestedHost.remove();
  });

  it("paginates audit using body cursor state", async () => {
    const api = client({ audit: (payload: Record<string, unknown>) => ({ events: [], nextCursor: payload.cursor === 0 ? 5 : null }) }); const user = userEvent.setup(); render(<App initialPath="/portal/admin/audit" client={api} initialSession={admin} />); await user.click(await screen.findByRole("button", { name: "Next page" })); expect(api.invoke).toHaveBeenCalledWith("audit", expect.objectContaining({ cursor: 5, pageSize: 5 })); expect(screen.getByText("Page 2")).toBeVisible();
  });

  it("ignores stale audit responses after the filter generation changes", async () => {
    const pending: Array<{ payload: Record<string, unknown>; resolve: (value: unknown) => void }> = [];
    const api = client({ audit: (payload: Record<string, unknown>) => new Promise(resolve => pending.push({ payload, resolve })) }); const user = userEvent.setup();
    render(<App initialPath="/portal/admin/audit" client={api} initialSession={admin} />); await waitFor(() => expect(pending).toHaveLength(1));
    await user.selectOptions(screen.getByLabelText("Category filter"), "request"); await waitFor(() => expect(pending).toHaveLength(2));
    pending[1]!.resolve({ events: [{ sequence: 20, tenantCode: "tenant_a", actorCode: "actor_admin", category: "request", action: "current_filter_result", outcome: "success", at: "2040-01-01T00:00:00Z" }], nextCursor: null });
    expect(await screen.findByText("current_filter_result")).toBeVisible();
    pending[0]!.resolve({ events: [{ sequence: 1, tenantCode: "tenant_a", actorCode: "actor_admin", category: "authentication", action: "stale_result", outcome: "success", at: "2040-01-01T00:00:00Z" }], nextCursor: null });
    await waitFor(() => expect(screen.queryByText("stale_result")).toBeNull()); expect(screen.getByText("current_filter_result")).toBeVisible();
  });

  it("keeps every row visible for a large packet", async () => {
    const readings = Array.from({ length: 80 }, (_, index) => ({ key: `row-${index}`, observedAt: `2040-01-${String(index % 28 + 1).padStart(2, "0")}T08:00:00Z`, systolicMmHg: 110 + index % 10, diastolicMmHg: 70 + index % 8, pulseBeatsPerMinute: null, source: "apple_health" as const, manual: "not_marked_manual" as const, pulseAssociation: "none" as const, windowName: null }));
    const large = { ...packet, readings }; const api = client({ packet_load: large }); const user = userEvent.setup(); render(<App initialPath="/portal/inbox" client={api} initialSession={session} />); await user.click(await screen.findByRole("button", { name: "Open report" })); const region = await screen.findByRole("region", { name: "Complete reading table — 80 of 80 rows visible" }); expect(within(region).getAllByRole("row")).toHaveLength(81);
  });

  it("keeps review, immutable history, print, stale and inaccessible states distinct", async () => {
    const reviewed = { ...packet, reviewed: { type: "reviewed", actorCode: "actor_clinician", at: "2040-01-09T12:00:00Z", revision: 1 }, history: [{ type: "reviewed", actorCode: "actor_clinician", at: "2040-01-09T12:00:00Z", revision: 1 }] } satisfies PacketRecord;
    const api = client({ packet_review: reviewed }); const user = userEvent.setup(); render(<App initialPath="/portal/inbox" client={api} initialSession={session} />); await user.click(await screen.findByRole("button", { name: "Open report" })); await user.click(screen.getByRole("button", { name: "Attest review separately" })); await user.click(within(screen.getByRole("dialog")).getByRole("button", { name: "Attest review" })); expect(await screen.findByText("Separate review attestation recorded.")).toBeVisible(); await user.click(screen.getByRole("link", { name: "View immutable history" })); expect(await screen.findByRole("heading", { name: "Immutable report history" })).toBeVisible(); history.pushState(null, "", "/portal/report/print"); window.dispatchEvent(new PopStateEvent("popstate")); expect(await screen.findByRole("heading", { name: "Blood-pressure document report" })).toBeVisible(); expect(screen.queryByRole("button", { name: "Acknowledge receipt" })).toBeNull(); cleanup();
    const stale = client({ packet_acknowledge: new PracticeClientError("stale_revision", 409) }); render(<App initialPath="/portal/inbox" client={stale} initialSession={session} />); await userEvent.setup().click(await screen.findByRole("button", { name: "Open report" })); await userEvent.setup().click(await screen.findByRole("button", { name: "Acknowledge receipt" })); await userEvent.setup().click(within(screen.getByRole("dialog")).getByRole("button", { name: "Acknowledge receipt" })); expect(await screen.findByText(/stale_revision/)).toBeVisible(); cleanup();
    const inaccessible = client({ packet_load: new PracticeClientError("operation_unavailable", 404) }); render(<App initialPath="/portal/inbox" client={inaccessible} initialSession={session} />); await userEvent.setup().click(await screen.findByRole("button", { name: "Open report" })); expect(await screen.findByText(/No partial clinical content is shown/)).toBeVisible();
  });

  it("renders both authoritative facts returned by an acknowledgment replay", async () => {
    const authoritative = { ...packet,
      acknowledged: { type: "acknowledged", actorCode: "actor_clinician", at: "2040-01-09T12:01:00Z", revision: 1 },
      reviewed: { type: "reviewed", actorCode: "actor_clinician_two", at: "2040-01-09T12:02:00Z", revision: 1 },
      history: [
        { type: "acknowledged", actorCode: "actor_clinician", at: "2040-01-09T12:01:00Z", revision: 1 },
        { type: "reviewed", actorCode: "actor_clinician_two", at: "2040-01-09T12:02:00Z", revision: 1 },
      ],
    } satisfies PacketRecord;
    const api = client({ packet_acknowledge: authoritative }); const user = userEvent.setup(); render(<App initialPath="/portal/inbox" client={api} initialSession={session} />);
    await user.click(await screen.findByRole("button", { name: "Open report" })); await user.click(screen.getByRole("button", { name: "Acknowledge receipt" })); await user.click(within(screen.getByRole("dialog")).getByRole("button", { name: "Acknowledge receipt" }));
    const facts = screen.getByRole("region", { name: "Separate workflow facts" }); expect(facts).toHaveTextContent("actor_clinician"); expect(facts).toHaveTextContent("actor_clinician_two");
  });

  it("reloads authoritative workflow facts after conflict and rotates only the affected action key", async () => {
    const refreshed = { ...packet, revision: 2, acknowledged: { type: "acknowledged", actorCode: "actor_clinician_two", at: "2040-01-09T12:05:00Z", revision: 2 }, history: [{ type: "acknowledged", actorCode: "actor_clinician_two", at: "2040-01-09T12:05:00Z", revision: 2 }] } satisfies PacketRecord;
    let loads = 0; let mutations = 0; const payloads: Record<string, unknown>[] = []; const api = client({ packet_load: () => ++loads === 1 ? packet : refreshed, packet_acknowledge: (payload: Record<string, unknown>) => { payloads.push(payload); if (++mutations === 1) throw new PracticeClientError("idempotency_conflict", 409); return refreshed; } }); const user = userEvent.setup(); render(<App initialPath="/portal/inbox" client={api} initialSession={session} />); await user.click(await screen.findByRole("button", { name: "Open report" })); await user.click(screen.getByRole("button", { name: "Acknowledge receipt" })); await user.click(within(screen.getByRole("dialog")).getByRole("button", { name: "Acknowledge receipt" })); expect(await screen.findByRole("button", { name: "Reload current workflow facts" })).toBeVisible(); const firstKey = payloads[0]?.idempotencyKey; expect(screen.getByRole("button", { name: "Acknowledge receipt" })).toBeDisabled(); expect(screen.getByRole("button", { name: "Attest review separately" })).toBeDisabled(); expect(screen.getByRole("button", { name: "Download canonical JSON" })).toBeDisabled(); await user.click(screen.getByRole("button", { name: "Acknowledge receipt" })); expect(payloads).toHaveLength(1); expect(screen.getByText(/idempotency_conflict/)).toBeVisible(); await user.click(screen.getByRole("button", { name: "Reload current workflow facts" })); expect(await screen.findByText(/Current acknowledged fact was recorded by actor_clinician_two at .*revision 2/)).toBeVisible(); expect(screen.getByText(/Immutable synthetic document · revision 2/)).toBeVisible(); await user.click(screen.getByRole("button", { name: "Acknowledge receipt" })); await user.click(within(screen.getByRole("dialog")).getByRole("button", { name: "Acknowledge receipt" })); expect(payloads[1]).toMatchObject({ expectedRevision: 2 }); expect(payloads[1]?.idempotencyKey).not.toBe(firstKey);
  });

  it("fails closed when bootstrap practice identity is missing or mismatched", async () => {
    for (const bootstrap of [
      { role: "clinician", capabilities, tenantCode: "tenant_a" },
      { role: "clinician", capabilities, tenantCode: "tenant_b", practiceDisplayName: "Fictional Practice A" },
      { role: "clinician", capabilities, tenantCode: "tenant_unknown", practiceDisplayName: "Fictional Practice A" },
    ]) {
      const api = client({ session_bootstrap: bootstrap }); render(<App initialPath="/portal" client={api} />);
      expect(await screen.findByRole("heading", { name: "Clinician sign in" })).toBeVisible(); expect(api.clear).toHaveBeenCalled(); cleanup();
    }
  });

  it("hides report mutations without exact capabilities", async () => {
    const readOnly = { role: "clinician" as const, capabilities: ["packet:read"] as const, tenantCode: "tenant_a", practiceDisplayName: "Fictional Practice A" }; const user = userEvent.setup(); render(<App initialPath="/portal/inbox" client={client()} initialSession={readOnly} />); await user.click(await screen.findByRole("button", { name: "Open report" })); await screen.findByRole("heading", { name: "Blood-pressure document report" }); expect(screen.queryByRole("button", { name: "Download canonical JSON" })).toBeNull(); expect(screen.queryByRole("button", { name: "Acknowledge receipt" })).toBeNull(); expect(screen.queryByRole("button", { name: "Attest review separately" })).toBeNull();
  });
});
