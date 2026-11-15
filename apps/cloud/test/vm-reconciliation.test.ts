import { afterEach, expect, it, vi } from "vitest";
import { randomBytes, randomUUID } from "node:crypto";
import { request as httpRequest } from "node:http";
import { mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { lstat, open, readdir, unlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { issueSession } from "../src/auth";
import { acquireUploadAdmission, markUploadObjectWritten, reconcileUploadIntents,
  reserveUploadIntent } from "../src/upload-intents";
import worker from "../src/index";
import { createVmEnvironment } from "../vm/runtime";
import { createSingleUserAccount } from "../vm/bootstrap";
import { startVmServer } from "../vm/server";
import { VmDatabase, VmObjectStore } from "../vm/storage";

// Pause real filesystem operations at precise interleavings, not a fake DB
// snapshot. Both HTTP listeners use separate connections to the same SQLite DB.
vi.mock("node:fs/promises", async (importOriginal) => {
  const fs = await importOriginal<typeof import("node:fs/promises")>();
  return { ...fs, readdir: vi.fn(fs.readdir), open: vi.fn(fs.open),
    lstat: vi.fn(fs.lstat), unlink: vi.fn(fs.unlink) };
});
const realFs = await vi.importActual<typeof import("node:fs/promises")>("node:fs/promises");
const roots: string[] = [];
const sourceDirectory = resolve(import.meta.dirname, "..");
const origin = "https://writer.example.test:18788";
const apiOrigin = "https://api.example.test";

function barrier() {
  let release!: () => void;
  const promise = new Promise<void>((done) => { release = done; });
  return { promise, release };
}

async function setup() {
  const directory = mkdtempSync(join(tmpdir(), "healthmd-vm-reconcile-synthetic-"));
  roots.push(directory);
  const secret = () => Buffer.from(randomBytes(32)).toString("base64");
  const config = { dataDirectory: directory, sourceDirectory, publicOrigin: origin,
    identityKey: secret(), exportKeys: JSON.stringify({ v1: secret() }), currentKeyId: "v1",
    passwordPepper: secret(), revisionRetention: "unlimited" as const, personalMvp: true };
  const runtime = createVmEnvironment(config);
  await createSingleUserAccount(runtime.env, "synthetic-owner", "owner@example.test",
    "synthetic-password-not-for-production");
  const user = runtime.db.connection.prepare("SELECT id FROM users").get() as { id: string };
  const session = await issueSession(runtime.env, user.id);
  const cookie = session.headers.get("set-cookie")!.split(";", 1)[0]!;
  const response = await worker.fetch(new Request(`${origin}/api/ingest-tokens`, {
    method: "POST", headers: { Origin: origin, Cookie: cookie, "Content-Type": "application/json" },
    body: JSON.stringify({ name: "Synthetic phone" }),
  }), runtime.env);
  expect(response.status).toBe(201);
  const token = await response.json() as { id: string; token: string };
  return { ...runtime, directory, config, cookie, token: token.token,
    principal: { userId: user.id, tokenId: token.id } };
}

async function reserve(runtime: Awaited<ReturnType<typeof setup>>) {
  const admission = await acquireUploadAdmission(runtime.env, runtime.principal);
  return reserveUploadIntent(runtime.env, runtime.principal, admission, "a".repeat(64), null, 100);
}

async function upload(port: number, token: string): Promise<Response> {
  const body = readFileSync(resolve(sourceDirectory,
    "../apple/docs/reference/generated/automation/api-export-v1.json"), "utf8");
  return new Promise((done, fail) => {
    const request = httpRequest({ host: "127.0.0.1", port, path: "/api/v1/exports", method: "POST",
      headers: { Host: new URL(apiOrigin).host, "X-Forwarded-Host": new URL(apiOrigin).host,
        "X-Forwarded-Proto": "https", Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    }, (response) => {
      const chunks: Uint8Array[] = [];
      response.on("data", (chunk: Uint8Array) => chunks.push(chunk));
      response.on("end", () => done(new Response(Uint8Array.from(Buffer.concat(chunks)).buffer,
        { status: response.statusCode ?? 0 })));
    });
    request.on("error", fail);
    request.end(body);
  });
}

async function listeners(runtime: Awaited<ReturnType<typeof setup>>) {
  const apiRuntime = createVmEnvironment({ ...runtime.config, publicOrigin: apiOrigin });
  const writer = await startVmServer(runtime.env, 0);
  const api = await startVmServer(apiRuntime.env, 0, "ingest");
  return { writer, api, close: async () => {
    await api.close(); await writer.close(); apiRuntime.db.close(); runtime.db.close();
  } };
}

afterEach(() => {
  vi.restoreAllMocks();
  vi.mocked(readdir).mockReset().mockImplementation(realFs.readdir);
  vi.mocked(open).mockReset().mockImplementation(realFs.open);
  vi.mocked(lstat).mockReset().mockImplementation(realFs.lstat);
  vi.mocked(unlink).mockReset().mockImplementation(realFs.unlink);
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

it.each(["before", "after"])("retains an accepted public upload published %s the directory snapshot", async (when) => {
  const runtime = await setup();
  const services = await listeners(runtime);
  const entered = barrier();
  const resume = barrier();
  vi.mocked(readdir).mockImplementationOnce(async (...args) => {
    const names = when === "after" ? await realFs.readdir(...args) : null;
    entered.release();
    await resume.promise;
    return names ?? realFs.readdir(...args);
  });
  const maintenance = services.writer.runMaintenance(() => runtime.objects.reconcile(runtime.db).then((n) => {
    expect(n).toBe(0);
  }));
  try {
    await entered.promise;
    const accepted = await upload(services.api.port, runtime.token);
    expect(accepted.status).toBe(201);
    const { id } = await accepted.json() as { id: string };
    resume.release();
    expect(await maintenance).toBe(true);
    const row = runtime.db.connection.prepare("SELECT object_key AS objectKey FROM exports WHERE id = ?")
      .get(id) as { objectKey: string };
    expect(await runtime.objects.get(row.objectKey)).not.toBeNull();
    const download = await worker.fetch(new Request(`${origin}/api/exports/${id}/download`, {
      headers: { Cookie: runtime.cookie },
    }), runtime.env);
    expect(download.status).toBe(200);
    expect(await download.text()).toBe(readFileSync(resolve(sourceDirectory,
      "../apple/docs/reference/generated/automation/api-export-v1.json"), "utf8"));
    expect(await runtime.objects.reconcile(runtime.db)).toBe(0);
  } finally {
    resume.release();
    await maintenance.catch(() => undefined);
    await services.close();
  }
});

it("preserves a public listener's open staging file during writer maintenance", async () => {
  const runtime = await setup();
  const services = await listeners(runtime);
  const entered = barrier();
  const resume = barrier();
  let stagingPath = "";
  vi.mocked(open).mockImplementationOnce(async (...args) => {
    const file = await realFs.open(...args);
    stagingPath = String(args[0]);
    const write = file.writeFile.bind(file);
    vi.spyOn(file, "writeFile").mockImplementationOnce(async (...writeArgs) => {
      entered.release(); await resume.promise; return write(...writeArgs);
    });
    return file;
  });
  const pending = upload(services.api.port, runtime.token);
  try {
    await entered.promise;
    const intent = runtime.db.connection.prepare("SELECT object_key AS objectKey, state FROM upload_intents")
      .get() as { objectKey: string; state: string };
    expect(intent.state).toBe("reserved");
    expect(stagingPath).toContain(`.write-${intent.objectKey.slice(3)}-`);
    expect(await services.writer.runMaintenance(async () => {
      expect(await runtime.objects.reconcile(runtime.db)).toBe(0);
    })).toBe(true);
    expect(statSync(stagingPath).isFile()).toBe(true);
    resume.release();
    const accepted = await pending;
    expect(accepted.status).toBe(201);
    await accepted.arrayBuffer();
    expect(await runtime.objects.reconcile(runtime.db)).toBe(0);
    expect(readdirSync(join(runtime.directory, "objects", "v1")))
      .toEqual([intent.objectKey.slice(3)]);
  } finally {
    resume.release();
    await pending.catch(() => undefined);
    await services.close();
  }
});

it.each(["reserved", "aborting"])("restarts with a valid %s intent without ciphertext and releases its expired quota", async (state) => {
  const runtime = await setup();
  const intent = await reserve(runtime);
  if (state === "aborting") {
    // Crash after claiming abandonment and removing the staged ciphertext,
    // but before deleting the intent and releasing its quota.
    await runtime.objects.put(intent.objectKey, new Uint8Array([1, 2, 3]));
    await markUploadObjectWritten(runtime.env, intent);
    runtime.db.connection.prepare("UPDATE upload_intents SET state = 'aborting' WHERE id = ?").run(intent.id);
    await runtime.objects.delete(intent.objectKey);
  }
  runtime.db.close();
  const restarted = createVmEnvironment(runtime.config);
  try {
    // Match writer startup: scheduled cleanup followed by filesystem integrity.
    await worker.scheduled({} as ScheduledEvent, restarted.env);
    expect(await restarted.objects.reconcile(restarted.db)).toBe(0);
    expect(restarted.db.connection.prepare("SELECT reserved_bytes FROM account_storage").get())
      .toMatchObject({ reserved_bytes: 100 });
    expect(await reconcileUploadIntents(restarted.env, 25, new Date(Date.parse(intent.expiresAt) + 1)))
      .toMatchObject({ expired: 1 });
    expect(await restarted.objects.reconcile(restarted.db)).toBe(0);
    expect(restarted.db.connection.prepare("SELECT reserved_bytes FROM account_storage").get())
      .toMatchObject({ reserved_bytes: 0 });
  } finally { restarted.db.close(); }
});

it("retains referenced crash files, then removes keyed and legacy staging leftovers after intent cleanup", async () => {
  const runtime = await setup();
  try {
    const intent = await reserve(runtime);
    await runtime.objects.put(intent.objectKey, new Uint8Array([1, 2, 3]));
    await markUploadObjectWritten(runtime.env, intent);
    const directory = join(runtime.directory, "objects", "v1");
    const staged = `.write-${intent.objectKey.slice(3)}-${randomUUID()}`;
    const legacy = `.write-${randomUUID()}`;
    const orphan = `.write-${randomUUID()}-${randomUUID()}`;
    for (const name of [staged, legacy, orphan]) {
      writeFileSync(join(directory, name), new Uint8Array([4, 5]), { mode: 0o600 });
    }
    expect(await runtime.objects.reconcile(runtime.db)).toBe(1);
    expect(readdirSync(directory).sort()).toEqual([intent.objectKey.slice(3), staged, legacy].sort());
    expect(await reconcileUploadIntents(runtime.env, 25, new Date(Date.parse(intent.expiresAt) + 1)))
      .toMatchObject({ expired: 1 });
    expect(await runtime.objects.reconcile(runtime.db)).toBe(2);
    expect(readdirSync(directory)).toEqual([]);
  } finally { runtime.db.close(); }
});

it.each(["stat", "unlink"])("tolerates a temporary file disappearing during %s", async (operation) => {
  const root = mkdtempSync(join(tmpdir(), "healthmd-vm-reconcile-synthetic-"));
  roots.push(root);
  const db = new VmDatabase(root, join(sourceDirectory, "migrations"));
  const objects = new VmObjectStore(root);
  try {
    await objects.put(`v1/${randomUUID()}`, new Uint8Array([1, 2, 3]));
    const path = join(root, "objects", "v1", `.write-${randomUUID()}-${randomUUID()}`);
    writeFileSync(path, new Uint8Array([4, 5]), { mode: 0o600 });
    if (operation === "stat") {
      vi.mocked(lstat).mockImplementation(async (...args) => {
        if (String(args[0]) === path) await realFs.unlink(path);
        return realFs.lstat(...args);
      });
    } else {
      vi.mocked(unlink).mockImplementation(async (...args) => {
        if (String(args[0]) === path) await realFs.unlink(path);
        return realFs.unlink(...args);
      });
    }
    expect(await objects.reconcile(db)).toBe(1); // Only the actual orphan removal is counted.
    expect(readdirSync(join(root, "objects", "v1"))).toEqual([]);
  } finally { db.close(); }
});

it("fails closed for missing object-written ciphertext and unsafe or unknown files", async () => {
  const runtime = await setup();
  try {
    const intent = await reserve(runtime);
    await markUploadObjectWritten(runtime.env, intent);
    await expect(runtime.objects.reconcile(runtime.db)).rejects.toThrow(/missing ciphertext/u);
    const directory = join(runtime.directory, "objects", "v1");
    const unknown = join(directory, "unexpected");
    writeFileSync(unknown, new Uint8Array([1]), { mode: 0o600 });
    await expect(runtime.objects.reconcile(runtime.db)).rejects.toThrow(/Unknown object-directory entry/u);
    rmSync(unknown);
    const unsafe = join(directory, randomUUID());
    writeFileSync(unsafe, new Uint8Array([1]), { mode: 0o600 });
    // An encrypted-file symlink must never be followed or deleted by scanning.
    await realFs.unlink(unsafe);
    await realFs.symlink(join(runtime.directory, "cloud.sqlite"), unsafe);
    await expect(runtime.objects.reconcile(runtime.db)).rejects.toThrow(/Unsafe encrypted object file/u);
    expect(statSync(join(runtime.directory, "cloud.sqlite")).isFile()).toBe(true);
  } finally { runtime.db.close(); }
});
