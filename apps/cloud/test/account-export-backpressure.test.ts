import { afterEach, expect, it, vi } from "vitest";
import { randomBytes } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { issueSession } from "../src/auth";
import worker from "../src/index";
import { createVmEnvironment } from "../vm/runtime";
import { createSingleUserAccount } from "../vm/bootstrap";

const roots: string[] = [];
const sourceDirectory = resolve(import.meta.dirname, "..");
const origin = "https://account.example.test";
const tick = () => new Promise<void>((done) => setImmediate(done));
function barrier() {
  let release!: () => void;
  const promise = new Promise<void>((done) => { release = done; });
  return { promise, release };
}

async function setup() {
  const directory = mkdtempSync(join(tmpdir(), "healthmd-tar-backpressure-synthetic-"));
  roots.push(directory);
  const secret = () => Buffer.from(randomBytes(32)).toString("base64");
  const { env, db } = createVmEnvironment({ dataDirectory: directory, sourceDirectory,
    publicOrigin: origin, identityKey: secret(), exportKeys: JSON.stringify({ v1: secret() }),
    currentKeyId: "v1", passwordPepper: secret(), revisionRetention: 30, approved: true });
  await createSingleUserAccount(env, "synthetic-owner", "owner@example.test",
    "synthetic-password-not-for-production");
  const user = db.connection.prepare("SELECT id FROM users").get() as { id: string };
  const session = await issueSession(env, user.id);
  const cookie = session.headers.get("set-cookie")!.split(";", 1)[0]!;
  const issued = await worker.fetch(new Request(`${origin}/api/ingest-tokens`, {
    method: "POST", headers: { Origin: origin, Cookie: cookie, "Content-Type": "application/json" },
    body: JSON.stringify({ name: "Synthetic portability phone" }),
  }), env);
  const token = (await issued.json() as { token: string }).token;
  const fixture = readFileSync(resolve(sourceDirectory,
    "../apple/docs/reference/generated/automation/api-export-v1.json"), "utf8");
  const originals = new Map<string, Uint8Array>();
  for (let index = 0; index < 5; index += 1) {
    const original = `${fixture}${" ".repeat(128 * 1024 + index)}`;
    const accepted = await worker.fetch(new Request(`${origin}/api/v1/exports`, {
      method: "POST", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: original,
    }), env);
    expect(accepted.status).toBe(201);
    originals.set((await accepted.json() as { id: string }).id, new TextEncoder().encode(original));
  }
  const request = () => worker.fetch(new Request(`${origin}/api/account/export/page/1`, {
    headers: { Cookie: cookie },
  }), env);
  return { env, db, request, originals };
}

async function chunk(reader: ReadableStreamDefaultReader<Uint8Array>): Promise<Uint8Array> {
  const result = await reader.read();
  expect(result.done).toBe(false);
  expect(result.value!.byteLength).toBeLessThanOrEqual(64 * 1024);
  return result.value!;
}

async function entry(reader: ReadableStreamDefaultReader<Uint8Array>) {
  const header = await chunk(reader);
  expect(header.byteLength).toBe(512);
  const name = new TextDecoder().decode(header.subarray(0, header.indexOf(0)));
  const octal = (start: number, end: number) => Number.parseInt(
    new TextDecoder().decode(header.subarray(start, end)).replace(/\0.*$/u, "").trim(), 8);
  const size = octal(124, 136);
  const checksum = octal(148, 156);
  const checkHeader = header.slice();
  checkHeader.fill(0x20, 148, 156);
  expect(checkHeader.reduce((sum, byte) => sum + byte, 0)).toBe(checksum);
  const bytes = new Uint8Array(size);
  let position = 0;
  while (position < size) {
    const part = await chunk(reader);
    expect(part.byteLength).toBeLessThanOrEqual(size - position);
    bytes.set(part, position);
    position += part.byteLength;
  }
  const padding = (512 - size % 512) % 512;
  if (padding) expect(await chunk(reader)).toEqual(new Uint8Array(padding));
  return { name, bytes };
}

afterEach(() => {
  vi.restoreAllMocks();
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

it("reads nothing without demand and only one verified envelope for a paused consumer", async () => {
  const { env, db, request, originals } = await setup();
  const get = vi.spyOn(env.EXPORTS, "get");
  try {
    const response = await request();
    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toBe("no-store");
    await tick();
    expect(get).not.toHaveBeenCalled();
    const reader = response.body!.getReader();
    const manifestEntry = await entry(reader);
    const manifest = JSON.parse(new TextDecoder().decode(manifestEntry.bytes)) as {
      files: Array<{ id: string; filename: string }>
    };
    expect(manifestEntry.name).toBe("manifest.json");
    expect(manifest.files).toHaveLength(5);
    expect(get).not.toHaveBeenCalled();
    const first = await entry(reader);
    expect(first.name).toBe(manifest.files[0]!.filename);
    expect(first.bytes).toEqual(originals.get(manifest.files[0]!.id));
    await tick();
    expect(get).toHaveBeenCalledTimes(1); // No page-wide prefetch, even after the entire first entry.
    await reader.cancel();
    await tick();
    expect(get).toHaveBeenCalledTimes(1);
  } finally { db.close(); }
});

it("cancels an unread archive without any object read", async () => {
  const { env, db, request } = await setup();
  const get = vi.spyOn(env.EXPORTS, "get");
  try {
    const response = await request();
    await response.body!.cancel();
    await tick();
    expect(get).not.toHaveBeenCalled();
  } finally { db.close(); }
});

it.each(["get", "arrayBuffer"])("stops after cancellation during an in-flight object %s", async (stage) => {
  const { env, db, request } = await setup();
  const originalGet = env.EXPORTS.get.bind(env.EXPORTS);
  const entered = barrier();
  const resume = barrier();
  const finished = barrier();
  const cancelObject = vi.fn();
  let materialize = vi.fn<() => Promise<ArrayBuffer>>();
  const get = vi.spyOn(env.EXPORTS, "get").mockImplementationOnce(async (key) => {
    const object = await originalGet(key);
    if (!object) throw new Error("Synthetic test object missing");
    const originalArrayBuffer = object.arrayBuffer.bind(object);
    materialize = vi.fn(async () => {
      if (stage === "arrayBuffer") { entered.release(); await resume.promise; }
      try { return await originalArrayBuffer(); }
      finally { finished.release(); }
    });
    if (stage === "get") { entered.release(); await resume.promise; finished.release(); }
    return Object.defineProperties(object, {
      body: { value: new ReadableStream({ cancel: cancelObject }, { highWaterMark: 0 }) },
      arrayBuffer: { value: materialize },
    });
  });
  try {
    const response = await request();
    const reader = response.body!.getReader();
    await entry(reader); // Manifest only; the next pull starts the first ciphertext read.
    const pending = reader.read();
    await entered.promise;
    await reader.cancel();
    expect(await pending).toEqual({ done: true, value: undefined });
    resume.release();
    await finished.promise;
    await tick();
    expect(get).toHaveBeenCalledTimes(1);
    expect(materialize).toHaveBeenCalledTimes(stage === "get" ? 0 : 1);
    if (stage === "get") expect(cancelObject).toHaveBeenCalledOnce();
  } finally {
    resume.release();
    db.close();
  }
});
