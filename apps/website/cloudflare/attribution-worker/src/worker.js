import {
  buildAppStoreUrl,
  buildDownloadUrl,
  buildPlayStoreUrl,
  parseCampaignSlug,
} from "../../../campaign-links.mjs";

function referrerHost(request) {
  const raw = request.headers.get("referer") || request.headers.get("referrer");
  if (!raw) return null;
  try {
    return new URL(raw).hostname;
  } catch {
    return "invalid-referrer";
  }
}

function clientSignal(request) {
  const ua = request.headers.get("user-agent") || "";
  if (/tiktok/i.test(ua)) return "tiktok";
  if (/instagram/i.test(ua)) return "instagram";
  if (/youtube|googlebot/i.test(ua)) return "youtube_or_google";
  if (/twitter|x-client/i.test(ua)) return "x";
  if (/bot|crawler|spider/i.test(ua)) return "bot";
  if (/iphone|ipad|ios/i.test(ua)) return "ios";
  if (/android/i.test(ua)) return "android";
  if (/macintosh|mac os/i.test(ua)) return "mac";
  return "other";
}

function detectOperatingSystem(request) {
  const platformHint = (request.headers.get("sec-ch-ua-platform") || "")
    .replaceAll('"', "")
    .toLowerCase();
  const ua = request.headers.get("user-agent") || "";

  if (platformHint.includes("android") || /android/i.test(ua)) return "android";
  if (platformHint.includes("ios") || /iphone|ipad|ipod/i.test(ua)) return "ios";
  if (/macintosh/i.test(ua) && /mobile/i.test(ua)) return "ios";
  if (platformHint.includes("macos") || /macintosh|mac os x/i.test(ua)) return "macos";
  return "other";
}

function redirectDestination(request, link, env) {
  const operatingSystem = detectOperatingSystem(request);

  if (operatingSystem === "android") {
    return {
      operatingSystem,
      destinationStore: "google_play",
      url: buildPlayStoreUrl(link, env),
    };
  }

  if (operatingSystem === "ios" || operatingSystem === "macos") {
    return {
      operatingSystem,
      destinationStore: "app_store",
      url: buildAppStoreUrl(link, env),
    };
  }

  return {
    operatingSystem,
    destinationStore: "download_page",
    url: buildDownloadUrl(link, env),
  };
}

function slugFromRequest(request) {
  const { pathname } = new URL(request.url);
  const match = pathname.match(/^\/v\/([^/]+)\/?$/);
  return match ? decodeURIComponent(match[1]) : null;
}

function jsonResponse(body, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
      ...extraHeaders,
    },
  });
}

const INSTALL_INGEST_PATH = "/v1/installs";
const MAX_INSTALL_BODY_BYTES = 4_096;
const MAX_INSTALLS_PER_MINUTE = 300;
const REQUIRED_INSTALL_FIELDS = new Set([
  "schemaVersion",
  "eventId",
  "installId",
  "eventName",
  "occurredAt",
  "platform",
  "appVersion",
  "buildNumber",
  "campaignToken",
  "source",
  "medium",
  "contentAngle",
]);
const OPTIONAL_INSTALL_FIELDS = new Set([
  "referrerClickTimestampSeconds",
  "installBeginTimestampSeconds",
]);
const ALLOWED_INSTALL_FIELDS = new Set([
  ...REQUIRED_INSTALL_FIELDS,
  ...OPTIONAL_INSTALL_FIELDS,
]);
const UUID_V4_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const CAMPAIGN_TOKEN_PATTERN = /^[a-z]{1,4}_[a-z0-9]+_[0-9]{3}$/;
const SOURCE_PATTERN = /^[a-z]{1,4}$/;
const CONTENT_ANGLE_PATTERN = /^[a-z0-9]+$/;
const APP_VERSION_PATTERN = /^[0-9A-Za-z._+\-]{1,32}$/;
const BUILD_NUMBER_PATTERN = /^[0-9]{1,20}$/;
const ISO_INSTANT_PATTERN = /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d{1,9}))?Z$/;

function isValidIsoInstant(value) {
  const match = ISO_INSTANT_PATTERN.exec(value);
  if (!match) return false;
  const milliseconds = (match[2] || "").padEnd(3, "0").slice(0, 3);
  const canonical = `${match[1]}.${milliseconds}Z`;
  const parsed = new Date(canonical);
  return !Number.isNaN(parsed.getTime()) && parsed.toISOString() === canonical;
}

function timingSafeEqual(left, right) {
  const encoder = new TextEncoder();
  const leftBytes = encoder.encode(left);
  const rightBytes = encoder.encode(right);
  const length = Math.max(leftBytes.length, rightBytes.length);
  let difference = leftBytes.length ^ rightBytes.length;
  for (let index = 0; index < length; index += 1) {
    difference |= (leftBytes[index] || 0) ^ (rightBytes[index] || 0);
  }
  return difference === 0;
}

function authorizationState(request, env) {
  const tokens = [
    env.CAMPAIGN_ATTRIBUTION_INGEST_TOKEN,
    env.CAMPAIGN_ATTRIBUTION_INGEST_TOKEN_PREVIOUS,
  ].filter(Boolean);
  if (tokens.length === 0) {
    return env.ALLOW_UNAUTHENTICATED_INGEST === "true"
      ? "authorized"
      : "unconfigured";
  }

  const authorization = request.headers.get("authorization") || "";
  let matches = false;
  for (const token of tokens) {
    matches = timingSafeEqual(authorization, `Bearer ${token}`) || matches;
  }
  return matches ? "authorized" : "unauthorized";
}

function normalizeOptionalTimestamp(value) {
  if (value === undefined || value === null) return null;
  if (!Number.isSafeInteger(value) || value <= 0) return undefined;
  return value;
}

function validateInstallPayload(payload) {
  if (!payload || Array.isArray(payload) || typeof payload !== "object") return null;
  const keys = Object.keys(payload);
  if (keys.some((key) => !ALLOWED_INSTALL_FIELDS.has(key))) return null;
  if ([...REQUIRED_INSTALL_FIELDS].some((key) => !Object.hasOwn(payload, key))) return null;

  const referrerClickTimestampSeconds = normalizeOptionalTimestamp(
    payload.referrerClickTimestampSeconds,
  );
  const installBeginTimestampSeconds = normalizeOptionalTimestamp(
    payload.installBeginTimestampSeconds,
  );
  if (referrerClickTimestampSeconds === undefined || installBeginTimestampSeconds === undefined) {
    return null;
  }

  if (payload.schemaVersion !== 1 ||
      payload.eventName !== "campaign_install_attributed" ||
      payload.platform !== "android" ||
      payload.medium !== "campaign_shortlink" ||
      typeof payload.eventId !== "string" || !UUID_V4_PATTERN.test(payload.eventId) ||
      typeof payload.installId !== "string" || !UUID_V4_PATTERN.test(payload.installId) ||
      typeof payload.occurredAt !== "string" || payload.occurredAt.length > 40 ||
        !isValidIsoInstant(payload.occurredAt) ||
      typeof payload.appVersion !== "string" || !APP_VERSION_PATTERN.test(payload.appVersion) ||
      typeof payload.buildNumber !== "string" || !BUILD_NUMBER_PATTERN.test(payload.buildNumber) ||
      typeof payload.campaignToken !== "string" || payload.campaignToken.length > 64 ||
        !CAMPAIGN_TOKEN_PATTERN.test(payload.campaignToken) ||
      typeof payload.source !== "string" || !SOURCE_PATTERN.test(payload.source) ||
      typeof payload.contentAngle !== "string" || payload.contentAngle.length > 32 ||
        !CONTENT_ANGLE_PATTERN.test(payload.contentAngle)) {
    return null;
  }

  const [campaignSource, campaignAngle] = payload.campaignToken.split("_");
  if (campaignSource !== payload.source || campaignAngle !== payload.contentAngle) return null;

  return {
    schemaVersion: 1,
    eventId: payload.eventId.toLowerCase(),
    installId: payload.installId.toLowerCase(),
    eventName: "campaign_install_attributed",
    occurredAt: payload.occurredAt,
    platform: "android",
    appVersion: payload.appVersion,
    buildNumber: payload.buildNumber,
    campaignToken: payload.campaignToken,
    source: payload.source,
    medium: "campaign_shortlink",
    contentAngle: payload.contentAngle,
    referrerClickTimestampSeconds,
    installBeginTimestampSeconds,
  };
}

function minuteWindowStart(date) {
  const value = new Date(date);
  value.setUTCSeconds(0, 0);
  return value.toISOString();
}

async function rateLimitInstallIngest(env, now) {
  const windowStart = minuteWindowStart(now);
  const result = await env.DB.prepare(`
    INSERT INTO campaign_ingest_windows (window_start, request_count)
    VALUES (?, 1)
    ON CONFLICT(window_start) DO UPDATE SET request_count = request_count + 1
    RETURNING request_count
  `).bind(windowStart).first();
  return Number(result?.request_count || 0) <= MAX_INSTALLS_PER_MINUTE;
}

function installRowMatches(row, event) {
  return row &&
    row.event_id === event.eventId &&
    row.install_id === event.installId &&
    row.event_name === event.eventName &&
    row.occurred_at === event.occurredAt &&
    row.platform === event.platform &&
    row.app_version === event.appVersion &&
    row.build_number === event.buildNumber &&
    row.campaign_token === event.campaignToken &&
    row.source === event.source &&
    row.medium === event.medium &&
    row.content_angle === event.contentAngle &&
    (row.referrer_click_timestamp_seconds ?? null) === event.referrerClickTimestampSeconds &&
    (row.install_begin_timestamp_seconds ?? null) === event.installBeginTimestampSeconds;
}

async function persistInstall(env, event, receivedAt) {
  const result = await env.DB.prepare(`
    INSERT OR IGNORE INTO campaign_installs (
      event_id,
      install_id,
      event_name,
      occurred_at,
      platform,
      app_version,
      build_number,
      campaign_token,
      source,
      medium,
      content_angle,
      referrer_click_timestamp_seconds,
      install_begin_timestamp_seconds,
      received_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(
    event.eventId,
    event.installId,
    event.eventName,
    event.occurredAt,
    event.platform,
    event.appVersion,
    event.buildNumber,
    event.campaignToken,
    event.source,
    event.medium,
    event.contentAngle,
    event.referrerClickTimestampSeconds,
    event.installBeginTimestampSeconds,
    receivedAt,
  ).run();

  if (Number(result.meta?.changes || 0) > 0) return "inserted";
  const existing = await env.DB.prepare(
    "SELECT * FROM campaign_installs WHERE event_id = ?",
  ).bind(event.eventId).first();
  return installRowMatches(existing, event) ? "duplicate" : "conflict";
}

async function readJsonBody(request) {
  const declaredLength = Number(request.headers.get("content-length") || 0);
  if (declaredLength > MAX_INSTALL_BODY_BYTES) return { error: "too_large" };
  if (!request.body) return { error: "invalid_json" };

  const reader = request.body.getReader();
  const chunks = [];
  let byteCount = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    byteCount += value.byteLength;
    if (byteCount > MAX_INSTALL_BODY_BYTES) {
      await reader.cancel().catch(() => undefined);
      return { error: "too_large" };
    }
    chunks.push(value);
  }

  const bytes = new Uint8Array(byteCount);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    const text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
    return { value: JSON.parse(text) };
  } catch {
    return { error: "invalid_json" };
  }
}

async function handleInstallIngest(request, env, ctx) {
  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405, { allow: "POST" });
  }
  if (!env.DB) return jsonResponse({ error: "Service unavailable" }, 503);
  const authorization = authorizationState(request, env);
  if (authorization === "unconfigured") {
    return jsonResponse({ error: "Service unavailable" }, 503);
  }
  if (authorization !== "authorized") {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }
  const mediaType = (request.headers.get("content-type") || "")
    .split(";", 1)[0]
    .trim()
    .toLowerCase();
  if (mediaType !== "application/json") {
    return jsonResponse({ error: "Content-Type must be application/json" }, 415);
  }

  const now = new Date();
  try {
    if (!await rateLimitInstallIngest(env, now)) {
      return jsonResponse({ error: "Rate limited" }, 429, { "retry-after": "60" });
    }
  } catch {
    return jsonResponse({ error: "Service unavailable" }, 503);
  }

  const parsed = await readJsonBody(request);
  if (parsed.error === "too_large") return jsonResponse({ error: "Payload too large" }, 413);
  if (parsed.error) return jsonResponse({ error: "Invalid JSON" }, 400);
  const event = validateInstallPayload(parsed.value);
  if (!event) return jsonResponse({ error: "Invalid attribution event" }, 400);

  try {
    const persistenceResult = await persistInstall(env, event, now.toISOString());
    if (persistenceResult === "inserted") {
      return jsonResponse({ accepted: true, duplicate: false }, 202);
    }
    if (persistenceResult === "duplicate") {
      return jsonResponse({ accepted: true, duplicate: true }, 200);
    }
    return jsonResponse({ error: "Event or install ID conflict" }, 409);
  } catch {
    return jsonResponse({ error: "Service unavailable" }, 503);
  }
}

function monthsAgoClamped(now, months) {
  const targetMonthIndex = now.getUTCFullYear() * 12 + now.getUTCMonth() - months;
  const targetYear = Math.floor(targetMonthIndex / 12);
  const targetMonth = ((targetMonthIndex % 12) + 12) % 12;
  const lastTargetDay = new Date(Date.UTC(targetYear, targetMonth + 1, 0)).getUTCDate();
  return new Date(Date.UTC(
    targetYear,
    targetMonth,
    Math.min(now.getUTCDate(), lastTargetDay),
    now.getUTCHours(),
    now.getUTCMinutes(),
    now.getUTCSeconds(),
    now.getUTCMilliseconds(),
  ));
}

async function deleteExpiredAttribution(env, now = new Date()) {
  if (!env.DB) throw new Error("Campaign attribution database is unavailable");
  const attributionCutoff = monthsAgoClamped(now, 13);
  const rateWindowCutoff = new Date(now.getTime() - 24 * 60 * 60 * 1_000).toISOString();
  await env.DB.batch([
    env.DB.prepare("DELETE FROM campaign_clicks WHERE created_at < ?")
      .bind(attributionCutoff.toISOString()),
    env.DB.prepare("DELETE FROM campaign_installs WHERE received_at < ?")
      .bind(attributionCutoff.toISOString()),
    env.DB.prepare("DELETE FROM campaign_ingest_windows WHERE window_start < ?")
      .bind(rateWindowCutoff),
  ]);
}

async function recordClick(env, event) {
  if (!env.DB) return;
  await env.DB.prepare(`
    INSERT INTO campaign_clicks (
      slug,
      campaign_token,
      platform,
      angle,
      referrer_host,
      client_signal,
      country,
      has_provider_token,
      has_custom_product_page,
      created_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(
    event.slug,
    event.campaignToken,
    event.platform,
    event.angle,
    event.referrerHost,
    event.clientSignal,
    event.country,
    event.hasProviderToken ? 1 : 0,
    event.hasCustomProductPage ? 1 : 0,
    event.ts,
  ).run();
}

export default {
  async scheduled(controller, env, ctx) {
    ctx.waitUntil(
      deleteExpiredAttribution(env, new Date(controller.scheduledTime))
        .catch(() => {
          console.error("Campaign attribution retention failed");
          throw new Error("Campaign attribution retention failed");
        }),
    );
  },

  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (url.pathname === INSTALL_INGEST_PATH) {
      if (url.search) return jsonResponse({ error: "Query parameters are not allowed" }, 400);
      return handleInstallIngest(request, env, ctx);
    }

    if (request.method !== "GET" && request.method !== "HEAD") {
      return jsonResponse({ error: "Method not allowed" }, 405);
    }

    if (url.pathname === "/health") {
      return jsonResponse({ ok: true, service: "healthmd-campaign-redirects" });
    }

    const slug = slugFromRequest(request);
    const link = parseCampaignSlug(slug);
    if (!link) {
      return new Response("Unknown Health.md campaign link. Use /v/<platform-angle-###>.", {
        status: 404,
        headers: {
          "content-type": "text/plain; charset=utf-8",
          "cache-control": "no-store",
        },
      });
    }

    const destination = redirectDestination(request, link, env);
    const isAppStoreDestination = destination.destinationStore === "app_store";
    const hasProviderToken = isAppStoreDestination && Boolean(env.APPLE_PROVIDER_TOKEN);
    const hasCustomProductPage = isAppStoreDestination && Boolean(link.ppidEnv && env[link.ppidEnv]);
    const event = {
      event: "healthmd_campaign_click",
      slug: link.slug,
      campaignToken: link.campaignToken,
      platform: link.platform,
      angle: link.angle,
      referrerHost: referrerHost(request),
      clientSignal: clientSignal(request),
      operatingSystem: destination.operatingSystem,
      destinationStore: destination.destinationStore,
      country: request.cf?.country || null,
      hasProviderToken,
      hasCustomProductPage,
      ts: new Date().toISOString(),
    };

    console.log(JSON.stringify(event));
    if (request.method === "GET") {
      ctx.waitUntil(recordClick(env, event));
    }

    const headers = new Headers({
      location: destination.url,
      "cache-control": "no-store, max-age=0",
      "referrer-policy": "strict-origin-when-cross-origin",
    });
    if (isAppStoreDestination && !hasProviderToken) {
      headers.set("x-healthmd-attribution-warning", "APPLE_PROVIDER_TOKEN is not set; App Store campaign attribution will be incomplete.");
    }

    return new Response(null, { status: 302, headers });
  },
};
