import { afterEach, expect, it } from "vitest";
import { randomBytes, randomUUID } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import worker from "../src/index";
import { issueSession } from "../src/auth";
import { createVmEnvironment } from "../vm/runtime";
import { createSingleUserAccount } from "../vm/bootstrap";

const roots: string[] = [];
const sourceDirectory = resolve(import.meta.dirname, "..");
const origin = "https://account.example.test";
function secret(): string { return Buffer.from(randomBytes(32)).toString("base64"); }

function tarEntries(archive: Uint8Array): Map<string, Uint8Array> {
  const entries = new Map<string, Uint8Array>();
  let offset = 0;
  while (offset + 512 <= archive.byteLength) {
    const header = archive.slice(offset, offset + 512);
    if (header.every((byte) => byte === 0)) break;
    const zero = header.indexOf(0);
    const name = new TextDecoder().decode(header.slice(0, zero < 0 ? 100 : zero));
    const sizeText = new TextDecoder().decode(header.slice(124, 136)).replace(/\0.*$/u, "").trim();
    const size = Number.parseInt(sizeText, 8);
    expect(Number.isSafeInteger(size)).toBe(true);
    offset += 512;
    entries.set(name, archive.slice(offset, offset + size));
    offset += size + (512 - size % 512) % 512;
  }
  return entries;
}

async function cookie(env: ReturnType<typeof createVmEnvironment>["env"], userId: string): Promise<string> {
  const response = await issueSession(env, userId);
  return response.headers.get("set-cookie")?.split(";", 1)[0] ?? "";
}

afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

it("streams paged owner-only TAR archives with exact verified legacy and account-key bytes", async () => {
  const directory = mkdtempSync(join(tmpdir(), "healthmd-portability-"));
  roots.push(directory);
  const { env, db } = createVmEnvironment({
    dataDirectory: directory,
    sourceDirectory,
    publicOrigin: origin,
    identityKey: secret(),
    exportKeys: JSON.stringify({ v1: secret() }),
    currentKeyId: "v1",
    passwordPepper: secret(),
    revisionRetention: 30,
    approved: true,
  });
  try {
    await createSingleUserAccount(env, "synthetic-owner", "owner@example.test",
      "synthetic-password-not-for-production");
    const owner = db.connection.prepare("SELECT id FROM users").get() as { id: string };
    const ownerCookie = await cookie(env, owner.id);
    const tokenResponse = await worker.fetch(new Request(`${origin}/api/ingest-tokens`, {
      method: "POST", headers: { Origin: origin, Cookie: ownerCookie, "Content-Type": "application/json" },
      body: JSON.stringify({ name: "Synthetic phone" }),
    }), env);
    const token = (await tokenResponse.json() as { token: string }).token;
    const fixture = readFileSync(resolve(sourceDirectory,
      "../apple/docs/reference/generated/automation/api-export-v1.json"), "utf8");
    const originals: string[] = [];
    for (let index = 0; index < 6; index += 1) {
      if (index === 1) {
        env.ACCOUNT_KEY_MODE = "per_account";
        env.CURRENT_ACCOUNT_WRAPPING_KEY_ID = "kek-v1";
        env.ACCOUNT_KEY_WRAPPING_KEYS_JSON = JSON.stringify({ "kek-v1": secret() });
      }
      const exact = `${fixture}${" ".repeat(index + 1)}`;
      originals.push(exact);
      const upload = await worker.fetch(new Request(`${origin}/api/v1/exports`, {
        method: "POST", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        body: exact,
      }), env);
      expect(upload.status).toBe(201);
    }

    const first = await worker.fetch(new Request(`${origin}/api/account/export/page/1`, {
      headers: { Cookie: ownerCookie },
    }), env);
    expect(first.status).toBe(200);
    expect(first.headers.get("content-type")).toBe("application/x-tar");
    expect(first.headers.get("content-disposition")).toContain("page-000001.tar");
    const firstEntries = tarEntries(new Uint8Array(await first.arrayBuffer()));
    expect(firstEntries.size).toBe(6);
    const firstManifest = JSON.parse(new TextDecoder().decode(firstEntries.get("manifest.json"))) as {
      totalExports: number; totalPages: number; nextPage: number; files: Array<{ filename: string }>
    };
    expect(firstManifest).toMatchObject({ totalExports: 6, totalPages: 2, nextPage: 2 });
    expect(firstManifest.files).toHaveLength(5);
    const recovered = firstManifest.files.map((entry) =>
      new TextDecoder().decode(firstEntries.get(entry.filename)));

    const second = await worker.fetch(new Request(`${origin}/api/account/export/page/2`, {
      headers: { Cookie: ownerCookie },
    }), env);
    const secondEntries = tarEntries(new Uint8Array(await second.arrayBuffer()));
    const secondManifest = JSON.parse(new TextDecoder().decode(secondEntries.get("manifest.json"))) as {
      nextPage: null; files: Array<{ filename: string }>
    };
    expect(secondManifest.nextPage).toBeNull();
    recovered.push(new TextDecoder().decode(secondEntries.get(secondManifest.files[0]!.filename)));
    expect(recovered.sort()).toEqual([...originals].sort());
    expect((await worker.fetch(new Request(`${origin}/api/account/export/page/3`, {
      headers: { Cookie: ownerCookie },
    }), env)).status).toBe(404);

    const otherId = randomUUID();
    db.connection.prepare(`INSERT INTO users
      (id, email_lookup, email_ciphertext, email_iv, status, created_at)
      VALUES (?, ?, 'synthetic', 'synthetic', 'active', ?)`).run(otherId, randomUUID(), new Date().toISOString());
    const otherCookie = await cookie(env, otherId);
    const other = await worker.fetch(new Request(`${origin}/api/account/export/page/1`, {
      headers: { Cookie: otherCookie },
    }), env);
    const otherEntries = tarEntries(new Uint8Array(await other.arrayBuffer()));
    const otherManifest = JSON.parse(new TextDecoder().decode(otherEntries.get("manifest.json"))) as {
      totalExports: number; files: unknown[]
    };
    expect(otherManifest).toMatchObject({ totalExports: 0, files: [] });

    const objectKey = (db.connection.prepare(
      "SELECT object_key AS objectKey FROM exports ORDER BY received_at, id LIMIT 1")
      .get() as { objectKey: string }).objectKey;
    // Simulate provider-side corruption without relying on a same-key overwrite;
    // normal ciphertext publication is intentionally create-only.
    await env.EXPORTS.delete(objectKey);
    await env.EXPORTS.put(objectKey, new Uint8Array([1, 2, 3]));
    const corrupt = await worker.fetch(new Request(`${origin}/api/account/export/page/1`, {
      headers: { Cookie: ownerCookie },
    }), env);
    await expect(corrupt.arrayBuffer()).rejects.toThrow();
  } finally { db.close(); }
});
