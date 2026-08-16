// @vitest-environment jsdom
import { cleanup, render, screen, waitFor } from "@testing-library/react";
import "@testing-library/jest-dom/vitest";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import authorizationPolicy from "../src/contracts/authorization-policy.json";
import type { Capability, OperationName, Role } from "../src/contracts/clinical";
import { App } from "../src/web/App";
import type { OperationClient } from "../src/web/api-client";

const capabilities = authorizationPolicy.roleCapabilities as Record<Role, Capability[]>;
const publicHeadings: Record<string, string> = {
  "/": "Clinician sign in", "/sign-in": "Clinician sign in", "/verify": "Verify identity", "/recovery": "Account recovery handoff",
  "/signed-out": "Signed out", "/access-denied": "Access denied", "/session-expired": "Session expired", "/unavailable": "Portal unavailable",
};
function failingClient(): OperationClient {
  return { clear: vi.fn(), invoke: vi.fn(async (_operation: OperationName) => { throw new Error("no synthetic session"); }) };
}
function inertClient(): OperationClient {
  return { clear: vi.fn(), invoke: vi.fn(async (operation: OperationName) => {
    if (operation === "template_list" || operation === "request_list" || operation === "members") return [];
    if (operation === "inbox") return { items: [], nextCursor: null };
    if (operation === "audit") return { events: [], nextCursor: null };
    if (operation === "retention") return { policy: { version: "practice.synthetic.retention/1.0-draft.1", status: "authoritative_synthetic_draft_only", acknowledgedDays: 30, unacknowledgedDays: 90, backupTargetDays: 35, legalApproval: false }, deletion: [] };
    return {};
  }) };
}
const protectedHeadings: Record<string, string> = {
  "/portal": "Practice portal overview", "/portal/relationships": "Find a synthetic relationship", "/portal/relationship": "Relationship selection expired",
  "/portal/templates": "Request templates", "/portal/template": "Template selection expired", "/portal/template/edit": "Create template",
  "/portal/requests": "Clinician request list", "/portal/request": "Request selection expired", "/portal/request/build": "Build a synthetic request",
  "/portal/request/preview": "Request preview selection expired", "/portal/invitation": "One-time invitation selection expired", "/portal/inbox": "Packet inbox",
  "/portal/report": "Report selection expired", "/portal/report/history": "Report selection expired", "/portal/report/print": "Report selection expired",
  "/portal/admin/members": "Practice members", "/portal/admin/retention": "Retention and deletion progress", "/portal/admin/audit": "Audit events",
};

beforeEach(() => { history.replaceState(null, "", "/sign-in"); vi.stubGlobal("requestAnimationFrame", (callback: FrameRequestCallback) => { callback(0); return 1; }); });
afterEach(() => { cleanup(); vi.unstubAllGlobals(); });

describe("canonical route authorization evidence", () => {
  it.each(authorizationPolicy.routes.filter(route => route.requiredCapability === "public"))("public route matrix: $route renders directly without a session", ({ route }) => {
    render(<App initialPath={route} client={failingClient()} />);
    expect(screen.getByRole("heading", { name: publicHeadings[route]! })).toBeVisible();
  });

  it.each(authorizationPolicy.routes.filter(route => route.noSessionTest))("protected route matrix: $route denies no session and returns to sign in", async ({ route }) => {
    render(<App initialPath={route} client={failingClient()} />);
    await waitFor(() => expect(location.pathname).toBe("/sign-in"));
    expect(screen.getByRole("heading", { name: "Clinician sign in" })).toBeVisible();
  });

  it.each(authorizationPolicy.routes.filter(route => route.wrongRoleTest))("protected route matrix: $route denies opposite role even with forged capabilities", ({ route, authorizedRoles }) => {
    const allowed = authorizedRoles[0] as Role; const opposite: Role = allowed === "clinician" ? "practice_admin" : "clinician";
    const forgedCapabilities = [...capabilities.practice_admin, ...capabilities.clinician];
    render(<App initialPath={route} client={inertClient()} initialSession={{ role: opposite, capabilities: forgedCapabilities, tenantCode: "tenant_a", practiceDisplayName: "Fictional Practice A" }} />);
    expect(screen.getByText("Capability unavailable")).toBeVisible();
  });

  it.each(authorizationPolicy.routes.filter(route => route.requiredCapability !== "public").flatMap(route => route.authorizedRoles.map(role => ({ ...route, declaredRole: role }))))("protected route positive matrix: $route renders for declared $declaredRole role", async ({ route, declaredRole }) => {
    render(<App initialPath={route} client={inertClient()} initialSession={{ role: declaredRole as Role, capabilities: capabilities[declaredRole as Role], tenantCode: "tenant_a", practiceDisplayName: "Fictional Practice A" }} />);
    expect(await screen.findByRole("heading", { name: protectedHeadings[route]! })).toBeVisible(); expect(screen.queryByText("Capability unavailable")).toBeNull();
  });
});
