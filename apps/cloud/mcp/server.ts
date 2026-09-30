import { createServer } from "node:http";
import type { IncomingMessage, ServerResponse } from "node:http";
import { Readable } from "node:stream";
import { DatabaseSync } from "node:sqlite";
import { createHash } from "node:crypto";
import { join } from "node:path";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { WebStandardStreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/webStandardStreamableHttp.js";
import * as z from "zod/v4";
import { authenticateReadToken } from "./auth";
import { ReaderError, VmHealthDataReader } from "./reader";
import type { HealthDataReader, ReadPrincipal } from "./reader";

const RESULT_BYTES = 16 * 1024;
const MCP_BODY_BYTES = 64 * 1024;
const MAX_REQUESTS_PER_MINUTE = 60;

function reply(response: ServerResponse, status: number, body: unknown, headers: Record<string, string> = {}): void {
  response.writeHead(status, { "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer", ...headers });
  response.end(JSON.stringify(body));
}

function safeToolResult(data: Record<string, unknown>) {
  const text = JSON.stringify(data);
  if (Buffer.byteLength(text) > RESULT_BYTES) {
    throw new ReaderError("response_too_large", "Response exceeds 16 KiB. Request fewer dates, a smaller page, or use byte paging.");
  }
  return { content: [{ type: "text" as const, text }], structuredContent: data };
}

function toolError(error: unknown) {
  const code = error instanceof ReaderError ? error.code : "unavailable_data";
  const message = error instanceof ReaderError ? error.message : "Health data could not be read safely.";
  const data = { error: { code, message } };
  return { isError: true, content: [{ type: "text" as const, text: JSON.stringify(data) }], structuredContent: data };
}

function createTools(reader: HealthDataReader, principal: ReadPrincipal): McpServer {
  const server = new McpServer({ name: "healthmd-export-read-only", version: "0.1.0" });
  const execute = async (name: string, action: () => Promise<Record<string, unknown>>) => {
    const start = performance.now();
    let status = "ok";
    try { return safeToolResult(await action()); }
    catch (error) { status = error instanceof ReaderError ? error.code : "unavailable_data"; return toolError(error); }
    finally {
      // Health-free audit: never log arguments, results, dates, raw identifiers or credentials.
      const actor = createHash("sha256").update(principal.tokenId).digest("hex").slice(0, 12);
      process.stderr.write(JSON.stringify({ actor, tool: name, status,
        durationMs: Math.round(performance.now() - start) }) + "\n");
    }
  };
  server.registerTool("health_list_metrics", {
    title: "List available health metrics", description: "List metric IDs present in the authenticated user's most recent 365 Apple v8 daily snapshots, with units, category and observed dates in that window. Older days remain queryable with exact metric IDs and a bounded range. No raw records or archives.",
    inputSchema: {},
  }, async () => execute("health_list_metrics", async () => ({ metrics: await reader.listMetrics(principal) })));
  server.registerTool("health_get_latest", {
    title: "Latest daily metric", description: "Get the most recent available daily aggregate for an exact metric ID from health_list_metrics. Daily aggregates have a date and timezone but no measurement timestamp; timestamp is null, never an invented upload time. Do not call heart_rate for heart_rate_avg.",
    inputSchema: { metric: z.string().min(1).max(80) },
  }, async ({ metric }) => execute("health_get_latest", async () => ({ result: await reader.getLatest(principal, metric) })));
  server.registerTool("health_get_range", {
    title: "Daily metric range", description: "Get daily aggregate values for an exact metric ID, inclusive civil YYYY-MM-DD bounds. Maximum 31 days and 16 KiB per response; ask for a narrower interval on overly_broad/response_too_large. Missing days are omitted, never zero-filled. No raw sample/archives.",
    inputSchema: { metric: z.string().min(1).max(80), start: z.string().min(10).max(10), end: z.string().min(10).max(10) },
  }, async ({ metric, start, end }) => execute("health_get_range", async () => ({ metric, samples: await reader.getRange(principal, metric, start, end) })));
  server.registerTool("health_get_daily_summary", {
    title: "Daily summary", description: "Get selected summary metrics for one YYYY-MM-DD calendar day; units/timezone explicit, absent metrics omitted. Does not return the original export or source archive.",
    inputSchema: { date: z.string().min(10).max(10) },
  }, async ({ date }) => execute("health_get_daily_summary", async () => ({ summary: await reader.getDailySummary(principal, date) })));
  server.registerTool("health_get_weekly_summary", {
    title: "Seven-day summary", description: "Get seven consecutive daily summaries starting at the given YYYY-MM-DD civil date, with explicit missing dates. Does not invent a weekly average or fill missing days with zeros.",
    inputSchema: { start: z.string().min(10).max(10) },
  }, async ({ start }) => execute("health_get_weekly_summary", async () => ({ summary: await reader.getWeeklySummary(principal, start) })));
  server.registerTool("health_search", {
    title: "Search metric catalog", description: "Search only metric IDs, display names and categories (not arbitrary text/files/SQL) across up to 14 days of daily summaries. Query must be 2–40 plain characters; no regex or paths.",
    inputSchema: { query: z.string().min(2).max(40), start: z.string().min(10).max(10), end: z.string().min(10).max(10) },
  }, async ({ query, start, end }) => execute("health_search", async () =>
    ({ results: await reader.search(principal, query, start, end) })));
  if (principal.scope === "full_export") {
    server.registerTool("health_export_guide", {
      title: "How to navigate all retained Health.md exports", description: "Call first: explains available Apple/Android daily profiles, historical revisions, embedded source archives and provider sidecars, exact-byte retrieval, pagination, capture gaps, privacy and tool selection. No health values returned.",
      inputSchema: {},
    }, async () => execute("health_export_guide", async () => ({
      scope: "full_export", origin: "Retained healthmd.api_export v1/v2 JSON envelopes uploaded to this account, not live device data",
      coverage: ["Apple daily v8 (all retained summary fields, optional HealthKit archive, optional typed provider sections)",
        "Android compatibility daily v4/v5 when uploaded", "v2 external provider sidecars", "failed-date details",
        "every retained historical revision and separate supplement, not just the current daily snapshot"],
      notAvailable: ["Health data never exported or already deleted", "Android Raw API Snapshot artifacts (not ingested here)",
        "Apple HealthKit/Android Health Connect data unavailable to the mobile app", "binary files outside retained JSON"],
      steps: ["For one day, health_find_export_for_date(date), then health_read_export_node(exportId, pointer).",
        "For all history, separate supplements or older revisions, page health_list_exports(cursor) until nextCursor is null; inspect retentionRole and original bytes without merging fields.",
        "Start navigation at pointer '' (root); follow items[].pointer. Page arrays/objects with nextOffset.",
        "Strings use UTF-8 base64 chunks; concatenate decoded bytes using nextOffsetBytes. Source binary already appears base64-encoded in original JSON.",
        "For exact integer digits, unavailable JSON Pointer keys, or complete fidelity, page health_read_export_bytes from offsetBytes 0 to nextOffsetBytes null and concatenate decoded bytes."],
      caution: "Values may contain precise routes, mental/clinical data, source identifiers and other sensitive material. Missing or partial capture is never zero or complete; Apple and Android schemas are distinct. Never infer platform parity or fabricate timestamps.",
      limits: { exportsPerPage: 20, childEntriesPerPage: 20, bytesPerPage: 8192,
        toolResultBytes: RESULT_BYTES, requestsPerMinute: MAX_REQUESTS_PER_MINUTE },
    })));
    server.registerTool("health_list_exports", {
      title: "Browse all retained export envelopes", description: "List ALL original, account-owned Health.md API-export envelopes, newest received first, including separate supplements, older revisions, Apple/Android profiles, failed-date details and v2 provider sidecars. retentionRole distinguishes a supplement from the current primary snapshot. No retention-time cutoff. Pass nextCursor until null (empty cursor starts over); request 1–20 entries per page. A listing is not a snapshot across uploads/deletions. Use health_find_export_for_date for the current primary daily snapshot.",
      inputSchema: { cursor: z.string().max(160).default(""), limit: z.number().int().min(1).max(20).default(10) },
    }, async ({ cursor, limit }) => execute("health_list_exports", async () =>
      reader.listExports(principal, cursor, limit)));
    server.registerTool("health_find_export_for_date", {
      title: "Find the current primary export for a calendar day", description: "Return only the current primary YYYY-MM-DD daily snapshot's export ID and JSON Pointer (for example /records/0). To find separate supplements, historical revisions or sidecar-only envelopes, page health_list_exports. Missing primary days are not zeros even when a supplement exists.",
      inputSchema: { date: z.string().length(10) },
    }, async ({ date }) => execute("health_find_export_for_date", async () =>
      reader.findExportForDate(principal, date)));
    server.registerTool("health_read_export_node", {
      title: "Navigate any retained JSON export field", description: "Read any JSON Pointer within an authenticated export envelope. Start with pointer '' for the root; follow returned child pointers, paging arrays/objects with offset and limit (1–20). The original envelope contains every retained daily field, provider sidecar, archive, metadata, free text and base64 binary. String values are returned as paged UTF-8 base64; decode chunks in byte order. JSON parsers may round huge integers: use health_read_export_bytes for exact source bytes. Never treat absent/partial capture as zero.",
      inputSchema: { exportId: z.string().uuid(), pointer: z.string().max(512).default(""),
        offset: z.number().int().min(0).max(25 * 1024 * 1024).default(0),
        limit: z.number().int().min(1).max(20).default(10) },
    }, async ({ exportId, pointer, offset, limit }) => execute("health_read_export_node", async () =>
      reader.readExportNode(principal, exportId, pointer, offset, limit)));
    server.registerTool("health_read_export_bytes", {
      title: "Read exact original export JSON in bounded pages", description: "Read one authenticated, original retained envelope in at most 8192-byte base64-encoded pages (offsetBytes; continue from nextOffsetBytes until null). This is lossless: preserves exact JSON bytes, large integer digits, raw archive/source identifiers, WHOOP sidecars and embedded binary. It never reads arbitrary files, fresh device data or data not sent to this server. Useful when JSON Pointer navigation cannot represent a key or number exactly.",
      inputSchema: { exportId: z.string().uuid(), offsetBytes: z.number().int().min(0).max(25 * 1024 * 1024).default(0) },
    }, async ({ exportId, offsetBytes }) => execute("health_read_export_bytes", async () =>
      reader.readExportBytes(principal, exportId, offsetBytes)));
  }
  return server;
}

export function startMcpServer(config: {
  dataDirectory: string;
  exportKeysJson: string;
  publicOrigin: string;
  port: number;
  reader?: HealthDataReader;
}): Promise<{ port: number; close: () => Promise<void> }> {
  const origin = new URL(config.publicOrigin);
  if (origin.protocol !== "https:" || origin.pathname !== "/" || origin.search || origin.hash ||
      origin.origin !== config.publicOrigin || !Number.isInteger(config.port) ||
      config.port < 0 || config.port > 65535) throw new Error("Invalid private MCP origin or port");
  const tokenDb = new DatabaseSync(join(config.dataDirectory, "cloud.sqlite"), { readOnly: true });
  let reader: HealthDataReader;
  try {
    tokenDb.exec("PRAGMA query_only = ON; PRAGMA trusted_schema = OFF;");
    tokenDb.prepare("SELECT id, read_scope FROM mcp_read_tokens LIMIT 0");
    reader = config.reader ?? new VmHealthDataReader(config.dataDirectory, config.exportKeysJson);
  } catch {
    tokenDb.close();
    throw new Error("Read-only MCP storage or migration is unavailable");
  }
  const usage = new Map<string, { minute: number; count: number }>();
  let running = 0;
  const server = createServer({ maxHeaderSize: 16 * 1024 }, async (request: IncomingMessage, response: ServerResponse) => {
    let mcp: McpServer | undefined;
    let transport: WebStandardStreamableHTTPServerTransport | undefined;
    try {
      const address = request.socket.remoteAddress;
      if (address !== "127.0.0.1" && address !== "::ffff:127.0.0.1") {
        reply(response, 421, { error: "unavailable" }); return;
      }
      if (request.headers.host !== origin.host || request.headers["x-forwarded-proto"] !== "https" ||
          request.headers["x-forwarded-host"] !== origin.host ||
          (request.headers.origin && request.headers.origin !== config.publicOrigin) ||
          request.url !== "/mcp") {
        reply(response, 421, { error: "unavailable" }); return;
      }
      const principal = authenticateReadToken(tokenDb, request.headers.authorization ?? null);
      if (!principal) {
        reply(response, 401, { error: "unauthorized" }, { "WWW-Authenticate": "Bearer realm=\"Health.md MCP\"" });
        return;
      }
      if (request.method !== "POST") {
        reply(response, 405, { error: "method_not_allowed" }, { Allow: "POST" }); return;
      }
      const minute = Math.floor(Date.now() / 60000);
      const bucket = usage.get(principal.tokenId);
      const count = bucket?.minute === minute ? bucket.count + 1 : 1;
      usage.set(principal.tokenId, { minute, count });
      if (usage.size > 1_000) {
        for (const [id, entry] of usage) if (entry.minute < minute) usage.delete(id);
      }
      if (count > MAX_REQUESTS_PER_MINUTE || running >= 2) {
        reply(response, 429, { error: "rate_limited" }, { "Retry-After": "2" }); return;
      }
      running += 1;
      try {
        const headers = new Headers();
        for (const [name, value] of Object.entries(request.headers)) {
          if (["authorization", "host", "connection", "transfer-encoding", "content-length", "cookie"].includes(name) ||
              value === undefined) continue;
          headers.set(name, Array.isArray(value) ? value.join(", ") : value);
        }
        headers.set("Host", origin.host);
        const webRequest = new Request(`${config.publicOrigin}/mcp`, {
          method: "POST", headers, body: Readable.toWeb(request) as BodyInit, duplex: "half",
        } as RequestInit);
        mcp = createTools(reader, principal);
        transport = new WebStandardStreamableHTTPServerTransport({
          sessionIdGenerator: undefined, enableJsonResponse: true, maxRequestBodySize: MCP_BODY_BYTES,
        });
        await mcp.connect(transport);
        const result = await transport.handleRequest(webRequest);
        const outputHeaders: Record<string, string> = { "Cache-Control": "no-store",
          "X-Content-Type-Options": "nosniff", "Referrer-Policy": "no-referrer" };
        result.headers.forEach((value, key) => { outputHeaders[key] = value; });
        response.writeHead(result.status, outputHeaders);
        if (result.body) await new Promise<void>((done, fail) => {
          const output = Readable.fromWeb(result.body as never);
          output.on("error", fail); response.on("error", fail); response.on("finish", done);
          output.pipe(response);
        });
        else response.end();
      } finally { running -= 1; }
    } catch {
      if (!response.headersSent) reply(response, 500, { error: "unavailable" });
      else response.destroy();
    } finally {
      await transport?.close();
      await mcp?.close();
    }
  });
  server.headersTimeout = 10_000;
  server.requestTimeout = 20_000;
  server.keepAliveTimeout = 5_000;
  server.maxConnections = 20;
  return new Promise((done, fail) => {
    server.once("error", fail);
    server.listen(config.port, "127.0.0.1", () => {
      const address = server.address();
      if (!address || typeof address === "string") { fail(new Error("No private MCP listener")); return; }
      done({ port: address.port, close: () => new Promise<void>((resolve, reject) =>
        server.close((error) => {
          if (reader instanceof VmHealthDataReader) reader.close();
          tokenDb.close();
          error ? reject(error) : resolve();
        })) });
    });
  });
}

if (process.env.HEALTHMD_MCP_START === "1") {
  const dataDirectory = process.env.HEALTHMD_VM_DATA_DIR;
  const exportKeysJson = process.env.EXPORT_ENCRYPTION_KEYS_JSON;
  const publicOrigin = process.env.MCP_PUBLIC_ORIGIN;
  const port = Number(process.env.MCP_LOOPBACK_PORT ?? "18789");
  if (!dataDirectory || !exportKeysJson || !publicOrigin || port !== 18789) {
    process.stderr.write("Private MCP configuration is incomplete.\n");
    process.exitCode = 1;
  } else {
    startMcpServer({ dataDirectory, exportKeysJson, publicOrigin, port }).catch(() => {
      process.stderr.write("Private MCP startup failed; no health data was logged.\n");
      process.exitCode = 1;
    });
  }
}
