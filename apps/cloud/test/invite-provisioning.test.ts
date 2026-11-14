import { afterEach, expect, it } from "vitest";
import { createHmac, randomBytes } from "node:crypto";
import { chmodSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";

const roots: string[] = [];
afterEach(() => { for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true }); });

function fixture() {
  const root = mkdtempSync(join(tmpdir(), "healthmd-invites-synthetic-"));
  roots.push(root);
  const emailFile = join(root, "emails.txt");
  const keyFile = join(root, "identity-key.txt");
  const outputFile = join(root, "invites.sql");
  const key = randomBytes(32);
  writeFileSync(emailFile, "FIRST@EXAMPLE.TEST\nsecond@example.test\n", { mode: 0o600 });
  writeFileSync(keyFile, `${Buffer.from(key).toString("base64")}\n`, { mode: 0o600 });
  return { root, emailFile, keyFile, outputFile, key };
}

function run(input: ReturnType<typeof fixture>, operation: "grant" | "revoke" = "grant") {
  return spawnSync(process.execPath, [resolve(import.meta.dirname, "../scripts/prepare-account-invites.mjs")], {
    encoding: "utf8",
    env: {
      ...process.env,
      HEALTHMD_INVITE_EMAIL_FILE: input.emailFile,
      HEALTHMD_IDENTITY_KEY_FILE: input.keyFile,
      HEALTHMD_INVITE_SQL_OUTPUT: input.outputFile,
      HEALTHMD_INVITE_OPERATION: operation,
      HEALTHMD_INVITE_EXPIRES_AT: operation === "grant" ?
        new Date(Date.now() + 30 * 86_400_000).toISOString() : undefined,
    },
  });
}

it("prepares owner-only SQL containing hashes rather than invite addresses", () => {
  const input = fixture();
  const result = run(input);
  expect({ status: result.status, stdout: result.stdout, stderr: result.stderr })
    .toEqual({ status: 0, stdout: "Prepared 2 hashed account invite grants.\n", stderr: "" });
  expect(statSync(input.outputFile).mode & 0o777).toBe(0o600);
  const sql = readFileSync(input.outputFile, "utf8");
  const expected = createHmac("sha256", input.key)
    .update("account-invite-v1\0first@example.test", "utf8").digest("hex");
  const durableUserLookup = createHmac("sha256", input.key)
    .update("email-lookup-v1\0first@example.test", "utf8").digest("hex");
  expect(sql).toContain("BEGIN TRANSACTION;");
  expect(sql).toContain(expected);
  expect(sql).not.toContain(durableUserLookup);
  expect(sql).toContain("ON CONFLICT(invite_lookup) DO UPDATE");
  expect(sql).toContain("COMMIT;");
  expect(sql).not.toMatch(/first@|second@|example\.test/iu);
});

it("prepares privacy-preserving invite revocation SQL", () => {
  const input = fixture();
  const result = run(input, "revoke");
  expect({ status: result.status, stdout: result.stdout, stderr: result.stderr })
    .toEqual({ status: 0, stdout: "Prepared 2 hashed account invite revocations.\n", stderr: "" });
  const sql = readFileSync(input.outputFile, "utf8");
  expect(sql).toContain("DELETE FROM account_invites WHERE invite_lookup = '");
  expect(sql).not.toContain("INSERT INTO account_invites");
  expect(sql).not.toMatch(/first@|second@|example\.test/iu);
});

it("refuses non-private inputs and existing output without disclosing values", () => {
  const input = fixture();
  chmodSync(input.emailFile, 0o644);
  const unsafe = run(input);
  expect(unsafe.status).not.toBe(0);
  expect(unsafe.stderr).toBe("Invite email input must be a regular owner-only file.\n");
  expect(`${unsafe.stdout}${unsafe.stderr}`).not.toContain("example.test");

  chmodSync(input.emailFile, 0o600);
  writeFileSync(input.outputFile, "do-not-overwrite", { mode: 0o600 });
  const existing = run(input);
  expect(existing.status).not.toBe(0);
  expect(existing.stderr).toBe("Invite SQL output already exists.\n");
  expect(readFileSync(input.outputFile, "utf8")).toBe("do-not-overwrite");
});
