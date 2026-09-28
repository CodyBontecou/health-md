import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { isIP } from "node:net";
import { Readable } from "node:stream";
import { resolve } from "node:path";
import worker from "../src/index";
import type { Env } from "../src/types";
import { createVmEnvironment } from "./runtime";
import { assertPrivateDirectory } from "./storage";

function safeError(response: ServerResponse, status: number): void {
  response.writeHead(status, { "Cache-Control": "no-store", "Content-Type": "application/json",
    "X-Content-Type-Options": "nosniff", ...(status === 503 ? { "Retry-After": "2" } : {}) });
  response.end('{"error":"unavailable"}');
}

function trustedProxyRequest(request: IncomingMessage, env: Env, accountOnly = false): Request | null {
  const remote = request.socket.remoteAddress;
  if (remote !== "127.0.0.1" && remote !== "::ffff:127.0.0.1") return null;
  const expected = new URL(env.PUBLIC_ORIGIN);
  if (expected.protocol !== "https:" ||
      request.headers.host !== expected.host ||
      request.headers["x-forwarded-host"] !== expected.host ||
      request.headers["x-forwarded-proto"] !== "https") return null;
  if (request.headers["sec-fetch-site"] === "cross-site") return null;
  const path = request.url ?? "/";
  if (!path.startsWith("/") || path.startsWith("//") || path.includes("#")) return null;
  const headers = new Headers();
  for (const [key, value] of Object.entries(request.headers)) {
    if (key === "host" || key === "connection" || key === "transfer-encoding" ||
        key === "content-length" || key === "cf-connecting-ip" || value === undefined) continue;
    headers.set(key, Array.isArray(value) ? value.join(", ") : value);
  }
  headers.set("Host", expected.host);
  const forwardedFor = request.headers["x-forwarded-for"];
  const lastForwardedIp = typeof forwardedFor === "string" ? forwardedFor.split(",").at(-1)?.trim() : null;
  if (lastForwardedIp && isIP(lastForwardedIp)) headers.set("CF-Connecting-IP", lastForwardedIp);
  // Tailscale Serve rewrites the browser Origin from HTTPS to its local HTTP
  // upstream. Only restore the expected Origin when the request carries the
  // dashboard's non-simple CSRF header; never rewrite an arbitrary origin.
  if (!accountOnly && headers.get("Origin") === `http://${expected.host}` &&
      headers.get("X-HealthMd-Intent") === "dashboard") headers.set("Origin", env.PUBLIC_ORIGIN);
  const method = request.method ?? "GET";
  const body = method === "GET" || method === "HEAD" ? undefined : Readable.toWeb(request);
  return new Request(`${env.PUBLIC_ORIGIN}${path}`, {
    method,
    headers,
    body: body as BodyInit | undefined,
    ...(body ? { duplex: "half" } : {}),
  } as RequestInit);
}

// Serialize one-account quota checks and metadata commits. A second legitimate
// upload waits its turn instead of failing spuriously when maintenance or an
// earlier daily batch is still in flight. Bound the queue to avoid a tailnet
// peer holding arbitrarily many streaming requests open.
class VmGate {
  private uploadTail: Promise<void> = Promise.resolve();
  private uploadCount = 0;
  private maintenance: Promise<void> | null = null;

  async reserveUpload(response: ServerResponse): Promise<(() => void) | null> {
    if (this.uploadCount >= 4) return null;
    this.uploadCount += 1;
    const previous = this.uploadTail;
    let release!: () => void;
    this.uploadTail = new Promise<void>((resolve) => { release = resolve; });
    try {
      await previous;
      if (this.maintenance) await this.maintenance;
      if (response.destroyed) { this.uploadCount -= 1; release(); return null; }
      return () => { this.uploadCount -= 1; release(); };
    } catch (error) {
      this.uploadCount -= 1;
      release();
      throw error;
    }
  }

  async runMaintenance(job: () => Promise<void>): Promise<boolean> {
    if (this.uploadCount > 0 || this.maintenance) return false;
    let finish!: () => void;
    this.maintenance = new Promise<void>((resolve) => { finish = resolve; });
    try { await job(); return true; }
    finally { this.maintenance = null; finish(); }
  }
}

// A dedicated public account listener has an exact, positive route/method list.
// It cannot reach ingestion, magic-link signup, scheduled maintenance or MCP.
function accountRoute(method: string, path: string): boolean {
  if (method === "GET") return new Set([
    "/health", "/login", "/dashboard", "/dashboard.js", "/style.css",
    "/api/runtime", "/api/account", "/api/ingest-tokens", "/api/agent-tokens", "/api/exports",
  ]).has(path) || /^\/api\/exports\/[a-f0-9-]{36}\/download$/u.test(path) ||
    /^\/api\/(?:exports|days)\/page\/[0-9]{1,7}$/u.test(path);
  if (method === "POST") return new Set([
    "/api/auth/password-login", "/api/auth/logout", "/api/ingest-tokens", "/api/agent-tokens",
    "/api/account/delete",
  ]).has(path);
  return method === "DELETE" && (
    /^\/api\/ingest-tokens\/[a-f0-9-]{36}$/u.test(path) ||
    /^\/api\/agent-tokens\/[a-f0-9-]{36}$/u.test(path));
}

async function respond(request: IncomingMessage, response: ServerResponse, env: Env,
  gate: VmGate, accountOnly: boolean): Promise<void> {
  let releaseIngest: (() => void) | null = null;
  try {
    const webRequest = trustedProxyRequest(request, env, accountOnly);
    if (!webRequest) { safeError(response, 421); return; }
    if (accountOnly && !accountRoute(webRequest.method, new URL(webRequest.url).pathname)) {
      safeError(response, 404); return;
    }
    if (webRequest.method === "POST" && new URL(webRequest.url).pathname === "/api/v1/exports") {
      releaseIngest = await gate.reserveUpload(response);
      if (!releaseIngest) {
        if (!response.destroyed) safeError(response, 503);
        return;
      }
    }
    const result = await worker.fetch(webRequest, env);
    const headers: Record<string, string> = {};
    result.headers.forEach((value, key) => { headers[key] = value; });
    response.writeHead(result.status, headers);
    if (!result.body) { response.end(); return; }
    await new Promise<void>((done, fail) => {
      const output = Readable.fromWeb(result.body as never);
      output.on("error", fail);
      response.on("error", fail);
      response.on("finish", done);
      output.pipe(response);
    });
  } catch {
    // Never log request data, credentials, response bodies or exception text.
    if (!response.headersSent) safeError(response, 500);
    else response.destroy();
  } finally {
    releaseIngest?.();
  }
}

export async function startVmServer(env: Env, port: number, accountOnly = false): Promise<{
  close: () => Promise<void>;
  runMaintenance: (job: () => Promise<void>) => Promise<boolean>;
  port: number;
}> {
  if (!Number.isInteger(port) || port < 0 || port > 65535) throw new Error("Invalid VM port");
  const gate = new VmGate();
  const server = createServer({ maxHeaderSize: 16 * 1024 },
    (req, res) => { void respond(req, res, env, gate, accountOnly); });
  server.headersTimeout = 15_000;
  server.requestTimeout = 120_000;
  server.keepAliveTimeout = 5_000;
  server.maxConnections = 25;
  await new Promise<void>((done, fail) => {
    server.once("error", fail);
    server.listen(port, "127.0.0.1", done);
  });
  const address = server.address();
  if (!address || typeof address === "string") throw new Error("VM server has no TCP address");
  return {
    port: address.port,
    close: () => new Promise<void>((done, fail) => server.close((error) => error ? fail(error) : done())),
    runMaintenance: (job) => gate.runMaintenance(job),
  };
}

export async function runVmServer(): Promise<void> {
  process.umask(0o077);
  const dataDirectory = process.env.HEALTHMD_VM_DATA_DIR;
  const sourceDirectory = process.env.HEALTHMD_CLOUD_SOURCE_DIR;
  if (!dataDirectory || !sourceDirectory || !process.env.PUBLIC_ORIGIN ||
      !process.env.IDENTITY_KEY_B64 || !process.env.EXPORT_ENCRYPTION_KEYS_JSON ||
      !process.env.PASSWORD_PEPPER_B64) throw new Error("VM configuration is incomplete");
  const syntheticOnly = process.env.SYNTHETIC_PREVIEW_ONLY === "1";
  const personalMvp = process.env.VM_PERSONAL_MVP_NO_BACKUP_ACK === "I_ACCEPT_PERMANENT_DATA_LOSS";
  const retentionSetting = process.env.REVISION_RETENTION_DAYS;
  const finiteRetention = Number(retentionSetting);
  const revisionRetention = retentionSetting === "unlimited" ? "unlimited" : finiteRetention;
  if (syntheticOnly && personalMvp) throw new Error("Incompatible VM profiles");
  if (personalMvp) {
    const origin = new URL(process.env.PUBLIC_ORIGIN);
    if (origin.protocol !== "https:" || !origin.hostname.endsWith(".ts.net") ||
        origin.port !== "18788") throw new Error("The personal MVP requires its own tailnet HTTPS port");
  }
  if (!syntheticOnly && ((personalMvp ?
      (process.env.CLOUD_RUNTIME_APPROVED !== undefined || revisionRetention !== "unlimited") :
      (process.env.CLOUD_RUNTIME_APPROVED !== "healthmd-cloud-v1-reviewed" ||
        !process.env.VM_RESTORE_DRILL_VERIFIED_AT ||
        (revisionRetention !== "unlimited" && (!Number.isInteger(revisionRetention) ||
          revisionRetention < 1 || revisionRetention > 3650)))))) {
    throw new Error("VM profile gate, retention choice or independent restore drill is missing");
  }
  const source = assertPrivateDirectory(resolve(sourceDirectory));
  const { env, db, objects } = createVmEnvironment({
    dataDirectory: resolve(dataDirectory), sourceDirectory: source,
    publicOrigin: process.env.PUBLIC_ORIGIN,
    identityKey: process.env.IDENTITY_KEY_B64,
    exportKeys: process.env.EXPORT_ENCRYPTION_KEYS_JSON,
    currentKeyId: process.env.CURRENT_EXPORT_KEY_ID ?? "v1",
    passwordPepper: process.env.PASSWORD_PEPPER_B64,
    revisionRetention: syntheticOnly ? "unlimited" : revisionRetention,
    approved: !syntheticOnly && !personalMvp,
    personalMvp,
    syntheticOnly,
  });
  const port = Number(process.env.VM_PORT ?? "18788");
  if (!Number.isInteger(port) || port < 1) throw new Error("VM production port must be explicit");
  await worker.scheduled({} as ScheduledEvent, env);
  await objects.reconcile(db);
  const service = await startVmServer(env, port);
  // Keep deletion and orphan cleanup moving, but never race an in-flight upload.
  setInterval(() => {
    void service.runMaintenance(async () => {
      await worker.scheduled({} as ScheduledEvent, env);
      await objects.reconcile(db);
    }).catch(() => {
      // If erasure/reconciliation cannot run, stop accepting sensitive exports.
      process.exitCode = 1;
      process.kill(process.pid, "SIGTERM");
    });
  }, 60_000).unref();
  // Systemd owns process lifecycle. No request bodies or identities are logged.
}

// Bundled VM entrypoint only. Importing this module in tests does not start a server.
if (process.env.HEALTHMD_VM_START === "1") {
  runVmServer().catch(() => {
    process.stderr.write("Health.md VM startup failed; check configuration and private directory permissions.\n");
    process.exitCode = 1;
  });
}
