import { resolve } from "node:path";
import { createVmEnvironment } from "./runtime";
import { startVmServer } from "./server";
import { assertPrivateDirectory } from "./storage";

// Public account management runs as a separate loopback process. Only the
// positive accountRoute list in vm/server.ts may reach its Worker adapter;
// the tailnet writer on 18788 and the read-only MCP process remain untouched.
export async function runVmAccountServer(): Promise<void> {
  process.umask(0o077);
  const dataDirectory = process.env.HEALTHMD_VM_DATA_DIR;
  const sourceDirectory = process.env.HEALTHMD_CLOUD_SOURCE_DIR;
  const writerOrigin = process.env.PUBLIC_ORIGIN;
  const origin = process.env.ACCOUNT_PUBLIC_ORIGIN;
  if (!dataDirectory || !sourceDirectory || !writerOrigin || !origin ||
      !process.env.IDENTITY_KEY_B64 || !process.env.PASSWORD_PEPPER_B64 ||
      !process.env.EXPORT_ENCRYPTION_KEYS_JSON ||
      process.env.VM_PERSONAL_MVP_NO_BACKUP_ACK !== "I_ACCEPT_PERMANENT_DATA_LOSS" ||
      process.env.ACCOUNT_LOOPBACK_PORT !== "18791") throw new Error("Account configuration is incomplete");
  const writer = new URL(writerOrigin);
  if (origin !== "https://account.healthmd.app" || writer.protocol !== "https:" ||
      !writer.hostname.endsWith(".ts.net") || writer.port !== "18788" ||
      (process.env.API_PUBLIC_ORIGIN !== undefined &&
        process.env.API_PUBLIC_ORIGIN !== "https://api.healthmd.app")) {
    throw new Error("Account or writer origin is not isolated");
  }
  const source = assertPrivateDirectory(resolve(sourceDirectory));
  const { env } = createVmEnvironment({
    dataDirectory: resolve(dataDirectory), sourceDirectory: source,
    publicOrigin: origin, identityKey: process.env.IDENTITY_KEY_B64,
    exportKeys: process.env.EXPORT_ENCRYPTION_KEYS_JSON,
    currentKeyId: process.env.CURRENT_EXPORT_KEY_ID ?? "v1",
    passwordPepper: process.env.PASSWORD_PEPPER_B64,
    revisionRetention: "unlimited", personalMvp: true,
  });
  // Keep the old tailnet target until the independent public ingestion Tunnel
  // has passed end-to-end negative and authorized synthetic upload checks.
  env.EXPORT_ENDPOINT_ORIGIN = process.env.API_PUBLIC_ORIGIN ?? writerOrigin;
  await startVmServer(env, 18791, "account");
  // No maintenance or writer actions here. The private writer owns reconciliation
  // and deletion cleanup; both processes use SQLite's existing WAL discipline.
}

if (process.env.HEALTHMD_ACCOUNT_START === "1") {
  runVmAccountServer().catch(() => {
    process.stderr.write("Health.md private account service startup failed.\n");
    process.exitCode = 1;
  });
}
