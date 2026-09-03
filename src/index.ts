/** Router for the RFC-0005 P2 wake doorbell worker. */

export interface Env {
  DB?: D1Database;
  APNS_AUTH_KEY?: string;
  APNS_KEY_ID?: string;
  APNS_TEAM_ID?: string;
  APNS_HOST?: "api.push.apple.com" | "api.sandbox.push.apple.com";
  BUNDLE_ID?: string;
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
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

    if (!isWakeRegister && !isWakeRequest) {
      return jsonResponse({ error: "Not found" }, 404);
    }

    const registerMethodOk = isWakeRegister && (method === "POST" || method === "DELETE");
    const requestMethodOk = isWakeRequest && method === "POST";
    if (!registerMethodOk && !requestMethodOk) {
      return jsonResponse({ error: "Method not allowed" }, 405);
    }

    if (!env.DB) {
      return jsonResponse({ error: "D1 binding not configured" }, 503);
    }

    const { handleWakeRegister, handleWakeUnregister, handleWakeRequest } = await import("./wake");
    const wakeEnv = { DB: env.DB };

    if (isWakeRegister && method === "POST") {
      return handleWakeRegister(request, wakeEnv);
    }
    if (isWakeRegister && method === "DELETE") {
      return handleWakeUnregister(request, wakeEnv);
    }
    if (isWakeRequest) {
      const apns =
        env.APNS_AUTH_KEY && env.APNS_KEY_ID && env.APNS_TEAM_ID
          ? {
            authKey: env.APNS_AUTH_KEY,
            keyId: env.APNS_KEY_ID,
            teamId: env.APNS_TEAM_ID,
            host: env.APNS_HOST ?? "api.push.apple.com",
            bundleId: env.BUNDLE_ID ?? "com.codybontecou.obsidianhealth",
          }
          : null;
      return handleWakeRequest(request, wakeEnv, apns);
    }

    return jsonResponse({ error: "Not found" }, 404);
  },
};
