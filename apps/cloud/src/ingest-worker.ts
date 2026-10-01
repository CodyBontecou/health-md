import core, { validateConfiguration } from "./index";
import { errorResponse, json, withSecurityHeaders } from "./http";
import { recordHttpMetric } from "./telemetry";
import type { Env } from "./types";

function allowed(request: Request): boolean {
  const path = new URL(request.url).pathname;
  return (request.method === "POST" && path === "/api/v1/exports") ||
    (request.method === "GET" && path === "/health");
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
      if (env.SERVICE_PROFILE !== "ingest") response = withSecurityHeaders(errorResponse(new Error()), env);
      else if (!allowed(request)) response = denied(env);
      else {
        const headers = new Headers(request.headers);
        headers.delete("Cookie");
        const result = await core.fetch(new Request(request, { headers }), env);
        const responseHeaders = new Headers(result.headers);
        responseHeaders.delete("Set-Cookie");
        response = new Response(result.body, {
          status: result.status,
          statusText: result.statusText,
          headers: responseHeaders,
        });
      }
    } catch {
      response = withSecurityHeaders(errorResponse(new Error()), env);
    }
    recordHttpMetric(env, "ingest", request, response, started);
    return response;
  },
};
