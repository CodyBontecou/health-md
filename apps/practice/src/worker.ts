import type { PracticeErrorResponse } from "./contracts/api";
import { parsePracticeEnvironment, PracticeConfigurationError } from "./environment";
import { jsonResponse, withSecurityHeaders } from "./http/security";
import { handleClinicalOperation } from "./http/clinical-api";
import { syntheticCatalog, syntheticMeta } from "./synthetic/catalog";
import { isPortalRoute } from "./web/routes";

export interface PracticeWorkerEnv {
  PRACTICE_RUNTIME_MODE?: string | undefined;
  ASSETS: Fetcher;
}

const assetPaths = new Set(["/styles.css", "/assets/app.js"]);

function errorResponse(
  code: PracticeErrorResponse["error"]["code"],
  message: string,
  status: number,
): Response {
  return jsonResponse({ error: { code, message } } satisfies PracticeErrorResponse, { status });
}

async function handleRequest(request: Request, env: PracticeWorkerEnv): Promise<Response> {
  parsePracticeEnvironment(env);
  const url = new URL(request.url);

  if (url.search || url.hash) {
    return errorResponse("not_found", "The requested resource is unavailable", 404);
  }

  if (url.pathname === "/api/v1/operation") {
    return handleClinicalOperation(request);
  }

  if (request.method !== "GET") {
    return errorResponse("method_not_allowed", "The requested operation is unavailable", 405);
  }

  if (url.pathname === "/api/v1/meta") {
    return jsonResponse(syntheticMeta);
  }
  if (url.pathname === "/api/v1/catalog") {
    return jsonResponse(syntheticCatalog);
  }
  if (url.pathname.startsWith("/api/")) {
    return errorResponse("not_found", "The requested resource is unavailable", 404);
  }

  if (assetPaths.has(url.pathname)) {
    return withSecurityHeaders(await env.ASSETS.fetch(request));
  }
  if (isPortalRoute(url.pathname)) {
    const indexRequest = new Request(new URL("/", request.url), request);
    return withSecurityHeaders(await env.ASSETS.fetch(indexRequest));
  }

  return withSecurityHeaders(new Response("Not found", {
    status: 404,
    headers: { "Content-Type": "text/plain; charset=utf-8" },
  }));
}

export default {
  async fetch(request: Request, env: PracticeWorkerEnv): Promise<Response> {
    try {
      return await handleRequest(request, env);
    } catch (error) {
      if (error instanceof PracticeConfigurationError) {
        return errorResponse(
          "configuration_unavailable",
          "Practice runtime is unavailable",
          503,
        );
      }
      return errorResponse("configuration_unavailable", "Practice runtime is unavailable", 503);
    }
  },
};
