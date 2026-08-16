import { createHash, randomBytes } from "node:crypto";
import { constants } from "node:fs";
import { chmod, lstat, mkdir, open, realpath, rename, unlink } from "node:fs/promises";
import { homedir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import type { InMemoryJsonInput } from "./loader.js";
import type { DocumentOrigin } from "./model.js";

const CACHE_SCHEMA = "healthmd.pi_dashboard_cache";
const CONFIG_SCHEMA = "healthmd.pi_dashboard_cache_config";
const MANIFEST_FILE = "healthmd-cache.json";
const MAX_MANIFEST_BYTES = 1024 * 1024;
const MAX_CACHE_ENTRIES = 256;
const MAX_RESTORED_FILES = 64;
const MAX_RESTORED_BYTES = 128 * 1024 * 1024;
const MAX_FILE_BYTES = 32 * 1024 * 1024;
const CACHE_LOCK_FILE = ".healthmd-cache.lock";
const CACHE_LOCK_WAIT_MS = 5_000;

type CacheOrigin = Extract<DocumentOrigin, "healthmd-cli" | "healthmd-mcp">;
interface CacheEntry {
  digest: string;
  file: string;
  bytes: number;
  origin: CacheOrigin;
  operation: string;
  fetched_at: string;
}
interface CacheManifest { schema: typeof CACHE_SCHEMA; schema_version: 1; entries: CacheEntry[] }
interface CacheConfig { schema: typeof CONFIG_SCHEMA; schema_version: 1; directory: string }

export interface PersistedCacheReceipt {
  directory: string;
  file: string;
  digest: string;
  entries: number;
}

function configPath(): string {
  const root = process.env.XDG_CONFIG_HOME?.trim() || join(homedir(), ".config");
  return join(root, "healthmd", "pi-dashboard.json");
}
function object(value: unknown): value is Record<string, unknown> { return value !== null && typeof value === "object" && !Array.isArray(value); }
function validDigest(value: unknown): value is string { return typeof value === "string" && /^[a-f0-9]{64}$/.test(value); }
function validEntry(value: unknown): value is CacheEntry {
  return object(value) && validDigest(value.digest) && value.file === `${value.digest}.json` && Number.isSafeInteger(value.bytes) && Number(value.bytes) >= 0 && Number(value.bytes) <= MAX_FILE_BYTES && (value.origin === "healthmd-cli" || value.origin === "healthmd-mcp") && typeof value.operation === "string" && /^[A-Za-z0-9_.-]{1,128}$/.test(value.operation) && typeof value.fetched_at === "string" && /^\d{4}-\d{2}-\d{2}T/.test(value.fetched_at) && value.fetched_at.length <= 64;
}
function parseManifest(text: string): CacheManifest {
  const value: unknown = JSON.parse(text);
  if (!object(value) || value.schema !== CACHE_SCHEMA || value.schema_version !== 1 || !Array.isArray(value.entries) || value.entries.length > MAX_CACHE_ENTRIES || !value.entries.every(validEntry)) throw new Error("Health.md cache manifest is invalid");
  return value as unknown as CacheManifest;
}
async function noFollowRead(path: string, maximum: number): Promise<Buffer> {
  const before = await lstat(path);
  if (before.isSymbolicLink() || !before.isFile()) throw new Error(`Health.md cache path is not a regular file: ${path}`);
  if (before.size > maximum) throw new Error(`Health.md cache file exceeds ${maximum} bytes: ${path}`);
  const handle = await open(path, constants.O_RDONLY | (constants.O_NOFOLLOW ?? 0));
  try {
    const opened = await handle.stat();
    if (!opened.isFile() || opened.size > maximum) throw new Error(`Health.md cache file exceeds ${maximum} bytes: ${path}`);
    const chunks: Buffer[] = [];
    let total = 0;
    for (;;) {
      const buffer = Buffer.allocUnsafe(Math.min(64 * 1024, maximum + 1 - total));
      const { bytesRead } = await handle.read(buffer, 0, buffer.length, null);
      if (bytesRead === 0) break;
      total += bytesRead;
      if (total > maximum) throw new Error(`Health.md cache file exceeds ${maximum} bytes: ${path}`);
      chunks.push(buffer.subarray(0, bytesRead));
    }
    const current = await lstat(path);
    if (opened.dev !== current.dev || opened.ino !== current.ino || current.isSymbolicLink()) throw new Error(`Health.md cache path identity changed: ${path}`);
    await handle.chmod(0o600);
    return Buffer.concat(chunks, total);
  } finally { await handle.close(); }
}
async function atomicWrite(path: string, data: string | Buffer, mode: number): Promise<void> {
  await mkdir(dirname(path), { recursive: true, mode: 0o700 });
  const temporary = join(dirname(path), `.${basename(path)}.${process.pid}.${randomBytes(8).toString("hex")}.tmp`);
  const handle = await open(temporary, constants.O_CREAT | constants.O_EXCL | constants.O_WRONLY | (constants.O_NOFOLLOW ?? 0), mode);
  try { await handle.writeFile(data); await handle.sync(); }
  catch (error) { await handle.close(); await unlink(temporary).catch(() => {}); throw error; }
  await handle.close();
  try { await rename(temporary, path); await chmod(path, mode); }
  catch (error) { await unlink(temporary).catch(() => {}); throw error; }
}
async function withCacheLock<T>(directory: string, action: () => Promise<T>): Promise<T> {
  const lockPath = join(directory, CACHE_LOCK_FILE), deadline = Date.now() + CACHE_LOCK_WAIT_MS;
  let handle: Awaited<ReturnType<typeof open>> | undefined;
  while (!handle) {
    try {
      handle = await open(lockPath, constants.O_CREAT | constants.O_EXCL | constants.O_WRONLY | (constants.O_NOFOLLOW ?? 0), 0o600);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error;
      const lock = await lstat(lockPath).catch(statError => { if ((statError as NodeJS.ErrnoException).code === "ENOENT") return undefined; throw statError; });
      if (!lock) continue;
      if (lock.isSymbolicLink() || !lock.isFile()) throw new Error("Health.md cache lock is not a regular file");
      if (Date.now() >= deadline) throw new Error(`Health.md cache is busy in another process; if no Health.md process is running, remove ${lockPath}`);
      await new Promise(resolveDelay => setTimeout(resolveDelay, 25));
    }
  }
  try { return await action(); }
  finally {
    const held = await handle.stat();
    const current = await lstat(lockPath).catch(() => undefined);
    await handle.close();
    if (current && !current.isSymbolicLink() && current.dev === held.dev && current.ino === held.ino) await unlink(lockPath).catch(() => {});
  }
}

export async function ensureCacheDirectory(path: string): Promise<string> {
  const requested = resolve(path);
  await mkdir(requested, { recursive: true, mode: 0o700 });
  const info = await lstat(requested);
  if (info.isSymbolicLink() || !info.isDirectory()) throw new Error(`Health.md cache directory is not a regular directory: ${path}`);
  const canonical = await realpath(requested);
  await chmod(canonical, 0o700);
  const objects = join(canonical, "objects");
  try { await mkdir(objects, { mode: 0o700 }); }
  catch (error) { if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error; }
  const objectsInfo = await lstat(objects);
  if (objectsInfo.isSymbolicLink() || !objectsInfo.isDirectory() || await realpath(objects) !== objects) throw new Error(`Health.md cache objects path escapes its configured directory: ${objects}`);
  await chmod(objects, 0o700);
  return canonical;
}

export async function rememberCacheDirectory(path: string): Promise<string> {
  const directory = await ensureCacheDirectory(path);
  const config: CacheConfig = { schema: CONFIG_SCHEMA, schema_version: 1, directory };
  await atomicWrite(configPath(), `${JSON.stringify(config)}\n`, 0o600);
  return directory;
}

export async function forgetCacheDirectory(): Promise<void> { await unlink(configPath()).catch(error => { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; }); }

export async function configuredCacheDirectory(explicit?: string): Promise<string | undefined> {
  if (explicit?.trim()) return ensureCacheDirectory(explicit.trim());
  let data: Buffer;
  try { data = await noFollowRead(configPath(), 16 * 1024); }
  catch (error) { if ((error as NodeJS.ErrnoException).code === "ENOENT") return undefined; throw error; }
  const value: unknown = JSON.parse(data.toString("utf8"));
  if (!object(value) || value.schema !== CONFIG_SCHEMA || value.schema_version !== 1 || typeof value.directory !== "string" || !value.directory) throw new Error("Health.md Pi dashboard cache configuration is invalid");
  return ensureCacheDirectory(value.directory);
}

async function readManifest(directory: string): Promise<CacheManifest> {
  const path = join(directory, MANIFEST_FILE);
  try { return parseManifest((await noFollowRead(path, MAX_MANIFEST_BYTES)).toString("utf8")); }
  catch (error) { if ((error as NodeJS.ErrnoException).code === "ENOENT") return { schema: CACHE_SCHEMA, schema_version: 1, entries: [] }; throw error; }
}

export async function persistFetchedEvidence(directoryPath: string, input: { text: string; origin: CacheOrigin; operation: string }): Promise<PersistedCacheReceipt> {
  const directory = await ensureCacheDirectory(directoryPath);
  const bytes = Buffer.byteLength(input.text, "utf8");
  if (bytes > MAX_FILE_BYTES) throw new Error(`Fetched Health.md cache object exceeds ${MAX_FILE_BYTES} bytes`);
  const digest = createHash("sha256").update(input.text).digest("hex");
  const file = `${digest}.json`, objectPath = join(directory, "objects", file);
  try {
    const existing = await noFollowRead(objectPath, MAX_FILE_BYTES);
    if (createHash("sha256").update(existing).digest("hex") !== digest || existing.length !== bytes) throw new Error("Existing Health.md cache object does not match its digest");
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
    await atomicWrite(objectPath, input.text, 0o600);
  }
  const entries = await withCacheLock(directory, async () => {
    const manifest = await readManifest(directory);
    const entry: CacheEntry = { digest, file, bytes, origin: input.origin, operation: input.operation, fetched_at: new Date().toISOString() };
    manifest.entries = [entry, ...manifest.entries.filter(item => item.digest !== digest || item.operation !== input.operation)].slice(0, MAX_CACHE_ENTRIES);
    await atomicWrite(join(directory, MANIFEST_FILE), `${JSON.stringify(manifest, null, 2)}\n`, 0o600);
    return manifest.entries.length;
  });
  return { directory, file: objectPath, digest, entries };
}

export async function loadCachedEvidence(directoryPath: string): Promise<InMemoryJsonInput[]> {
  const directory = await ensureCacheDirectory(directoryPath);
  const manifest = await readManifest(directory), inputs: InMemoryJsonInput[] = [];
  let total = 0;
  for (const entry of manifest.entries) {
    if (inputs.length >= MAX_RESTORED_FILES || total + entry.bytes > MAX_RESTORED_BYTES) break;
    const path = join(directory, "objects", entry.file);
    const bytes = await noFollowRead(path, MAX_FILE_BYTES);
    if (bytes.length !== entry.bytes) throw new Error(`Health.md cache size mismatch: ${entry.file}`);
    if (createHash("sha256").update(bytes).digest("hex") !== entry.digest) throw new Error(`Health.md cache digest mismatch: ${entry.file}`);
    total += bytes.length;
    inputs.push({ path: `healthmd-cache://${entry.digest}`, text: bytes.toString("utf8"), origin: entry.origin, operation: entry.operation });
  }
  return inputs;
}
