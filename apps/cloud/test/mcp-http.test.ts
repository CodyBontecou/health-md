import { afterEach, expect, it } from "vitest";
import { randomBytes, randomUUID } from "node:crypto";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { request as httpRequest } from "node:http";
import { VmDatabase } from "../vm/storage";
import { createReadToken, revokeReadToken, tokenDigest } from "../mcp/auth";
import { startMcpServer } from "../mcp/server";
import type { HealthDataReader, ReadPrincipal, MetricValue, DailySummary } from "../mcp/reader";

const folders: string[] = [];
afterEach(() => { for (const path of folders.splice(0)) rmSync(path, { recursive: true, force: true }); });

it("serves authenticated, scoped, read-only Streamable HTTP MCP and revokes immediately", async () => {
  const root = mkdtempSync(join(tmpdir(), "healthmd-mcp-http-synthetic-"));
  folders.push(root);
  process.umask(0o077);
  const db = new VmDatabase(root, resolve(import.meta.dirname, "../migrations"));
  const userA = randomUUID();
  const userB = randomUUID();
  for (const userId of [userA, userB]) {
    db.connection.prepare(`INSERT INTO users (id, email_lookup, email_ciphertext, email_iv, status, created_at)
      VALUES (?, ?, 'synthetic', 'synthetic', 'active', ?)`)
      .run(userId, randomUUID(), new Date().toISOString());
  }
  const issuedA = createReadToken(db.connection, userA, "Synthetic agent A");
  const issuedB = createReadToken(db.connection, userB, "Synthetic agent B");
  const issuedFull = createReadToken(db.connection, userA, "Synthetic full reader", 30, "full_export");
  expect(db.connection.prepare("SELECT read_scope AS scope FROM mcp_read_tokens WHERE id = ?")
    .get(issuedA.id)).toMatchObject({ scope: "aggregates" });
  expect(issuedA.token).toMatch(/^hmd_read_[A-Za-z0-9_-]{43}$/u);
  expect(JSON.stringify(db.connection.prepare("SELECT * FROM mcp_read_tokens").all())).not.toContain(issuedA.token);
  expect(db.connection.prepare("SELECT token_hash AS hash FROM mcp_read_tokens WHERE id = ?")
    .get(issuedA.id)).toMatchObject({ hash: tokenDigest(issuedA.token) });
  const metric = (principal: ReadPrincipal): MetricValue => ({ metric: "steps", date: "2026-03-15",
    timestamp: null, calendarTimezone: "America/Los_Angeles",
    value: principal.userId === userA ? 12345 : 54321, unit: "steps", kind: "daily_aggregate" });
  const info = { metric: "steps", displayName: "Steps", category: "Activity", unit: "steps",
    earliestDate: "2026-03-15", latestDate: "2026-03-15", kind: "daily_aggregate" as const };
  const daily = (principal: ReadPrincipal): DailySummary => ({ date: "2026-03-15",
    calendarTimezone: "America/Los_Angeles", metrics: [metric(principal)] });
  const reader: HealthDataReader = {
    listMetrics: async () => [info],
    getLatest: async (principal) => metric(principal),
    getRange: async (principal) => [metric(principal)],
    getDailySummary: async (principal) => daily(principal),
    getWeeklySummary: async (principal) => ({ start: "2026-03-15", end: "2026-03-21",
      days: [daily(principal)], missingDates: ["2026-03-16"] }),
    search: async (principal, query) => ({ query, matches: [{ metric: info, values: [metric(principal)] }] }),
    listExports: async (principal) => ({ owner: principal.userId }),
    findExportForDate: async (principal) => ({ owner: principal.userId }),
    readExportNode: async (principal) => ({ owner: principal.userId }),
    readExportBytes: async (principal) => ({ owner: principal.userId }),
  };
  const origin = "https://mcp.example.test";
  const service = await startMcpServer({ dataDirectory: root, reader, publicOrigin: origin,
    exportKeysJson: JSON.stringify({ v1: Buffer.from(randomBytes(32)).toString("base64") }), port: 0 });
  async function request(body: unknown, token?: string, method = "POST", path = "/mcp",
    headers: Record<string, string> = {}): Promise<{ status: number; parsed: any; headers: Record<string, string | string[] | undefined> }> {
    const payload = body === undefined ? undefined : JSON.stringify(body);
    return new Promise((done, fail) => {
      const req = httpRequest({ host: "127.0.0.1", port: service.port, path, method, headers: {
        Host: "mcp.example.test", "X-Forwarded-Proto": "https", "X-Forwarded-Host": "mcp.example.test",
        "Content-Type": "application/json", Accept: "application/json, text/event-stream",
        "MCP-Protocol-Version": "2025-11-25",
        ...(token ? { Authorization: `Bearer ${token}` } : {}), ...headers,
      } }, (response) => {
        const chunks: Uint8Array[] = [];
        response.on("data", (chunk: Uint8Array) => chunks.push(chunk));
        response.on("end", () => {
          const raw = Buffer.concat(chunks).toString("utf8");
          done({ status: response.statusCode ?? 0, parsed: raw ? JSON.parse(raw) : null, headers: response.headers });
        });
      });
      req.on("error", fail);
      if (payload) req.write(payload);
      req.end();
    });
  }
  const rpc = (id: number, method: string, params: unknown) => ({ jsonrpc: "2.0", id, method, params });
  const tool = (id: number, name: string, args: object = {}) => rpc(id, "tools/call", { name, arguments: args });
  try {
    expect((await request(rpc(1, "initialize", { protocolVersion: "2025-11-25",
      capabilities: {}, clientInfo: { name: "synthetic-test", version: "1" } }), issuedA.token)).status).toBe(200);
    expect((await request(rpc(2, "tools/list", {}))).status).toBe(401);
    expect((await request(rpc(3, "tools/list", {}), `hmd_ing_${Buffer.from(randomBytes(32)).toString("base64url")}`)).status).toBe(401);
    expect((await request(rpc(4, "tools/list", {}), "hmd_read_invalid")).status).toBe(401);
    const tools = await request(rpc(5, "tools/list", {}), issuedA.token);
    expect(tools.status).toBe(200);
    expect(tools.parsed.result.tools.map((item: { name: string }) => item.name).sort()).toEqual([
      "health_get_daily_summary", "health_get_latest", "health_get_range", "health_get_weekly_summary",
      "health_list_metrics", "health_search",
    ]);
    const fullTools = await request(rpc(6, "tools/list", {}), issuedFull.token);
    expect(fullTools.parsed.result.tools).toHaveLength(11);
    for (const name of ["health_export_guide", "health_list_exports", "health_find_export_for_date",
      "health_read_export_node", "health_read_export_bytes"]) {
      expect(fullTools.parsed.result.tools.map((item: { name: string }) => item.name)).toContain(name);
      const denied = await request(tool(7, name), issuedA.token);
      expect(denied.parsed.error !== undefined || denied.parsed.result?.isError === true).toBe(true);
    }
    const fullResult = await request(tool(8, "health_list_exports"), issuedFull.token);
    expect(fullResult.parsed.result.structuredContent.owner).toBe(userA);
    const guide = await request(tool(9, "health_export_guide"), issuedFull.token);
    expect(guide.parsed.result.structuredContent.scope).toBe("full_export");
    const cases: Array<[string, object, string]> = [
      ["health_list_metrics", {}, "Steps"],
      ["health_get_latest", { metric: "steps" }, "12345"],
      ["health_get_range", { metric: "steps", start: "2026-03-15", end: "2026-03-15" }, "12345"],
      ["health_get_daily_summary", { date: "2026-03-15" }, "12345"],
      ["health_get_weekly_summary", { start: "2026-03-15" }, "missingDates"],
      ["health_search", { query: "steps", start: "2026-03-15", end: "2026-03-15" }, "12345"],
    ];
    for (const [name, args, expected] of cases) {
      const response = await request(tool(10, name, args), issuedA.token);
      expect(response.status).toBe(200);
      expect(JSON.stringify(response.parsed.result.structuredContent)).toContain(expected);
      expect(response.headers["cache-control"]).toBe("no-store");
    }
    expect(JSON.stringify((await request(tool(20, "health_get_latest", { metric: "steps" }),
      issuedB.token)).parsed.result.structuredContent)).toContain("54321");
    expect(JSON.stringify((await request(tool(21, "health_get_latest", { metric: "steps" }),
      issuedB.token)).parsed.result.structuredContent)).not.toContain("12345");
    const forbidden = await request(tool(22, "read_file", { path: "/etc/passwd" }), issuedA.token);
    expect(forbidden.parsed.error !== undefined || forbidden.parsed.result?.isError === true).toBe(true);
    const malformed = await request(tool(23, "health_get_range", { metric: "steps", start: "bad" }), issuedA.token);
    expect(malformed.parsed.error !== undefined || malformed.parsed.result?.isError === true).toBe(true);
    expect((await request(undefined, issuedA.token, "GET")).status).toBe(405);
    expect((await request(tool(24, "health_list_metrics"), issuedA.token, "POST", "/mcp/../admin"))
      .status).toBe(421);
    expect((await request(tool(25, "health_list_metrics"), issuedA.token, "POST", "/mcp",
      { Origin: "https://evil.example.test" })).status).toBe(421);
    expect((await request(tool(26, "health_list_metrics", { padding: "x".repeat(70_000) }),
      issuedA.token)).status).toBe(413);
    db.connection.prepare("UPDATE mcp_read_tokens SET expires_at = ? WHERE id = ?")
      .run("2020-01-01T00:00:00.000Z", issuedB.id);
    expect((await request(tool(27, "health_list_metrics"), issuedB.token)).status).toBe(401);
    expect(revokeReadToken(db.connection, issuedA.id)).toBe(true);
    expect((await request(tool(26, "health_list_metrics"), issuedA.token)).status).toBe(401);
    db.connection.prepare("UPDATE users SET status = 'disabled' WHERE id = ?").run(userA);
    expect((await request(tool(28, "health_export_guide"), issuedFull.token)).status).toBe(401);
    db.connection.prepare("UPDATE users SET status = 'active' WHERE id = ?").run(userA);
    expect(revokeReadToken(db.connection, issuedFull.id)).toBe(true);
    expect((await request(tool(29, "health_list_exports"), issuedFull.token)).status).toBe(401);
  } finally { await service.close(); db.close(); }
}, 30_000);
