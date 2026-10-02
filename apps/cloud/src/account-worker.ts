import core, { validateConfiguration } from "./index";
import { errorResponse, json, requestMatchesPublicEndpoint, withSecurityHeaders } from "./http";
import { recordHttpMetric } from "./telemetry";
import type { Env } from "./types";

const GET_ROUTES = new Set([
  "/", "/health", "/login", "/login.html", "/dashboard", "/dashboard.html", "/dashboard.js",
  "/explore", "/explore.js", "/repair", "/repair.js", "/repair-panel", "/deletion-status",
  "/deletion-status.js", "/style.css", "/api/runtime", "/api/account", "/api/account/deletion-status", "/api/sessions", "/api/security-events", "/api/ingest-tokens", "/api/exports",
  "/api/dashboard/trends", "/api/explore/catalog", "/api/repair/drafts",
]);

const POST_ROUTES = new Set([
  "/api/auth/request-link", "/api/auth/consume-link", "/api/auth/logout",
  "/api/sessions/revoke-others", "/api/ingest-tokens", "/api/account/delete", "/api/explore/chart",
  "/api/explore/exports", "/api/explore/node", "/api/repair/preview", "/api/repair/drafts",
  "/api/repair/supplements",
]);

function allowed(request: Request): boolean {
  const path = new URL(request.url).pathname;
  if (request.method === "GET") {
    return GET_ROUTES.has(path) || /^\/api\/exports\/[a-f0-9-]{36}\/download$/u.test(path) ||
      /^\/api\/(?:exports|days)\/page\/[0-9]{1,7}$/u.test(path) ||
      /^\/api\/account\/export\/page\/[0-9]{1,8}$/u.test(path);
  }
  if (request.method === "POST") return POST_ROUTES.has(path);
  return request.method === "DELETE" && (
    /^\/api\/repair\/drafts\/[a-f0-9-]{36}$/u.test(path) ||
    /^\/api\/sessions\/[a-f0-9-]{36}$/u.test(path) ||
    /^\/api\/ingest-tokens\/[a-f0-9-]{36}$/u.test(path));
}

function denied(env: Env): Response {
  return withSecurityHeaders(json({ error: "not_found", message: "Endpoint not found." }, { status: 404 }), env);
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const started = Date.now();
    let response: Response;
    try {
      validateConfiguration(env);
      if (env.SERVICE_PROFILE !== "account") response = withSecurityHeaders(errorResponse(new Error()), env);
      else if (!requestMatchesPublicEndpoint(request, env) || !allowed(request)) response = denied(env);
      else response = await core.fetch(request, env);
    } catch {
      response = withSecurityHeaders(errorResponse(new Error()), env);
    }
    recordHttpMetric(env, "account", request, response, started);
    return response;
  },
};
