import { afterEach, expect, it } from "vitest";
import { copyFileSync, mkdirSync, mkdtempSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { randomUUID } from "node:crypto";
import { VmDatabase } from "../vm/storage";

const dirs: string[] = [];
afterEach(() => { for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true }); });
for (const priorCount of [7, 8, 9, 10, 11, 12, 13, 14, 15]) it(`applies forward-only migrations from v${priorCount} to v16`, () => {
  const root = mkdtempSync(join(tmpdir(), "healthmd-repair-migrate-")); dirs.push(root);
  const prior = join(root, "prior"); const data = join(root, "data");
  mkdirSync(prior, { mode: 0o700 }); mkdirSync(data, { mode: 0o700 });
  const current = resolve(import.meta.dirname, "../migrations");
  for (const name of readdirSync(current).filter((file) => /^[0-9]{4}_.+\.sql$/u.test(file) &&
    Number(file.slice(0, 4)) <= priorCount)) {
    copyFileSync(join(current, name), join(prior, name));
  }
  const id = randomUUID();
  const deletionId = randomUUID();
  const originalUmask = process.umask(0o077);
  try {
    const before = new VmDatabase(data, prior);
    try {
      before.connection.prepare(`INSERT INTO users (id, email_lookup, email_ciphertext, email_iv, created_at)
        VALUES (?, 'synthetic', 'synthetic', 'synthetic', ?)`).run(id, new Date().toISOString());
      if (priorCount >= 12 && priorCount <= 14) {
        before.connection.prepare(`INSERT INTO account_deletions
          (id, user_id, requested_at, status_token_hash, status_expires_at)
          VALUES (?, ?, ?, ?, '2030-01-01T00:00:00.000Z')`)
          .run(deletionId, id, new Date().toISOString(), "a".repeat(64));
      }
      expect((before.connection.prepare("SELECT COUNT(*) AS n FROM vm_migrations").get() as { n: number }).n).toBe(priorCount);
    } finally { before.close(); }
    const after = new VmDatabase(data, current);
    try {
      expect((after.connection.prepare("SELECT COUNT(*) AS n FROM vm_migrations").get() as { n: number }).n).toBe(16);
      expect((after.connection.prepare("SELECT id FROM users WHERE id = ?").get(id) as { id: string }).id).toBe(id);
      expect((after.connection.prepare("PRAGMA integrity_check").get() as { integrity_check: string }).integrity_check)
        .toBe("ok");
      expect(after.connection.prepare("SELECT COUNT(*) AS n FROM repair_drafts").get()).toMatchObject({ n: 0 });
      expect(after.connection.prepare("SELECT COUNT(*) AS n FROM repair_devices").get()).toMatchObject({ n: 0 });
      expect(after.connection.prepare("SELECT COUNT(*) AS n FROM supplemental_exports").get()).toMatchObject({ n: 0 });
      expect(after.connection.prepare(
        "SELECT committed_bytes, reserved_bytes, quota_bytes FROM account_storage WHERE user_id = ?",
      ).get(id)).toMatchObject({ committed_bytes: 0, reserved_bytes: 0, quota_bytes: 1_073_741_824 });
      expect(after.connection.prepare("SELECT COUNT(*) AS n FROM upload_intents").get()).toMatchObject({ n: 0 });
      expect(after.connection.prepare("SELECT COUNT(*) AS n FROM account_export_keys").get()).toMatchObject({ n: 0 });
      expect(after.connection.prepare(`SELECT COUNT(*) AS n FROM pragma_table_info('account_deletions')
        WHERE name IN ('status_token_hash', 'status_expires_at')`).get()).toMatchObject({ n: 2 });
      expect(after.connection.prepare(`SELECT COUNT(*) AS n FROM pragma_table_info('account_export_keys')
        WHERE name = 'rewrapped_at'`).get()).toMatchObject({ n: 1 });
      expect(after.connection.prepare("SELECT COUNT(*) AS n FROM maintenance_cursors").get())
        .toMatchObject({ n: 0 });
      expect(after.connection.prepare("SELECT COUNT(*) AS n FROM account_deletion_receipts").get())
        .toMatchObject({ n: priorCount >= 12 && priorCount <= 14 ? 1 : 0 });
      if (priorCount >= 12 && priorCount <= 14) {
        expect(after.connection.prepare(`SELECT status_token_hash AS statusTokenHash,
          status_expires_at AS statusExpiresAt FROM account_deletions WHERE id = ?`).get(deletionId))
          .toMatchObject({ statusTokenHash: null, statusExpiresAt: null });
      }
      expect(after.connection.prepare(`SELECT COUNT(*) AS n FROM pragma_table_info('magic_links')
        WHERE name = 'claim_nonce'`).get()).toMatchObject({ n: 1 });
    } finally { after.close(); }
  } finally { process.umask(originalUmask); }
});
