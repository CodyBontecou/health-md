import { describe, expect, it } from "vitest";
import accountWorker from "../src/account-worker";
import ingestWorker from "../src/ingest-worker";
import maintenanceWorker from "../src/maintenance-worker";
import type { Env, LifecycleMessage } from "../src/types";

function profile(kind: "ingest" | "account" | "maintenance", origin: string): Env {
  return {
    DB: {} as D1Database,
    EXPORTS: {} as R2Bucket,
    ASSETS: kind === "account" ? { fetch: async () => new Response(null, { status: 404 }) } as unknown as Fetcher : undefined,
    LIFECYCLE_QUEUE: kind === "ingest" ? undefined : {
      send: async () => undefined,
    } as unknown as Queue<LifecycleMessage>,
    ENVIRONMENT: "production",
    SERVICE_PROFILE: kind,
    DEPLOYMENT_REVISION: "a".repeat(40),
    PUBLIC_ORIGIN: origin,
    EXPORT_ENDPOINT_ORIGIN: kind === "account" ? "https://api.healthmd.app" : undefined,
    AUTH_SIGNUP_MODE: "closed",
    AUTH_EMAIL_FROM: kind === "account" ? "Health.md Cloud <cloud@healthmd.app>" : "",
    RESEND_API_KEY: kind === "account" ? "synthetic-provider-secret" : "",
    IDENTITY_KEY_B64: kind === "account" ? Buffer.alloc(32, 5).toString("base64") : undefined,
    EXPORT_ENCRYPTION_KEYS_JSON: kind === "maintenance" ? undefined : JSON.stringify({
      v1: Buffer.alloc(32, 6).toString("base64"),
    }),
    CURRENT_EXPORT_KEY_ID: "v1",
    ACCOUNT_KEY_MODE: "per_account",
    CURRENT_ACCOUNT_WRAPPING_KEY_ID: "kek-v1",
    ACCOUNT_KEY_WRAPPING_KEYS_JSON: JSON.stringify({
      "kek-v1": Buffer.alloc(32, 7).toString("base64"),
    }),
    CLOUD_RUNTIME_APPROVED: "healthmd-cloud-v1-reviewed",
    HEALTH_FREE_METRICS_REQUIRED: "1",
    METRICS: { writeDataPoint: () => undefined } as AnalyticsEngineDataset,
    MAX_EXPORT_BYTES: "26214400",
    SESSION_TTL_DAYS: "30",
    MAGIC_LINK_TTL_MINUTES: "15",
    EMAIL_SEND_HOURLY_LIMIT: kind === "account" ? "100" : undefined,
    INGEST_TOKEN_HOURLY_LIMIT: kind === "ingest" ? "120" : undefined,
    INGEST_ACCOUNT_HOURLY_LIMIT: kind === "ingest" ? "240" : undefined,
    REVISION_RETENTION_DAYS: kind === "maintenance" ? "30" : undefined,
    DELETION_STATUS_TTL_DAYS: kind === "ingest" ? undefined : "30",
  } as Env;
}

describe("split production Worker profiles", () => {
  it("keeps the ingest Worker write-only and strips browser authority", async () => {
    const env = profile("ingest", "https://api.healthmd.app");
    const health = await ingestWorker.fetch(new Request("https://api.healthmd.app/health"), env);
    expect(health.status).toBe(200);
    expect(await health.json()).toEqual({ status: "ok", revision: "aaaaaaaaaaaa" });
    const denied = await ingestWorker.fetch(new Request("https://api.healthmd.app/api/account", {
      headers: { Cookie: "sensitive=session" },
    }), env);
    expect(denied.status).toBe(404);
    expect(denied.headers.get("cache-control")).toBe("no-store");
    const upload = await ingestWorker.fetch(new Request("https://api.healthmd.app/api/v1/exports", {
      method: "POST",
      headers: { Cookie: "sensitive=session", "Content-Type": "application/json" },
      body: "{}",
    }), env);
    expect(upload.status).toBe(401);
    expect(upload.headers.get("set-cookie")).toBeNull();
    expect((await ingestWorker.fetch(new Request("https://api.healthmd.app/api/security-events"), env)).status)
      .toBe(404);
  });

  it("keeps the account Worker from accepting ingest or MCP traffic", async () => {
    const env = profile("account", "https://account.healthmd.app");
    expect((await accountWorker.fetch(new Request("https://account.healthmd.app/health"), env)).status).toBe(200);
    expect((await accountWorker.fetch(new Request("https://account.healthmd.app/api/v1/exports", {
      method: "POST", headers: { "Content-Type": "application/json" }, body: "{}",
    }), env)).status).toBe(404);
    expect((await accountWorker.fetch(new Request("https://account.healthmd.app/mcp", {
      method: "POST", headers: { "Content-Type": "application/json" }, body: "{}",
    }), env)).status).toBe(404);
    expect((await accountWorker.fetch(new Request("https://account.healthmd.app/api/security-events"), env)).status)
      .toBe(401);
  });

  it("gives maintenance no public HTTP surface and fails closed on profile mismatch", async () => {
    const maintenance = profile("maintenance", "https://maintenance.healthmd.app");
    expect((await maintenanceWorker.fetch(new Request("https://maintenance.healthmd.app/health"),
      maintenance)).status).toBe(404);
    const wrong = profile("account", "https://api.healthmd.app");
    const response = await ingestWorker.fetch(new Request("https://api.healthmd.app/health"), wrong);
    expect(response.status).toBe(500);
    expect(await response.json()).toEqual({
      error: "internal_error", message: "The request could not be completed.",
    });
  });

  it("fails closed when required telemetry or account wrapping keys are absent", async () => {
    const noMetrics = profile("ingest", "https://api.healthmd.app");
    noMetrics.METRICS = undefined;
    expect((await ingestWorker.fetch(new Request("https://api.healthmd.app/health"), noMetrics)).status).toBe(500);

    const noWrappingKey = profile("account", "https://account.healthmd.app");
    noWrappingKey.ACCOUNT_KEY_WRAPPING_KEYS_JSON = undefined;
    expect((await accountWorker.fetch(new Request("https://account.healthmd.app/health"), noWrappingKey)).status)
      .toBe(500);

    const noIdentityKey = profile("account", "https://account.healthmd.app");
    delete (noIdentityKey as Partial<Env>).IDENTITY_KEY_B64;
    expect((await accountWorker.fetch(new Request("https://account.healthmd.app/health"), noIdentityKey)).status)
      .toBe(500);

    const malformedIdentityKey = profile("account", "https://account.healthmd.app");
    malformedIdentityKey.IDENTITY_KEY_B64 = Buffer.alloc(31).toString("base64");
    expect((await accountWorker.fetch(new Request("https://account.healthmd.app/health"),
      malformedIdentityKey)).status).toBe(500);

    const noLegacyKeys = profile("ingest", "https://api.healthmd.app");
    delete (noLegacyKeys as Partial<Env>).EXPORT_ENCRYPTION_KEYS_JSON;
    expect((await ingestWorker.fetch(new Request("https://api.healthmd.app/health"), noLegacyKeys)).status).toBe(500);

    const missingCurrentLegacyKey = profile("account", "https://account.healthmd.app");
    missingCurrentLegacyKey.EXPORT_ENCRYPTION_KEYS_JSON = JSON.stringify({
      historical: Buffer.alloc(32, 6).toString("base64"),
    });
    expect((await accountWorker.fetch(new Request("https://account.healthmd.app/health"),
      missingCurrentLegacyKey)).status).toBe(500);

    const reusedIdentityKey = profile("account", "https://account.healthmd.app");
    reusedIdentityKey.EXPORT_ENCRYPTION_KEYS_JSON = JSON.stringify({ v1: reusedIdentityKey.IDENTITY_KEY_B64 });
    expect((await accountWorker.fetch(new Request("https://account.healthmd.app/health"),
      reusedIdentityKey)).status).toBe(500);

    const reusedWrappingKey = profile("ingest", "https://api.healthmd.app");
    reusedWrappingKey.ACCOUNT_KEY_WRAPPING_KEYS_JSON = JSON.stringify({
      "kek-v1": Buffer.alloc(32, 6).toString("base64"),
    });
    expect((await ingestWorker.fetch(new Request("https://api.healthmd.app/health"),
      reusedWrappingKey)).status).toBe(500);

    const duplicateHistoricalKek = profile("maintenance", "https://maintenance.healthmd.app");
    duplicateHistoricalKek.ACCOUNT_KEY_WRAPPING_KEYS_JSON = JSON.stringify({
      "kek-v1": Buffer.alloc(32, 7).toString("base64"),
      historical: Buffer.alloc(32, 7).toString("base64"),
    });
    await expect(maintenanceWorker.scheduled({} as ScheduledEvent, duplicateHistoricalKek))
      .rejects.toThrow("configuration is incomplete");

    const noAbuseBudget = profile("ingest", "https://api.healthmd.app");
    noAbuseBudget.INGEST_ACCOUNT_HOURLY_LIMIT = undefined;
    expect((await ingestWorker.fetch(new Request("https://api.healthmd.app/health"), noAbuseBudget)).status)
      .toBe(500);

    const noDatabase = profile("ingest", "https://api.healthmd.app");
    delete (noDatabase as Partial<Env>).DB;
    expect((await ingestWorker.fetch(new Request("https://api.healthmd.app/health"), noDatabase)).status).toBe(500);

    const noBucket = profile("account", "https://account.healthmd.app");
    delete (noBucket as Partial<Env>).EXPORTS;
    expect((await accountWorker.fetch(new Request("https://account.healthmd.app/health"), noBucket)).status)
      .toBe(500);

    const noAssets = profile("account", "https://account.healthmd.app");
    delete (noAssets as Partial<Env>).ASSETS;
    expect((await accountWorker.fetch(new Request("https://account.healthmd.app/health"), noAssets)).status)
      .toBe(500);

    const excessIngestAssets = profile("ingest", "https://api.healthmd.app");
    excessIngestAssets.ASSETS = { fetch: async () => new Response() } as unknown as Fetcher;
    expect((await ingestWorker.fetch(new Request("https://api.healthmd.app/health"),
      excessIngestAssets)).status).toBe(500);

    const excessIngestQueue = profile("ingest", "https://api.healthmd.app");
    excessIngestQueue.LIFECYCLE_QUEUE = { send: async () => undefined } as unknown as Queue<LifecycleMessage>;
    expect((await ingestWorker.fetch(new Request("https://api.healthmd.app/health"),
      excessIngestQueue)).status).toBe(500);

    const excessIngestIdentity = profile("ingest", "https://api.healthmd.app");
    excessIngestIdentity.IDENTITY_KEY_B64 = Buffer.alloc(32, 5).toString("base64");
    expect((await ingestWorker.fetch(new Request("https://api.healthmd.app/health"),
      excessIngestIdentity)).status).toBe(500);

    const noLifecycleQueue = profile("account", "https://account.healthmd.app");
    noLifecycleQueue.LIFECYCLE_QUEUE = undefined;
    expect((await accountWorker.fetch(new Request("https://account.healthmd.app/health"),
      noLifecycleQueue)).status).toBe(500);

    const noExportEndpoint = profile("account", "https://account.healthmd.app");
    noExportEndpoint.EXPORT_ENDPOINT_ORIGIN = undefined;
    expect((await accountWorker.fetch(new Request("https://account.healthmd.app/health"),
      noExportEndpoint)).status).toBe(500);

    const malformedExportEndpoint = profile("account", "https://account.healthmd.app");
    malformedExportEndpoint.EXPORT_ENDPOINT_ORIGIN = "https://token@example.invalid/upload";
    expect((await accountWorker.fetch(new Request("https://account.healthmd.app/health"),
      malformedExportEndpoint)).status).toBe(500);

    const sameExportEndpoint = profile("account", "https://account.healthmd.app");
    sameExportEndpoint.EXPORT_ENDPOINT_ORIGIN = sameExportEndpoint.PUBLIC_ORIGIN;
    expect((await accountWorker.fetch(new Request("https://account.healthmd.app/health"),
      sameExportEndpoint)).status).toBe(500);

    const noMaintenanceQueue = profile("maintenance", "https://maintenance.healthmd.app");
    noMaintenanceQueue.LIFECYCLE_QUEUE = undefined;
    await expect(maintenanceWorker.scheduled({} as ScheduledEvent, noMaintenanceQueue))
      .rejects.toThrow("configuration is incomplete");

    const excessMaintenanceAssets = profile("maintenance", "https://maintenance.healthmd.app");
    excessMaintenanceAssets.ASSETS = { fetch: async () => new Response() } as unknown as Fetcher;
    await expect(maintenanceWorker.scheduled({} as ScheduledEvent, excessMaintenanceAssets))
      .rejects.toThrow("configuration is incomplete");

    const excessMaintenanceLegacyKey = profile("maintenance", "https://maintenance.healthmd.app");
    excessMaintenanceLegacyKey.EXPORT_ENCRYPTION_KEYS_JSON = JSON.stringify({
      v1: Buffer.alloc(32, 6).toString("base64"),
    });
    await expect(maintenanceWorker.scheduled({} as ScheduledEvent, excessMaintenanceLegacyKey))
      .rejects.toThrow("configuration is incomplete");

    const unapprovedRepair = profile("account", "https://account.healthmd.app");
    unapprovedRepair.CLOUD_REPAIR_DEVICE_ENROLLMENT_ENABLED = "1";
    expect((await accountWorker.fetch(new Request("https://account.healthmd.app/health"),
      unapprovedRepair)).status).toBe(500);

    const emptyBatch = { messages: [] } as unknown as MessageBatch<LifecycleMessage>;
    await expect(maintenanceWorker.queue(emptyBatch,
      profile("maintenance", "https://maintenance.healthmd.app"))).resolves.toBeUndefined();
    const unapprovedQueue = profile("maintenance", "https://maintenance.healthmd.app");
    unapprovedQueue.CLOUD_RUNTIME_APPROVED = undefined;
    await expect(maintenanceWorker.queue(emptyBatch, unapprovedQueue))
      .rejects.toThrow("configuration is incomplete");

    const noPayloadLimit = profile("ingest", "https://api.healthmd.app");
    delete (noPayloadLimit as Partial<Env>).MAX_EXPORT_BYTES;
    expect((await ingestWorker.fetch(new Request("https://api.healthmd.app/health"), noPayloadLimit)).status)
      .toBe(500);

    const invalidSessionTtl = profile("account", "https://account.healthmd.app");
    invalidSessionTtl.SESSION_TTL_DAYS = "31";
    expect((await accountWorker.fetch(new Request("https://account.healthmd.app/health"),
      invalidSessionTtl)).status).toBe(500);

    const noMagicLinkTtl = profile("account", "https://account.healthmd.app");
    delete (noMagicLinkTtl as Partial<Env>).MAGIC_LINK_TTL_MINUTES;
    expect((await accountWorker.fetch(new Request("https://account.healthmd.app/health"),
      noMagicLinkTtl)).status).toBe(500);

    const unlimitedProductionRevisions = profile("maintenance", "https://maintenance.healthmd.app");
    unlimitedProductionRevisions.REVISION_RETENTION_DAYS = "unlimited";
    await expect(maintenanceWorker.scheduled({} as ScheduledEvent, unlimitedProductionRevisions))
      .rejects.toThrow("configuration is incomplete");

    const placeholderRevision = profile("account", "https://account.healthmd.app");
    placeholderRevision.DEPLOYMENT_REVISION = "REPLACE_WITH_FULL_GIT_COMMIT_SHA";
    expect((await accountWorker.fetch(new Request("https://account.healthmd.app/health"),
      placeholderRevision)).status).toBe(500);

    const invalidSignupMode = profile("account", "https://account.healthmd.app");
    invalidSignupMode.AUTH_SIGNUP_MODE = "invalid" as Env["AUTH_SIGNUP_MODE"];
    expect((await accountWorker.fetch(new Request("https://account.healthmd.app/health"),
      invalidSignupMode)).status).toBe(500);
  });

  it("does not require account email credentials in non-identity profiles", async () => {
    const ingest = profile("ingest", "https://api.healthmd.app");
    ingest.RESEND_API_KEY = "";
    ingest.AUTH_EMAIL_FROM = "";
    expect((await ingestWorker.fetch(new Request("https://api.healthmd.app/health"), ingest)).status).toBe(200);

    const account = profile("account", "https://account.healthmd.app");
    account.RESEND_API_KEY = "";
    expect((await accountWorker.fetch(new Request("https://account.healthmd.app/health"), account)).status).toBe(500);

    const noSender = profile("account", "https://account.healthmd.app");
    noSender.AUTH_EMAIL_FROM = "";
    expect((await accountWorker.fetch(new Request("https://account.healthmd.app/health"), noSender)).status)
      .toBe(500);

    const passwordAccount = profile("account", "https://account.healthmd.app");
    passwordAccount.AUTH_MODE = "password";
    passwordAccount.PASSWORD_PEPPER_B64 = Buffer.alloc(32, 9).toString("base64");
    expect((await accountWorker.fetch(new Request("https://account.healthmd.app/health"),
      passwordAccount)).status).toBe(500);

    const unusedPasswordPepper = profile("account", "https://account.healthmd.app");
    unusedPasswordPepper.PASSWORD_PEPPER_B64 = Buffer.alloc(32, 9).toString("base64");
    expect((await accountWorker.fetch(new Request("https://account.healthmd.app/health"),
      unusedPasswordPepper)).status).toBe(500);
  });
});
