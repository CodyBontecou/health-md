import { afterEach, describe, expect, it } from "vitest";
import { randomBytes, randomUUID } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync, statSync, unlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { resolve, join } from "node:path";
import { request as httpRequest } from "node:http";
import { connect } from "node:net";
import { DatabaseSync } from "node:sqlite";
import { createVmEnvironment } from "../vm/runtime";
import { createSingleUserAccount } from "../vm/bootstrap";
import { startVmServer } from "../vm/server";
import { authenticateReadToken, createReadToken } from "../mcp/auth";
import { processAccountDeletions, purgeArchivedRevisions } from "../src/lifecycle";
import type { Env } from "../src/types";
import worker from "../src/index";

const sourceDirectory = resolve(import.meta.dirname, "..");
const fakeOrigin = "https://preview.tailnet.test:18788";
const tempDirectories: string[] = [];
const fakePassword = "synthetic-password-not-for-production";
const email = "pilot@example.test";

function createTestEnv(profile: "approved" | "personal-mvp" = "approved"): {
  env: Env; db: ReturnType<typeof createVmEnvironment>["db"];
  objects: ReturnType<typeof createVmEnvironment>["objects"]; directory: string;
} {
  const directory = mkdtempSync(join(tmpdir(), "healthmd-vm-synthetic-"));
  tempDirectories.push(directory);
  const identityKey = Buffer.from(randomBytes(32)).toString("base64");
  const exportKey = Buffer.from(randomBytes(32)).toString("base64");
  const pepper = Buffer.from(randomBytes(32)).toString("base64");
  const { env, db, objects } = createVmEnvironment({ dataDirectory: directory, sourceDirectory,
    publicOrigin: fakeOrigin, identityKey, exportKeys: JSON.stringify({ v1: exportKey }),
    currentKeyId: "v1", passwordPepper: pepper, revisionRetention: "unlimited",
    approved: profile === "approved", personalMvp: profile === "personal-mvp" });
  return { env, db, objects, directory };
}

afterEach(() => {
  for (const directory of tempDirectories.splice(0)) rmSync(directory, { recursive: true, force: true });
});

async function proxiedRequest(port: number, path: string, method = "GET", body?: unknown,
  cookie?: string, origin = `http://preview.tailnet.test:18788`, intent = true,
  host = "preview.tailnet.test:18788", authorization?: string,
  contentType = "application/json") {
  const payload = body === undefined ? undefined : JSON.stringify(body);
  return new Promise<{ status: number; headers: Record<string, string | string[] | undefined>; body: string }>(
    (done, fail) => {
      const request = httpRequest({ host: "127.0.0.1", port, path, method, headers: {
        Host: host,
        "X-Forwarded-Proto": "https",
        "X-Forwarded-Host": host,
        "X-Forwarded-For": "100.64.0.23",
        ...(payload === undefined ? {} : { "Content-Type": contentType }),
        ...(method === "GET" ? {} : { Origin: origin, ...(intent ? { "X-HealthMd-Intent": "dashboard" } : {}) }),
        ...(cookie ? { Cookie: cookie } : {}),
        ...(authorization ? { Authorization: authorization } : {}),
      } }, (response) => {
        const chunks: Uint8Array[] = [];
        response.on("data", (chunk: Uint8Array) => chunks.push(chunk));
        response.on("end", () => done({ status: response.statusCode ?? 0,
          headers: response.headers, body: Buffer.concat(chunks).toString("utf8") }));
      });
      request.on("error", fail);
      if (payload) request.write(payload);
      request.end();
    },
  );
}

async function abortProxiedUpload(port: number, token: string): Promise<void> {
  await new Promise<void>((done, fail) => {
    const socket = connect(port, "127.0.0.1");
    socket.once("error", fail);
    socket.once("connect", () => {
      socket.write([
        "POST /api/v1/exports HTTP/1.1",
        "Host: api.example.test",
        "X-Forwarded-Proto: https",
        "X-Forwarded-Host: api.example.test",
        "X-Forwarded-For: 100.64.0.23",
        `Authorization: Bearer ${token}`,
        "Content-Type: application/json",
        "Content-Length: 1048576",
        "Connection: close",
        "",
        "{\"partial\":",
      ].join("\r\n"), (error) => {
        if (error) { fail(error); return; }
        setTimeout(() => { socket.destroy(); done(); }, 50);
      });
    });
  });
}

describe("isolated VM-native single-user backend (synthetic fixtures only)", () => {
  it("requires explicit no-backup MVP profile and shows the risk", async () => {
    const { env, db } = createTestEnv("personal-mvp");
    try {
      const runtime = await worker.fetch(new Request(`${fakeOrigin}/api/runtime`), env);
      expect(await runtime.json()).toMatchObject({ unbackedPersonalMvp: true, authMode: "password" });
      const loginPage = await worker.fetch(new Request(`${fakeOrigin}/login`), env);
      expect(await loginPage.text()).toContain("Unbacked personal trial");
      const unsafe = { ...env, REVISION_RETENTION_DAYS: "30" };
      expect((await worker.fetch(new Request(`${fakeOrigin}/health`), unsafe)).status).toBe(500);
    } finally { db.close(); }
  });

  it("migrates an owner-only SQLite store and protects the password verifier", async () => {
    const { env, db, directory } = createTestEnv();
    try {
      await createSingleUserAccount(env, "pilot", email, fakePassword);
      await expect(createSingleUserAccount(env, "another", "another@example.test", fakePassword))
        .rejects.toThrow(/already exists/u);
      const credentials = db.connection.prepare("SELECT * FROM password_credentials").get() as
        { verifier: string; salt: string; username_lookup: string };
      expect(credentials.verifier).not.toContain(fakePassword);
      expect(credentials.username_lookup).not.toContain("pilot");
      expect(credentials.salt).not.toEqual(credentials.verifier);
      expect(statSync(join(directory, "cloud.sqlite")).mode & 0o077).toBe(0);
    } finally { db.close(); }
  });

  it("serves signed-in owner and accepts an encrypted synthetic Apple envelope", async () => {
    const { env, db, objects, directory } = createTestEnv();
    await createSingleUserAccount(env, "pilot", email, fakePassword);
    const service = await startVmServer(env, 0);
    try {
      const direct = await fetch(`http://127.0.0.1:${service.port}/health`);
      expect(direct.status).toBe(421);
      const health = await proxiedRequest(service.port, "/health");
      expect(health.status).toBe(200);
      const wrongOrigin = await proxiedRequest(service.port, "/api/auth/password-login", "POST",
        { username: "pilot", password: fakePassword }, undefined, "https://external.example.test");
      expect(wrongOrigin.status).toBe(403);
      let finishMaintenance!: () => void;
      let enteredMaintenance!: () => void;
      const waiting = new Promise<void>((done) => { enteredMaintenance = done; });
      const release = new Promise<void>((done) => { finishMaintenance = done; });
      const maintenance = service.runMaintenance(async () => { enteredMaintenance(); await release; });
      await waiting;
      let queuedSettled = false;
      const queued = proxiedRequest(service.port, "/api/v1/exports", "POST", {})
        .then((result) => { queuedSettled = true; return result; });
      await new Promise((done) => setTimeout(done, 100));
      expect(queuedSettled).toBe(false);
      finishMaintenance();
      expect(await maintenance).toBe(true);
      expect((await queued).status).toBe(401); // Served after maintenance, not a spurious 503.
      const invalidPassword = await proxiedRequest(service.port, "/api/auth/password-login", "POST",
        { username: "pilot", password: "synthetic-incorrect-password" });
      expect(invalidPassword.status).toBe(401);
      const csrf = await proxiedRequest(service.port, "/api/auth/password-login", "POST",
        { username: "pilot", password: fakePassword }, undefined, undefined, false);
      expect(csrf.status).toBe(403);
      const login = await proxiedRequest(service.port, "/api/auth/password-login", "POST",
        { username: "pilot", password: fakePassword });
      expect(login.status).toBe(200);
      const cookie = (login.headers["set-cookie"] as string[] | undefined)?.[0]?.split(";")[0];
      expect(cookie).toMatch(/^__Host-healthmd_cloud_session=/u);
      expect(login.headers["cache-control"]).toBe("no-store");
      const account = await proxiedRequest(service.port, "/api/account", "GET", undefined, cookie);
      expect(JSON.parse(account.body)).toEqual({ email });
      const token = await proxiedRequest(service.port, "/api/ingest-tokens", "POST",
        { name: "Synthetic iPhone" }, cookie);
      expect(token.status).toBe(201);
      const ingestToken = JSON.parse(token.body).token as string;
      const fixture = JSON.parse(readFileSync(resolve(sourceDirectory,
        "../apple/docs/reference/generated/automation/api-export-v1.json"), "utf8"));
      const upload = await proxiedRequest(service.port, "/api/v1/exports", "POST", fixture,
        undefined, "http://preview.tailnet.test:18788");
      // This route needs a write-only bearer credential; browser session is insufficient.
      expect(upload.status).toBe(401);
      const result = await new Promise<{ status: number; body: string }>((done, fail) => {
        const req = httpRequest({ host: "127.0.0.1", port: service.port, path: "/api/v1/exports", method: "POST",
          headers: { Host: "preview.tailnet.test:18788", "X-Forwarded-Proto": "https",
            "X-Forwarded-Host": "preview.tailnet.test:18788", Authorization: `Bearer ${ingestToken}`,
            "Content-Type": "application/json" } }, (res) => {
          const chunks: Uint8Array[] = [];
          res.on("data", (chunk: Uint8Array) => chunks.push(chunk));
          res.on("end", () => done({ status: res.statusCode ?? 0, body: Buffer.concat(chunks).toString("utf8") }));
        });
        req.on("error", fail); req.end(JSON.stringify(fixture));
      });
      expect(result.status).toBe(201);
      const receipt = JSON.parse(result.body).id as string;
      const saved = db.connection.prepare("SELECT object_key FROM exports WHERE id = ?").get(receipt) as
        { object_key: string };
      const objectPath = join(directory, "objects", saved.object_key);
      const ciphertext = readFileSync(objectPath);
      expect(Buffer.from(ciphertext).toString("utf8")).not.toContain("healthmd.api_export");
      expect(await objects.reconcile(db)).toBe(0);
      const orphan = `v1/${randomUUID()}`;
      await objects.put(orphan, new Uint8Array([1, 2, 3]));
      expect(await objects.reconcile(db)).toBe(1);
      expect(statSync(join(directory, "objects", orphan), { throwIfNoEntry: false })).toBeUndefined();
      unlinkSync(objectPath);
      await expect(objects.reconcile(db)).rejects.toThrow(/missing ciphertext/u);
      await objects.put(saved.object_key, ciphertext);
      expect(await objects.reconcile(db)).toBe(0);
      const download = await proxiedRequest(service.port, `/api/exports/${receipt}/download`, "GET", undefined, cookie);
      expect(download.status).toBe(200);
      expect(JSON.parse(download.body)).toEqual(fixture);
      db.connection.prepare("UPDATE exports SET received_at = ? WHERE id = ?")
        .run("2020-01-01T00:00:00.000Z", receipt);
      await worker.scheduled({} as ScheduledEvent, env);
      expect(db.connection.prepare("SELECT COUNT(*) AS n FROM exports").get()).toMatchObject({ n: 1 });
      expect(await purgeArchivedRevisions(env, 30)).toBe(0); // Current pointer is preserved.
      const later = { ...fixture, exported_at: "2026-03-16T12:34:56.000Z" };
      const replacement = await worker.fetch(new Request(`${fakeOrigin}/api/v1/exports`, {
        method: "POST", headers: { Authorization: `Bearer ${ingestToken}`,
          "Content-Type": "application/json" }, body: JSON.stringify(later),
      }), env);
      expect(replacement.status).toBe(201);
      const latestId = (await replacement.json() as { id: string }).id;
      const latest = db.connection.prepare("SELECT object_key FROM exports WHERE id = ?").get(latestId) as
        { object_key: string };
      await worker.scheduled({} as ScheduledEvent, env); // Unlimited: archived copy stays.
      expect(statSync(join(directory, "objects", saved.object_key)).isFile()).toBe(true);
      expect(await purgeArchivedRevisions(env, 30)).toBe(1); // Explicit finite policy is still testable.
      expect(statSync(join(directory, "objects", saved.object_key), { throwIfNoEntry: false })).toBeUndefined();
      expect(statSync(join(directory, "objects", latest.object_key)).isFile()).toBe(true);
      const deletion = await proxiedRequest(service.port, "/api/account/delete", "POST",
        { password: fakePassword, confirmation: "DELETE",
          statusToken: `hmd_del_${Buffer.from(randomBytes(32)).toString("base64url")}` }, cookie);
      expect(deletion.status).toBe(202);
      const unauthorizedAfterDeletion = await proxiedRequest(service.port, "/api/account", "GET",
        undefined, cookie);
      expect(unauthorizedAfterDeletion.status).toBe(401);
      await processAccountDeletions(env);
      await processAccountDeletions(env);
      expect(db.connection.prepare("SELECT COUNT(*) AS n FROM users").get()).toMatchObject({ n: 0 });
      expect(db.connection.prepare("SELECT COUNT(*) AS n FROM exports").get()).toMatchObject({ n: 0 });
      expect(db.connection.prepare("SELECT completed_at FROM account_deletions").get()).toMatchObject({
        completed_at: expect.any(String),
      });
      expect(statSync(join(directory, "objects", latest.object_key), { throwIfNoEntry: false })).toBeUndefined();
    } finally { await service.close(); db.close(); }
  }, 30_000);

  it("charts only current, bounded Apple-v8 daily summaries for an owner session", async () => {
    const { env, db, directory } = createTestEnv("personal-mvp");
    const { env: accountEnv, db: accountDb } = createVmEnvironment({
      dataDirectory: directory, sourceDirectory, publicOrigin: "https://account.example.test",
      identityKey: env.IDENTITY_KEY_B64, exportKeys: env.EXPORT_ENCRYPTION_KEYS_JSON ?? "",
      currentKeyId: "v1", passwordPepper: env.PASSWORD_PEPPER_B64 ?? "",
      personalMvp: true, revisionRetention: "unlimited",
    });
    await createSingleUserAccount(env, "pilot", email, fakePassword);
    const account = await startVmServer(accountEnv, 0, "account");
    const req = (path: string, cookie?: string, bearer?: string) => proxiedRequest(account.port,
      path, "GET", undefined, cookie, "https://account.example.test", true,
      "account.example.test", bearer);
    try {
      expect((await req("/api/dashboard/trends")).status).toBe(401);
      const login = await proxiedRequest(account.port, "/api/auth/password-login", "POST",
        { username: "pilot", password: fakePassword }, undefined, "https://account.example.test",
        true, "account.example.test");
      const cookie = (login.headers["set-cookie"] as string[] | undefined)?.[0]?.split(";")[0];
      expect(cookie).toBeDefined();
      const token = await proxiedRequest(account.port, "/api/ingest-tokens", "POST",
        { name: "Synthetic phone" }, cookie, "https://account.example.test", true, "account.example.test");
      const bearer = JSON.parse(token.body).token as string;
      expect((await req("/api/dashboard/trends", undefined, `Bearer ${bearer}`)).status).toBe(401);
      const blank = await req("/api/dashboard/trends", cookie);
      expect(blank.status).toBe(200);
      expect(blank.headers["cache-control"]).toBe("no-store");
      expect(JSON.parse(blank.body)).toMatchObject({ window: { start: null, end: null }, days: [] });
      const fixture = JSON.parse(readFileSync(resolve(sourceDirectory,
        "../apple/docs/reference/generated/automation/api-export-v1.json"), "utf8"));
      const summary = JSON.parse(readFileSync(resolve(sourceDirectory,
        "../apple/docs/reference/generated/core/summary-day.json"), "utf8"));
      summary.date = fixture.records[0].date;
      fixture.records = [summary];
      const upload = await worker.fetch(new Request(`${fakeOrigin}/api/v1/exports`, {
        method: "POST", headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json" },
        body: JSON.stringify(fixture),
      }), env);
      expect(upload.status).toBe(201);
      const body = JSON.parse((await req("/api/dashboard/trends", cookie)).body);
      expect(JSON.parse((await req("/api/exports", cookie)).body))
        .toMatchObject({ storage: { count: 1, dayCount: 1 }, days: [{ date: summary.date, source: "ios" }] });
      expect(body.version).toBe(1);
      expect(body.days).toHaveLength(30);
      expect(body.window.end).toBe(summary.date);
      expect(body.metrics).toEqual(expect.arrayContaining([
        { id: "steps", label: "Steps", unit: "steps" },
        { id: "sleep_total", label: "Total Sleep", unit: "hours" },
      ]));
      expect(body.days.at(-1)).toMatchObject({ date: summary.date, status: "available",
        values: { steps: summary.activity.steps, sleep_total: 7.75 } });
      expect(body.days[0]).toMatchObject({ status: "not_uploaded",
        values: { steps: null, sleep_total: null, resting_heart_rate: null } });
      expect(body).not.toHaveProperty("healthkit_record_archive");
      expect(body.days.at(-1).values).not.toHaveProperty("providers");
      const replacement = { ...fixture, exported_at: "2026-03-20T12:00:00Z",
        records: [{ ...summary, activity: { ...summary.activity, steps: 0 } }] };
      expect((await worker.fetch(new Request(`${fakeOrigin}/api/v1/exports`, {
        method: "POST", headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json" },
        body: JSON.stringify(replacement),
      }), env)).status).toBe(201);
      const updated = JSON.parse((await req("/api/dashboard/trends", cookie)).body);
      expect(updated.days.at(-1).values.steps).toBe(0);
      const current = db.connection.prepare(`SELECT e.object_key AS objectKey FROM daily_records d
        JOIN exports e ON e.id = d.export_id WHERE d.owner_date = ?`).get(summary.date) as { objectKey: string };
      const storedPath = join(directory, "objects", current.objectKey);
      const original = readFileSync(storedPath);
      const tampered = Buffer.from(original);
      tampered[tampered.length - 1] ^= 1;
      writeFileSync(storedPath, tampered);
      expect((await req("/api/dashboard/trends", cookie)).status).toBe(503);
      writeFileSync(storedPath, original);
      const unsupported = { ...fixture, source: "android", daily_record_schema_version: 4,
        exported_at: "2026-03-21T12:00:00Z",
        records: [{ schema: "healthmd.health_data", schema_version: 4, date: summary.date }] };
      expect((await worker.fetch(new Request(`${fakeOrigin}/api/v1/exports`, {
        method: "POST", headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json" },
        body: JSON.stringify(unsupported),
      }), env)).status).toBe(201);
      expect(JSON.parse((await req("/api/dashboard/trends", cookie)).body).days.at(-1))
        .toMatchObject({ status: "unsupported_profile", values: { steps: null, sleep_total: null } });
      expect(JSON.parse((await req("/api/exports", cookie)).body).days)
        .toMatchObject([{ date: summary.date, source: "android" }]);
      expect((await req("/api/dashboard/trends?date=2026-03-15", cookie)).status).toBe(400);
      expect((await req("/api/dashboard/trends", cookie, "Bearer invalid")).status).toBe(200);
    } finally { await account.close(); accountDb.close(); db.close(); }
  }, 30_000);

  it("isolates public write-only ingestion from the private writer and account APIs", async () => {
    const { env, db, directory } = createTestEnv("personal-mvp");
    const { env: apiEnv, db: apiDb } = createVmEnvironment({
      dataDirectory: directory, sourceDirectory,
      publicOrigin: "https://api.example.test", identityKey: env.IDENTITY_KEY_B64,
      exportKeys: env.EXPORT_ENCRYPTION_KEYS_JSON ?? "", currentKeyId: "v1",
      passwordPepper: env.PASSWORD_PEPPER_B64 ?? "", personalMvp: true,
      revisionRetention: "unlimited",
    });
    await createSingleUserAccount(env, "pilot", email, fakePassword);
    const writer = await startVmServer(env, 0);
    const api = await startVmServer(apiEnv, 0, "ingest");
    const request = (path: string, method = "GET", body?: unknown, cookie?: string,
      token?: string, host = "api.example.test", contentType = "application/json") =>
      proxiedRequest(api.port, path, method, body, cookie, "https://api.example.test", false,
        host, token ? `Bearer ${token}` : undefined, contentType);
    try {
      const login = await proxiedRequest(writer.port, "/api/auth/password-login", "POST",
        { username: "pilot", password: fakePassword });
      expect(login.status).toBe(200);
      const cookie = (login.headers["set-cookie"] as string[] | undefined)?.[0]?.split(";")[0];
      expect(cookie).toBeDefined();
      const create = await proxiedRequest(writer.port, "/api/ingest-tokens", "POST",
        { name: "Synthetic phone" }, cookie);
      expect(create.status).toBe(201);
      const token = JSON.parse(create.body).token as string;
      const id = (db.connection.prepare("SELECT id FROM users").get() as { id: string }).id;
      const readToken = createReadToken(db.connection, id, "Synthetic read-only client").token;
      const fixture = JSON.parse(readFileSync(resolve(sourceDirectory,
        "../apple/docs/reference/generated/automation/api-export-v1.json"), "utf8"));
      await Promise.all(Array.from({ length: 4 }, () => abortProxiedUpload(api.port, token)));
      await new Promise((done) => setTimeout(done, 100));
      expect((await request("/api/v1/exports", "POST", fixture, cookie)).status).toBe(401);
      expect((await request("/health")).status).toBe(200);
      expect((await request("/api/runtime")).status).toBe(404);
      expect((await request("/login")).status).toBe(404);
      expect((await request("/dashboard")).status).toBe(404);
      expect((await request("/api/account", "GET", undefined, cookie, token)).status).toBe(404);
      expect((await request("/api/exports", "GET", undefined, cookie, token)).status).toBe(404);
      expect((await request("/api/dashboard/trends", "GET", undefined, cookie, token)).status).toBe(404);
      expect((await request("/api/explore/catalog", "GET", undefined, cookie, token)).status).toBe(404);
      expect((await request("/api/explore/chart", "POST", {}, cookie, token)).status).toBe(404);
      expect((await request("/api/explore/exports", "POST", {}, cookie, token)).status).toBe(404);
      expect((await request("/api/explore/node", "POST", {}, cookie, token)).status).toBe(404);
      expect((await request("/api/ingest-tokens", "POST", {}, cookie, token)).status).toBe(404);
      expect((await request("/api/auth/password-login", "POST", {}, cookie)).status).toBe(404);
      expect((await request("/mcp", "POST", {}, undefined, token)).status).toBe(404);
      expect((await request("/api/v1/exports", "GET", undefined, undefined, token)).status).toBe(404);
      expect((await request("/api/v1/exports", "POST", fixture, undefined, token,
        "wrong.example.test")).status).toBe(421);
      expect((await request("/api/v1/exports", "POST", fixture, cookie)).status).toBe(401);
      expect((await request("/api/v1/exports", "POST", fixture, undefined, readToken)).status).toBe(401);
      expect((await request("/api/v1/exports", "POST", fixture, undefined, token,
        "api.example.test", "application/x-ndjson")).status).toBe(415);
      const accepted = await request("/api/v1/exports", "POST", fixture, cookie, token);
      expect(accepted.status).toBe(201);
      expect(accepted.headers["cache-control"]).toBe("no-store");
      expect(accepted.headers["set-cookie"]).toBeUndefined();
      const duplicate = await request("/api/v1/exports", "POST", fixture, undefined, token);
      expect(duplicate.status).toBe(200);
      expect(JSON.parse(duplicate.body)).toMatchObject({ accepted: true, duplicate: true });
      expect(db.connection.prepare("SELECT COUNT(*) AS n FROM exports").get()).toMatchObject({ n: 1 });
      expect((await proxiedRequest(writer.port, "/api/exports", "GET", undefined, cookie)).status).toBe(200);
    } finally { await api.close(); await writer.close(); apiDb.close(); db.close(); }
  }, 30_000);

  it("exposes only account routes and issues/revokes full-export credentials after reauthentication", async () => {
    const { env, db, directory } = createTestEnv("personal-mvp");
    const { env: accountEnv, db: accountDb } = createVmEnvironment({
      dataDirectory: directory, sourceDirectory,
      publicOrigin: "https://account.example.test", identityKey: env.IDENTITY_KEY_B64,
      exportKeys: env.EXPORT_ENCRYPTION_KEYS_JSON ?? "", currentKeyId: "v1",
      passwordPepper: env.PASSWORD_PEPPER_B64 ?? "", personalMvp: true,
      revisionRetention: "unlimited",
    });
    accountEnv.EXPORT_ENDPOINT_ORIGIN = fakeOrigin;
    await createSingleUserAccount(env, "pilot", email, fakePassword);
    const user = db.connection.prepare("SELECT id FROM users").get() as { id: string };
    const otherId = randomUUID();
    db.connection.prepare(`INSERT INTO users (id, email_lookup, email_ciphertext, email_iv, status, created_at)
      VALUES (?, ?, 'synthetic', 'synthetic', 'active', ?)`).run(otherId, randomUUID(), new Date().toISOString());
    const other = createReadToken(db.connection, otherId, "Other agent");
    const account = await startVmServer(accountEnv, 0, "account");
    const req = (path: string, method = "GET", body?: unknown, cookie?: string,
      origin = "https://account.example.test", intent = true) =>
      proxiedRequest(account.port, path, method, body, cookie, origin, intent, "account.example.test");
    try {
      expect((await req("/api/v1/exports", "POST", {})).status).toBe(404);
      expect((await req("/api/auth/request-link", "POST", {})).status).toBe(404);
      expect((await req("/dashboard")).status).toBe(303);
      expect((await req("/api/agent-tokens")).status).toBe(401);
      expect((await req("/api/exports/page/0")).status).toBe(401);
      expect((await req("/api/dashboard/trends")).status).toBe(401);
      expect((await req("/api/agent-tokens", "POST", {})).status).toBe(401);
      expect(JSON.parse((await req("/api/runtime")).body)).toMatchObject({
        unbackedPersonalMvp: true, exportEndpoint: `${fakeOrigin}/api/v1/exports`,
      });
      accountEnv.EXPORT_ENDPOINT_ORIGIN = "https://api.example.test";
      expect(JSON.parse((await req("/api/runtime")).body)).toMatchObject({
        exportEndpoint: "https://api.example.test/api/v1/exports",
      });
      const login = await req("/api/auth/password-login", "POST",
        { username: "pilot", password: fakePassword });
      expect(login.status).toBe(200);
      const cookie = (login.headers["set-cookie"] as string[] | undefined)?.[0]?.split(";")[0];
      expect(cookie).toBeDefined();
      expect(JSON.parse((await req("/api/exports/page/0", "GET", undefined, cookie)).body))
        .toMatchObject({ exports: [], nextOffset: null });
      expect(JSON.parse((await req("/api/days/page/0", "GET", undefined, cookie)).body))
        .toMatchObject({ days: [], nextOffset: null });
      expect(JSON.parse((await req("/api/dashboard/trends", "GET", undefined, cookie)).body))
        .toMatchObject({ version: 1, window: { start: null, end: null }, days: [] });
      expect((await req("/api/dashboard/trends", "GET", undefined, undefined,
        "https://account.example.test", true)).status).toBe(401);
      expect((await req("/api/exports/page/1000001", "GET", undefined, cookie)).status).toBe(400);
      expect((await req("/api/agent-tokens", "POST", {}, cookie,
        "https://other.example.test")).status).toBe(403);
      const input = { label: "Synthetic model", days: 30, password: fakePassword,
        consent: true, scope: "full_export" };
      expect((await req("/api/agent-tokens", "POST", { ...input, consent: false }, cookie)).status).toBe(400);
      expect((await req("/api/agent-tokens", "POST", { ...input, password: "wrong" }, cookie)).status).toBe(401);
      const created = await req("/api/agent-tokens", "POST", input, cookie);
      expect(created.status).toBe(201);
      expect(created.headers["cache-control"]).toBe("no-store");
      const issued = JSON.parse(created.body) as { id: string; token: string; scope: string };
      expect(issued.token).toMatch(/^hmd_read_[A-Za-z0-9_-]{43}$/u);
      expect(issued.scope).toBe("full_export");
      const readOnly = new DatabaseSync(join(directory, "cloud.sqlite"), { readOnly: true });
      readOnly.exec("PRAGMA query_only = ON");
      try {
        expect(authenticateReadToken(readOnly, `Bearer ${issued.token}`)).toMatchObject({
          userId: user.id, tokenId: issued.id, scope: "full_export",
        });
        expect(JSON.stringify(db.connection.prepare("SELECT * FROM mcp_read_tokens").all()))
          .not.toContain(issued.token);
        const inventory = await req("/api/agent-tokens", "GET", undefined, cookie);
        expect(inventory.body).not.toContain(issued.token);
        expect(JSON.parse(inventory.body).tokens).toHaveLength(1);
        expect((await req(`/api/agent-tokens/${other.id}`, "DELETE", undefined, cookie)).status).toBe(404);
        expect(authenticateReadToken(readOnly, `Bearer ${other.token}`)).toMatchObject({ userId: otherId });
        expect((await req(`/api/agent-tokens/${issued.id}`, "DELETE", undefined, cookie)).status).toBe(200);
        expect(authenticateReadToken(readOnly, `Bearer ${issued.token}`)).toBeNull();
      } finally { readOnly.close(); }
      expect((await req(`/api/agent-tokens/${issued.id}`, "DELETE", undefined, cookie)).status).toBe(200);
      expect((await req("/api/v1/exports", "POST", {}, cookie)).status).toBe(404);
    } finally { await account.close(); accountDb.close(); db.close(); }
  }, 30_000);
});
