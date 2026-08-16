// @vitest-environment jsdom
import { cleanup, render, screen } from "@testing-library/react";
import "@testing-library/jest-dom/vitest";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { OperationName, PacketRecord, RequestBuilder, RequestRecord, RequestTemplateRevision } from "../src/contracts/clinical";
import { createAcceptanceReview, createRequestPreview } from "../src/synthetic/request-domain";
import { App } from "../src/web/App";
import type { OperationClient } from "../src/web/api-client";

const session = { role: "clinician" as const, capabilities: ["relationship:search", "request:write", "packet:read", "packet:download", "packet:acknowledge", "packet:review"] as const, tenantCode: "tenant_a", practiceDisplayName: "Fictional Practice A" };
const packet: PacketRecord = {
  id: "packet_timezone", tenantId: "tenant_a", requestId: "request_timezone", relationshipLabel: "Timezone Fiction", revision: 1, shape: "complete", availability: "available", receivedAt: "2040-01-09T12:00:00Z", requestedPeriod: "2040-01-01/2040-01-08", submittedPeriod: "2040-01-01/2040-01-08", timezone: "America/Los_Angeles", coverage: "satisfied",
  readings: [
    { key: "one", observedAt: "2040-01-02T01:00:00Z", systolicMmHg: 118, diastolicMmHg: 76, pulseBeatsPerMinute: 68, source: "apple_health", manual: "not_marked_manual", pulseAssociation: "patient_confirmed_same_source_nearby", windowName: null },
    { key: "two", observedAt: "2040-01-02T18:00:00Z", systolicMmHg: 120, diastolicMmHg: 77, pulseBeatsPerMinute: 69, source: "apple_health", manual: "not_marked_manual", pulseAssociation: "patient_confirmed_same_source_nearby", windowName: null },
  ],
  disclosures: ["Synthetic timezone fixture"], limitations: "Synthetic only.", supersedesPacketId: null, supersededByPacketId: null, opened: null, acknowledged: null, reviewed: null, history: [],
};
function client(): OperationClient {
  return {
    clear: vi.fn(),
    invoke: vi.fn(async (operation: OperationName) => {
      if (operation === "inbox") return { items: [{ id: packet.id, relationshipLabel: packet.relationshipLabel, requestId: packet.requestId, context: "pre_visit", revision: 1, shape: "complete", availability: "available", receivedAt: packet.receivedAt, requestedPeriod: packet.requestedPeriod, submittedPeriod: packet.submittedPeriod, coverage: "satisfied", supersedesPacketId: null, supersededByPacketId: null, opened: false, acknowledged: false, reviewed: false }], nextCursor: null };
      if (operation === "packet_load") return packet;
      throw new Error(`unexpected operation ${operation}`);
    }),
  };
}
const requestBuilder: RequestBuilder = { context: "pre_visit", period: { kind: "fixed_dates", startLocalDate: "2040-01-01", endLocalDateExclusive: "2040-01-08", timezoneRule: "acceptance_time_iana" }, schedule: { type: "all_readings", windows: [] }, cadence: { type: "at_period_end" }, pulse: "preferred" };
const requestPreview = createRequestPreview({ relationshipId: "relationship_unique_a", templateId: "template_default_a", templateRevision: 1, builder: requestBuilder, practiceDisplayName: "Fictional Practice A" });
const requestRecord: RequestRecord = { id: "request_acceptance_ui", tenantId: "tenant_a", relationshipId: "relationship_unique_a", revision: 1, lifecycle: "issued", delivery: "not_attempted", claim: "available", submission: "none", representation: requestPreview.representation, canonicalJson: requestPreview.canonicalJson, predecessorRequestId: null, successorRequestId: null, acceptance: null, history: [] };
const acceptanceReview = createAcceptanceReview({ representation: requestPreview.representation, requestRepresentationSha256: "3".repeat(64), practiceDisplayName: "Fictional Practice A", deviceIanaTimezone: "America/New_York" });
function acceptanceClient() {
  const template: RequestTemplateRevision = { id: "template_default_a", tenantId: "tenant_a", revision: 1, state: "active", builder: requestBuilder, authorCode: "actor_admin", modifiedAt: "2040-01-01T00:00:00Z", previousRevision: null };
  const invoke = vi.fn(async (operation: OperationName) => {
    if (operation === "relationship_search") return { state: "unique", results: [{ id: "relationship_unique_a", label: "Avery Fiction — synthetic", state: "active", nameProvenance: "patient_confirmed", dobProvenance: "patient_confirmed", practiceReferenceProvenance: "practice_supplied" }] };
    if (operation === "relationship_select") return { selected: true };
    if (operation === "request_list") return [requestRecord];
    if (operation === "template_list") return [template];
    if (operation === "request_preview") return requestPreview;
    if (operation === "request_issue") return { request: requestRecord, invitation: { requestId: requestRecord.id, token: "invitation_acceptance_ui", genericText: "A synthetic document request is available.", displayState: "available_once" } };
    if (operation === "invitation_claim") return { requestId: requestRecord.id, claimantReceipt: "claimant_acceptance_ui", expiresAt: "2040-01-01T00:05:00Z", review: acceptanceReview, reviewSha256: "4".repeat(64) };
    if (operation === "invitation_accept") return { requestId: requestRecord.id, claim: "accepted" };
    throw new Error(`unexpected operation ${operation}`);
  });
  return { clear: vi.fn(), invoke } as OperationClient & { invoke: typeof invoke };
}
afterEach(() => cleanup());

describe("fixed request timezone report rendering", () => {
  it("renders table and chart alternatives in the packet timezone instead of the source offset", async () => {
    const user = userEvent.setup(); const { container } = render(<App initialPath="/portal/inbox" client={client()} initialSession={session} />);
    await user.click(await screen.findByRole("button", { name: "Open report" }));
    expect(await screen.findByText("2040-01-01 17:00:00 America/Los_Angeles")).toBeVisible();
    expect(screen.getByText("2040-01-02 10:00:00 America/Los_Angeles")).toBeVisible();
    expect(container.querySelector("#trend-description")).toHaveTextContent("Text alternative in America/Los_Angeles");
    expect(container.querySelector("#trend-description")).not.toHaveTextContent("2040-01-02T01:00:00Z");
  });
});

describe("exact acceptance review UI", () => {
  it("shows the server-materialized instructions and binds acceptance to their digest", async () => {
    const api = acceptanceClient(); const user = userEvent.setup(); render(<App initialPath="/portal/relationships" client={api} initialSession={session} />);
    await user.click(screen.getByRole("button", { name: "Search relationships" })); await user.click(await screen.findByRole("button", { name: "Select this relationship" }));
    await user.click(screen.getByRole("link", { name: "Requests" })); await user.click(await screen.findByRole("button", { name: "Start new request" }));
    await user.click(screen.getByRole("button", { name: "Validate and preview" })); await user.click(await screen.findByRole("button", { name: "Issue this exact preview" }));
    await user.click(screen.getByRole("button", { name: "Synthetic claim" }));
    expect(await screen.findByRole("heading", { name: "Exact instructions to review before acceptance" })).toBeVisible();
    expect(screen.getByRole("table", { name: "Acceptance-time materialization" })).toHaveTextContent("America/New_York");
    expect(screen.getByText(/2040-01-01 through before 2040-01-08 in America\/New_York/)).toBeVisible();
    await user.click(screen.getByRole("button", { name: "Accept these exact instructions" }));
    expect(api.invoke).toHaveBeenCalledWith("invitation_accept", { claimantReceipt: "claimant_acceptance_ui", reviewedAcceptanceSha256: "4".repeat(64) });
  });
});
