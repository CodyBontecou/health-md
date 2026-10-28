/** Notification-only router: deployed APNs v1 plus an opt-in FCM v2 extension. */
import { jsonResponse } from "./http";

// Keep the inherited optional bindings; this slice does not mutate deployment config.
export interface Env {
  DB?: D1Database;
  APNS_AUTH_KEY?: string;
  APNS_KEY_ID?: string;
  APNS_TEAM_ID?: string;
  APNS_HOST?: "api.push.apple.com" | "api.sandbox.push.apple.com";
  BUNDLE_ID?: string;
  /** Optional private service-account configuration. Never returned or logged. */
  FCM_SERVICE_ACCOUNT_JSON?: string;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const { method } = request;
    const { pathname } = new URL(request.url);
    if (pathname === "/health") {
      if (method !== "GET") return jsonResponse({ error: "Method not allowed" }, 405);
      return jsonResponse({ ok: true, service: "healthmd-wake" });
    }
    const isWakeRegister = pathname === "/wake/register";
    const isWakeRequest = pathname === "/wake/request";
    const isV2Register = pathname === "/wake/v2/register";
    const isV2Request = pathname === "/wake/v2/request";
    if (!isWakeRegister && !isWakeRequest && !isV2Register && !isV2Request) {
      return jsonResponse({ error: "Not found" }, 404);
    }
    const registerMethodOk = (isWakeRegister || isV2Register) && (method === "POST" || method === "DELETE");
    const requestMethodOk = (isWakeRequest || isV2Request) && method === "POST";
    if (!registerMethodOk && !requestMethodOk) return jsonResponse({ error: "Method not allowed" }, 405);
    if (!env.DB) return jsonResponse({ error: "D1 binding not configured" }, 503);

    try {
      const wakeEnv = { DB: env.DB };
      if (isV2Request) {
        const { handleV2Request } = await import("./v2-delivery");
        return await handleV2Request(request, wakeEnv, env.FCM_SERVICE_ACCOUNT_JSON);
      }
      if (isV2Register) {
        const { handleV2Register, handleV2Unregister } = await import("./v2");
        return await (method === "DELETE" ? handleV2Unregister : handleV2Register)(request, wakeEnv);
      }
      const { handleWakeRegister, handleWakeUnregister, handleWakeRequest } = await import("./wake");
      if (isWakeRegister) {
        return await (method === "DELETE" ? handleWakeUnregister : handleWakeRegister)(request, wakeEnv);
      }
      const apns = env.APNS_AUTH_KEY && env.APNS_KEY_ID && env.APNS_TEAM_ID ? {
        authKey: env.APNS_AUTH_KEY,
        keyId: env.APNS_KEY_ID,
        teamId: env.APNS_TEAM_ID,
        host: env.APNS_HOST ?? "api.push.apple.com",
        bundleId: env.BUNDLE_ID ?? "com.codybontecou.obsidianhealth",
      } : null;
      return await handleWakeRequest(request, wakeEnv, apns);
    } catch {
      // Do not allow D1 errors (which may contain bindings) into platform exception logs.
      return jsonResponse({ error: "wake_storage_unavailable" }, 503);
    }
  },
} satisfies ExportedHandler<Env>;
