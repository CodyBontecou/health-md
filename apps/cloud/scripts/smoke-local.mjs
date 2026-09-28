import { spawn, spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { createServer } from "node:net";
import { setTimeout as pause } from "node:timers/promises";

const cwd = resolve(import.meta.dirname, "..");
const varsPath = join(cwd, ".dev.vars");
const state = mkdtempSync(join(tmpdir(), "healthmd-cloud-smoke-"));
const wrangler = join(cwd, "node_modules", ".bin", "wrangler");
let server;
let createdVars = false;

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function checkStatus(result, expected, label) {
  assert(result.status === expected, `${label}: HTTP ${result.status}, expected ${expected}`);
}

function command(args) {
  const result = spawnSync(wrangler, args, { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
  if (result.status !== 0) throw new Error(`Local Wrangler setup failed: ${args.slice(0, 3).join(" ")}\n${result.stderr}`);
}

async function freePort() {
  const listener = createServer();
  listener.listen(0, "127.0.0.1");
  await new Promise((done) => listener.once("listening", done));
  const port = listener.address().port;
  await new Promise((done) => listener.close(done));
  return port;
}

async function jsonRequest(origin, path, method = "GET", body, cookie, bearer) {
  const response = await fetch(`${origin}${path}`, {
    method,
    headers: {
      Origin: origin,
      ...(body ? { "Content-Type": "application/json" } : {}),
      ...(cookie ? { Cookie: cookie } : {}),
      ...(bearer ? { Authorization: `Bearer ${bearer}` } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  const parsed = await response.json();
  return { response, parsed, status: response.status };
}

async function waitForServer(origin) {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    if (server.exitCode !== null) throw new Error("Local Wrangler exited before health check");
    try {
      const response = await fetch(`${origin}/health`);
      if (response.ok) return;
    } catch {
      // Wrangler has not started listening yet.
    }
    await pause(150);
  }
  throw new Error("Local Wrangler did not become ready");
}

async function run() {
  if (existsSync(varsPath)) throw new Error("Refusing to overwrite an existing .dev.vars");
  const identity = randomBytes(32).toString("base64");
  const encryption = randomBytes(32).toString("base64");
  writeFileSync(varsPath, [
    `IDENTITY_KEY_B64=${identity}`,
    `EXPORT_ENCRYPTION_KEYS_JSON=${JSON.stringify({ v1: encryption })}`,
    "DEV_SHOW_MAGIC_LINK=1",
    "AUTH_INVITE_EMAILS=alice@example.test,bob@example.test",
    "RESEND_API_KEY=synthetic-not-used",
  ].join("\n") + "\n", { mode: 0o600 });
  createdVars = true;
  command(["d1", "migrations", "apply", "healthmd-cloud", "--local", "--persist-to", state]);
  const port = await freePort();
  const origin = `http://127.0.0.1:${port}`;
  server = spawn(wrangler, [
    "dev", "--local", "--ip", "127.0.0.1", "--port", String(port),
    "--persist-to", state, "--log-level", "none", "--show-interactive-dev-session", "false",
    "--var", "ENVIRONMENT:development", "--var", `PUBLIC_ORIGIN:${origin}`,
    "--var", "AUTH_SIGNUP_MODE:invite",
  ], { cwd, stdio: "ignore" });
  await waitForServer(origin);
  const loginPage = await fetch(`${origin}/login`);
  assert(loginPage.status === 200 && loginPage.headers.get("content-security-policy")?.includes("default-src 'none'"),
    "Login page must have a restrictive CSP");
  const script = await fetch(`${origin}/dashboard.js`);
  const stylesheet = await fetch(`${origin}/style.css`);
  assert(script.status === 200 && stylesheet.status === 200,
    "Dashboard scripts and stylesheet must be served from the same origin");
  const unauthenticatedPage = await fetch(`${origin}/dashboard`, { redirect: "manual" });
  assert(unauthenticatedPage.status === 303 && unauthenticatedPage.headers.get("location") === "/login",
    "The dashboard must require a browser session");

  async function signIn(email) {
    const link = await jsonRequest(origin, "/api/auth/request-link", "POST", { email });
    checkStatus(link, 200, "request magic link");
    assert(link.parsed.devLink, "Local invite should return a synthetic link");
    const token = new URL(link.parsed.devLink).hash.slice("#token=".length);
    const consumed = await jsonRequest(origin, "/api/auth/consume-link", "POST", { token });
    checkStatus(consumed, 200, "consume magic link");
    const replay = await jsonRequest(origin, "/api/auth/consume-link", "POST", { token });
    checkStatus(replay, 400, "reject magic link replay");
    const cookie = consumed.response.headers.get("set-cookie")?.split(";", 1)[0];
    assert(cookie?.startsWith("healthmd_cloud_session_dev="), "Expected a dev session cookie");
    return cookie;
  }

  const cookie = await signIn("alice@example.test");
  const protectedPage = await fetch(`${origin}/dashboard`, { redirect: "manual", headers: { Cookie: cookie } });
  assert(protectedPage.status === 200, `Dashboard should be available to signed-in user (HTTP ${protectedPage.status}, content-type ${protectedPage.headers.get("content-type")}, location ${protectedPage.headers.get("location")})`);
  const newToken = await jsonRequest(origin, "/api/ingest-tokens", "POST", { name: "Synthetic iPhone" }, cookie);
  checkStatus(newToken, 201, "create export token");
  const ingestToken = newToken.parsed.token;
  const fixture = JSON.parse(readFileSync(resolve(cwd, "../apple/docs/reference/generated/automation/api-export-v1.json"), "utf8"));
  const noAuth = await jsonRequest(origin, "/api/v1/exports", "POST", fixture);
  checkStatus(noAuth, 401, "reject unauthenticated export");
  const stored = await jsonRequest(origin, "/api/v1/exports", "POST", fixture, null, ingestToken);
  checkStatus(stored, 201, "ingest Apple reference envelope");
  const duplicate = await jsonRequest(origin, "/api/v1/exports", "POST", fixture, null, ingestToken);
  checkStatus(duplicate, 200, "idempotent repeat");
  assert(duplicate.parsed.duplicate === true, "Expected exact replay detection");
  const invalid = await jsonRequest(origin, "/api/v1/exports", "POST", {
    ...fixture, record_count: 2,
  }, null, ingestToken);
  checkStatus(invalid, 422, "reject invalid envelope count");
  const v2 = JSON.parse(readFileSync(resolve(cwd,
    "../apple/docs/reference/generated/automation/api-export-v2-provider-sidecar.json"), "utf8"));
  v2.exported_at = "2026-03-16T12:34:56.000Z";
  const providerReceipt = await jsonRequest(origin, "/api/v1/exports", "POST", v2, null, ingestToken);
  checkStatus(providerReceipt, 201, "ingest synthetic Apple v2 provider envelope");
  const android = {
    ...fixture, source: "android", daily_record_schema_version: 4,
    date_range: { start: "2026-03-16", end: "2026-03-16" },
    records: [{ schema: "healthmd.health_data", schema_version: 4,
      date: "2026-03-16", activity: { steps: 123 } }],
    failed_date_details: [],
    exported_at: "2026-03-17T12:34:56.000Z",
  };
  const androidReceipt = await jsonRequest(origin, "/api/v1/exports", "POST", android, null, ingestToken);
  checkStatus(androidReceipt, 201, "ingest synthetic Android v4 compatibility envelope");
  const older = structuredClone(fixture);
  older.exported_at = "2026-03-14T12:34:56.000Z";
  const oldReceipt = await jsonRequest(origin, "/api/v1/exports", "POST", older, null, ingestToken);
  checkStatus(oldReceipt, 201, "archive older snapshot without replacing newer day");
  const inventory = await jsonRequest(origin, "/api/exports", "GET", null, cookie);
  checkStatus(inventory, 200, "list exports");
  assert(inventory.parsed.storage.count === 4 && inventory.parsed.days.length === 2,
    "Expected four accepted envelopes and two current daily pointers");
  assert(inventory.parsed.days.find((day) => day.date === "2026-03-15")?.exportedAt === "2026-03-16T12:34:56.000Z",
    "An older revision must not replace the newest day");
  const download = await fetch(`${origin}/api/exports/${stored.parsed.id}/download`, { headers: { Cookie: cookie } });
  assert(download.status === 200 && download.headers.get("cache-control") === "no-store", "Private download headers missing");
  assert(JSON.stringify(await download.json()) === JSON.stringify(fixture), "Exact envelope roundtrip failed");
  const otherCookie = await signIn("bob@example.test");
  const otherInventory = await jsonRequest(origin, "/api/exports", "GET", null, otherCookie);
  assert(otherInventory.parsed.storage.count === 0, "Account isolation failed");
  const otherDownload = await fetch(`${origin}/api/exports/${stored.parsed.id}/download`, { headers: { Cookie: otherCookie } });
  assert(otherDownload.status === 404, "Another account must not read a stored export");
  const revoke = await jsonRequest(origin, `/api/ingest-tokens/${newToken.parsed.id}`, "DELETE", null, cookie);
  checkStatus(revoke, 200, "revoke token");
  const revoked = await jsonRequest(origin, "/api/v1/exports", "POST", fixture, null, ingestToken);
  checkStatus(revoked, 401, "reject revoked token");
  console.log("Local synthetic accounts, Apple v1/v2 and Android v4 ingestion, replacement ordering, encrypted roundtrip, tenant isolation, and revocation passed.");
}

try {
  await run();
} finally {
  if (server) {
    server.kill("SIGTERM");
    await pause(300);
    if (server.exitCode === null) server.kill("SIGKILL");
  }
  if (createdVars) rmSync(varsPath, { force: true });
  rmSync(state, { recursive: true, force: true });
}
