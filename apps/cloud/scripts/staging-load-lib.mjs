import { readFileSync, statSync } from "node:fs";

export const TWO_X_CONCURRENCY = 500;
export const TWO_X_UPLOADS_PER_SECOND = 50;
export const DEFAULT_DURATION_SECONDS = 600;
export const MAX_REQUESTS_PER_ACCOUNT = 50;
export const SUSTAINED_REQUESTS_PER_ACCOUNT = MAX_REQUESTS_PER_ACCOUNT - 3;
export const DEDICATED_SLOW_BODY_ACCOUNTS = 1;
export const ADMISSION_LEASE_SECONDS = 15 * 60;
export const SLOW_BODY_TIMEOUT_MS = (ADMISSION_LEASE_SECONDS + 2 * 60) * 1_000;
export const MAX_EXPORT_BYTES = 25 * 1024 * 1024;

const LIVE_HOSTS = new Set([
  "api.healthmd.app", "account.healthmd.app", "mcp.healthmd.app", "healthmd.app", "www.healthmd.app",
]);

function integer(value, fallback, minimum, maximum, label) {
  const parsed = value === undefined || value === "" ? fallback : Number(value);
  if (!Number.isInteger(parsed) || parsed < minimum || parsed > maximum) {
    throw new Error(`${label} must be an integer from ${minimum} to ${maximum}`);
  }
  return parsed;
}

export function parseStagingLoadConfig(environment = process.env) {
  if (environment.HEALTHMD_LOAD_CONFIRM_SYNTHETIC_ONLY !== "SYNTHETIC_ONLY") {
    throw new Error("Synthetic-only confirmation is required");
  }
  if (environment.HEALTHMD_LOAD_DISTINCT_ACCOUNTS !== "YES") {
    throw new Error("Distinct synthetic-account attestation is required");
  }
  const endpoint = new URL(environment.HEALTHMD_LOAD_ENDPOINT ?? "");
  if (endpoint.protocol !== "https:" || endpoint.username || endpoint.password || endpoint.search || endpoint.hash ||
      endpoint.pathname !== "/api/v1/exports") {
    throw new Error("Staging endpoint must be an exact credential-free HTTPS export URL");
  }
  if (LIVE_HOSTS.has(endpoint.hostname) || !/(?:^|[.-])(staging|synthetic)(?:[.-]|$)/u.test(endpoint.hostname)) {
    throw new Error("Refusing a live or non-staging hostname");
  }
  const expectedRevision = environment.HEALTHMD_LOAD_EXPECTED_REVISION ?? "";
  if (!/^[a-f0-9]{40}$/u.test(expectedRevision)) throw new Error("Expected full deployment revision is required");
  const concurrency = integer(environment.HEALTHMD_LOAD_CONCURRENCY, TWO_X_CONCURRENCY, 1, 1_000, "Concurrency");
  const uploadsPerSecond = integer(environment.HEALTHMD_LOAD_UPLOADS_PER_SECOND,
    TWO_X_UPLOADS_PER_SECOND, 1, 100, "Uploads per second");
  const durationSeconds = integer(environment.HEALTHMD_LOAD_DURATION_SECONDS,
    DEFAULT_DURATION_SECONDS, 1, 3_600, "Duration seconds");
  const largeConcurrency = integer(environment.HEALTHMD_LOAD_LARGE_CONCURRENCY, 10, 1, 10,
    "Large concurrency");
  return { endpoint, expectedRevision, concurrency, uploadsPerSecond, durationSeconds, largeConcurrency };
}

export function readDistinctAccountTokens(path, requiredCount) {
  if (!path) throw new Error("Owner-only synthetic token file is required");
  const metadata = statSync(path);
  if (!metadata.isFile() || (metadata.mode & 0o077) !== 0) {
    throw new Error("Synthetic token file must be a regular owner-only file");
  }
  if (metadata.size > 256 * 1024) throw new Error("Synthetic token file is too large");
  const tokens = readFileSync(path, "utf8").split(/\r?\n/u).map((line) => line.trim()).filter(Boolean);
  if (tokens.some((token) => !/^hmd_ing_[A-Za-z0-9_-]{20,200}$/u.test(token))) {
    throw new Error("Synthetic token file contains an invalid token");
  }
  if (new Set(tokens).size !== tokens.length) throw new Error("Synthetic token file contains duplicates");
  if (tokens.length < requiredCount) throw new Error(`At least ${requiredCount} distinct synthetic accounts are required`);
  return tokens;
}

export function requiredDistinctAccounts(config) {
  const sustained = config.uploadsPerSecond * config.durationSeconds;
  return Math.max(Math.ceil(config.concurrency / 2), config.largeConcurrency,
    Math.ceil(sustained / SUSTAINED_REQUESTS_PER_ACCOUNT)) + DEDICATED_SLOW_BODY_ACCOUNTS;
}

export function fragmentedRequestBody(bytes, chunkBytes = 16_381) {
  if (!(bytes instanceof Uint8Array) || bytes.byteLength === 0 ||
      !Number.isSafeInteger(chunkBytes) || chunkBytes < 1 || chunkBytes > 64 * 1024) {
    throw new Error("Synthetic fragmented request configuration is invalid");
  }
  let offset = 0;
  return new ReadableStream({
    pull(controller) {
      if (offset >= bytes.byteLength) {
        controller.close();
        return;
      }
      const end = Math.min(bytes.byteLength, offset + chunkBytes);
      controller.enqueue(bytes.subarray(offset, end));
      offset = end;
    },
  });
}

export function stalledRequestBody() {
  const prefix = new TextEncoder().encode('{"schema":"healthmd.api_export","synthetic_stalled":');
  return new ReadableStream({
    start(controller) { controller.enqueue(prefix); },
  });
}

export function nextEligibleAccount(active, launched, cursor) {
  if (!Array.isArray(active) || !Array.isArray(launched) || active.length === 0 ||
      active.length !== launched.length || !Number.isInteger(cursor) || cursor < 0 || cursor >= active.length) {
    throw new Error("Synthetic account scheduler state is invalid");
  }
  for (let offset = 0; offset < active.length; offset += 1) {
    const candidate = (cursor + offset) % active.length;
    if (active[candidate] < 2 && launched[candidate] < SUSTAINED_REQUESTS_PER_ACCOUNT) return candidate;
  }
  return -1;
}

export function buildSyntheticEnvelope(targetBytes = 1_024, marker = "synthetic") {
  if (!Number.isInteger(targetBytes) || targetBytes < 512 || targetBytes > MAX_EXPORT_BYTES) {
    throw new Error("Synthetic envelope byte target is outside the supported range");
  }
  const envelope = {
    schema: "healthmd.api_export",
    schema_version: 1,
    daily_record_schema: "healthmd.health_data",
    daily_record_schema_version: 8,
    exported_at: "2020-01-02T03:04:05.000Z",
    source: "ios",
    date_range: { start: "2020-01-01", end: "2020-01-01" },
    record_count: 1,
    records: [{
      schema: "healthmd.health_data", schema_version: 8, date: "2020-01-01",
      raw_capture_status: "not_requested", synthetic_load_fixture: true,
      synthetic_marker: marker.slice(0, 80), synthetic_padding: "",
    }],
    failed_date_details: [],
  };
  const encoder = new TextEncoder();
  const baseline = encoder.encode(JSON.stringify(envelope)).byteLength;
  if (baseline > targetBytes) throw new Error("Synthetic envelope byte target is too small");
  envelope.records[0].synthetic_padding = "x".repeat(targetBytes - baseline);
  const bytes = encoder.encode(JSON.stringify(envelope));
  if (bytes.byteLength !== targetBytes) throw new Error("Synthetic envelope construction was not exact");
  return bytes;
}

export function percentile(values, quantile) {
  if (!values.length) return null;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.ceil(quantile * sorted.length) - 1)];
}
