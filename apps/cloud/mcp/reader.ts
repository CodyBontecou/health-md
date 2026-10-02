import { DatabaseSync } from "node:sqlite";
import { lstatSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { decryptExport, parseExportKeyring, sha256Hex } from "../src/crypto";
import registry from "../../../packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json" with { type: "json" };

export class ReaderError extends Error {
  constructor(readonly code: string, message: string) { super(message); }
}

export interface ReadPrincipal { readonly userId: string; readonly tokenId: string; readonly scope: "aggregates" | "full_export" }
export interface MetricValue {
  metric: string;
  date: string;
  // Daily summaries have no measurement instant: never invent one from the
  // envelope upload timestamp, UTC midnight or a carried-forward source.
  timestamp: null;
  calendarTimezone: string;
  value: number;
  unit: string;
  kind: "daily_aggregate";
}
export interface MetricInfo {
  metric: string;
  displayName: string;
  category: string;
  unit: string;
  earliestDate: string;
  latestDate: string;
  kind: "daily_aggregate";
}
export interface DailySummary { date: string; calendarTimezone: string; metrics: MetricValue[] }
export interface HealthDataReader {
  listMetrics(principal: ReadPrincipal): Promise<MetricInfo[]>;
  getLatest(principal: ReadPrincipal, metric: string): Promise<MetricValue>;
  getRange(principal: ReadPrincipal, metric: string, start: string, end: string): Promise<MetricValue[]>;
  getDailySummary(principal: ReadPrincipal, date: string): Promise<DailySummary>;
  getWeeklySummary(principal: ReadPrincipal, start: string): Promise<{
    start: string; end: string; days: DailySummary[]; missingDates: string[];
  }>;
  search(principal: ReadPrincipal, query: string, start: string, end: string): Promise<{
    query: string; matches: Array<{ metric: MetricInfo; values: MetricValue[] }>;
  }>;
  listExports(principal: ReadPrincipal, cursor: string, limit: number): Promise<Record<string, unknown>>;
  findExportForDate(principal: ReadPrincipal, date: string): Promise<Record<string, unknown>>;
  readExportNode(principal: ReadPrincipal, exportId: string, pointer: string, offset: number,
    limit: number): Promise<Record<string, unknown>>;
  readExportBytes(principal: ReadPrincipal, exportId: string, offset: number): Promise<Record<string, unknown>>;
}

type ScalarPath = readonly [string, string];
interface Binding { id: string; path: ScalarPath; outputKey: string; divisor?: number }
// Only verified Apple-v8 summary projections are exposed. Source archive,
// provider text, metadata, UUIDs and time-series arrays are never returned.
// These IDs, labels, units and categories come from the shared metric registry;
// paths alone are adapter-specific. Android v4 is not falsely projected into
// Apple-v8 metrics before its distinct mappings receive contract review.
const BINDINGS: readonly Binding[] = [
  { id: "steps", path: ["activity", "steps"], outputKey: "steps" },
  { id: "active_energy", path: ["activity", "activeCalories"], outputKey: "active_calories" },
  { id: "heart_rate_avg", path: ["heart", "averageHeartRate"], outputKey: "average_heart_rate" },
  { id: "heart_rate_min", path: ["heart", "heartRateMin"], outputKey: "heart_rate_min" },
  { id: "heart_rate_max", path: ["heart", "heartRateMax"], outputKey: "heart_rate_max" },
  { id: "resting_heart_rate", path: ["heart", "restingHeartRate"], outputKey: "resting_heart_rate" },
  { id: "hrv", path: ["heart", "hrv"], outputKey: "hrv_ms" },
  { id: "sleep_total", path: ["sleep", "totalDuration"], outputKey: "sleep_total_hours", divisor: 3600 },
  { id: "sleep_deep", path: ["sleep", "deepSleep"], outputKey: "sleep_deep_hours", divisor: 3600 },
  { id: "sleep_rem", path: ["sleep", "remSleep"], outputKey: "sleep_rem_hours", divisor: 3600 },
  { id: "weight", path: ["body", "weight"], outputKey: "weight_kg" },
];
const metricRows = new Map(registry.metrics.map((row) => [row.semantic_id, row]));
const bindings = new Map(BINDINGS.map((binding) => {
  const row = metricRows.get(binding.id);
  if (!row?.apple || row.apple.outputs?.[0]?.key !== binding.outputKey) {
    throw new Error("MCP metric binding no longer matches the shared registry");
  }
  return [binding.id, binding] as const;
}));

interface StoredExport {
  objectKey: string; exportId: string; encryptionKeyId: string; byteCount: number; plaintextSha256: string;
}
interface DayRow extends StoredExport { date: string; recordIndex: number }
interface ExportMetadata extends StoredExport {
  source: string; envelopeSchemaVersion: number; dailyRecordSchemaVersion: number;
  exportedAt: string; receivedAt: string; dateStart: string; dateEnd: string;
  recordCount: number; failureCount: number; externalRecordCount: number;
  retentionRole: "current" | "supplemental" | "unreferenced";
}
interface DailyRecord {
  date?: unknown; schema?: unknown; schema_version?: unknown;
  time_context?: { calendar_timezone?: unknown };
  units?: Record<string, unknown>;
  [key: string]: unknown;
}
const DATE = /^\d{4}-\d{2}-\d{2}$/u;
const OBJECT_KEY = /^v1\/[a-f0-9-]{36}$/u;
const MAX_DAYS = 31;
const MAX_CATALOG_DAYS = 365;
const MAX_OBJECT_BYTES = 25 * 1024 * 1024 + 256;
const MAX_READ_BYTES = 64 * 1024 * 1024;
const EXPORT_ID = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/u;
const PAGE_LIMIT = 20;
const BYTE_PAGE = 8 * 1024;
const POINTER_LIMIT = 512;
const exportFields = `e.id AS exportId, e.object_key AS objectKey, e.encryption_key_id AS encryptionKeyId,
  e.plaintext_sha256 AS plaintextSha256, e.byte_count AS byteCount, e.source AS source,
  e.envelope_schema_version AS envelopeSchemaVersion, e.daily_record_schema_version AS dailyRecordSchemaVersion,
  e.exported_at AS exportedAt, e.received_at AS receivedAt, e.date_start AS dateStart, e.date_end AS dateEnd,
  e.record_count AS recordCount, e.failure_count AS failureCount, e.external_record_count AS externalRecordCount,
  CASE WHEN EXISTS (SELECT 1 FROM supplemental_exports s WHERE s.export_id = e.id)
    THEN 'supplemental' WHEN EXISTS (SELECT 1 FROM daily_records d WHERE d.export_id = e.id)
    THEN 'current' ELSE 'unreferenced' END AS retentionRole`;
function requireFull(principal: ReadPrincipal): void {
  if (principal.scope !== "full_export") throw new ReaderError("forbidden", "Full export scope is required.");
}
function pageNumber(value: number, maximum: number, name: string): number {
  if (!Number.isSafeInteger(value) || value < 0 || value > maximum) {
    throw new ReaderError("invalid_page", `Invalid ${name}; use a non-negative integer at most ${maximum}.`);
  }
  return value;
}
function encodeCursor(row: Pick<ExportMetadata, "receivedAt" | "exportId">): string {
  return Buffer.from(JSON.stringify([row.receivedAt, row.exportId])).toString("base64url");
}
function decodeCursor(cursor: string): [string, string] | null {
  if (cursor === "") return null;
  if (!/^[A-Za-z0-9_-]{1,160}$/u.test(cursor)) throw new ReaderError("invalid_cursor", "Invalid export cursor.");
  try {
    const value: unknown = JSON.parse(Buffer.from(cursor, "base64url").toString("utf8"));
    if (Array.isArray(value) && value.length === 2 &&
        typeof value[0] === "string" && /^\d{4}-\d{2}-\d{2}T[\d:.+-]+Z$/u.test(value[0]) &&
        typeof value[1] === "string" && EXPORT_ID.test(value[1]) && encodeCursor({
          receivedAt: value[0], exportId: value[1],
        }) === cursor) return [value[0], value[1]];
  } catch { /* Invalid external cursor. */ }
  throw new ReaderError("invalid_cursor", "Invalid export cursor.");
}
function publicMetadata(row: ExportMetadata) {
  const { exportId, source, envelopeSchemaVersion, dailyRecordSchemaVersion, exportedAt,
    receivedAt, dateStart, dateEnd, recordCount, failureCount, externalRecordCount, byteCount,
    retentionRole } = row;
  return { exportId, source, envelopeSchemaVersion, dailyRecordSchemaVersion, exportedAt,
    receivedAt, dateStart, dateEnd, recordCount, failureCount, externalRecordCount, byteCount, retentionRole };
}
function pointerParts(pointer: string): string[] {
  if (pointer === "") return [];
  if (pointer.length > POINTER_LIMIT || !pointer.startsWith("/")) {
    throw new ReaderError("invalid_pointer", "Use a JSON Pointer of at most 512 characters, or an empty pointer for the envelope root.");
  }
  const parts = pointer.slice(1).split("/");
  if (parts.length > 40 || parts.some((part) => /~(?![01])/u.test(part))) {
    throw new ReaderError("invalid_pointer", "Invalid JSON Pointer escape or depth.");
  }
  return parts.map((part) => part.replace(/~1/gu, "/").replace(/~0/gu, "~"));
}
function childPointer(pointer: string, key: string): string {
  return `${pointer}/${key.replace(/~/gu, "~0").replace(/\//gu, "~1")}`;
}
function nodeType(value: unknown): string {
  return value === null ? "null" : Array.isArray(value) ? "array" : typeof value;
}
function entry(pointer: string, value: unknown) {
  const type = nodeType(value);
  return { pointer, type, ...(type === "array" ? { length: (value as unknown[]).length } : {}),
    ...(type === "object" ? { length: Object.keys(value as Record<string, unknown>).length } : {}),
    ...(type === "string" ? { lengthBytes: Buffer.byteLength(value as string) } : {}),
    ...(["number", "boolean", "null"].includes(type) &&
        (type !== "number" || !Number.isInteger(value) || Number.isSafeInteger(value)) ? { value } : {}),
    ...(type === "string" && Buffer.byteLength(value as string) <= 256 ? { value } : {}) };
}


export function validDate(input: string): string {
  if (!DATE.test(input)) throw new ReaderError("invalid_date", "Use a real date in YYYY-MM-DD format.");
  const [year, month, day] = input.split("-").map(Number);
  const ms = Date.UTC(year ?? 0, (month ?? 0) - 1, day ?? 0);
  const date = new Date(ms);
  if (!Number.isFinite(ms) || date.toISOString().slice(0, 10) !== input) {
    throw new ReaderError("invalid_date", "Use a real date in YYYY-MM-DD format.");
  }
  return input;
}
function span(start: string, end: string, maximum = MAX_DAYS): number {
  validDate(start);
  validDate(end);
  const count = (Date.parse(`${end}T00:00:00Z`) - Date.parse(`${start}T00:00:00Z`)) / 86400000 + 1;
  if (count < 1) throw new ReaderError("empty_range", "End must not precede start.");
  if (count > maximum) throw new ReaderError("overly_broad", `Request at most ${maximum} calendar days.`);
  return count;
}
function nextDay(date: string, days: number): string {
  return new Date(Date.parse(`${date}T00:00:00Z`) + days * 86400000).toISOString().slice(0, 10);
}
function metricBinding(metric: string): Binding {
  const binding = bindings.get(metric);
  if (!binding) throw new ReaderError("unknown_metric", "Unknown metric. Call health_list_metrics for available IDs; daily heart rate uses heart_rate_avg, not heart_rate.");
  return binding;
}
function asObject(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value) ? value as Record<string, unknown> : null;
}

export class VmHealthDataReader implements HealthDataReader {
  private readonly db: DatabaseSync;
  private readonly objectRoot: string;
  private readonly keys: ReadonlyMap<string, string>;

  constructor(dataDirectory: string, exportKeysJson: string) {
    this.db = new DatabaseSync(join(dataDirectory, "cloud.sqlite"), { readOnly: true });
    this.db.exec("PRAGMA query_only = ON; PRAGMA trusted_schema = OFF;");
    this.objectRoot = join(dataDirectory, "objects");
    this.keys = parseExportKeyring(exportKeysJson);
  }
  close(): void { this.db.close(); }

  // Filter reviewed current profiles before applying catalog/latest limits.
  // Unsupported snapshots remain discoverable through the full-export tools;
  // never fall back to an older Apple revision for an unsupported current day.
  private rows(userId: string, start?: string, end?: string,
    limit = MAX_CATALOG_DAYS + 1, descending = false): DayRow[] {
    const where = start && end ? "AND d.owner_date BETWEEN ? AND ?" : "";
    const sql = `SELECT d.owner_date AS date, d.record_index AS recordIndex,
      e.object_key AS objectKey, e.id AS exportId, e.encryption_key_id AS encryptionKeyId,
      e.byte_count AS byteCount, e.plaintext_sha256 AS plaintextSha256
      FROM daily_records d JOIN exports e ON e.id = d.export_id AND e.user_id = d.user_id
      JOIN users u ON u.id = d.user_id AND u.status = 'active'
      WHERE d.user_id = ? AND e.source = 'ios' AND e.envelope_schema_version IN (1, 2)
        AND e.daily_record_schema_version = 8 AND d.schema_version = 8
        ${where} ORDER BY d.owner_date ${descending ? "DESC" : "ASC"} LIMIT ?`;
    return this.db.prepare(sql).all(userId, ...(start && end ? [start, end] : []), limit) as unknown as DayRow[];
  }

  private async readStored(userId: string, row: StoredExport, budget: { bytes: number }): Promise<Buffer> {
    if (!OBJECT_KEY.test(row.objectKey) || !EXPORT_ID.test(row.exportId) ||
        !Number.isSafeInteger(row.byteCount) || row.byteCount < 1 || row.byteCount > 25 * 1024 * 1024) {
      throw new ReaderError("unavailable_data", "Stored daily record cannot be safely read.");
    }
    const path = join(this.objectRoot, row.objectKey);
    const key = this.keys.get(row.encryptionKeyId);
    if (!key) throw new ReaderError("unavailable_data", "Stored export key is unavailable.");
    try {
      const stat = lstatSync(path);
      if (!stat.isFile() || stat.isSymbolicLink() || stat.size > MAX_OBJECT_BYTES) throw new Error("object");
      budget.bytes += stat.size;
      if (budget.bytes > MAX_READ_BYTES) throw new ReaderError("overly_broad", "Read exceeds 64 MiB; request fewer days or a narrower metric.");
      const plaintext = await decryptExport(readFileSync(path), key, userId, row.exportId);
      if (plaintext.byteLength !== row.byteCount || await sha256Hex(plaintext) !== row.plaintextSha256) {
        throw new Error("integrity");
      }
      return Buffer.from(plaintext);
    } catch (error) {
      if (error instanceof ReaderError) throw error;
      // Never include paths, ciphertext, parser errors or health contents.
      throw new ReaderError("unavailable_data", "Stored daily record cannot be safely read.");
    }
  }

  private async readDay(userId: string, row: DayRow, budget: { bytes: number }): Promise<DailyRecord> {
    if (!Number.isSafeInteger(row.recordIndex) || row.recordIndex < 0) {
      throw new ReaderError("unavailable_data", "Stored daily record cannot be safely read.");
    }
    const bytes = await this.readStored(userId, row, budget);
    try {
      const envelope = asObject(JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)));
      if (envelope?.schema !== "healthmd.api_export" || ![1, 2].includes(Number(envelope.schema_version)) ||
          envelope.source !== "ios" || envelope.daily_record_schema_version !== 8 ||
          !Array.isArray(envelope.records)) throw new Error("unsupported");
      const day = asObject(envelope.records[row.recordIndex]);
      if (day?.schema !== "healthmd.health_data" || day.schema_version !== 8 || day.date !== row.date) {
        throw new Error("wrong record");
      }
      return day as DailyRecord;
    } catch { throw new ReaderError("unavailable_data", "Stored daily record cannot be safely read."); }
  }

  private exportRow(userId: string, exportId: string): ExportMetadata {
    if (!EXPORT_ID.test(exportId)) throw new ReaderError("invalid_export", "Invalid export ID.");
    const row = this.db.prepare(`SELECT ${exportFields} FROM exports e JOIN users u ON u.id = e.user_id
      AND u.status = 'active' WHERE e.user_id = ? AND e.id = ?`).get(userId, exportId) as ExportMetadata | undefined;
    if (!row) throw new ReaderError("unavailable_data", "Export not found for this account.");
    return row;
  }

  private async fullExport(principal: ReadPrincipal, exportId: string): Promise<{ row: ExportMetadata; bytes: Buffer }> {
    const row = this.exportRow(principal.userId, exportId);
    return { row, bytes: await this.readStored(principal.userId, row, { bytes: 0 }) };
  }

  async listExports(principal: ReadPrincipal, cursor: string, limit: number): Promise<Record<string, unknown>> {
    requireFull(principal);
    if (!Number.isSafeInteger(limit) || limit < 1 || limit > PAGE_LIMIT) {
      throw new ReaderError("invalid_page", "Request 1–20 exports per page.");
    }
    const after = decodeCursor(cursor);
    const rows = this.db.prepare(`SELECT ${exportFields} FROM exports e JOIN users u ON u.id = e.user_id
      AND u.status = 'active' WHERE e.user_id = ?
      ${after ? "AND (e.received_at < ? OR (e.received_at = ? AND e.id < ?))" : ""}
      ORDER BY e.received_at DESC, e.id DESC LIMIT ?`)
      .all(principal.userId, ...(after ? [after[0], after[0], after[1]] : []), limit + 1) as unknown as ExportMetadata[];
    const hasMore = rows.length > limit;
    const page = rows.slice(0, limit);
    return { exports: page.map(publicMetadata), nextCursor: hasMore ? encodeCursor(page.at(-1)!) : null,
      note: "All retained envelopes, including separate supplements, superseded revisions and provider sidecars; newest received first. Supplements do not change current daily aggregates. Listing is not a snapshot across concurrent uploads/deletions." };
  }

  async findExportForDate(principal: ReadPrincipal, date: string): Promise<Record<string, unknown>> {
    requireFull(principal);
    validDate(date);
    const row = this.db.prepare(`SELECT d.record_index AS recordIndex, ${exportFields}
      FROM daily_records d JOIN exports e ON e.id = d.export_id AND e.user_id = d.user_id
      JOIN users u ON u.id = d.user_id AND u.status = 'active'
      WHERE d.user_id = ? AND d.owner_date = ?`).get(principal.userId, date) as
      (ExportMetadata & { recordIndex: number }) | undefined;
    if (!row || !Number.isSafeInteger(row.recordIndex) || row.recordIndex < 0 || row.recordIndex >= row.recordCount) {
      throw new ReaderError("unavailable_data", "No current daily export for this date. List retained exports to inspect historical or sidecar-only envelopes.");
    }
    return { ...publicMetadata(row), date, pointer: `/records/${row.recordIndex}`,
      note: "This date's current primary snapshot only. Separate supplements and older revisions remain discoverable via health_list_exports; never treat this as a merged view." };
  }

  async readExportBytes(principal: ReadPrincipal, exportId: string, offset: number): Promise<Record<string, unknown>> {
    requireFull(principal);
    pageNumber(offset, 25 * 1024 * 1024, "byte offset");
    const { row, bytes } = await this.fullExport(principal, exportId);
    if (offset >= bytes.length) throw new ReaderError("invalid_page", "Byte offset must be smaller than the export size.");
    const end = Math.min(offset + BYTE_PAGE, bytes.length);
    return { exportId: row.exportId, encoding: "base64", contentType: "application/json; charset=utf-8",
      totalBytes: bytes.length, offsetBytes: offset, nextOffsetBytes: end < bytes.length ? end : null,
      chunkBase64: Buffer.from(bytes.subarray(offset, end)).toString("base64"),
      note: "Exact original envelope UTF-8 bytes, including full-precision JSON numbers. Decode and concatenate chunks in byte-offset order." };
  }

  async readExportNode(principal: ReadPrincipal, exportId: string, pointer: string,
    offset: number, limit: number): Promise<Record<string, unknown>> {
    requireFull(principal);
    pageNumber(offset, 25 * 1024 * 1024, "page offset");
    if (!Number.isSafeInteger(limit) || limit < 1 || limit > PAGE_LIMIT) {
      throw new ReaderError("invalid_page", "Request 1–20 children per page.");
    }
    const parts = pointerParts(pointer);
    const { row, bytes } = await this.fullExport(principal, exportId);
    let value: unknown;
    try {
      const root: unknown = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
      const envelope = asObject(root);
      if (envelope?.schema !== "healthmd.api_export" || envelope.schema_version !== row.envelopeSchemaVersion ||
          envelope.daily_record_schema_version !== row.dailyRecordSchemaVersion || envelope.source !== row.source ||
          !Array.isArray(envelope.records) || envelope.records.length !== row.recordCount ||
          (envelope.schema_version === 2 && (!Array.isArray(envelope.external_records) ||
            envelope.external_records.length !== row.externalRecordCount))) throw new Error("metadata");
      value = root;
      for (const part of parts) {
        if (Array.isArray(value)) {
          if (!/^(0|[1-9]\d*)$/u.test(part) || !Number.isSafeInteger(Number(part)) || Number(part) >= value.length) {
            throw new ReaderError("invalid_pointer", "No such array element in this export.");
          }
          value = value[Number(part)];
        } else if (asObject(value) && Object.hasOwn(value as object, part)) value = (value as Record<string, unknown>)[part];
        else throw new ReaderError("invalid_pointer", "No such object property in this export.");
      }
    } catch (error) {
      if (error instanceof ReaderError) throw error;
      throw new ReaderError("unavailable_data", "Stored export JSON cannot be safely read.");
    }
    const type = nodeType(value);
    if (type === "object" || type === "array") {
      const keys = type === "array" ? null : Object.keys(value as Record<string, unknown>);
      const totalChildren = keys ? keys.length : (value as unknown[]).length;
      if (offset >= totalChildren && totalChildren > 0) throw new ReaderError("invalid_page", "Page offset is beyond available children.");
      const items = Array.from({ length: Math.min(limit, totalChildren - offset) }, (_, pageIndex) => {
        const index = offset + pageIndex;
        const key = keys ? keys[index]! : String(index);
        const item = keys ? (value as Record<string, unknown>)[key] : (value as unknown[])[index];
        return { key, ...entry(childPointer(pointer, key), item) };
      });
      return { exportId, pointer, type, totalChildren, offset,
        nextOffset: offset + items.length < totalChildren ? offset + items.length : null, items,
        note: "Follow child pointers for nested fields. Values beyond 256 bytes require health_read_export_bytes for byte-exact retrieval." };
    }
    if (type === "string") {
      const utf8 = Buffer.from(value as string, "utf8");
      if (offset >= utf8.length && utf8.length > 0) throw new ReaderError("invalid_page", "Byte offset is beyond this string.");
      const end = Math.min(offset + BYTE_PAGE, utf8.length);
      return { exportId, pointer, type, encoding: "utf8_base64", totalBytes: utf8.length,
        offsetBytes: offset, nextOffsetBytes: end < utf8.length ? end : null,
        chunkBase64: Buffer.from(utf8.subarray(offset, end)).toString("base64"),
        note: "Decode and concatenate UTF-8 bytes in order; this string may contain exact base64-encoded source binary." };
    }
    if (offset !== 0) throw new ReaderError("invalid_page", "Scalar values require offset zero.");
    return { exportId, pointer, type,
      ...(type === "number" && Number.isInteger(value) && !Number.isSafeInteger(value) ? {
        note: "This integer is not safely representable by JavaScript; use health_read_export_bytes for exact JSON digits.",
      } : { value }) };
  }

  private project(day: DailyRecord, binding: Binding): MetricValue | null {
    const section = asObject(day[binding.path[0]]);
    const raw = section?.[binding.path[1]];
    const expectedUnit = metricRows.get(binding.id)?.apple?.outputs?.[0]?.unit;
    const unit = day.units?.[binding.outputKey];
    const timezone = day.time_context?.calendar_timezone;
    if (typeof raw !== "number" || !Number.isFinite(raw) ||
        typeof unit !== "string" || unit !== expectedUnit ||
        typeof timezone !== "string" || !/^[A-Za-z0-9_+\/-]{1,64}$/u.test(timezone) ||
        typeof day.date !== "string") return null;
    return { metric: binding.id, date: day.date, timestamp: null,
      calendarTimezone: timezone, value: raw / (binding.divisor ?? 1),
      unit, kind: "daily_aggregate" };
  }

  private async summaries(principal: ReadPrincipal, start: string, end: string): Promise<DailySummary[]> {
    span(start, end);
    const rows = this.rows(principal.userId, start, end, MAX_DAYS + 1);
    const result: DailySummary[] = [];
    const budget = { bytes: 0 };
    for (const row of rows) {
      const day = await this.readDay(principal.userId, row, budget);
      const metrics = BINDINGS.flatMap((binding) => {
        const value = this.project(day, binding);
        return value ? [value] : [];
      });
      result.push({ date: row.date, calendarTimezone: typeof day.time_context?.calendar_timezone === "string" ?
        day.time_context.calendar_timezone : "unavailable", metrics });
    }
    return result;
  }

  async listMetrics(principal: ReadPrincipal): Promise<MetricInfo[]> {
    // An unlimited-retention account may hold years of exports. Intentionally
    // catalog only the most recent 365 supported snapshots; do not permanently disable
    // discovery when day 366 arrives or pretend the window is all history.
    const rows = this.rows(principal.userId, undefined, undefined, MAX_CATALOG_DAYS, true).reverse();
    const seen = new Map<string, MetricInfo>();
    const budget = { bytes: 0 };
    for (const row of rows) {
      const day = await this.readDay(principal.userId, row, budget);
      for (const binding of BINDINGS) {
        const value = this.project(day, binding);
        if (!value) continue;
        const entry = seen.get(binding.id);
        if (entry) { entry.latestDate = row.date; continue; }
        const registered = metricRows.get(binding.id)!;
        seen.set(binding.id, { metric: binding.id, displayName: registered.apple!.reference_name ?? binding.id,
          category: registered.apple!.category_id ?? "Other", unit: value.unit,
          earliestDate: row.date, latestDate: row.date, kind: "daily_aggregate" });
      }
    }
    return [...seen.values()];
  }

  async getLatest(principal: ReadPrincipal, metric: string): Promise<MetricValue> {
    const binding = metricBinding(metric);
    const rows = this.rows(principal.userId, undefined, undefined, MAX_CATALOG_DAYS + 1, true);
    const budget = { bytes: 0 };
    for (const row of rows.slice(0, MAX_CATALOG_DAYS)) {
      const value = this.project(await this.readDay(principal.userId, row, budget), binding);
      if (value) return value;
    }
    if (rows.length > MAX_CATALOG_DAYS) throw new ReaderError("overly_broad", "No observation in the latest 365 snapshots; query a specific 31-day range.");
    throw new ReaderError("unavailable_data", "No available observation for this metric.");
  }

  async getRange(principal: ReadPrincipal, metric: string, start: string, end: string): Promise<MetricValue[]> {
    const binding = metricBinding(metric);
    const summaries = await this.summaries(principal, start, end);
    const values = summaries.flatMap((day) => day.metrics.filter((value) => value.metric === binding.id));
    if (values.length === 0) throw new ReaderError("empty_range", "No observations in this date range.");
    return values;
  }

  async getDailySummary(principal: ReadPrincipal, date: string): Promise<DailySummary> {
    const [day] = await this.summaries(principal, validDate(date), date);
    if (!day) throw new ReaderError("unavailable_data", "No supported daily summary is available for that date.");
    return day;
  }

  async getWeeklySummary(principal: ReadPrincipal, start: string): Promise<{
    start: string; end: string; days: DailySummary[]; missingDates: string[];
  }> {
    validDate(start);
    const end = nextDay(start, 6);
    const days = await this.summaries(principal, start, end);
    if (days.length === 0) throw new ReaderError("empty_range", "No supported daily summaries are available in this week.");
    const available = new Set(days.map((day) => day.date));
    const missingDates = Array.from({ length: 7 }, (_, index) => nextDay(start, index))
      .filter((date) => !available.has(date));
    return { start, end, days, missingDates };
  }

  async search(principal: ReadPrincipal, query: string, start: string, end: string): Promise<{
    query: string; matches: Array<{ metric: MetricInfo; values: MetricValue[] }>;
  }> {
    span(start, end, 14);
    if (!/^[A-Za-z][A-Za-z0-9 _-]{1,39}$/u.test(query)) {
      throw new ReaderError("invalid_query", "Use 2–40 plain text characters; no regex or paths.");
    }
    const needle = query.toLowerCase().trim();
    const summaries = await this.summaries(principal, start, end);
    const matches: Array<{ metric: MetricInfo; values: MetricValue[] }> = [];
    for (const binding of BINDINGS) {
      const registered = metricRows.get(binding.id)!;
      if (![binding.id, registered.apple!.reference_name, registered.apple!.category_id]
        .some((candidate) => typeof candidate === "string" && candidate.toLowerCase().includes(needle))) continue;
      const values = summaries.flatMap((day) => day.metrics.filter((value) => value.metric === binding.id));
      if (values.length === 0) continue;
      matches.push({ metric: { metric: binding.id, displayName: registered.apple!.reference_name ?? binding.id,
        category: registered.apple!.category_id ?? "Other", unit: values[0]!.unit,
        earliestDate: values[0]!.date, latestDate: values.at(-1)!.date,
        kind: "daily_aggregate" }, values });
    }
    return { query, matches };
  }
}
