import { resolve } from "node:path";
import { createVmEnvironment } from "./runtime";
import { startVmServer } from "./server";
import { assertPrivateDirectory } from "./storage";

// Dedicated, positive-route public writer. The private tailnet writer retains
// :18788, and this process cannot serve account, download or MCP routes.
export async function runVmIngestServer(): Promise<void> {
  process.umask(0o077);
  const dataDirectory = process.env.HEALTHMD_VM_DATA_DIR;
  const sourceDirectory = process.env.HEALTHMD_CLOUD_SOURCE_DIR;
  const writerOrigin = process.env.PUBLIC_ORIGIN;
  if (!dataDirectory || !sourceDirectory || !writerOrigin ||
      !process.env.IDENTITY_KEY_B64 || !process.env.EXPORT_ENCRYPTION_KEYS_JSON ||
      !process.env.PASSWORD_PEPPER_B64 ||
      process.env.VM_PERSONAL_MVP_NO_BACKUP_ACK !== "I_ACCEPT_PERMANENT_DATA_LOSS" ||
      process.env.API_PUBLIC_ORIGIN !== "https://api.healthmd.app" ||
      process.env.API_LOOPBACK_PORT !== "18793") throw new Error("Public ingest configuration is incomplete");
  const writer = new URL(writerOrigin);
  if (writer.protocol !== "https:" || !writer.hostname.endsWith(".ts.net") ||
      writer.port !== "18788" || writer.origin !== writerOrigin) {
    throw new Error("Public ingest must preserve the separate private writer");
  }
  const source = assertPrivateDirectory(resolve(sourceDirectory));
  const { env } = createVmEnvironment({
    dataDirectory: resolve(dataDirectory), sourceDirectory: source,
    publicOrigin: "https://api.healthmd.app", identityKey: process.env.IDENTITY_KEY_B64,
    exportKeys: process.env.EXPORT_ENCRYPTION_KEYS_JSON,
    currentKeyId: process.env.CURRENT_EXPORT_KEY_ID ?? "v1",
    passwordPepper: process.env.PASSWORD_PEPPER_B64,
    revisionRetention: "unlimited", personalMvp: true,
  });
  await startVmServer(env, 18793, "ingest");
  // The private writer exclusively owns reconciliation and scheduled cleanup.
}

if (process.env.HEALTHMD_INGEST_START === "1") {
  runVmIngestServer().catch(() => {
    process.stderr.write("Health.md public ingest startup failed.\n");
    process.exitCode = 1;
  });
}
