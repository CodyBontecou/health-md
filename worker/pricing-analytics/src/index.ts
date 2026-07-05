export interface Env {
  DB: D1Database;
  INGEST_TOKEN?: string;
  MAX_BATCH_SIZE?: string;
}

type PricingValue = string | number;
type PricingProperties = Record<string, PricingValue>;

type PricingEventRow = {
  id: string;
  installId: string;
  eventName: string;
  properties: PricingProperties;
};

const MAX_BODY_BYTES = 64 * 1024;
const DEFAULT_MAX_BATCH_SIZE = 50;

const EVENT_NAMES = new Set([
  "pricing_paywall_viewed",
  "pricing_onboarding_started",
  "pricing_onboarding_step_viewed",
  "pricing_onboarding_folder_selected",
  "pricing_onboarding_continue_free_tapped",
  "pricing_onboarding_purchase_tapped",
  "pricing_onboarding_completed",
  "pricing_health_authorization_completed",
  "pricing_export_preview_opened",
  "pricing_export_preview_generated",
  "pricing_export_preview_failed",
  "pricing_export_succeeded",
  "pricing_free_export_used",
  "pricing_paywall_shown",
  "pricing_paywall_cta_tapped",
  "pricing_export_blocked_by_quota",
  "pricing_purchase_started",
  "pricing_purchase_finished",
  "pricing_restore_started",
  "pricing_restore_finished",
  "pricing_schedule_enable_blocked",
  "pricing_schedule_enable_unblocked",
]);

const STRING_PROPERTY_KEYS = new Set([
  "experimentId",
  "variantId",
  "appVersion",
  "buildNumber",
  "platform",
  "paywallContext",
  "onboardingStep",
  "exportTargetType",
  "metricCountBucket",
  "dateRangePreset",
  "dateSpanBucket",
  "productId",
  "purchaseOutcome",
  "authorizationStatus",
  "errorCategory",
]);

const INTEGER_PROPERTY_KEYS = new Set([
  "freeExportsUsed",
  "freeExportsRemaining",
  "formatCount",
]);

const ALLOWED_PROPERTY_KEYS = new Set([
  ...STRING_PROPERTY_KEYS,
  ...INTEGER_PROPERTY_KEYS,
]);

const KNOWN_EXPERIMENT_IDS = new Set([
  "pricing_subscription_transition",
  // Kept so older released builds can continue flushing queued events.
  "pricing_lifetime_unlock",
]);
const KNOWN_VARIANT_IDS = new Set([
  "baseline_lifetime_only",
  "subscription_lifetime_mix",
  // Kept so older released builds can continue flushing queued events.
  "baseline_lifetime_current",
  "test_lifetime_1499",
]);
const PLATFORMS = new Set(["ios", "macos"]);
const ONBOARDING_STEPS = new Set(["welcome", "health_access", "sample_export", "obsidian_plugin", "folder_setup", "unlock", "ready"]);
const PAYWALL_CONTEXTS = new Set([
  "export",
  "onboarding",
  "settings",
  "schedule",
  "shortcut",
  "mac_target",
  "export_quota",
  "restore",
]);
const EXPORT_TARGET_TYPES = new Set(["local_file", "connected_mac", "preview_only"]);
const METRIC_COUNT_BUCKETS = new Set(["0", "1_5", "6_10", "11_20", "21_plus"]);
const DATE_RANGE_PRESETS = new Set(["today", "yesterday", "last_7_days", "last_30_days", "all_time", "custom"]);
const DATE_SPAN_BUCKETS = new Set(["same_day", "1_7_days", "8_30_days", "31_90_days", "91_plus_days"]);
const PRODUCT_IDS = new Set([
  "com.codybontecou.obsidianhealth.pro.monthly",
  "com.codybontecou.obsidianhealth.pro.yearly",
  "com.codybontecou.obsidianhealth.unlock",
  "com.codybontecou.obsidianhealth.pro.family.monthly",
  "com.codybontecou.obsidianhealth.pro.family.yearly",
  "com.codybontecou.obsidianhealth.unlock.family",
  "com.codybontecou.obsidianhealth.unlock.family.upgrade",
]);
const PURCHASE_OUTCOMES = new Set(["started", "succeeded", "failed", "cancelled", "pending"]);
const AUTHORIZATION_STATUSES = new Set(["authorized", "not_authorized", "unavailable", "unknown"]);
const ERROR_CATEGORIES = new Set([
  "network_unavailable",
  "store_unavailable",
  "user_cancelled",
  "payment_not_allowed",
  "verification_failed",
  "configuration_unavailable",
  "no_data",
  "not_unlocked",
  "unknown",
]);

const IDENTIFIER_RE = /^[a-z0-9._-]{1,80}$/;
const APP_VERSION_RE = /^\d+(?:\.\d+){0,3}$/;
const BUILD_NUMBER_RE = /^\d{1,12}$/;
const INSTALL_ID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const RAW_DATE_PATTERNS = [
  /(?:^|[^0-9])(?:19|20)\d{2}[-_.](?:0[1-9]|1[0-2])[-_.](?:0[1-9]|[12]\d|3[01])(?:$|[^0-9])/,
  /(?:^|[^0-9])(?:19|20)\d{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\d|3[01])(?:$|[^0-9])/,
];
const SENSITIVE_IDENTIFIER_TOKENS = [
  "hkquantity",
  "hkcategory",
  "hkcorrelation",
  "hksample",
  "step",
  "heart",
  "blood",
  "sleep",
  "workout",
  "medication",
  "medicine",
  "metformin",
  "insulin",
  "dose",
  "health",
  "calorie",
  "energy",
  "distance",
  "weight",
  "body",
  "mindful",
  "respiratory",
  "vault",
  "folder",
  "file",
  "obsidian",
  "documents",
  "desktop",
  "downloads",
  "icloud",
];

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const pathname = normalizedPathname(url.pathname);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }

    if (request.method === "GET" && pathname === "/health") {
      return json({ ok: true, service: "health-md-pricing-analytics" });
    }

    if (request.method === "POST" && pathname === "/v1/events") {
      return ingestEvents(request, env);
    }

    return json({ ok: false, error: "not_found" }, 404);
  },
};

async function ingestEvents(request: Request, env: Env): Promise<Response> {
  const authError = authorize(request, env);
  if (authError) return authError;

  const contentLength = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(contentLength) && contentLength > MAX_BODY_BYTES) {
    return json({ ok: false, error: "body_too_large" }, 413);
  }

  const rawBody = await request.text();
  if (new TextEncoder().encode(rawBody).byteLength > MAX_BODY_BYTES) {
    return json({ ok: false, error: "body_too_large" }, 413);
  }

  let body: unknown;
  try {
    body = JSON.parse(rawBody);
  } catch {
    return json({ ok: false, error: "invalid_json" }, 400);
  }

  let rows: PricingEventRow[];
  try {
    rows = normalizeIngestBody(body, maxBatchSize(env));
  } catch (error) {
    return json({ ok: false, error: error instanceof Error ? error.message : "invalid_payload" }, 400);
  }

  if (rows.length === 0) {
    return json({ ok: false, error: "empty_batch" }, 400);
  }

  const insert = env.DB.prepare(`
    INSERT OR IGNORE INTO pricing_events (
      id,
      install_id,
      event_name,
      experiment_id,
      variant_id,
      app_version,
      build_number,
      platform,
      paywall_context,
      onboarding_step,
      free_exports_used,
      free_exports_remaining,
      export_target_type,
      format_count,
      metric_count_bucket,
      date_range_preset,
      date_span_bucket,
      product_id,
      purchase_outcome,
      authorization_status,
      error_category,
      payload_json
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);

  await env.DB.batch(rows.map((row) => insert.bind(
    row.id,
    row.installId,
    row.eventName,
    stringProperty(row.properties, "experimentId"),
    stringProperty(row.properties, "variantId"),
    stringProperty(row.properties, "appVersion"),
    stringProperty(row.properties, "buildNumber"),
    stringProperty(row.properties, "platform"),
    stringProperty(row.properties, "paywallContext"),
    stringProperty(row.properties, "onboardingStep"),
    integerProperty(row.properties, "freeExportsUsed"),
    integerProperty(row.properties, "freeExportsRemaining"),
    stringProperty(row.properties, "exportTargetType"),
    integerProperty(row.properties, "formatCount"),
    stringProperty(row.properties, "metricCountBucket"),
    stringProperty(row.properties, "dateRangePreset"),
    stringProperty(row.properties, "dateSpanBucket"),
    stringProperty(row.properties, "productId"),
    stringProperty(row.properties, "purchaseOutcome"),
    stringProperty(row.properties, "authorizationStatus"),
    stringProperty(row.properties, "errorCategory"),
    JSON.stringify({ eventName: row.eventName, properties: row.properties }),
  )));

  return json({ ok: true, accepted: rows.length });
}

function normalizeIngestBody(body: unknown, maxBatch: number): PricingEventRow[] {
  if (!isObject(body)) throw new Error("payload_must_be_object");

  const batchInstallId = optionalString(body.installId);
  const incomingEvents = Array.isArray(body.events) ? body.events : [body];

  if (incomingEvents.length > maxBatch) throw new Error("batch_too_large");

  return incomingEvents.map((event) => normalizeEvent(event, batchInstallId));
}

function normalizeEvent(event: unknown, batchInstallId: string | undefined): PricingEventRow {
  if (!isObject(event)) throw new Error("event_must_be_object");

  const eventName = requiredString(event.eventName, "eventName");
  if (!EVENT_NAMES.has(eventName)) throw new Error("unknown_event_name");

  const eventId = validateEventId(optionalString(event.eventId) ?? optionalString(event.id));
  const installId = validateInstallId(optionalString(event.installId) ?? batchInstallId);
  const properties = normalizeProperties(isObject(event.properties) ? event.properties : {});

  return {
    id: storageEventId(eventId, installId, eventName, properties),
    installId,
    eventName,
    properties,
  };
}

function normalizeProperties(properties: Record<string, unknown>): PricingProperties {
  const normalized: PricingProperties = {};

  for (const [key, value] of Object.entries(properties)) {
    if (!ALLOWED_PROPERTY_KEYS.has(key)) throw new Error(`unknown_property:${key}`);

    if (STRING_PROPERTY_KEYS.has(key)) {
      normalized[key] = validateStringProperty(key, value);
      continue;
    }

    if (INTEGER_PROPERTY_KEYS.has(key)) {
      normalized[key] = validateIntegerProperty(key, value);
    }
  }

  return normalized;
}

function storageEventId(
  eventId: string,
  installId: string,
  eventName: string,
  properties: PricingProperties,
): string {
  if (eventName === "pricing_health_authorization_completed") {
    const authorizationStatus = stringProperty(properties, "authorizationStatus") ?? "unknown";
    return `dedupe:${eventName}:${installId}:${authorizationStatus}`;
  }

  return eventId;
}

function validateStringProperty(key: string, value: unknown): string {
  if (typeof value !== "string") throw new Error(`invalid_property_type:${key}`);

  switch (key) {
    case "experimentId":
      return validateKnownIdentifier(key, value, KNOWN_EXPERIMENT_IDS);
    case "variantId":
      return validateKnownIdentifier(key, value, KNOWN_VARIANT_IDS);
    case "appVersion":
      if (!APP_VERSION_RE.test(value)) throw new Error(`invalid_property:${key}`);
      return value;
    case "buildNumber":
      if (!BUILD_NUMBER_RE.test(value)) throw new Error(`invalid_property:${key}`);
      return value;
    case "platform":
      return validateSetValue(key, value, PLATFORMS);
    case "paywallContext":
      return validateSetValue(key, value, PAYWALL_CONTEXTS);
    case "onboardingStep":
      return validateSetValue(key, value, ONBOARDING_STEPS);
    case "exportTargetType":
      return validateSetValue(key, value, EXPORT_TARGET_TYPES);
    case "metricCountBucket":
      return validateSetValue(key, value, METRIC_COUNT_BUCKETS);
    case "dateRangePreset":
      return validateSetValue(key, value, DATE_RANGE_PRESETS);
    case "dateSpanBucket":
      return validateSetValue(key, value, DATE_SPAN_BUCKETS);
    case "productId":
      return validateSetValue(key, value, PRODUCT_IDS);
    case "purchaseOutcome":
      return validateSetValue(key, value, PURCHASE_OUTCOMES);
    case "authorizationStatus":
      return validateSetValue(key, value, AUTHORIZATION_STATUSES);
    case "errorCategory":
      return validateSetValue(key, value, ERROR_CATEGORIES);
    default:
      throw new Error(`unknown_property:${key}`);
  }
}

function validateIntegerProperty(key: string, value: unknown): number {
  if (typeof value !== "number" || !Number.isInteger(value)) throw new Error(`invalid_property_type:${key}`);

  if (key === "freeExportsUsed" || key === "freeExportsRemaining") {
    if (value < 0 || value > 3) throw new Error(`invalid_property:${key}`);
    return value;
  }

  if (key === "formatCount") {
    if (value < 1 || value > 4) throw new Error(`invalid_property:${key}`);
    return value;
  }

  throw new Error(`unknown_property:${key}`);
}

function validateKnownIdentifier(key: string, value: string, knownValues: Set<string>): string {
  if (!IDENTIFIER_RE.test(value)) throw new Error(`invalid_property:${key}`);
  if (RAW_DATE_PATTERNS.some((pattern) => pattern.test(value))) throw new Error(`invalid_property:${key}`);
  if (containsSensitiveIdentifierToken(value)) throw new Error(`invalid_property:${key}`);
  if (!knownValues.has(value)) throw new Error(`unknown_property_value:${key}`);
  return value;
}

function validateSetValue(key: string, value: string, allowedValues: Set<string>): string {
  if (!allowedValues.has(value)) throw new Error(`unknown_property_value:${key}`);
  return value;
}

function validateEventId(value: string | undefined): string {
  if (!value || !INSTALL_ID_RE.test(value)) throw new Error("invalid_event_id");
  return value.toLowerCase();
}

function validateInstallId(value: string | undefined): string {
  if (!value || !INSTALL_ID_RE.test(value)) throw new Error("invalid_install_id");
  return value.toLowerCase();
}

function containsSensitiveIdentifierToken(value: string): boolean {
  const normalized = value.replace(/[.-]/g, "_").toLowerCase();
  return SENSITIVE_IDENTIFIER_TOKENS.some((token) => normalized.includes(token));
}

function authorize(request: Request, env: Env): Response | undefined {
  if (!env.INGEST_TOKEN) return undefined;

  const expected = `Bearer ${env.INGEST_TOKEN}`;
  if (request.headers.get("authorization") === expected) return undefined;

  return json({ ok: false, error: "unauthorized" }, 401);
}

function maxBatchSize(env: Env): number {
  const parsed = Number(env.MAX_BATCH_SIZE ?? DEFAULT_MAX_BATCH_SIZE);
  return Number.isInteger(parsed) && parsed > 0 ? Math.min(parsed, DEFAULT_MAX_BATCH_SIZE) : DEFAULT_MAX_BATCH_SIZE;
}

function stringProperty(properties: PricingProperties, key: string): string | null {
  const value = properties[key];
  return typeof value === "string" ? value : null;
}

function integerProperty(properties: PricingProperties, key: string): number | null {
  const value = properties[key];
  return typeof value === "number" ? value : null;
}

function requiredString(value: unknown, key: string): string {
  if (typeof value !== "string" || value.length === 0) throw new Error(`missing_${key}`);
  return value;
}

function optionalString(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function json(body: unknown, status = 200): Response {
  return Response.json(body, { status, headers: corsHeaders() });
}

function normalizedPathname(pathname: string): string {
  const normalized = pathname.replace(/\/+$/, "");
  return normalized.length > 0 ? normalized : "/";
}

function corsHeaders(): HeadersInit {
  return {
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "GET,POST,OPTIONS",
    "access-control-allow-headers": "authorization,content-type",
    "cache-control": "no-store",
  };
}
