import { join } from "node:path";
import type { Env } from "../src/types";
import { decodeBase64, parseExportKeyring } from "../src/crypto";
import { VmAssets, VmDatabase, VmObjectStore, assertReaderDirectory, vmReaderGroupId } from "./storage";

export function createVmEnvironment(config: {
  dataDirectory: string;
  sourceDirectory: string;
  publicOrigin: string;
  identityKey: string;
  exportKeys: string;
  currentKeyId: string;
  passwordPepper: string;
  revisionRetention?: number | "unlimited";
  approved?: boolean;
  personalMvp?: boolean;
  syntheticOnly?: boolean;
}): { env: Env; db: VmDatabase; objects: VmObjectStore } {
  if (decodeBase64(config.identityKey).byteLength !== 32 ||
      decodeBase64(config.passwordPepper).byteLength !== 32 ||
      config.identityKey === config.passwordPepper) throw new Error("Invalid independent VM identity secrets");
  const keyring = parseExportKeyring(config.exportKeys);
  if (!keyring.has(config.currentKeyId) || [...keyring.values()].some((key) =>
    key === config.identityKey || key === config.passwordPepper)) {
    throw new Error("Invalid independent VM export keys");
  }
  const readerGroup = vmReaderGroupId();
  const privateRoot = assertReaderDirectory(config.dataDirectory);
  process.umask(readerGroup === null ? 0o077 : 0o027);
  const db = new VmDatabase(privateRoot, join(config.sourceDirectory, "migrations"));
  const objects = new VmObjectStore(privateRoot);
  const assets = new VmAssets(join(config.sourceDirectory, "public"));
  const env: Env = {
    DB: db as unknown as D1Database,
    EXPORTS: objects as unknown as R2Bucket,
    ASSETS: assets as unknown as Fetcher,
    ENVIRONMENT: config.syntheticOnly ? "development" : "production",
    PUBLIC_ORIGIN: config.publicOrigin,
    AUTH_SIGNUP_MODE: "closed",
    AUTH_MODE: "password",
    AUTH_EMAIL_FROM: "",
    RESEND_API_KEY: "",
    IDENTITY_KEY_B64: config.identityKey,
    EXPORT_ENCRYPTION_KEYS_JSON: config.exportKeys,
    CURRENT_EXPORT_KEY_ID: config.currentKeyId,
    PASSWORD_PEPPER_B64: config.passwordPepper,
    REVISION_RETENTION_DAYS: config.revisionRetention?.toString(),
    MAX_EXPORT_BYTES: "26214400",
    SESSION_TTL_DAYS: "7",
    MAGIC_LINK_TTL_MINUTES: "15",
    CLOUD_RUNTIME_APPROVED: config.approved ? "healthmd-cloud-v1-reviewed" : undefined,
    VM_PERSONAL_MVP_NO_BACKUP_ACK: config.personalMvp ? "I_ACCEPT_PERMANENT_DATA_LOSS" : undefined,
    SYNTHETIC_PREVIEW_ONLY: config.syntheticOnly ? "1" : undefined,
  };
  return { env, db, objects };
}
