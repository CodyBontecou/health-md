import { assertSameOrigin, HttpError, json, readJson } from "./http";
import { object, readVerifiedEnvelope, validDate, type EnvelopeRow } from "./dashboard";
import type { Env } from "./types";

const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/u;
const PAGE_SIZE = 20;
const POINTER_LIMIT = 512;
interface InventoryRequest {
  source?: unknown; version?: unknown; scope?: unknown;
  start?: unknown; end?: unknown; offset?: unknown;
}
interface NodeRequest { exportId?: unknown; pointer?: unknown; offset?: unknown }
interface ExportRecord extends EnvelopeRow {
  id: string; exportedAt: string; receivedAt: string; dateStart: string; dateEnd: string;
  failureCount: number; externalRecordCount: number;
}
const fields = `e.id AS id, e.id AS exportId, e.source AS source,
  e.envelope_schema_version AS envelopeVersion, e.daily_record_schema_version AS dailyVersion,
  e.object_key AS objectKey, e.encryption_key_id AS keyId, e.plaintext_sha256 AS digest,
  e.byte_count AS byteCount, e.record_count AS recordCount, e.failure_count AS failureCount,
  e.external_record_count AS externalRecordCount, e.exported_at AS exportedAt,
  e.received_at AS receivedAt, e.date_start AS dateStart, e.date_end AS dateEnd`;
function integer(value: unknown, max: number): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0 && value <= max;
}
function publicRow(row: ExportRecord) {
  const { id, source, envelopeVersion, dailyVersion, byteCount, recordCount, failureCount,
    externalRecordCount, exportedAt, receivedAt, dateStart, dateEnd } = row;
  return { id, source, envelopeVersion, dailyVersion, byteCount, recordCount, failureCount,
    externalRecordCount, exportedAt, receivedAt, dateStart, dateEnd };
}

// Metadata filters describe actual retained envelope fields, never an app's
// saved profile name (which is not carried by v1/v2). Current means at least
// one day still points to this envelope; all includes replaced revisions and
// sidecar-only envelopes. Pagination is not a concurrent-write snapshot.
export async function exploreExports(request: Request, env: Env, userId: string): Promise<Response> {
  assertSameOrigin(request, env);
  const input = await readJson<InventoryRequest>(request);
  if (!object(input) || (input.source !== "all" && input.source !== "ios" && input.source !== "android") ||
      (input.version !== "all" && ![4, 5, 6, 7, 8].includes(input.version as number)) ||
      (input.scope !== "all" && input.scope !== "current") || !integer(input.offset, 1_000_000) ||
      (input.start !== null && !validDate(input.start)) ||
      (input.end !== null && !validDate(input.end)) ||
      (input.start !== null && input.end !== null && (input.start as string) > (input.end as string))) {
    throw new HttpError(400, "invalid_filter", "Invalid export metadata filter.");
  }
  const clauses = ["e.user_id = ?"];
  const values: Array<string | number> = [userId];
  if (input.source !== "all") { clauses.push("e.source = ?"); values.push(input.source as string); }
  if (input.version !== "all") { clauses.push("e.daily_record_schema_version = ?"); values.push(input.version as number); }
  if (input.start !== null) { clauses.push("e.date_end >= ?"); values.push(input.start as string); }
  if (input.end !== null) { clauses.push("e.date_start <= ?"); values.push(input.end as string); }
  if (input.scope === "current") {
    clauses.push(`EXISTS (SELECT 1 FROM daily_records d WHERE d.user_id = e.user_id AND d.export_id = e.id)`);
  }
  const rows = await env.DB.prepare(`SELECT ${fields} FROM exports e WHERE ${clauses.join(" AND ")}
    ORDER BY e.received_at DESC, e.id DESC LIMIT 21 OFFSET ?`)
    .bind(...values, input.offset).all<ExportRecord>();
  return json({ exports: rows.results.slice(0, PAGE_SIZE).map(publicRow),
    nextOffset: rows.results.length > PAGE_SIZE ? input.offset + PAGE_SIZE : null,
    note: "Date filters overlap the envelope's declared range, including failed dates. Saved export profile names are not in this envelope." });
}

function pointerParts(pointer: string): string[] {
  if (pointer.length > POINTER_LIMIT || (pointer !== "" && !pointer.startsWith("/"))) {
    throw new HttpError(400, "invalid_pointer", "Use a JSON Pointer of at most 512 characters.");
  }
  if (pointer === "") return [];
  const parts = pointer.slice(1).split("/");
  if (parts.length > 40 || parts.some((part) => /~(?![01])/u.test(part))) {
    throw new HttpError(400, "invalid_pointer", "Invalid JSON Pointer escape or depth.");
  }
  return parts.map((part) => part.replace(/~1/gu, "/").replace(/~0/gu, "~"));
}
function childPointer(pointer: string, key: string): string {
  return `${pointer}/${key.replace(/~/gu, "~0").replace(/\//gu, "~1")}`;
}
function nodeType(value: unknown): string {
  return value === null ? "null" : Array.isArray(value) ? "array" : typeof value;
}
function preview(value: unknown): Record<string, unknown> {
  const type = nodeType(value);
  if (type === "string") {
    const text = value as string;
    return { type, byteLength: new TextEncoder().encode(text).length,
      preview: text.length <= 512 ? text : `${text.slice(0, 512)}…`, truncated: text.length > 512 };
  }
  if (type === "number" && Number.isInteger(value) && !Number.isSafeInteger(value)) {
    return { type, exactValueUnavailable: true, note: "Download original JSON for the exact integer." };
  }
  if (type === "number" && !Number.isInteger(value)) {
    return { type, value, approximate: true, note: "Download original JSON for exact decimal digits." };
  }
  if (type === "null" || type === "boolean" || type === "number") return { type, value };
  return { type, length: Array.isArray(value) ? value.length : Object.keys(value as object).length };
}

// Every request rechecks the owner session in the router, the owner-bound
// export row here, then authenticated ciphertext/metadata integrity. Pages
// contain at most 20 direct children; long strings are previews only.
export async function exploreNode(request: Request, env: Env, userId: string): Promise<Response> {
  assertSameOrigin(request, env);
  const input = await readJson<NodeRequest>(request, 2048);
  if (!object(input) || typeof input.exportId !== "string" || !UUID.test(input.exportId) ||
      typeof input.pointer !== "string" || !integer(input.offset, 25 * 1024 * 1024)) {
    throw new HttpError(400, "invalid_node", "Invalid export, pointer or offset.");
  }
  const parts = pointerParts(input.pointer);
  const row = await env.DB.prepare(`SELECT ${fields} FROM exports e WHERE e.user_id = ? AND e.id = ?`)
    .bind(userId, input.exportId).first<ExportRecord>();
  if (!row) throw new HttpError(404, "not_found", "Export not found for this account.");
  const envelope = await readVerifiedEnvelope(row, env, userId);
  let value: unknown = envelope;
  for (const part of parts) {
    if (Array.isArray(value)) {
      if (!/^(0|[1-9]\d*)$/u.test(part) || !Number.isSafeInteger(Number(part)) || Number(part) >= value.length) {
        throw new HttpError(404, "not_found", "No such export node.");
      }
      value = value[Number(part)];
    } else {
      const current = object(value);
      if (!current || !Object.hasOwn(current, part)) throw new HttpError(404, "not_found", "No such export node.");
      value = current[part];
    }
  }
  const type = nodeType(value);
  if (type === "object" || type === "array") {
    const keys = type === "object" ? Object.keys(value as object) : null;
    const total = keys ? keys.length : (value as unknown[]).length;
    if (input.offset >= total && total > 0) throw new HttpError(400, "invalid_page", "Page exceeds node length.");
    const offset = input.offset;
    const items = Array.from({ length: Math.min(PAGE_SIZE, total - offset) }, (_, index) => {
      const key = keys ? keys[offset + index]! : String(offset + index);
      const item = keys ? (value as Record<string, unknown>)[key] : (value as unknown[])[Number(key)];
      return { key, pointer: childPointer(input.pointer as string, key), ...preview(item) };
    });
    return json({ exportId: row.id, pointer: input.pointer, type, totalChildren: total,
      offset: input.offset, nextOffset: input.offset + items.length < total ? input.offset + items.length : null,
      items, note: "Long strings and unsafe integers require downloading the original JSON for exact bytes." });
  }
  if (input.offset !== 0) throw new HttpError(400, "invalid_page", "Scalar nodes require offset zero.");
  return json({ exportId: row.id, pointer: input.pointer, ...preview(value),
    note: "Long strings and unsafe integers require downloading the original JSON for exact bytes." });
}
