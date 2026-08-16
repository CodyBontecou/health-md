import { describe, expect, it } from "vitest";
import {
  auditCategories, authStates, cadenceTypes, capabilities, careContexts, claimStates, coverageStates,
  deliveryStates, manualDisclosures, membershipStates, mfaStates, operationNames, packetAvailabilityStates,
  packetShapes, platforms, pulseAssociations, pulsePolicies, recoveryStates, relationshipProvenance,
  relationshipSearchStates, requestLifecycleStates, roles, scheduleTypes, sessionStates, submissionStates,
  templateStates, validationErrorCodes, type RequestBuilder,
} from "../src/contracts/clinical";
import { canonicalJson, createRequestPreview, renderCommonInstructions, RequestValidationError, validateRequestBuilder } from "../src/synthetic/request-domain";

function builder(): RequestBuilder {
  return { context: "pre_visit", period: { kind: "fixed_dates", startLocalDate: "2040-01-01", endLocalDateExclusive: "2040-01-08", timezoneRule: "acceptance_time_iana" }, schedule: { type: "all_readings", windows: [] }, cadence: { type: "at_period_end" }, pulse: "preferred" };
}

describe("typed synthetic domain", () => {
  it("exposes lookup and explicit selection without general patient-chart mutation operations", () => {
    expect(operationNames.filter(operation => operation.startsWith("relationship_"))).toEqual(["relationship_search", "relationship_select"]);
    expect(operationNames.some(operation => /patient|chart|diagnosis|message/.test(operation))).toBe(false);
  });

  it("pins every governed enum and keeps role names separate from capabilities", () => {
    expect(roles).toEqual(["practice_admin", "clinician"]);
    expect(capabilities).toHaveLength(10);
    expect(authStates).toEqual(["signed_out", "primary_verified", "mfa_required", "authenticated", "idle_warning", "reauthentication_required", "recovery_handoff", "expired", "revoked", "denied", "identity_unavailable", "authenticated_reduced"]);
    expect(mfaStates).toEqual(["required", "verified", "failed", "expired", "exhausted", "replayed"]);
    expect(recoveryStates).toEqual(["not_requested", "handoff_required"]);
    expect(membershipStates).toEqual(["active", "disabled", "offboarded", "role_changed"]);
    expect(sessionStates).toEqual(["active", "expired", "revoked"]);
    expect(relationshipProvenance).toEqual(["practice_supplied", "patient_confirmed", "unverified"]);
    expect(relationshipSearchStates).toEqual(["zero", "unique", "ambiguous", "inactive", "denied"]);
    expect(careContexts).toEqual(["pre_visit", "medication_follow_up", "recurring_collection"]);
    expect(scheduleTypes).toEqual(["all_readings", "once_daily", "morning_evening", "custom_windows"]);
    expect(cadenceTypes).toEqual(["at_period_end", "daily", "weekly", "every_n_days", "patient_initiated"]);
    expect(pulsePolicies).toEqual(["required", "preferred", "not_requested"]);
    expect(templateStates).toEqual(["draft", "active", "superseded", "archived"]);
    expect(requestLifecycleStates).toEqual(["created", "issued", "claimed", "accepted", "active", "completed", "expired", "canceled", "superseded", "renewed"]);
    expect(deliveryStates).toEqual(["not_attempted", "delivered", "failed"]);
    expect(claimStates).toEqual(["available", "claimed", "accepted", "expired", "revoked"]);
    expect(submissionStates).toEqual(["none", "partial", "complete"]);
    expect(packetShapes).toEqual(["complete", "partial", "empty", "manual_source", "missing_pulse"]);
    expect(packetAvailabilityStates).toEqual(["available", "quarantined", "superseded", "rejected", "revoked", "deleted", "expired", "inaccessible"]);
    expect(platforms).toEqual(["apple_health", "health_connect"]);
    expect(coverageStates).toHaveLength(4);
    expect(manualDisclosures).toHaveLength(4);
    expect(pulseAssociations).toHaveLength(3);
    expect(auditCategories).toHaveLength(10);
    expect(operationNames).toHaveLength(34);
  });

  it.each([
    ["equal fixed dates", (value: RequestBuilder) => { if (value.period.kind === "fixed_dates") value.period.endLocalDateExclusive = value.period.startLocalDate; }, "fixed_period_invalid"],
    ["impossible calendar date", (value: RequestBuilder) => { if (value.period.kind === "fixed_dates") value.period.startLocalDate = "2040-02-31"; }, "fixed_period_invalid"],
    ["relative zero", (value: RequestBuilder) => { value.period = { kind: "relative_completed_days", days: 0, timezoneRule: "acceptance_time_iana" }; }, "relative_days_invalid"],
    ["relative medication", (value: RequestBuilder) => { value.context = "medication_follow_up"; value.period = { kind: "relative_completed_days", days: 3, timezoneRule: "acceptance_time_iana" }; }, "finite_fixed_bounds_required"],
    ["relative recurring", (value: RequestBuilder) => { value.context = "recurring_collection"; value.period = { kind: "relative_completed_days", days: 3, timezoneRule: "acceptance_time_iana" }; }, "finite_fixed_bounds_required"],
    ["every N zero", (value: RequestBuilder) => { value.cadence = { type: "every_n_days", everyNDays: 0 }; }, "every_n_days_invalid"],
    ["HTML", (value: RequestBuilder) => { value.practiceCollectionInstructions = "<b>unsafe</b>"; }, "html_not_allowed"],
    ["Markdown", (value: RequestBuilder) => { value.practiceContactText = "[link](bad)"; }, "markdown_not_allowed"],
    ["Markdown heading", (value: RequestBuilder) => { value.practiceContactText = "# Heading"; }, "markdown_not_allowed"],
    ["Markdown quote", (value: RequestBuilder) => { value.practiceContactText = "> quote"; }, "markdown_not_allowed"],
    ["Markdown unordered list", (value: RequestBuilder) => { value.practiceContactText = "- item"; }, "markdown_not_allowed"],
    ["Markdown ordered list", (value: RequestBuilder) => { value.practiceContactText = "1. item"; }, "markdown_not_allowed"],
    ["Markdown setext heading", (value: RequestBuilder) => { value.practiceContactText = "Heading\n---"; }, "markdown_not_allowed"],
    ["Markdown reference link", (value: RequestBuilder) => { value.practiceContactText = "See [label][ref]"; }, "markdown_not_allowed"],
    ["Markdown reference definition", (value: RequestBuilder) => { value.practiceContactText = "[ref]: destination"; }, "markdown_not_allowed"],
    ["Markdown tilde fence", (value: RequestBuilder) => { value.practiceContactText = "~~~\ntext\n~~~"; }, "markdown_not_allowed"],
    ["Markdown backtick fence", (value: RequestBuilder) => { value.practiceContactText = "```\ntext\n```"; }, "markdown_not_allowed"],
    ["link", (value: RequestBuilder) => { value.practiceContactText = "https://remote.invalid"; }, "link_not_allowed"],
    ["undeclared variable", (value: RequestBuilder) => { value.practiceContactText = "{{other}}"; }, "undeclared_variable"],
  ])("returns a stable blocking code for %s", (_label, mutate, code) => {
    const value = builder(); mutate(value);
    expect(validateRequestBuilder(value).map(issue => issue.code)).toContain(code);
  });

  it("validates cardinality, names, positive counts, overlap, touching, overnight, DST and cadence gaps", () => {
    const once = builder(); once.schedule = { type: "once_daily", windows: [] };
    expect(validateRequestBuilder(once).map(i => i.code)).toContain("window_cardinality_invalid");
    const custom = builder(); custom.schedule = { type: "custom_windows", windows: [
      { name: "Morning", startLocalTime: "08:00", endLocalTime: "10:00", minimumCount: 1 },
      { name: "Morning", startLocalTime: "09:00", endLocalTime: "11:00", minimumCount: 0 },
    ] }; custom.cadence = { type: "weekly" };
    const codes = validateRequestBuilder(custom).map(i => i.code);
    expect(codes).toEqual(expect.arrayContaining(["window_name_invalid", "window_count_invalid", "window_overlap", "dst_materialization_unresolved", "cadence_anchor_unresolved"]));
    const touching = builder(); touching.schedule = { type: "morning_evening", windows: [
      { name: "One", startLocalTime: "08:00", endLocalTime: "10:00", minimumCount: 1 },
      { name: "Two", startLocalTime: "10:00", endLocalTime: "12:00", minimumCount: 1 },
    ] };
    expect(validateRequestBuilder(touching).map(i => i.code)).toContain("touching_window_unresolved");
    const overnight = builder(); overnight.schedule = { type: "once_daily", windows: [{ name: "Night", startLocalTime: "22:00", endLocalTime: "06:00", minimumCount: 1 }] };
    expect(validateRequestBuilder(overnight).map(i => i.code)).toContain("overnight_window_unresolved");
  });

  it("preserves normal plain punctuation while rejecting Markdown forms", () => {
    const value = builder(); value.practiceContactText = "Call the office - weekdays, 8:00 a.m. to 5:00 p.m.";
    expect(validateRequestBuilder(value)).toEqual([]);
  });

  it("blocks unresolved relative preview rather than inventing dates", () => {
    const relative = builder(); relative.period = { kind: "relative_completed_days", days: 3, timezoneRule: "acceptance_time_iana" };
    expect(() => createRequestPreview({ relationshipId: "r", templateId: "t", templateRevision: 1, builder: relative, practiceDisplayName: "Fictional Practice" })).toThrow(RequestValidationError);
  });

  it("renders exact common structure from bounded plain text and canonicalizes deterministically", () => {
    const preview = createRequestPreview({ relationshipId: "r", templateId: "t", templateRevision: 1, builder: builder(), practiceDisplayName: "Fictional Practice" });
    expect(preview.representation.protocolVersion).toBe("1.0-draft.4");
    expect(preview.representation.instructionVersion).toBe("practice-bp-common/1.0-draft.1");
    expect(preview.representation.renderedInstructions).toContain("exchanges a document");
    expect(new TextDecoder().decode(Uint8Array.from(preview.canonicalBytes))).toBe(preview.canonicalJson);
    expect(canonicalJson({ z: 1, a: 2 })).toBe('{"a":2,"z":1}');
    expect(() => renderCommonInstructions({ practice_display_name: "<script>", care_context_label: "x", collection_period_text: "x", schedule_text: "x", submission_cadence_text: "x", requested_values_text: "x" })).toThrow("html_not_allowed");
    expect(validationErrorCodes).toContain("dst_materialization_unresolved");
  });
});
