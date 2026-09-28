import { describe, expect, it } from "vitest";
import { parseAndValidateEnvelope } from "../src/envelope";

const encode = (data: unknown) => new TextEncoder().encode(JSON.stringify(data));

function envelope() {
  return {
    schema: "healthmd.api_export",
    schema_version: 1,
    daily_record_schema: "healthmd.health_data",
    daily_record_schema_version: 8,
    exported_at: "2026-08-01T12:00:00.000Z",
    source: "ios",
    date_range: { start: "2026-07-31", end: "2026-07-31" },
    record_count: 1,
    records: [{
      schema: "healthmd.health_data",
      schema_version: 8,
      date: "2026-07-31",
      raw_capture_status: "partial",
      healthkit_record_archive: { schema: "healthmd.healthkit_records", schema_version: 1 },
    }],
    failed_date_details: [],
  };
}

describe("API Endpoint compatibility boundary", () => {
  it("accepts an Apple v8 day without modifying the original envelope", () => {
    const payload = envelope();
    const info = parseAndValidateEnvelope(encode(payload));
    expect(info).toMatchObject({
      envelopeSchemaVersion: 1,
      dailyRecordSchemaVersion: 8,
      source: "ios",
      recordCount: 1,
      dailyRecords: [{ date: "2026-07-31", index: 0, captureStatus: "partial" }],
    });
    expect(payload.records[0]!.healthkit_record_archive.schema).toBe("healthmd.healthkit_records");
  });

  it("accepts an Android v4 day and an Apple v2 provider sidecar", () => {
    const android = envelope();
    android.source = "android";
    android.daily_record_schema_version = 4;
    android.records[0]!.schema_version = 4;
    expect(parseAndValidateEnvelope(encode(android)).dailyRecordSchemaVersion).toBe(4);

    const v2 = {
      ...envelope(),
      schema_version: 2,
      external_record_schema: "healthmd.external_provider_daily",
      external_record_schema_version: 1,
      external_record_count: 1,
      external_records: [{ schema: "healthmd.external_provider_daily", schema_version: 1, date: "2026-07-31" }],
    };
    expect(parseAndValidateEnvelope(encode(v2)).externalRecordCount).toBe(1);
  });

  it("accepts a failure-only batch without fabricating a daily snapshot", () => {
    const failureOnly = {
      ...envelope(), record_count: 0, records: [],
      failed_date_details: [{ date: "2026-07-31T00:00:00Z", reason: "no_health_data" }],
    };
    expect(parseAndValidateEnvelope(encode(failureOnly)).dailyRecords).toEqual([]);
  });

  it.each([
    ["unsupported envelope", { ...envelope(), schema_version: 3 }],
    ["version mismatch", { ...envelope(), daily_record_schema_version: 7 }],
    ["count mismatch", { ...envelope(), record_count: 2 }],
    ["duplicate date", { ...envelope(), record_count: 2, records: [envelope().records[0], envelope().records[0]] }],
    ["invalid date", { ...envelope(), records: [{ ...envelope().records[0], date: "2026-02-30" }] }],
    ["out of range", { ...envelope(), records: [{ ...envelope().records[0], date: "2026-07-30" }] }],
    ["missing data", { ...envelope(), record_count: 0, records: [] }],
    ["unknown status", { ...envelope(), records: [{ ...envelope().records[0], raw_capture_status: "complete-ish" }] }],
    ["wrong source", { ...envelope(), source: "server" }],
    ["nontimestamp", { ...envelope(), exported_at: "2026-08-01" }],
    ["malformed failure", { ...envelope(), failed_date_details: [{}] }],
    ["reversed range", { ...envelope(), date_range: { start: "2026-08-01", end: "2026-07-31" } }],
  ])("rejects %s", (_name, body) => {
    expect(() => parseAndValidateEnvelope(encode(body))).toThrow();
  });

  it("rejects malformed UTF-8 instead of silently replacing bytes", () => {
    expect(() => parseAndValidateEnvelope(new Uint8Array([0xff]))).toThrow();
  });
});
