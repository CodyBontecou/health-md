import { afterEach, describe, expect, it } from "vitest";
import { randomBytes, randomUUID } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync, statSync, unlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { resolve, join } from "node:path";
import { request as httpRequest } from "node:http";
import { createVmEnvironment } from "../vm/runtime";
import { createSingleUserAccount } from "../vm/bootstrap";
import { startVmServer } from "../vm/server";
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
  cookie?: string, origin = `http://preview.tailnet.test:18788`, intent = true) {
  const payload = body === undefined ? undefined : JSON.stringify(body);
  return new Promise<{ status: number; headers: Record<string, string | string[] | undefined>; body: string }>(
    (done, fail) => {
      const request = httpRequest({ host: "127.0.0.1", port, path, method, headers: {
        Host: "preview.tailnet.test:18788",
        "X-Forwarded-Proto": "https",
        "X-Forwarded-Host": "preview.tailnet.test:18788",
        "X-Forwarded-For": "100.64.0.23",
        ...(payload === undefined ? {} : { "Content-Type": "application/json" }),
        ...(method === "GET" ? {} : { Origin: origin, ...(intent ? { "X-HealthMd-Intent": "dashboard" } : {}) }),
        ...(cookie ? { Cookie: cookie } : {}),
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
        { password: fakePassword, confirmation: "DELETE" }, cookie);
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
});
