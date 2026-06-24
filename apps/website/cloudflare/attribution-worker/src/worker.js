import { buildAppStoreUrl, DEFAULT_APP_STORE_URL, parseCampaignSlug } from "../../../campaign-links.mjs";

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

function slugFromRequest(request) {
  const { pathname } = new URL(request.url);
  const match = pathname.match(/^\/v\/([^/]+)\/?$/);
  return match ? decodeURIComponent(match[1]) : null;
}

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body, null, 2), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });
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
  async fetch(request, env, ctx) {
    if (request.method !== "GET" && request.method !== "HEAD") {
      return jsonResponse({ error: "Method not allowed" }, 405);
    }

    const url = new URL(request.url);
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

    const destination = buildAppStoreUrl(link, env) || DEFAULT_APP_STORE_URL;
    const hasProviderToken = Boolean(env.APPLE_PROVIDER_TOKEN);
    const hasCustomProductPage = Boolean(link.ppidEnv && env[link.ppidEnv]);
    const event = {
      event: "healthmd_campaign_click",
      slug: link.slug,
      campaignToken: link.campaignToken,
      platform: link.platform,
      angle: link.angle,
      referrerHost: referrerHost(request),
      clientSignal: clientSignal(request),
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
      location: destination,
      "cache-control": "no-store, max-age=0",
      "referrer-policy": "strict-origin-when-cross-origin",
    });
    if (!hasProviderToken) {
      headers.set("x-healthmd-attribution-warning", "APPLE_PROVIDER_TOKEN is not set; App Store campaign attribution will be incomplete.");
    }

    return new Response(null, { status: 302, headers });
  },
};
