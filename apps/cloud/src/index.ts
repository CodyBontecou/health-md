import {
  accountSummary, consumeMagicLink, createIngestToken, getSession, listIngestTokens,
  logout, requestMagicLink, requireSession, revokeIngestToken,
} from "./auth";
import { downloadExport, ingest, listDayPage, listExportPage, listExports } from "./exports";
import { dashboardTrends, exploreCatalog, exploreChart } from "./dashboard";
import { exploreExports, exploreNode } from "./explore";
import { createAgentToken, listAgentTokens, revokeAgentToken } from "./agent-tokens";
import { passwordLogin } from "./password";
import { processAccountDeletions, purgeArchivedRevisions, requestAccountDeletion } from "./lifecycle";
import { errorResponse, HttpError, json, parsePositiveInteger, redirect, withSecurityHeaders } from "./http";
import type { Env } from "./types";

const STATIC_PATHS = new Set(["/login", "/dashboard", "/dashboard.js", "/explore", "/explore.js", "/style.css"]);
const STATIC_CSP = "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'";

function validateConfiguration(env: Env): void {
  if (env.ENVIRONMENT !== "development" && env.ENVIRONMENT !== "production") {
    throw new Error("Invalid deployment environment");
  }
  if (env.AUTH_MODE && env.AUTH_MODE !== "email_link" && env.AUTH_MODE !== "password") {
    throw new Error("Invalid authentication mode");
  }
  const origin = new URL(env.PUBLIC_ORIGIN);
  if (env.ENVIRONMENT === "production" && origin.protocol !== "https:") {
    throw new Error("Production requires a HTTPS public origin");
  }
  if (origin.pathname !== "/" || origin.search || origin.hash || origin.origin !== env.PUBLIC_ORIGIN) {
    throw new Error("PUBLIC_ORIGIN must be a bare origin");
  }
  if (env.ENVIRONMENT === "production") {
    const personalMvp = env.VM_PERSONAL_MVP_NO_BACKUP_ACK === "I_ACCEPT_PERMANENT_DATA_LOSS";
    if (env.SYNTHETIC_PREVIEW_ONLY || env.DEV_SHOW_MAGIC_LINK || env.AUTH_SIGNUP_MODE === "open" ||
        (personalMvp ? (env.CLOUD_RUNTIME_APPROVED !== undefined || env.AUTH_MODE !== "password" ||
          env.AUTH_SIGNUP_MODE !== "closed" || env.REVISION_RETENTION_DAYS !== "unlimited" ||
          !env.PASSWORD_PEPPER_B64) :
          (env.CLOUD_RUNTIME_APPROVED !== "healthmd-cloud-v1-reviewed" ||
            (env.AUTH_MODE === "password" ? (!env.PASSWORD_PEPPER_B64 || env.AUTH_SIGNUP_MODE !== "closed") :
              (!env.RESEND_API_KEY || env.AUTH_EMAIL_FROM.includes("example"))))) ||
        env.CURRENT_EXPORT_KEY_ID.includes("REPLACE")) {
      throw new Error("Production or personal-MVP configuration is incomplete");
    }
  }
}

function expectedRequestOrigin(request: Request, env: Env, url: URL): boolean {
  if (url.origin === env.PUBLIC_ORIGIN) return true;
  // Wrangler's *synthetic-only* loopback preview sees Tailscale's HTTPS proxy
  // as HTTP. Never enable forwarded-header trust for production or ingestion.
  if (env.ENVIRONMENT !== "development" || env.SYNTHETIC_PREVIEW_ONLY !== "1") return false;
  const expected = new URL(env.PUBLIC_ORIGIN);
  return expected.protocol === "https:" && url.protocol === "http:" &&
    url.host === expected.host &&
    request.headers.get("X-Forwarded-Proto") === "https" &&
    request.headers.get("X-Forwarded-Host") === expected.host;
}

async function route(request: Request, env: Env): Promise<Response> {
  validateConfiguration(env);
  const url = new URL(request.url);
  if (!expectedRequestOrigin(request, env, url)) {
    throw new HttpError(421, "wrong_host", "Request host is not configured for this service.");
  }
  if (url.search && url.pathname !== "/health") {
    throw new HttpError(400, "invalid_request", "Query parameters are not supported.");
  }
  const path = url.pathname;
  const method = request.method;
  if (method === "GET" && path === "/health") {
    return json({ status: "ok" });
  }
  if (method === "GET" && path === "/api/runtime") {
    return json({ syntheticPreviewOnly: env.SYNTHETIC_PREVIEW_ONLY === "1",
      unbackedPersonalMvp: env.VM_PERSONAL_MVP_NO_BACKUP_ACK === "I_ACCEPT_PERMANENT_DATA_LOSS",
      authMode: env.AUTH_MODE ?? "email_link",
      exportEndpoint: `${env.EXPORT_ENDPOINT_ORIGIN ?? env.PUBLIC_ORIGIN}/api/v1/exports` });
  }
  if (method === "GET" && path === "/") return redirect("/dashboard");
  if (method === "GET" && (path === "/login.html" || path === "/dashboard.html")) {
    return redirect(path.slice(0, -5), 307);
  }
  if (method === "GET" && STATIC_PATHS.has(path)) {
    if ((path === "/dashboard" || path === "/explore") && !await getSession(request, env)) {
      return redirect("/login");
    }
    const asset = await env.ASSETS.fetch(request);
    const headers = new Headers(asset.headers);
    headers.set("Cache-Control", "no-store");
    headers.set("Content-Security-Policy", STATIC_CSP);
    return new Response(asset.body, { status: asset.status, headers });
  }
  if (method === "POST" && path === "/api/auth/request-link" && env.AUTH_MODE !== "password") {
    return requestMagicLink(request, env);
  }
  if (method === "POST" && path === "/api/auth/consume-link" && env.AUTH_MODE !== "password") {
    return consumeMagicLink(request, env);
  }
  if (method === "POST" && path === "/api/auth/password-login" && env.AUTH_MODE === "password") {
    return passwordLogin(request, env);
  }
  if (method === "POST" && path === "/api/v1/exports") {
    if (env.SYNTHETIC_PREVIEW_ONLY === "1") {
      throw new HttpError(403, "preview_no_ingest", "This synthetic preview does not accept exports.");
    }
    return ingest(request, env);
  }
  if (method === "GET" && path === "/api/account") {
    return accountSummary(env, await requireSession(request, env));
  }
  if (method === "POST" && path === "/api/account/delete") {
    return requestAccountDeletion(request, env, (await requireSession(request, env)).id);
  }
  if (method === "POST" && path === "/api/auth/logout") {
    return logout(request, env, await requireSession(request, env));
  }
  if (method === "GET" && path === "/api/ingest-tokens") {
    return listIngestTokens(env, (await requireSession(request, env)).id);
  }
  if (method === "POST" && path === "/api/ingest-tokens") {
    if (env.SYNTHETIC_PREVIEW_ONLY === "1") {
      throw new HttpError(403, "preview_no_ingest", "This synthetic preview does not issue export tokens.");
    }
    return createIngestToken(request, env, (await requireSession(request, env)).id);
  }
  const revoke = /^\/api\/ingest-tokens\/([a-f0-9-]{36})$/u.exec(path);
  if (method === "DELETE" && revoke?.[1]) {
    return revokeIngestToken(request, env, (await requireSession(request, env)).id, revoke[1]);
  }
  if (method === "GET" && path === "/api/agent-tokens") {
    return listAgentTokens(env, (await requireSession(request, env)).id);
  }
  if (method === "POST" && path === "/api/agent-tokens") {
    return createAgentToken(request, env, (await requireSession(request, env)).id);
  }
  const agentRevoke = /^\/api\/agent-tokens\/([a-f0-9-]{36})$/u.exec(path);
  if (method === "DELETE" && agentRevoke?.[1]) {
    return revokeAgentToken(request, env, (await requireSession(request, env)).id, agentRevoke[1]);
  }
  if (method === "GET" && path === "/api/exports") {
    return listExports(env, (await requireSession(request, env)).id);
  }
  if (method === "GET" && path === "/api/dashboard/trends") {
    return dashboardTrends(env, (await requireSession(request, env)).id);
  }
  if (method === "GET" && path === "/api/explore/catalog") {
    await requireSession(request, env);
    return exploreCatalog();
  }
  if (method === "POST" && path === "/api/explore/chart") {
    return exploreChart(request, env, (await requireSession(request, env)).id);
  }
  if (method === "POST" && path === "/api/explore/exports") {
    return exploreExports(request, env, (await requireSession(request, env)).id);
  }
  if (method === "POST" && path === "/api/explore/node") {
    return exploreNode(request, env, (await requireSession(request, env)).id);
  }
  const exportPage = /^\/api\/exports\/page\/([0-9]{1,7})$/u.exec(path);
  if (method === "GET" && exportPage?.[1]) {
    return listExportPage(env, (await requireSession(request, env)).id, Number(exportPage[1]));
  }
  const dayPage = /^\/api\/days\/page\/([0-9]{1,7})$/u.exec(path);
  if (method === "GET" && dayPage?.[1]) {
    return listDayPage(env, (await requireSession(request, env)).id, Number(dayPage[1]));
  }
  const exportDownload = /^\/api\/exports\/([a-f0-9-]{36})\/download$/u.exec(path);
  if (method === "GET" && exportDownload?.[1]) {
    return downloadExport(env, (await requireSession(request, env)).id, exportDownload[1]);
  }
  throw new HttpError(404, "not_found", "Endpoint not found.");
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      return withSecurityHeaders(await route(request, env), env);
    } catch (error) {
      // Intentionally no logging: Worker error objects may contain account or health data.
      return withSecurityHeaders(errorResponse(error), env);
    }
  },
  async scheduled(_event: ScheduledEvent, env: Env): Promise<void> {
    validateConfiguration(env);
    if (env.SYNTHETIC_PREVIEW_ONLY !== "1") {
      await processAccountDeletions(env);
      if (env.REVISION_RETENTION_DAYS && env.REVISION_RETENTION_DAYS !== "unlimited") {
        await purgeArchivedRevisions(env, parsePositiveInteger(env.REVISION_RETENTION_DAYS,
          "REVISION_RETENTION_DAYS", 1, 3650));
      }
    }
    const now = new Date().toISOString();
    await env.DB.batch([
      env.DB.prepare("DELETE FROM magic_links WHERE expires_at < ?").bind(now),
      env.DB.prepare("DELETE FROM sessions WHERE expires_at < ?").bind(now),
      env.DB.prepare("DELETE FROM auth_rate_limits WHERE expires_at < ?").bind(now),
    ]);
  },
};
