import {
  buildAppStoreUrl,
  buildDownloadUrl,
  buildPlayStoreUrl,
  parseCampaignSlug,
} from "../../../campaign-links.mjs";
import { FUNNEL_ENDPOINT } from "../../../assets/funnel-contract.js";
import { handleWebFunnel } from "./web-funnel.js";

// Known date-style YouTube links predate the current campaign-token format.
// Recover their content intent without inventing store/install attribution.
const LEGACY_GUIDE_REDIRECTS = Object.freeze({
  "/v/yt-csv-0702": "/apple-health-to-csv/",
  "/v/yt-obsidian-0702": "/blog/export-apple-health-data-to-obsidian/",
  "/v/yt-obsidian-0703": "/blog/export-apple-health-data-to-obsidian/",
  "/v/yt-obsidian-070312": "/blog/export-apple-health-data-to-obsidian/",
});

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
  // Remove the next cutoff day too: daily buckets must not exceed retention
  // between scheduled sweeps. This does not change native attribution retention.
  const funnelCutoff = monthsAgoClamped(new Date(now.getTime() + 24 * 60 * 60 * 1_000), 13);
  const rateWindowCutoff = new Date(now.getTime() - 24 * 60 * 60 * 1_000).toISOString();
  await env.DB.batch([
    env.DB.prepare("DELETE FROM campaign_clicks WHERE created_at < ?")
      .bind(attributionCutoff.toISOString()),
    env.DB.prepare("DELETE FROM campaign_installs WHERE received_at < ?")
      .bind(attributionCutoff.toISOString()),
    env.DB.prepare("DELETE FROM campaign_ingest_windows WHERE window_start < ?")
      .bind(rateWindowCutoff),
    env.DB.prepare("DELETE FROM web_funnel_daily WHERE day <= ?")
      .bind(funnelCutoff.toISOString().slice(0, 10)),
    env.DB.prepare("DELETE FROM web_funnel_ingest_windows WHERE window_start < ?")
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
    if (url.pathname === FUNNEL_ENDPOINT) return handleWebFunnel(request, env);
    if (url.pathname === INSTALL_INGEST_PATH) {
      // Retired app attribution: drop legacy uploads without reading the body or DB.
      return new Response(null, { status: request.method === "POST" ? 204 : 410,
        headers: { "cache-control": "no-store" } });
    }

    if (request.method !== "GET" && request.method !== "HEAD") {
      return jsonResponse({ error: "Method not allowed" }, 405);
    }

    if (url.pathname === "/health") {
      return jsonResponse({ ok: true, service: "healthmd-campaign-redirects" });
    }

    const legacyPath = url.pathname.replace(/\/$/, "");
    if (Object.hasOwn(LEGACY_GUIDE_REDIRECTS, legacyPath)) {
      return new Response(null, {
        status: 301,
        headers: {
          location: new URL(LEGACY_GUIDE_REDIRECTS[legacyPath], "https://healthmd.app").href,
          "cache-control": "public, max-age=3600",
          "referrer-policy": "no-referrer",
        },
      });
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
