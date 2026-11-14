import { createInterface } from "node:readline/promises";
import { resolve } from "node:path";
import { createVmEnvironment } from "./runtime";
import { createSingleUserAccount } from "./bootstrap";

function hiddenQuestion(label: string): Promise<string> {
  if (!process.stdin.isTTY || !process.stdin.setRawMode) throw new Error("Interactive TTY required");
  process.stdout.write(label);
  process.stdin.setRawMode(true);
  process.stdin.resume();
  const bytes: number[] = [];
  return new Promise((resolve, reject) => {
    const complete = (error?: Error) => {
      process.stdin.removeListener("data", onData);
      process.stdin.setRawMode(false);
      process.stdin.pause();
      process.stdout.write("\n");
      if (error) reject(error);
      else resolve(Buffer.from(bytes).toString("utf8"));
    };
    const onData = (chunk: Buffer) => {
      for (const byte of chunk) {
        if (byte === 3) { complete(new Error("Password entry cancelled")); return; }
        if (byte === 10 || byte === 13) { complete(); return; }
        if (byte === 127 || byte === 8) bytes.pop();
        else if (bytes.length < 4096) bytes.push(byte);
      }
    };
    process.stdin.on("data", onData);
  });
}

async function main(): Promise<void> {
  process.umask(0o077);
  const personalMvp = process.env.VM_PERSONAL_MVP_NO_BACKUP_ACK === "I_ACCEPT_PERMANENT_DATA_LOSS";
  if (!(personalMvp ? process.env.CLOUD_RUNTIME_APPROVED === undefined :
      process.env.CLOUD_RUNTIME_APPROVED === "healthmd-cloud-v1-reviewed") ||
      !process.env.HEALTHMD_VM_DATA_DIR || !process.env.HEALTHMD_CLOUD_SOURCE_DIR ||
      !process.env.PUBLIC_ORIGIN || !process.env.IDENTITY_KEY_B64 ||
      !process.env.EXPORT_ENCRYPTION_KEYS_JSON || !process.env.PASSWORD_PEPPER_B64) {
    throw new Error("Offline bootstrap requires an explicitly approved VM profile");
  }
  const { env, db } = createVmEnvironment({
    dataDirectory: resolve(process.env.HEALTHMD_VM_DATA_DIR),
    sourceDirectory: resolve(process.env.HEALTHMD_CLOUD_SOURCE_DIR),
    publicOrigin: process.env.PUBLIC_ORIGIN,
    identityKey: process.env.IDENTITY_KEY_B64,
    exportKeys: process.env.EXPORT_ENCRYPTION_KEYS_JSON,
    currentKeyId: process.env.CURRENT_EXPORT_KEY_ID ?? "v1",
    passwordPepper: process.env.PASSWORD_PEPPER_B64,
    approved: !personalMvp,
    personalMvp,
    revisionRetention: process.env.REVISION_RETENTION_DAYS === "unlimited" ? "unlimited" : undefined,
  });
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  const username = await rl.question("Single-user username: ");
  const email = await rl.question("Account email (not sent without explicit email delivery): ");
  rl.close();
  const password = await hiddenQuestion("Password (16+ characters; hidden): ");
  const confirmation = await hiddenQuestion("Confirm password (hidden): ");
  try {
    if (password !== confirmation) throw new Error("Password confirmation does not match");
    await createSingleUserAccount(env, username, email, password);
    process.stdout.write("Single-user account initialized. No credential was printed.\n");
  } finally {
    db.close();
  }
}

main().catch(() => { process.stderr.write("Offline account setup failed; inspect configuration, not credential input.\n"); process.exitCode = 1; });
