import { resolveExportKey } from "./account-export-keys";
import { decryptExport, encryptedExportByteCount, sha256Hex } from "./crypto";
import { HttpError, parsePositiveInteger } from "./http";
import type { Env } from "./types";

const PAGE_SIZE = 5;
const TAR_BLOCK = 512;

interface ExportRow {
  id: string;
  objectKey: string;
  keyId: string;
  sha256: string;
  byteCount: number;
  receivedAt: string;
  exportedAt: string;
  source: string;
  schemaVersion: number;
}

function writeAscii(target: Uint8Array, offset: number, length: number, value: string): void {
  const bytes = new TextEncoder().encode(value);
  if (bytes.byteLength > length) throw new Error("TAR field is too long");
  target.set(bytes, offset);
}

function writeOctal(target: Uint8Array, offset: number, length: number, value: number): void {
  if (!Number.isSafeInteger(value) || value < 0) throw new Error("TAR numeric field is invalid");
  const encoded = value.toString(8).padStart(length - 1, "0") + "\0";
  if (encoded.length > length) throw new Error("TAR numeric field is too large");
  writeAscii(target, offset, length, encoded);
}

function tarHeader(name: string, size: number, modifiedAt: string): Uint8Array {
  const header = new Uint8Array(TAR_BLOCK);
  writeAscii(header, 0, 100, name);
  writeOctal(header, 100, 8, 0o600);
  writeOctal(header, 108, 8, 0);
  writeOctal(header, 116, 8, 0);
  writeOctal(header, 124, 12, size);
  const timestamp = Math.max(0, Math.floor(Date.parse(modifiedAt) / 1000));
  writeOctal(header, 136, 12, Number.isFinite(timestamp) ? timestamp : 0);
  header.fill(0x20, 148, 156);
  header[156] = 0x30;
  writeAscii(header, 257, 6, "ustar\0");
  writeAscii(header, 263, 2, "00");
  writeAscii(header, 265, 32, "healthmd");
  writeAscii(header, 297, 32, "healthmd");
  let checksum = 0;
  for (const byte of header) checksum += byte;
  writeAscii(header, 148, 8, checksum.toString(8).padStart(6, "0") + "\0 ");
  return header;
}

function enqueueTarEntry(controller: ReadableStreamDefaultController<Uint8Array>, name: string,
  bytes: Uint8Array, modifiedAt: string): void {
  controller.enqueue(tarHeader(name, bytes.byteLength, modifiedAt));
  controller.enqueue(bytes);
  const padding = (TAR_BLOCK - bytes.byteLength % TAR_BLOCK) % TAR_BLOCK;
  if (padding) controller.enqueue(new Uint8Array(padding));
}

export async function downloadAccountExportPage(
  env: Env,
  userId: string,
  page: number,
): Promise<Response> {
  if (!Number.isSafeInteger(page) || page < 1 || page > 10_000_000) {
    throw new HttpError(404, "not_found", "Account export page was not found.");
  }
  const count = await env.DB.prepare("SELECT COUNT(*) AS count FROM exports WHERE user_id = ?")
    .bind(userId).first<{ count: number }>();
  const total = count?.count ?? 0;
  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));
  if (page > totalPages) throw new HttpError(404, "not_found", "Account export page was not found.");
  const offset = (page - 1) * PAGE_SIZE;
  const result = await env.DB.prepare(
    `SELECT id, object_key AS objectKey, encryption_key_id AS keyId, plaintext_sha256 AS sha256,
            byte_count AS byteCount, received_at AS receivedAt, exported_at AS exportedAt, source,
            daily_record_schema_version AS schemaVersion
     FROM exports WHERE user_id = ? ORDER BY received_at, id LIMIT ? OFFSET ?`,
  ).bind(userId, PAGE_SIZE, offset).all<ExportRow>();
  const rows = result.results;
  const maxBytes = parsePositiveInteger(env.MAX_EXPORT_BYTES, "MAX_EXPORT_BYTES", 1024, 100 * 1024 * 1024);
  if (rows.some((row) => !Number.isSafeInteger(row.byteCount) || row.byteCount < 1 || row.byteCount > maxBytes)) {
    throw new HttpError(503, "unavailable_data", "A retained export is unavailable.");
  }
  const files = rows.map((row, index) => ({
    filename: `${String(offset + index + 1).padStart(8, "0")}-${row.id}.json`,
    id: row.id,
    receivedAt: row.receivedAt,
    exportedAt: row.exportedAt,
    source: row.source,
    schemaVersion: row.schemaVersion,
    byteCount: row.byteCount,
    sha256: row.sha256,
  }));
  const generatedAt = new Date().toISOString();
  const manifest = new TextEncoder().encode(`${JSON.stringify({
    schema: "healthmd.account_portability_manifest",
    version: 1,
    generatedAt,
    page,
    pageSize: PAGE_SIZE,
    totalPages,
    totalExports: total,
    nextPage: page < totalPages ? page + 1 : null,
    files,
  }, null, 2)}\n`);
  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      try {
        enqueueTarEntry(controller, "manifest.json", manifest, generatedAt);
        for (let index = 0; index < rows.length; index += 1) {
          const row = rows[index]!;
          const object = await env.EXPORTS.get(row.objectKey);
          if (!object || object.size !== encryptedExportByteCount(row.byteCount)) {
            throw new Error("A retained export object is unavailable");
          }
          const key = await resolveExportKey(env, userId, row.keyId);
          const plaintext = await decryptExport(new Uint8Array(await object.arrayBuffer()), key, userId, row.id);
          if (plaintext.byteLength !== row.byteCount || await sha256Hex(plaintext) !== row.sha256) {
            throw new Error("A retained export failed integrity verification");
          }
          enqueueTarEntry(controller, files[index]!.filename, plaintext, row.receivedAt);
        }
        controller.enqueue(new Uint8Array(TAR_BLOCK * 2));
        controller.close();
      } catch (error) {
        controller.error(error);
      }
    },
  });
  return new Response(stream, {
    headers: {
      "Content-Type": "application/x-tar",
      "Content-Disposition": `attachment; filename="healthmd-account-export-page-${String(page).padStart(6, "0")}.tar"`,
      "Cache-Control": "no-store",
    },
  });
}
