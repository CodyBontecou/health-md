import { afterEach, expect, it } from "vitest";
import { copyFileSync, mkdirSync, mkdtempSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { randomUUID } from "node:crypto";
import { VmDatabase } from "../vm/storage";

const dirs: string[] = [];
afterEach(() => { for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true }); });
for (const priorCount of [7, 8]) it(`applies forward-only repair migrations from v${priorCount} to v9`, () => {
  const root = mkdtempSync(join(tmpdir(), "healthmd-repair-migrate-")); dirs.push(root);
  const prior = join(root, "prior"); const data = join(root, "data");
  mkdirSync(prior, { mode: 0o700 }); mkdirSync(data, { mode: 0o700 });
  const current = resolve(import.meta.dirname, "../migrations");
  for (const name of readdirSync(current).filter((file) => /^000[1-8]_.+\.sql$/u.test(file) &&
    Number(file.slice(0, 4)) <= priorCount)) {
    copyFileSync(join(current, name), join(prior, name));
  }
  const id = randomUUID();
  const originalUmask = process.umask(0o077);
  try {
    const before = new VmDatabase(data, prior);
    try {
      before.connection.prepare(`INSERT INTO users (id, email_lookup, email_ciphertext, email_iv, created_at)
        VALUES (?, 'synthetic', 'synthetic', 'synthetic', ?)`).run(id, new Date().toISOString());
      expect((before.connection.prepare("SELECT COUNT(*) AS n FROM vm_migrations").get() as { n: number }).n).toBe(priorCount);
    } finally { before.close(); }
    const after = new VmDatabase(data, current);
    try {
      expect((after.connection.prepare("SELECT COUNT(*) AS n FROM vm_migrations").get() as { n: number }).n).toBe(9);
      expect((after.connection.prepare("SELECT id FROM users WHERE id = ?").get(id) as { id: string }).id).toBe(id);
      expect((after.connection.prepare("PRAGMA integrity_check").get() as { integrity_check: string }).integrity_check)
        .toBe("ok");
      expect(after.connection.prepare("SELECT COUNT(*) AS n FROM repair_drafts").get()).toMatchObject({ n: 0 });
      expect(after.connection.prepare("SELECT COUNT(*) AS n FROM repair_devices").get()).toMatchObject({ n: 0 });
      expect(after.connection.prepare("SELECT COUNT(*) AS n FROM supplemental_exports").get()).toMatchObject({ n: 0 });
    } finally { after.close(); }
  } finally { process.umask(originalUmask); }
});
