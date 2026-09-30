import { DatabaseSync } from "node:sqlite";
import { lstatSync, readdirSync, readFileSync, statSync } from "node:fs";
import { lstat, mkdir, open, readFile, readdir, rename, unlink } from "node:fs/promises";
import { basename, join, resolve } from "node:path";
import { randomUUID } from "node:crypto";

const OBJECT_KEY = /^v1\/[a-f0-9-]{36}$/u;
const ASSETS = new Map([
  ["/login", ["login.html", "text/html; charset=utf-8"]],
  ["/dashboard", ["dashboard.html", "text/html; charset=utf-8"]],
  ["/dashboard.js", ["dashboard.js", "text/javascript; charset=utf-8"]],
  ["/explore", ["explore.html", "text/html; charset=utf-8"]],
  ["/explore.js", ["explore.js", "text/javascript; charset=utf-8"]],
  ["/repair", ["repair.html", "text/html; charset=utf-8"]],
  ["/repair.js", ["repair.js", "text/javascript; charset=utf-8"]],
  ["/repair-panel", ["repair-panel.html", "text/html; charset=utf-8"]],
  ["/style.css", ["style.css", "text/css; charset=utf-8"]],
]);

// An opt-in dedicated reader Unix group permits only read/search access to
// encrypted data. With no group configured, the original 0700/0600 profile is
// unchanged. Never make the writer's own primary group a reader credential.
export function vmReaderGroupId(): number | null {
  const value = process.env.HEALTHMD_VM_READER_GID;
  if (value === undefined) return null;
  if (!/^[1-9][0-9]{0,9}$/u.test(value) || !Number.isSafeInteger(Number(value)) ||
      Number(value) === process.getgid?.()) {
    throw new Error("Invalid or non-dedicated VM reader group ID");
  }
  return Number(value);
}

function safeVmMode(stats: { uid: number; gid: number; mode: number }, directory: boolean): boolean {
  if (stats.uid !== process.getuid?.() || (stats.mode & 0o007) !== 0) return false;
  const groupBits = stats.mode & 0o070;
  if (groupBits === 0) return true;
  const gid = vmReaderGroupId();
  return gid !== null && stats.gid === gid && groupBits === (directory ? 0o050 : 0o040);
}

export function assertPrivateDirectory(path: string): string {
  const absolute = resolve(path);
  const stats = lstatSync(absolute, { throwIfNoEntry: false });
  if (!stats?.isDirectory() || stats.isSymbolicLink() || !safeVmMode(stats, true)) {
    throw new Error("VM data directory must be owner-only or shared only with its read group");
  }
  return absolute;
}

export function assertReaderDirectory(path: string): string {
  const directory = assertPrivateDirectory(path);
  const gid = vmReaderGroupId();
  if (gid !== null) {
    const stats = lstatSync(directory);
    if (stats.gid !== gid || (stats.mode & 0o2070) !== 0o2050) {
      throw new Error("Dedicated reader directory is not setgid and group read/search only");
    }
  }
  return directory;
}

export class VmStatement {
  constructor(private readonly db: DatabaseSync, private readonly sql: string,
    private readonly values: unknown[] = []) {}

  bind(...values: unknown[]): VmStatement {
    return new VmStatement(this.db, this.sql, values);
  }

  async first<T>(): Promise<T | null> {
    return (this.db.prepare(this.sql).get(...this.values as never[]) as T | undefined) ?? null;
  }

  async all<T>(): Promise<{ results: T[] }> {
    return { results: this.db.prepare(this.sql).all(...this.values as never[]) as T[] };
  }

  runSync(): { meta: { changes: number } } {
    return { meta: { changes: Number(this.db.prepare(this.sql).run(...this.values as never[]).changes) } };
  }

  async run(): Promise<{ meta: { changes: number } }> {
    return this.runSync();
  }
}

export class VmDatabase {
  readonly connection: DatabaseSync;

  constructor(dataDirectory: string, migrationsDirectory: string) {
    const privateRoot = assertReaderDirectory(dataDirectory);
    const path = join(privateRoot, "cloud.sqlite");
    const existing = lstatSync(path, { throwIfNoEntry: false });
    if (existing && (!existing.isFile() || existing.isSymbolicLink() || !safeVmMode(existing, false))) {
      throw new Error("VM database file permissions are unsafe");
    }
    this.connection = new DatabaseSync(path);
    this.connection.exec("PRAGMA foreign_keys = ON; PRAGMA secure_delete = ON; PRAGMA journal_mode = WAL; PRAGMA synchronous = FULL; PRAGMA busy_timeout = 5000;");
    this.connection.exec("CREATE TABLE IF NOT EXISTS vm_migrations (name TEXT PRIMARY KEY) STRICT;");
    for (const name of readdirSync(migrationsDirectory).filter((item) => /^\d{4}_.+\.sql$/u.test(item)).sort()) {
      if (this.connection.prepare("SELECT 1 FROM vm_migrations WHERE name = ?").get(name)) continue;
      const sql = readFileSync(join(migrationsDirectory, name), "utf8");
      this.connection.exec("BEGIN IMMEDIATE");
      try {
        this.connection.exec(sql);
        this.connection.prepare("INSERT INTO vm_migrations (name) VALUES (?)").run(name);
        this.connection.exec("COMMIT");
      } catch (error) {
        this.connection.exec("ROLLBACK");
        throw error;
      }
    }
    const permissions = statSync(path);
    if (!safeVmMode(permissions, false)) {
      throw new Error("VM database file permissions are unsafe");
    }
  }

  prepare(sql: string): VmStatement { return new VmStatement(this.connection, sql); }

  async batch(statements: VmStatement[]): Promise<Array<{ meta: { changes: number } }>> {
    this.connection.exec("BEGIN IMMEDIATE");
    try {
      const result = statements.map((statement) => {
        if (!(statement instanceof VmStatement)) throw new Error("Unexpected DB statement type");
        return statement.runSync();
      });
      this.connection.exec("COMMIT");
      return result;
    } catch (error) {
      this.connection.exec("ROLLBACK");
      throw error;
    }
  }

  close(): void { this.connection.close(); }
}

export class VmObjectStore {
  private readonly root: string;
  constructor(dataDirectory: string) {
    this.root = join(assertReaderDirectory(dataDirectory), "objects");
    this.assertSafeDirectory(this.root);
  }

  private assertSafeDirectory(path: string): void {
    const info = lstatSync(path, { throwIfNoEntry: false });
    if (info && (!info.isDirectory() || info.isSymbolicLink() || !safeVmMode(info, true))) {
      throw new Error("Private object directory has unsafe permissions");
    }
    if (vmReaderGroupId() !== null) assertReaderDirectory(path);
  }

  private path(key: string): string {
    if (!OBJECT_KEY.test(key)) throw new Error("Invalid private object key");
    return join(this.root, key);
  }

  async put(key: string, bytes: Uint8Array): Promise<void> {
    const destination = this.path(key);
    const directory = join(this.root, "v1");
    await mkdir(directory, { recursive: true, mode: vmReaderGroupId() === null ? 0o700 : 0o750 });
    this.assertSafeDirectory(this.root);
    this.assertSafeDirectory(directory);
    const temp = join(directory, `.write-${randomUUID()}`);
    const file = await open(temp, "wx", vmReaderGroupId() === null ? 0o600 : 0o640);
    try {
      await file.writeFile(bytes);
      await file.sync();
    } finally {
      await file.close();
    }
    try {
      await rename(temp, destination);
      const dir = await open(directory, "r");
      try { await dir.sync(); } finally { await dir.close(); }
    } catch (error) {
      await unlink(temp).catch(() => undefined);
      throw error;
    }
  }

  async get(key: string): Promise<{ arrayBuffer: () => Promise<ArrayBuffer> } | null> {
    let bytes: Uint8Array;
    try { bytes = await readFile(this.path(key)); }
    catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") return null;
      throw error;
    }
    return { arrayBuffer: async () => Uint8Array.from(bytes).buffer };
  }

  async delete(key: string): Promise<void> {
    try { await unlink(this.path(key)); }
    catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
    }
    let dir;
    try { dir = await open(join(this.root, "v1"), "r"); }
    catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") return;
      throw error;
    }
    try { await dir.sync(); } finally { await dir.close(); }
  }

  // Call only with ingestion paused (at startup or under the VM maintenance
  // gate). Metadata referring to a missing object is a fatal integrity error;
  // uncommitted encrypted writes are removed after a crash/rejected request.
  async reconcile(db: VmDatabase): Promise<number> {
    const directory = join(this.root, "v1");
    await mkdir(directory, { recursive: true, mode: vmReaderGroupId() === null ? 0o700 : 0o750 });
    this.assertSafeDirectory(this.root);
    this.assertSafeDirectory(directory);
    const rows = await db.prepare(`SELECT object_key AS objectKey FROM exports
      UNION SELECT object_key AS objectKey FROM upload_intents
      WHERE state IN ('reserved', 'object_written')`).all<{ objectKey: string }>();
    const expected = new Set(rows.results.map(({ objectKey }) => {
      this.path(objectKey);
      return objectKey.slice(3);
    }));
    const names = await readdir(directory);
    const found = new Set<string>();
    const orphans: string[] = [];
    for (const name of names) {
      if (!/^[a-f0-9-]{36}$/u.test(name) && !/^\.write-[a-f0-9-]{36}$/u.test(name)) {
        throw new Error("Unknown object-directory entry");
      }
      const file = await lstat(join(directory, name));
      if (!file.isFile() || file.isSymbolicLink() || !safeVmMode(file, false)) {
        throw new Error("Unsafe encrypted object file");
      }
      if (expected.has(name)) found.add(name);
      else orphans.push(name);
    }
    if (found.size !== expected.size) throw new Error("Stored export metadata has missing ciphertext");
    for (const name of orphans) await unlink(join(directory, name));
    if (orphans.length > 0) {
      const dir = await open(directory, "r");
      try { await dir.sync(); } finally { await dir.close(); }
    }
    return orphans.length;
  }
}

export class VmAssets {
  constructor(private readonly publicDirectory: string) {}
  async fetch(request: Request): Promise<Response> {
    const asset = ASSETS.get(new URL(request.url).pathname);
    if (!asset) return new Response(null, { status: 404 });
    const [name, type] = asset;
    if (!name || !type || basename(name) !== name) return new Response(null, { status: 404 });
    const bytes = await readFile(join(this.publicDirectory, name));
    return new Response(Uint8Array.from(bytes).buffer, { headers: { "Content-Type": type } });
  }
}
