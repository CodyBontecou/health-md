import { expect, it } from "vitest";
import ingestWorker from "../src/ingest-worker";
import accountWorker from "../src/account-worker";
import type { Env } from "../src/types";

const wrapping = Buffer.alloc(32, 9).toString("base64");

function env(profile: "ingest" | "account", points: unknown[]): Env {
  return {
    DB: {} as D1Database,
    EXPORTS: {} as R2Bucket,
    ASSETS: profile === "account" ? { fetch: async () => new Response(null, { status: 404 }) } as unknown as Fetcher : undefined,
    LIFECYCLE_QUEUE: profile === "account" ? { send: async () => undefined } as unknown as Queue : undefined,
    ENVIRONMENT: "production",
    SERVICE_PROFILE: profile,
    DEPLOYMENT_REVISION: "b".repeat(40),
    PUBLIC_ORIGIN: profile === "ingest" ? "https://api.healthmd.app" : "https://account.healthmd.app",
    AUTH_SIGNUP_MODE: "closed",
    AUTH_EMAIL_FROM: profile === "account" ? "Health.md Cloud <cloud@healthmd.app>" : "",
    RESEND_API_KEY: profile === "account" ? "synthetic-provider-secret" : "",
    IDENTITY_KEY_B64: profile === "account" ? Buffer.alloc(32, 8).toString("base64") : undefined,
    EXPORT_ENCRYPTION_KEYS_JSON: JSON.stringify({ v1: Buffer.alloc(32, 7).toString("base64") }),
    CURRENT_EXPORT_KEY_ID: "v1",
    ACCOUNT_KEY_MODE: "per_account",
    CURRENT_ACCOUNT_WRAPPING_KEY_ID: "kek-v1",
    ACCOUNT_KEY_WRAPPING_KEYS_JSON: JSON.stringify({ "kek-v1": wrapping }),
    CLOUD_RUNTIME_APPROVED: "healthmd-cloud-v1-reviewed",
    HEALTH_FREE_METRICS_REQUIRED: "1",
    METRICS: { writeDataPoint: (point: unknown) => { points.push(point); } } as AnalyticsEngineDataset,
    MAX_EXPORT_BYTES: "26214400",
    SESSION_TTL_DAYS: "30",
    MAGIC_LINK_TTL_MINUTES: "15",
    EMAIL_SEND_HOURLY_LIMIT: profile === "account" ? "100" : undefined,
    INGEST_TOKEN_HOURLY_LIMIT: profile === "ingest" ? "120" : undefined,
    INGEST_ACCOUNT_HOURLY_LIMIT: profile === "ingest" ? "240" : undefined,
    DELETION_STATUS_TTL_DAYS: profile === "account" ? "30" : undefined,
  } as Env;
}

it("records only low-cardinality buckets without request identifiers, credentials, or data", async () => {
  const points: unknown[] = [];
  const ingestEnv = env("ingest", points);
  const secretToken = "hmd_ing_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
  const sensitiveBody = JSON.stringify({ email: "person@example.test", date: "2026-01-02", value: 12345 });
  const upload = await ingestWorker.fetch(new Request("https://api.healthmd.app/api/v1/exports", {
    method: "POST",
    headers: { Authorization: `Bearer ${secretToken}`, Cookie: "private=session",
      "Content-Type": "application/json", "Content-Length": String(sensitiveBody.length) },
    body: sensitiveBody,
  }), ingestEnv);
  expect(upload.status).toBe(500); // No test DB binding; telemetry must still be bounded.

  const accountEnv = env("account", points);
  const exportId = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee";
  const response = await accountWorker.fetch(new Request(
    `https://account.healthmd.app/api/exports/${exportId}/download?private=secret`, {
      headers: { Cookie: "private=session", Authorization: "Bearer private" },
    }), accountEnv);
  expect(response.status).toBe(400);

  expect(points).toHaveLength(2);
  expect(points).toEqual([
    { indexes: ["ingest"], blobs: ["export_ingest", "5xx", expect.any(String), "le_64k"], doubles: [1] },
    { indexes: ["account"], blobs: ["export_download", "4xx", expect.any(String), "not_applicable"], doubles: [1] },
  ]);
  const serialized = JSON.stringify(points);
  for (const forbidden of [secretToken, "private=session", "person@example.test", "2026-01-02",
    "12345", exportId, "private=secret", sensitiveBody]) expect(serialized).not.toContain(forbidden);
});

it("never changes request behavior when the metrics provider fails", async () => {
  const target = env("ingest", []);
  target.METRICS = { writeDataPoint: () => { throw new Error("synthetic telemetry outage"); } } as
    AnalyticsEngineDataset;
  const response = await ingestWorker.fetch(new Request("https://api.healthmd.app/health"), target);
  expect(response.status).toBe(200);
  expect(await response.json()).toEqual({ status: "ok", revision: "bbbbbbbbbbbb" });
});
