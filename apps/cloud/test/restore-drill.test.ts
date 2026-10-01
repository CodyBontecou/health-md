import { afterEach, expect, it } from "vitest";
import { randomBytes, randomUUID } from "node:crypto";
import { chmodSync, cpSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import worker from "../src/index";
import { issueSession } from "../src/auth";
import { createVmEnvironment } from "../vm/runtime";
import { createSingleUserAccount } from "../vm/bootstrap";

const roots: string[] = [];
const sourceDirectory = resolve(import.meta.dirname, "..");
const origin = "https://restore.example.test";
function secret(): string { return Buffer.from(randomBytes(32)).toString("base64"); }

function freshRoot(label: string): string {
  const root = mkdtempSync(join(tmpdir(), `healthmd-${label}-`));
  roots.push(root);
  return root;
}

async function cookie(env: ReturnType<typeof createVmEnvironment>["env"], userId: string): Promise<string> {
  const response = await issueSession(env, userId);
  return response.headers.get("set-cookie")?.split(";", 1)[0] ?? "";
}

afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

it("restores an isolated encrypted synthetic snapshot with exact hashes and tenant isolation", async () => {
  const sourceRoot = freshRoot("restore-source");
  const backupRoot = freshRoot("restore-backup");
  const restoreRoot = freshRoot("restore-target");
  const wrongKeyRoot = freshRoot("restore-wrong-key");
  const identityKey = secret();
  const legacyKeyring = JSON.stringify({ v1: secret() });
  const passwordPepper = secret();
  const wrappingKey = secret();
  const config = {
    sourceDirectory, publicOrigin: origin, identityKey, exportKeys: legacyKeyring,
    currentKeyId: "v1", passwordPepper, revisionRetention: 30, approved: true,
  } as const;
  const source = createVmEnvironment({ ...config, dataDirectory: sourceRoot });
  let exportId = "";
  let ownerId = "";
  const fixture = readFileSync(resolve(sourceDirectory,
    "../apple/docs/reference/generated/automation/api-export-v1.json"), "utf8");
  try {
    source.env.ACCOUNT_KEY_MODE = "per_account";
    source.env.CURRENT_ACCOUNT_WRAPPING_KEY_ID = "kek-v1";
    source.env.ACCOUNT_KEY_WRAPPING_KEYS_JSON = JSON.stringify({ "kek-v1": wrappingKey });
    await createSingleUserAccount(source.env, "synthetic-owner", "owner@example.test",
      "synthetic-password-not-for-production");
    ownerId = (source.db.connection.prepare("SELECT id FROM users").get() as { id: string }).id;
    const ownerCookie = await cookie(source.env, ownerId);
    const tokenResponse = await worker.fetch(new Request(`${origin}/api/ingest-tokens`, {
      method: "POST", headers: { Origin: origin, Cookie: ownerCookie, "Content-Type": "application/json" },
      body: JSON.stringify({ name: "Synthetic restore phone" }),
    }), source.env);
    const token = (await tokenResponse.json() as { token: string }).token;
    const upload = await worker.fetch(new Request(`${origin}/api/v1/exports`, {
      method: "POST", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: fixture,
    }), source.env);
    expect(upload.status).toBe(201);
    exportId = (await upload.json() as { id: string }).id;
    expect(source.db.connection.prepare("PRAGMA integrity_check").get()).toMatchObject({ integrity_check: "ok" });
  } finally { source.db.close(); }

  // Snapshot only after the database is closed; this models a consistent encrypted backup artifact.
  rmSync(backupRoot, { recursive: true, force: true });
  cpSync(sourceRoot, backupRoot, { recursive: true, preserveTimestamps: true });
  chmodSync(backupRoot, 0o700);
  rmSync(restoreRoot, { recursive: true, force: true });
  cpSync(backupRoot, restoreRoot, { recursive: true, preserveTimestamps: true });
  chmodSync(restoreRoot, 0o700);
  const restored = createVmEnvironment({ ...config, dataDirectory: restoreRoot });
  try {
    restored.env.ACCOUNT_KEY_MODE = "per_account";
    restored.env.CURRENT_ACCOUNT_WRAPPING_KEY_ID = "kek-v1";
    restored.env.ACCOUNT_KEY_WRAPPING_KEYS_JSON = JSON.stringify({ "kek-v1": wrappingKey });
    expect(restored.db.connection.prepare("PRAGMA integrity_check").get()).toMatchObject({ integrity_check: "ok" });
    expect(restored.db.connection.prepare("SELECT COUNT(*) AS n FROM vm_migrations").get())
      .toMatchObject({ n: 17 });
    const ownerCookie = await cookie(restored.env, ownerId);
    const exact = await worker.fetch(new Request(`${origin}/api/exports/${exportId}/download`, {
      headers: { Cookie: ownerCookie },
    }), restored.env);
    expect(exact.status).toBe(200);
    expect(await exact.text()).toBe(fixture);

    const otherId = randomUUID();
    restored.db.connection.prepare(`INSERT INTO users
      (id, email_lookup, email_ciphertext, email_iv, status, created_at)
      VALUES (?, ?, 'synthetic', 'synthetic', 'active', ?)`).run(otherId, randomUUID(), new Date().toISOString());
    const otherCookie = await cookie(restored.env, otherId);
    expect((await worker.fetch(new Request(`${origin}/api/exports/${exportId}/download`, {
      headers: { Cookie: otherCookie },
    }), restored.env)).status).toBe(404);
  } finally { restored.db.close(); }

  rmSync(wrongKeyRoot, { recursive: true, force: true });
  cpSync(backupRoot, wrongKeyRoot, { recursive: true, preserveTimestamps: true });
  chmodSync(wrongKeyRoot, 0o700);
  const wrong = createVmEnvironment({ ...config, dataDirectory: wrongKeyRoot });
  try {
    wrong.env.ACCOUNT_KEY_MODE = "per_account";
    wrong.env.CURRENT_ACCOUNT_WRAPPING_KEY_ID = "kek-v1";
    wrong.env.ACCOUNT_KEY_WRAPPING_KEYS_JSON = JSON.stringify({ "kek-v1": secret() });
    const ownerCookie = await cookie(wrong.env, ownerId);
    const denied = await worker.fetch(new Request(`${origin}/api/exports/${exportId}/download`, {
      headers: { Cookie: ownerCookie },
    }), wrong.env);
    expect(denied.status).toBe(500);
    expect(await denied.text()).not.toContain("Synthetic fixture");
  } finally { wrong.db.close(); }
});
