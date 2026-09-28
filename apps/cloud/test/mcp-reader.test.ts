import { afterEach, expect, it } from "vitest";
import { randomBytes, randomUUID } from "node:crypto";
import { request as httpRequest } from "node:http";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { createVmEnvironment } from "../vm/runtime";
import { createSingleUserAccount } from "../vm/bootstrap";
import { encryptExport, sha256Hex } from "../src/crypto";
import { ReaderError, VmHealthDataReader } from "../mcp/reader";
import { createReadToken } from "../mcp/auth";
import { startMcpServer } from "../mcp/server";

const folders: string[] = [];
afterEach(() => { for (const path of folders.splice(0)) rmSync(path, { recursive: true, force: true }); });

it("reads only scoped, current synthetic Apple summaries with registry units and bounded errors", async () => {
  const root = mkdtempSync(join(tmpdir(), "healthmd-mcp-synthetic-"));
  folders.push(root);
  const sourceDirectory = resolve(import.meta.dirname, "..");
  const identityKey = Buffer.from(randomBytes(32)).toString("base64");
  const encryptionKey = Buffer.from(randomBytes(32)).toString("base64");
  const pepper = Buffer.from(randomBytes(32)).toString("base64");
  const { env, db, objects } = createVmEnvironment({ dataDirectory: root, sourceDirectory,
    publicOrigin: "https://synthetic.example.test:18788", identityKey,
    exportKeys: JSON.stringify({ v1: encryptionKey }), currentKeyId: "v1",
    passwordPepper: pepper, revisionRetention: "unlimited", approved: true });
  await createSingleUserAccount(env, "pilot", "pilot@example.test", "synthetic-password-for-tests-only");
  const userA = db.connection.prepare("SELECT id FROM users").get() as { id: string };
  const userB = randomUUID();
  db.connection.prepare(`INSERT INTO users (id, email_lookup, email_ciphertext, email_iv, status, created_at)
    VALUES (?, ?, 'synthetic', 'synthetic', 'active', ?)`)
    .run(userB, randomUUID(), new Date().toISOString());
  const template = JSON.parse(readFileSync(resolve(sourceDirectory,
    "../apple/docs/reference/generated/core/summary-day.json"), "utf8")) as Record<string, unknown>;
  async function addDay(userId: string, date: string, steps: number): Promise<void> {
    const day = structuredClone(template);
    day.date = date;
    day.activity = { ...(day.activity as Record<string, unknown>), steps };
    const envelope = { schema: "healthmd.api_export", schema_version: 1,
      daily_record_schema: "healthmd.health_data", daily_record_schema_version: 8,
      source: "ios", exported_at: "2026-03-17T12:00:00Z",
      date_range: { start: date, end: date }, record_count: 1, records: [day], failed_date_details: [] };
    const bytes = new TextEncoder().encode(JSON.stringify(envelope));
    const exportId = randomUUID();
    const key = `v1/${randomUUID()}`;
    await objects.put(key, await encryptExport(bytes, encryptionKey, userId, exportId));
    db.connection.prepare(`INSERT INTO exports (id, user_id, object_key, encryption_key_id,
      plaintext_sha256, byte_count, envelope_schema_version, daily_record_schema_version,
      source, exported_at, received_at, date_start, date_end, record_count, failure_count,
      external_record_count) VALUES (?, ?, ?, 'v1', ?, ?, 1, 8, 'ios', ?, ?, ?, ?, 1, 0, 0)`)
      .run(exportId, userId, key, await sha256Hex(bytes), bytes.length,
        "2026-03-17T12:00:00Z", new Date().toISOString(), date, date);
    db.connection.prepare(`INSERT INTO daily_records (user_id, owner_date, export_id, record_index,
      schema_version, capture_status, exported_at, received_at) VALUES (?, ?, ?, 0, 8,
      'not_requested', ?, ?)`).run(userId, date, exportId,
      "2026-03-17T12:00:00Z", new Date().toISOString());
  }
  try {
    await addDay(userA.id, "2026-03-15", 12345);
    await addDay(userA.id, "2026-03-16", 9999);
    await addDay(userB, "2026-03-15", 777777);
    // A separate, older retained envelope is not selected in daily_records;
    // full-export discovery must still expose its v2 sidecar and exact bytes.
    const archived = structuredClone(template);
    archived.date = "2026-03-15";
    archived["a/b~c"] = "synthetic pointer";
    archived.healthkit_record_archive = { schema: "healthmd.healthkit_records", schema_version: 1,
      records: [{ original_uuid: "00000000-0000-0000-0000-000000000001",
        precise_integer: "EXACT_INTEGER_SENTINEL", data: "Z".repeat(20_000) }] };
    const archivedEnvelope = { schema: "healthmd.api_export", schema_version: 2,
      daily_record_schema: "healthmd.health_data", daily_record_schema_version: 8,
      external_record_schema: "healthmd.external_provider_daily", external_record_schema_version: 1,
      external_record_count: 1, external_records: [{ schema: "healthmd.external_provider_daily",
        schema_version: 1, date: "2026-03-15", provider: "synthetic", payload: { score: 42 } }],
      source: "ios", exported_at: "2026-03-16T12:00:00Z",
      date_range: { start: "2026-03-15", end: "2026-03-15" }, record_count: 1,
      records: [archived], failed_date_details: [] };
    const archivedBytes = new TextEncoder().encode(JSON.stringify(archivedEnvelope)
      .replace('"EXACT_INTEGER_SENTINEL"', "18446744073709551615"));
    const archivedId = randomUUID();
    const archivedKey = `v1/${randomUUID()}`;
    await objects.put(archivedKey, await encryptExport(archivedBytes, encryptionKey, userA.id, archivedId));
    db.connection.prepare(`INSERT INTO exports (id, user_id, object_key, encryption_key_id,
      plaintext_sha256, byte_count, envelope_schema_version, daily_record_schema_version,
      source, exported_at, received_at, date_start, date_end, record_count, failure_count,
      external_record_count) VALUES (?, ?, ?, 'v1', ?, ?, 2, 8, 'ios', ?, ?, ?, ?, 1, 0, 1)`)
      .run(archivedId, userA.id, archivedKey, await sha256Hex(archivedBytes), archivedBytes.length,
        "2026-03-16T12:00:00Z", "2026-03-16T12:00:00.000Z", "2026-03-15", "2026-03-15");
    const reader = new VmHealthDataReader(root, JSON.stringify({ v1: encryptionKey }));
    try {
      const a = { userId: userA.id, tokenId: randomUUID(), scope: "aggregates" as const };
      const b = { userId: userB, tokenId: randomUUID(), scope: "aggregates" as const };
      const metrics = await reader.listMetrics(a);
      expect(metrics.find((m) => m.metric === "steps")).toMatchObject({
        unit: "steps", earliestDate: "2026-03-15", latestDate: "2026-03-16",
      });
      expect(await reader.getLatest(a, "steps")).toMatchObject({
        value: 9999, timestamp: null, date: "2026-03-16", unit: "steps",
      });
      expect((await reader.getRange(a, "steps", "2026-03-15", "2026-03-16"))
        .map((value) => value.value)).toEqual([12345, 9999]);
      expect((await reader.getRange(b, "steps", "2026-03-15", "2026-03-15"))[0]?.value).toBe(777777);
      const daily = await reader.getDailySummary(a, "2026-03-15");
      expect(daily.metrics.find((metric) => metric.metric === "sleep_total")).toMatchObject({
        value: 7.75, unit: "hours",
      });
      expect(JSON.stringify(daily)).not.toContain("healthkit_record_archive");
      const full = { ...a, scope: "full_export" as const };
      await expect(reader.listExports(a, "", 10)).rejects.toMatchObject({ code: "forbidden" });
      const first = await reader.listExports(full, "", 1);
      expect((first.exports as unknown[])).toHaveLength(1);
      const second = await reader.listExports(full, first.nextCursor as string, 10);
      expect((second.exports as Array<{ exportId: string }>).some((row) => row.exportId === archivedId)).toBe(true);
      expect(second.nextCursor).toBeNull();
      expect((await reader.findExportForDate(full, "2026-03-15")).pointer).toBe("/records/0");
      await expect(reader.listExports(full, "bad!", 10)).rejects.toMatchObject({ code: "invalid_cursor" });
      await expect(reader.readExportNode({ ...b, scope: "full_export" }, archivedId, "", 0, 10))
        .rejects.toMatchObject({ code: "unavailable_data" });
      const rootNode = await reader.readExportNode(full, archivedId, "", 0, 4);
      expect(rootNode.nextOffset).toBe(4);
      expect((await reader.readExportNode(full, archivedId, "/records/0/a~1b~0c", 0, 10))
        .chunkBase64).toBe(Buffer.from("synthetic pointer").toString("base64"));
      const sidecar = await reader.readExportNode(full, archivedId, "/external_records/0/payload/score", 0, 10);
      expect(sidecar.value).toBe(42);
      const exact = await reader.readExportNode(full, archivedId,
        "/records/0/healthkit_record_archive/records/0/precise_integer", 0, 10);
      expect(exact).not.toHaveProperty("value");
      expect(exact.note).toContain("health_read_export_bytes");
      const longPointer = "/records/0/healthkit_record_archive/records/0/data";
      const part = await reader.readExportNode(full, archivedId, longPointer, 0, 10);
      const remaining = await reader.readExportNode(full, archivedId, longPointer, part.nextOffsetBytes as number, 10);
      expect(Buffer.from((part.chunkBase64 as string), "base64").length).toBe(8192);
      expect(Buffer.from((remaining.chunkBase64 as string), "base64").length).toBe(8192);
      const bytesPage = await reader.readExportBytes(full, archivedId, 0);
      expect(bytesPage.nextOffsetBytes).toBe(8192);
      let offset: number | null = 0;
      const assembled: Buffer[] = [];
      while (offset !== null) {
        const page = await reader.readExportBytes(full, archivedId, offset);
        assembled.push(Buffer.from(page.chunkBase64 as string, "base64"));
        offset = page.nextOffsetBytes as number | null;
      }
      expect(Buffer.concat(assembled)).toEqual(Buffer.from(archivedBytes));
      expect(Buffer.concat(assembled).toString("utf8")).toContain("18446744073709551615");
      await expect(reader.readExportBytes(full, archivedId, archivedBytes.length))
        .rejects.toMatchObject({ code: "invalid_page" });
      await expect(reader.readExportNode(full, archivedId, longPointer, 20_001, 10))
        .rejects.toMatchObject({ code: "invalid_page" });
      await expect(reader.readExportNode(full, archivedId, "/toString", 0, 10))
        .rejects.toMatchObject({ code: "invalid_pointer" });
      await expect(reader.readExportNode(full, archivedId, "/records/0/~2", 0, 10))
        .rejects.toMatchObject({ code: "invalid_pointer" });
      const weekly = await reader.getWeeklySummary(a, "2026-03-15");
      expect(weekly.days).toHaveLength(2);
      expect(weekly.missingDates).toHaveLength(5);
      const search = await reader.search(a, "sleep", "2026-03-15", "2026-03-16");
      expect(search.matches.some((match) => match.metric.metric === "sleep_total")).toBe(true);
      await expect(reader.getLatest(a, "heart_rate")).rejects.toMatchObject({ code: "unknown_metric" });
      await expect(reader.getDailySummary(a, "2026-02-30")).rejects.toMatchObject({ code: "invalid_date" });
      await expect(reader.getRange(a, "steps", "2026-01-01", "2026-03-15"))
        .rejects.toMatchObject({ code: "overly_broad" });
      await expect(reader.search(a, "../", "2026-03-15", "2026-03-15"))
        .rejects.toMatchObject({ code: "invalid_query" });
      await expect(reader.getDailySummary({ userId: randomUUID(), tokenId: randomUUID(), scope: "aggregates" }, "2026-03-15"))
        .rejects.toBeInstanceOf(ReaderError);
    } finally { reader.close(); }
    // Integrate the actual SDK transport, token lookup, SQLite reader and AES
    // decryption against one synthetic owned export (not just a fake reader).
    const issued = createReadToken(db.connection, userA.id, "Synthetic full-stack MCP");
    const issuedFull = createReadToken(db.connection, userA.id, "Synthetic full-export MCP", 30, "full_export");
    const service = await startMcpServer({ dataDirectory: root, exportKeysJson: JSON.stringify({ v1: encryptionKey }),
      publicOrigin: "https://mcp.example.test", port: 0 });
    try {
      const fullStack = await new Promise<{ status: number; value: number }>((done, fail) => {
        const req = httpRequest({ host: "127.0.0.1", port: service.port, path: "/mcp", method: "POST",
          headers: { Host: "mcp.example.test", "X-Forwarded-Proto": "https",
            "X-Forwarded-Host": "mcp.example.test", Authorization: `Bearer ${issued.token}`,
            "Content-Type": "application/json", Accept: "application/json, text/event-stream",
            "MCP-Protocol-Version": "2025-11-25" } }, (response) => {
          const chunks: Uint8Array[] = [];
          response.on("data", (chunk: Uint8Array) => chunks.push(chunk));
          response.on("end", () => {
            const body = JSON.parse(Buffer.concat(chunks).toString("utf8"));
            done({ status: response.statusCode ?? 0, value: body.result.structuredContent.result.value });
          });
        });
        req.on("error", fail);
        req.end(JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/call",
          params: { name: "health_get_latest", arguments: { metric: "steps" } } }));
      });
      expect(fullStack).toEqual({ status: 200, value: 9999 });
      const fullStackNode = await new Promise<{ status: number; value: number }>((done, fail) => {
        const req = httpRequest({ host: "127.0.0.1", port: service.port, path: "/mcp", method: "POST",
          headers: { Host: "mcp.example.test", "X-Forwarded-Proto": "https",
            "X-Forwarded-Host": "mcp.example.test", Authorization: `Bearer ${issuedFull.token}`,
            "Content-Type": "application/json", Accept: "application/json, text/event-stream",
            "MCP-Protocol-Version": "2025-11-25" } }, (response) => {
          const chunks: Uint8Array[] = [];
          response.on("data", (chunk: Uint8Array) => chunks.push(chunk));
          response.on("end", () => {
            const body = JSON.parse(Buffer.concat(chunks).toString("utf8"));
            done({ status: response.statusCode ?? 0, value: body.result.structuredContent.value });
          });
        });
        req.on("error", fail);
        req.end(JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/call",
          params: { name: "health_read_export_node", arguments: {
            exportId: archivedId, pointer: "/external_records/0/payload/score" } } }));
      });
      expect(fullStackNode).toEqual({ status: 200, value: 42 });
    } finally { await service.close(); }
    const latest = db.connection.prepare(`SELECT e.object_key AS objectKey FROM daily_records d
      JOIN exports e ON e.id = d.export_id WHERE d.user_id = ? AND d.owner_date = ?`)
      .get(userA.id, "2026-03-16") as { objectKey: string };
    const objectPath = join(root, "objects", latest.objectKey);
    const damaged = readFileSync(objectPath);
    damaged[damaged.length - 1] = damaged[damaged.length - 1]! ^ 1;
    writeFileSync(objectPath, damaged);
    const tamperedReader = new VmHealthDataReader(root, JSON.stringify({ v1: encryptionKey }));
    try {
      await expect(tamperedReader.getLatest({ userId: userA.id, tokenId: randomUUID(), scope: "aggregates" }, "steps"))
        .rejects.toMatchObject({ code: "unavailable_data" });
    } finally { tamperedReader.close(); }
  } finally { db.close(); }
});
