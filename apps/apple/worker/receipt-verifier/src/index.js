import { routeNotificationRequest } from "./notifications.js";
import { handleScheduled } from "./scheduled.js";

var __defProp = Object.defineProperty;
var __getOwnPropNames = Object.getOwnPropertyNames;
var __name = (target, value) => __defProp(target, "name", { value, configurable: true });
var __esm = (fn, res) => function __init() {
  return fn && (res = (0, fn[__getOwnPropNames(fn)[0]])(fn = 0)), res;
};
var __export = (target, all) => {
  for (var name in all)
    __defProp(target, name, { get: all[name], enumerable: true });
};

// src/index.ts
function base64urlDecode(input) {
  let b64 = input.replace(/-/g, "+").replace(/_/g, "/");
  while (b64.length % 4 !== 0)
    b64 += "=";
  return atob(b64);
}
function decodeAppTransactionJWS(jws) {
  const parts = jws.split(".");
  if (parts.length !== 3)
    return null;
  try {
    const payload = JSON.parse(base64urlDecode(parts[1]));
    if (!payload.bundleId || !payload.originalApplicationVersion)
      return null;
    if (typeof payload.originalPurchaseDate !== "number")
      return null;
    return payload;
  } catch {
    return null;
  }
}
function isPlausiblePurchaseDate(ms, now = Date.now()) {
  if (!Number.isFinite(ms))
    return false;
  if (ms < MIN_PLAUSIBLE_PURCHASE_MS)
    return false;
  if (ms > now + 24 * 60 * 60 * 1e3)
    return false;
  return true;
}
function isLegacyUnlock(originalPurchaseDateMs) {
  return new Date(originalPurchaseDateMs) < GRANDFATHER_CUTOFF_DATE;
}
async function verifyWithApple(receiptData, sharedSecret, url) {
  const body = {
    "receipt-data": receiptData,
    "exclude-old-transactions": false
  };
  if (sharedSecret) {
    body["password"] = sharedSecret;
  }
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body)
  });
  return response.json();
}
function jsonResponse2(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      // Receipts are sensitive — never cache this response.
      "Cache-Control": "no-store"
    }
  });
}
var BUNDLE_ID, GRANDFATHER_CUTOFF_DATE, APPLE_PRODUCTION_URL, APPLE_SANDBOX_URL, MIN_PLAUSIBLE_PURCHASE_MS, src_default;
var init_src = __esm({
  "src/index.ts"() {
    BUNDLE_ID = "com.codybontecou.obsidianhealth";
    GRANDFATHER_CUTOFF_DATE = /* @__PURE__ */ new Date("2026-04-26T00:00:00Z");
    APPLE_PRODUCTION_URL = "https://buy.itunes.apple.com/verifyReceipt";
    APPLE_SANDBOX_URL = "https://sandbox.itunes.apple.com/verifyReceipt";
    __name(base64urlDecode, "base64urlDecode");
    __name(decodeAppTransactionJWS, "decodeAppTransactionJWS");
    MIN_PLAUSIBLE_PURCHASE_MS = (/* @__PURE__ */ new Date("2008-07-10T00:00:00Z")).getTime();
    __name(isPlausiblePurchaseDate, "isPlausiblePurchaseDate");
    __name(isLegacyUnlock, "isLegacyUnlock");
    __name(verifyWithApple, "verifyWithApple");
    __name(jsonResponse2, "jsonResponse");
    src_default = {
      async fetch(request, env) {
        const { method, url } = request;
        const { pathname } = new URL(url);
        if (pathname === "/health" && method === "GET") {
          return jsonResponse2({ ok: true });
        }
        const notificationResponse = await routeNotificationRequest(request, env);
        if (notificationResponse) return notificationResponse;
        if (method !== "POST") {
          return jsonResponse2({ error: "Method not allowed" }, 405);
        }
        if (pathname === "/verify-legacy-jws") {
          let body2;
          try {
            body2 = await request.json();
          } catch {
            return jsonResponse2({ error: "Invalid JSON body" }, 400);
          }
          if (!body2.jws || typeof body2.jws !== "string") {
            return jsonResponse2({ error: "Missing or invalid 'jws' field" }, 400);
          }
          const payload = decodeAppTransactionJWS(body2.jws);
          if (!payload) {
            return jsonResponse2({ error: "Invalid JWS structure" }, 400);
          }
          if (payload.bundleId !== BUNDLE_ID) {
            return jsonResponse2({ error: "Bundle ID mismatch" }, 400);
          }
          const originalVersion2 = payload.originalApplicationVersion;
          const originalPurchaseDateMs2 = payload.originalPurchaseDate;
          if (!isPlausiblePurchaseDate(originalPurchaseDateMs2)) {
            return jsonResponse2({ error: "Implausible originalPurchaseDate" }, 400);
          }
          const isLegacy2 = env.DEBUG_FORCE_LEGACY === "true" ? true : isLegacyUnlock(originalPurchaseDateMs2);
          console.log(JSON.stringify({
            route: "/verify-legacy-jws",
            isLegacy: isLegacy2,
            originalVersion: originalVersion2,
            originalPurchaseDateMs: originalPurchaseDateMs2,
            rayId: request.headers.get("cf-ray") ?? null
          }));
          return jsonResponse2({ isLegacy: isLegacy2, originalVersion: originalVersion2 });
        }
        if (pathname !== "/verify-legacy") {
          return jsonResponse2({ error: "Not found" }, 404);
        }
        let body;
        try {
          body = await request.json();
        } catch {
          return jsonResponse2({ error: "Invalid JSON body" }, 400);
        }
        if (!body.receipt || typeof body.receipt !== "string") {
          return jsonResponse2({ error: "Missing or invalid 'receipt' field" }, 400);
        }
        let result = await verifyWithApple(body.receipt, env.APPLE_SHARED_SECRET, APPLE_PRODUCTION_URL);
        if (result.status === 21007) {
          result = await verifyWithApple(body.receipt, env.APPLE_SHARED_SECRET, APPLE_SANDBOX_URL);
        }
        if (result.status !== 0) {
          return jsonResponse2(
            { error: "Apple receipt verification failed", appleStatus: result.status },
            400
          );
        }
        if (!result.receipt) {
          return jsonResponse2({ error: "No receipt data in Apple response" }, 400);
        }
        if (result.receipt.bundle_id !== BUNDLE_ID) {
          return jsonResponse2({ error: "Bundle ID mismatch" }, 400);
        }
        const originalVersion = result.receipt.original_application_version;
        const purchaseDateMsRaw = result.receipt.original_purchase_date_ms;
        if (!purchaseDateMsRaw) {
          return jsonResponse2({ error: "Receipt missing original_purchase_date_ms" }, 400);
        }
        const originalPurchaseDateMs = Number(purchaseDateMsRaw);
        if (!isPlausiblePurchaseDate(originalPurchaseDateMs)) {
          return jsonResponse2({ error: "Implausible original_purchase_date_ms" }, 400);
        }
        const isLegacy = env.DEBUG_FORCE_LEGACY === "true" ? true : isLegacyUnlock(originalPurchaseDateMs);
        console.log(JSON.stringify({
          route: "/verify-legacy",
          isLegacy,
          originalVersion,
          originalPurchaseDateMs,
          rayId: request.headers.get("cf-ray") ?? null
        }));
        return jsonResponse2({ isLegacy, originalVersion });
      },
      async scheduled(event, env, ctx) {
        return handleScheduled(event, env, ctx);
      }
    };
  }
});
init_src();
export {
  BUNDLE_ID,
  GRANDFATHER_CUTOFF_DATE,
  MIN_PLAUSIBLE_PURCHASE_MS,
  base64urlDecode,
  decodeAppTransactionJWS,
  src_default as default,
  isLegacyUnlock,
  isPlausiblePurchaseDate
};
