export interface Env {
  DB: D1Database;
  EXPORTS: R2Bucket;
  ASSETS: Fetcher;
  ENVIRONMENT: "development" | "production";
  PUBLIC_ORIGIN: string;
  EXPORT_ENDPOINT_ORIGIN?: string;
  SERVICE_PROFILE?: "combined" | "ingest" | "account" | "maintenance";
  DEPLOYMENT_REVISION?: string;
  AUTH_SIGNUP_MODE: "closed" | "invite" | "open";
  AUTH_MODE?: "email_link" | "password";
  AUTH_EMAIL_FROM: string;
  CURRENT_EXPORT_KEY_ID?: string;
  ACCOUNT_KEY_MODE?: "legacy" | "per_account";
  CURRENT_ACCOUNT_WRAPPING_KEY_ID?: string;
  ACCOUNT_KEY_WRAPPING_KEYS_JSON?: string;
  MAX_EXPORT_BYTES: string;
  SESSION_TTL_DAYS: string;
  MAGIC_LINK_TTL_MINUTES: string;
  EMAIL_SEND_HOURLY_LIMIT?: string;
  INGEST_TOKEN_HOURLY_LIMIT?: string;
  INGEST_ACCOUNT_HOURLY_LIMIT?: string;
  IDENTITY_KEY_B64: string;
  EXPORT_ENCRYPTION_KEYS_JSON?: string;
  RESEND_API_KEY: string;
  PASSWORD_PEPPER_B64?: string;
  REVISION_RETENTION_DAYS?: string;
  AUDIT_RETENTION_DAYS?: string;
  DELETION_STATUS_TTL_DAYS?: string;
  CLOUD_RUNTIME_APPROVED?: string;
  VM_PERSONAL_MVP_NO_BACKUP_ACK?: string;
  AUTH_INVITE_EMAILS?: string;
  DEV_SHOW_MAGIC_LINK?: string;
  SYNTHETIC_PREVIEW_ONLY?: string;
  CLOUD_REPAIR_DEVICE_ENROLLMENT_ENABLED?: string;
  CLOUD_REPAIR_DISPATCH_ENABLED?: string;
  LIFECYCLE_QUEUE?: Queue<LifecycleMessage>;
  METRICS?: AnalyticsEngineDataset;
  HEALTH_FREE_METRICS_REQUIRED?: string;
}

export interface LifecycleMessage {
  version: 1;
  type: "account.delete";
  deletionId: string;
}

export interface UserRow {
  id: string;
  email_lookup: string;
  email_ciphertext: string;
  email_iv: string;
  status: "active" | "disabled";
  created_at: string;
}

export interface SessionUser {
  id: string;
  emailCiphertext: string;
  emailIv: string;
  sessionId: string;
  sessionCreatedAt: string;
}

export interface IngestPrincipal {
  userId: string;
  tokenId: string;
}

export interface DailyRecordInfo {
  date: string;
  index: number;
  schemaVersion: number;
  captureStatus: string | null;
}

export interface EnvelopeInfo {
  envelopeSchemaVersion: number;
  dailyRecordSchemaVersion: number;
  source: "ios" | "android";
  exportedAt: string;
  dateStart: string;
  dateEnd: string;
  recordCount: number;
  failureCount: number;
  failureTimestamps: string[];
  externalRecordCount: number;
  dailyRecords: DailyRecordInfo[];
}
