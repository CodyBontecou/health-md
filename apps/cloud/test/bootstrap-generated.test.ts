import { afterEach, expect, it } from "vitest";
import { randomBytes } from "node:crypto";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { DatabaseSync } from "node:sqlite";
import { buildSync } from "esbuild";

const directories: string[] = [];
afterEach(() => {
  for (const path of directories.splice(0)) rmSync(path, { recursive: true, force: true });
});

it("generates one offline account from a piped password without exposing it", () => {
  const directory = mkdtempSync(join(tmpdir(), "healthmd-generated-bootstrap-synthetic-"));
  directories.push(directory);
  const sourceDirectory = resolve(import.meta.dirname, "..");
  const bundle = join(directory, "bootstrap.mjs");
  buildSync({ entryPoints: [join(sourceDirectory, "vm/bootstrap-generated.ts")],
    outfile: bundle, bundle: true, platform: "node", target: "node24", format: "esm" });
  const makeKey = () => Buffer.from(randomBytes(32)).toString("base64");
  const env = {
    ...process.env,
    HEALTHMD_VM_DATA_DIR: directory,
    HEALTHMD_CLOUD_SOURCE_DIR: sourceDirectory,
    PUBLIC_ORIGIN: "https://synthetic.example.test:18788",
    VM_PERSONAL_MVP_NO_BACKUP_ACK: "I_ACCEPT_PERMANENT_DATA_LOSS",
    REVISION_RETENTION_DAYS: "unlimited",
    IDENTITY_KEY_B64: makeKey(),
    PASSWORD_PEPPER_B64: makeKey(),
    EXPORT_ENCRYPTION_KEYS_JSON: JSON.stringify({ v1: makeKey() }),
    CURRENT_EXPORT_KEY_ID: "v1",
    CLOUD_RUNTIME_APPROVED: undefined,
  };
  const password = "synthetic-generated-passphrase-not-real";
  const start = () => spawnSync(process.execPath, [bundle], {
    env, input: `${password}\n`, encoding: "utf8", timeout: 15_000,
  });
  const first = start();
  expect(first.status).toBe(0);
  expect(`${first.stdout}${first.stderr}`).not.toContain(password);
  const db = new DatabaseSync(join(directory, "cloud.sqlite"), { readOnly: true });
  try {
    expect(db.prepare("SELECT COUNT(*) AS count FROM users").get()).toMatchObject({ count: 1 });
    const row = db.prepare("SELECT verifier FROM password_credentials").get() as { verifier: string };
    expect(row.verifier).not.toContain(password);
  } finally { db.close(); }
  const repeat = start();
  expect(repeat.status).not.toBe(0);
  expect(`${repeat.stdout}${repeat.stderr}`).not.toContain(password);
});
