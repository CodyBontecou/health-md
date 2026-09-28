import { resolve } from "node:path";
import { createVmEnvironment } from "./runtime";
import { createSingleUserAccount } from "./bootstrap";

// One-time personal-MVP bootstrap. A root-owned provisioning process passes a
// generated password over stdin; neither arguments nor the service environment
// contain the password. There is no HTTP signup or password recovery.
async function main(): Promise<void> {
  process.umask(0o077);
  if (process.stdin.isTTY || process.env.VM_PERSONAL_MVP_NO_BACKUP_ACK !== "I_ACCEPT_PERMANENT_DATA_LOSS" ||
      process.env.CLOUD_RUNTIME_APPROVED !== undefined || process.env.REVISION_RETENTION_DAYS !== "unlimited" ||
      !process.env.HEALTHMD_VM_DATA_DIR || !process.env.HEALTHMD_CLOUD_SOURCE_DIR ||
      !process.env.PUBLIC_ORIGIN || !process.env.IDENTITY_KEY_B64 ||
      !process.env.EXPORT_ENCRYPTION_KEYS_JSON || !process.env.PASSWORD_PEPPER_B64) {
    throw new Error("Generated bootstrap requires the unbacked personal-MVP profile and a password pipe");
  }
  const chunks: Uint8Array[] = [];
  let size = 0;
  for await (const chunk of process.stdin) {
    size += chunk.length;
    if (size > 256) throw new Error("Password input too long");
    chunks.push(chunk);
  }
  const password = Buffer.concat(chunks).toString("utf8").replace(/\r?\n$/u, "");
  const { env, db } = createVmEnvironment({
    dataDirectory: resolve(process.env.HEALTHMD_VM_DATA_DIR),
    sourceDirectory: resolve(process.env.HEALTHMD_CLOUD_SOURCE_DIR),
    publicOrigin: process.env.PUBLIC_ORIGIN,
    identityKey: process.env.IDENTITY_KEY_B64,
    exportKeys: process.env.EXPORT_ENCRYPTION_KEYS_JSON,
    currentKeyId: process.env.CURRENT_EXPORT_KEY_ID ?? "v1",
    passwordPepper: process.env.PASSWORD_PEPPER_B64,
    revisionRetention: "unlimited",
    personalMvp: true,
  });
  try {
    await createSingleUserAccount(env, "owner", "owner@example.test", password);
    process.stdout.write("Single owner account created. Password was not printed.\n");
  } finally {
    db.close();
  }
}

main().catch(() => {
  process.stderr.write("Generated account setup failed; inspect deployment state without exposing credentials.\n");
  process.exitCode = 1;
});
