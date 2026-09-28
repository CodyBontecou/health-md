import type { DailyRecordInfo, EnvelopeInfo } from "./types";

const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/u;
const TIMESTAMP_PATTERN = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/u;
const CAPTURE_STATUSES = new Set(["complete", "partial", "not_requested", "legacy_unavailable"]);
const SUPPORTED_DAILY_VERSIONS = new Set([4, 5, 6, 7, 8]);

export class EnvelopeValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "EnvelopeValidationError";
  }
}

function object(value: unknown, field: string): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new EnvelopeValidationError(`${field} must be an object`);
  }
  return value as Record<string, unknown>;
}

function integer(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value)) {
    throw new EnvelopeValidationError(`${field} must be an integer`);
  }
  return value;
}

function string(value: unknown, field: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new EnvelopeValidationError(`${field} must be a non-empty string`);
  }
  return value;
}

function array(value: unknown, field: string): unknown[] {
  if (!Array.isArray(value)) throw new EnvelopeValidationError(`${field} must be an array`);
  return value;
}

function canonicalDate(value: unknown, field: string): string {
  const candidate = string(value, field);
  if (!DATE_PATTERN.test(candidate)) throw new EnvelopeValidationError(`${field} must be YYYY-MM-DD`);
  const [yearText, monthText, dayText] = candidate.split("-");
  const year = Number(yearText);
  const month = Number(monthText);
  const day = Number(dayText);
  const parsed = new Date(Date.UTC(year, month - 1, day));
  if (
    parsed.getUTCFullYear() !== year ||
    parsed.getUTCMonth() + 1 !== month ||
    parsed.getUTCDate() !== day
  ) {
    throw new EnvelopeValidationError(`${field} is not a calendar date`);
  }
  return candidate;
}

function canonicalTimestamp(value: unknown, field: string): string {
  const candidate = string(value, field);
  const milliseconds = Date.parse(candidate);
  if (!TIMESTAMP_PATTERN.test(candidate) || !Number.isFinite(milliseconds)) {
    throw new EnvelopeValidationError(`${field} must be an ISO timestamp`);
  }
  return new Date(milliseconds).toISOString();
}

export function parseAndValidateEnvelope(bytes: Uint8Array): EnvelopeInfo {
  let parsed: unknown;
  try {
    parsed = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    throw new EnvelopeValidationError("Request body must be valid UTF-8 JSON");
  }
  const root = object(parsed, "body");
  if (root.schema !== "healthmd.api_export") {
    throw new EnvelopeValidationError("Unsupported envelope schema");
  }
  const envelopeSchemaVersion = integer(root.schema_version, "schema_version");
  if (envelopeSchemaVersion !== 1 && envelopeSchemaVersion !== 2) {
    throw new EnvelopeValidationError("Unsupported envelope schema version");
  }
  if (root.daily_record_schema !== "healthmd.health_data") {
    throw new EnvelopeValidationError("Unsupported daily record schema");
  }
  const dailyRecordSchemaVersion = integer(
    root.daily_record_schema_version,
    "daily_record_schema_version",
  );
  if (!SUPPORTED_DAILY_VERSIONS.has(dailyRecordSchemaVersion)) {
    throw new EnvelopeValidationError("Unsupported daily record schema version");
  }
  const source = string(root.source, "source");
  if (source !== "ios" && source !== "android") {
    throw new EnvelopeValidationError("Unsupported export source");
  }
  const exportedAt = canonicalTimestamp(root.exported_at, "exported_at");
  const dateRange = object(root.date_range, "date_range");
  const dateStart = canonicalDate(dateRange.start, "date_range.start");
  const dateEnd = canonicalDate(dateRange.end, "date_range.end");
  if (dateStart > dateEnd) throw new EnvelopeValidationError("date_range is reversed");

  const records = array(root.records, "records");
  const recordCount = integer(root.record_count, "record_count");
  if (records.length !== recordCount) throw new EnvelopeValidationError("record_count does not match records");
  if (recordCount > 7) throw new EnvelopeValidationError("An API export batch may contain at most 7 records");

  const dates = new Set<string>();
  const dailyRecords: DailyRecordInfo[] = records.map((value, index) => {
    const record = object(value, `records[${index}]`);
    if (record.schema !== "healthmd.health_data") {
      throw new EnvelopeValidationError(`records[${index}] has an unsupported schema`);
    }
    const schemaVersion = integer(record.schema_version, `records[${index}].schema_version`);
    if (schemaVersion !== dailyRecordSchemaVersion) {
      throw new EnvelopeValidationError(`records[${index}] schema version does not match the envelope`);
    }
    const date = canonicalDate(record.date, `records[${index}].date`);
    if (date < dateStart || date > dateEnd) {
      throw new EnvelopeValidationError(`records[${index}].date is outside date_range`);
    }
    if (dates.has(date)) throw new EnvelopeValidationError("records contains a duplicate date");
    dates.add(date);
    let captureStatus: string | null = null;
    if (record.healthkit_record_archive !== undefined) {
      const archive = object(record.healthkit_record_archive, `records[${index}].healthkit_record_archive`);
      if (archive.schema !== "healthmd.healthkit_records" || archive.schema_version !== 1) {
        throw new EnvelopeValidationError(`records[${index}] has an unsupported HealthKit archive schema`);
      }
    }
    if (record.raw_capture_status !== undefined) {
      const status = string(record.raw_capture_status, `records[${index}].raw_capture_status`);
      if (!CAPTURE_STATUSES.has(status)) {
        throw new EnvelopeValidationError(`records[${index}] has an unsupported raw_capture_status`);
      }
      captureStatus = status;
    }
    return { date, index, schemaVersion, captureStatus };
  });

  const failures = array(root.failed_date_details, "failed_date_details");
  if (records.length + failures.length > 7) {
    throw new EnvelopeValidationError("An API export batch may contain at most 7 dates");
  }
  failures.forEach((value, index) => {
    const failure = object(value, `failed_date_details[${index}]`);
    canonicalTimestamp(failure.date, `failed_date_details[${index}].date`);
    string(failure.reason, `failed_date_details[${index}].reason`);
  });
  if (records.length + failures.length === 0) {
    throw new EnvelopeValidationError("Envelope contains no retained or failed dates");
  }

  let externalRecordCount = 0;
  if (envelopeSchemaVersion === 2) {
    if (root.external_record_schema !== "healthmd.external_provider_daily") {
      throw new EnvelopeValidationError("Unsupported external record schema");
    }
    if (integer(root.external_record_schema_version, "external_record_schema_version") !== 1) {
      throw new EnvelopeValidationError("Unsupported external record schema version");
    }
    const externalRecords = array(root.external_records, "external_records");
    externalRecordCount = integer(root.external_record_count, "external_record_count");
    if (externalRecords.length !== externalRecordCount) {
      throw new EnvelopeValidationError("external_record_count does not match external_records");
    }
    externalRecords.forEach((value, index) => {
      const sidecar = object(value, `external_records[${index}]`);
      if (sidecar.schema !== "healthmd.external_provider_daily" || sidecar.schema_version !== 1) {
        throw new EnvelopeValidationError(`external_records[${index}] has an unsupported schema`);
      }
      const date = canonicalDate(sidecar.date, `external_records[${index}].date`);
      if (date < dateStart || date > dateEnd) {
        throw new EnvelopeValidationError(`external_records[${index}].date is outside date_range`);
      }
    });
  }

  return {
    envelopeSchemaVersion,
    dailyRecordSchemaVersion,
    source,
    exportedAt,
    dateStart,
    dateEnd,
    recordCount,
    failureCount: failures.length,
    externalRecordCount,
    dailyRecords,
  };
}
