import {
  accountSummary, consumeMagicLink, createIngestToken, getSession, listIngestTokens, listSecurityActivity,
  listSessions, logout, requestMagicLink, requireSession, revokeIngestToken, revokeOtherSessions, revokeSession,
} from "./auth";
import { downloadExport, ingest, listDayPage, listExportPage, listExports } from "./exports";
import { downloadAccountExportPage } from "./account-export";
import { rewrapAccountExportKeys } from "./account-export-keys";
import { dashboardTrends, exploreCatalog, exploreChart } from "./dashboard";
import { exploreExports, exploreNode } from "./explore";
import { createAgentToken, listAgentTokens, revokeAgentToken } from "./agent-tokens";
import { passwordLogin } from "./password";
import { cancelRepairDraft, createRepairDraft, listRepairDrafts, previewRepairRequest,
  purgeExpiredRepairDrafts } from "./repair-drafts";
import { approveRepairDevice, listRepairDevices, purgeExpiredRepairDevices,
  repairDeviceStatus, revokeRepairDevice, startRepairDeviceEnrollment } from "./repair-devices";
import { readSupplementEvidence } from "./repair-supplements";
import { cancelRepairDispatch, claimRepairDispatch, declineRepairDispatch,
  listRepairDispatches, queueRepairDispatch, resumeRepairDispatch } from "./repair-dispatch";
import { getAccountDeletionStatus, processAccountDeletions, purgeArchivedRevisions,
  purgeExpiredDeletionReceipts, requestAccountDeletion } from "./lifecycle";
import { reconcileUploadIntents } from "./upload-intents";
import { reconcileOrphanExportObjects } from "./object-reconciliation";
import { errorResponse, HttpError, json, parsePositiveInteger, redirect, withSecurityHeaders } from "./http";
import { decodeBase64, parseExportKeyring } from "./crypto";
import type { Env } from "./types";

const STATIC_PATHS = new Set(["/login", "/dashboard", "/dashboard.js", "/explore", "/explore.js",
  "/repair", "/repair.js", "/repair-panel", "/deletion-status", "/deletion-status.js", "/style.css"]);
const STATIC_CSP = "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'";

function validateConfiguration(env: Env): void {
  if (env.ENVIRONMENT !== "development" && env.ENVIRONMENT !== "production") {
    throw new Error("Invalid deployment environment");
  }
  if (env.AUTH_MODE && env.AUTH_MODE !== "email_link" && env.AUTH_MODE !== "password") {
    throw new Error("Invalid authentication mode");
  }
  const profile = env.SERVICE_PROFILE ?? "combined";
  if (!["combined", "ingest", "account", "maintenance"].includes(profile)) {
    throw new Error("Invalid service profile");
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
    const splitNonIdentity = profile === "ingest" || profile === "maintenance";
    const invalidProductionIdentity = splitNonIdentity ?
      (env.AUTH_SIGNUP_MODE !== "closed" || env.AUTH_MODE === "password" || !!env.PASSWORD_PEPPER_B64) :
      (env.AUTH_MODE === "password" ? (!env.PASSWORD_PEPPER_B64 || env.AUTH_SIGNUP_MODE !== "closed") :
        (!env.RESEND_API_KEY || !env.AUTH_EMAIL_FROM || env.AUTH_EMAIL_FROM.includes("example")));
    let invalidIdentityKey = false;
    if (profile === "account" || profile === "combined") {
      try { invalidIdentityKey = decodeBase64(env.IDENTITY_KEY_B64 ?? "").byteLength !== 32; }
      catch { invalidIdentityKey = true; }
    }
    let invalidLegacyKeys = false;
    if (profile === "ingest" || profile === "account" || profile === "combined") {
      try {
        invalidLegacyKeys = !parseExportKeyring(env.EXPORT_ENCRYPTION_KEYS_JSON ?? "")
          .has(env.CURRENT_EXPORT_KEY_ID);
      } catch { invalidLegacyKeys = true; }
    }
    const invalidMetrics = profile !== "combined" &&
      (env.HEALTH_FREE_METRICS_REQUIRED !== "1" || !env.METRICS);
    const invalidDeploymentRevision = profile !== "combined" &&
      !/^[a-f0-9]{40}$/u.test(env.DEPLOYMENT_REVISION ?? "");
    let invalidDeletionTtl = false;
    if (profile === "account" || profile === "maintenance") {
      try {
        if (!env.DELETION_STATUS_TTL_DAYS) invalidDeletionTtl = true;
        else parsePositiveInteger(env.DELETION_STATUS_TTL_DAYS, "DELETION_STATUS_TTL_DAYS", 1, 90);
      } catch { invalidDeletionTtl = true; }
    }
    let invalidAbuseLimits = false;
    try {
      if (profile === "ingest") {
        if (!env.INGEST_TOKEN_HOURLY_LIMIT || !env.INGEST_ACCOUNT_HOURLY_LIMIT) invalidAbuseLimits = true;
        else {
          parsePositiveInteger(env.INGEST_TOKEN_HOURLY_LIMIT, "INGEST_TOKEN_HOURLY_LIMIT", 1, 100_000);
          parsePositiveInteger(env.INGEST_ACCOUNT_HOURLY_LIMIT, "INGEST_ACCOUNT_HOURLY_LIMIT", 1, 100_000);
        }
      } else if (profile === "account") {
        if (!env.EMAIL_SEND_HOURLY_LIMIT) invalidAbuseLimits = true;
        else parsePositiveInteger(env.EMAIL_SEND_HOURLY_LIMIT, "EMAIL_SEND_HOURLY_LIMIT", 1, 100_000);
      }
    } catch { invalidAbuseLimits = true; }
    let invalidAccountKeys = false;
    if (profile === "ingest" || profile === "account" || profile === "maintenance") {
      try {
        const keys = parseExportKeyring(env.ACCOUNT_KEY_WRAPPING_KEYS_JSON ?? "");
        invalidAccountKeys = env.ACCOUNT_KEY_MODE !== "per_account" ||
          !env.CURRENT_ACCOUNT_WRAPPING_KEY_ID || !keys.has(env.CURRENT_ACCOUNT_WRAPPING_KEY_ID);
      } catch { invalidAccountKeys = true; }
    }
    if (env.SYNTHETIC_PREVIEW_ONLY || env.DEV_SHOW_MAGIC_LINK || env.AUTH_SIGNUP_MODE === "open" ||
        (personalMvp ? (profile !== "combined" || env.CLOUD_RUNTIME_APPROVED !== undefined ||
          env.AUTH_MODE !== "password" || env.AUTH_SIGNUP_MODE !== "closed" ||
          env.REVISION_RETENTION_DAYS !== "unlimited" || !env.PASSWORD_PEPPER_B64 ||
          invalidIdentityKey || invalidLegacyKeys) :
          (env.CLOUD_RUNTIME_APPROVED !== "healthmd-cloud-v1-reviewed" || invalidProductionIdentity ||
            invalidAccountKeys || invalidIdentityKey || invalidLegacyKeys || invalidMetrics ||
            invalidDeletionTtl || invalidAbuseLimits || invalidDeploymentRevision)) ||
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
    return json({ status: "ok", ...(env.DEPLOYMENT_REVISION ?
      { revision: env.DEPLOYMENT_REVISION.slice(0, 12) } : {}) });
  }
  if (method === "GET" && path === "/api/runtime") {
    return json({ syntheticPreviewOnly: env.SYNTHETIC_PREVIEW_ONLY === "1",
      unbackedPersonalMvp: env.VM_PERSONAL_MVP_NO_BACKUP_ACK === "I_ACCEPT_PERMANENT_DATA_LOSS",
      authMode: env.AUTH_MODE ?? "email_link",
      exportEndpoint: `${env.EXPORT_ENDPOINT_ORIGIN ?? env.PUBLIC_ORIGIN}/api/v1/exports` });
  }
  if (method === "GET" && path === "/") return redirect("/dashboard");
  if (method === "GET" && (path === "/login.html" || path === "/dashboard.html" ||
      path === "/deletion-status.html")) {
    return redirect(path.slice(0, -5), 307);
  }
  if (method === "GET" && STATIC_PATHS.has(path)) {
    if ((path === "/dashboard" || path === "/explore" || path === "/repair" || path === "/repair-panel") &&
        !await getSession(request, env)) {
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
    return requestAccountDeletion(request, env, await requireSession(request, env));
  }
  if (method === "GET" && path === "/api/account/deletion-status") {
    return getAccountDeletionStatus(request, env);
  }
  if (method === "GET" && path === "/api/sessions") {
    return listSessions(env, await requireSession(request, env));
  }
  if (method === "GET" && path === "/api/security-events") {
    return listSecurityActivity(env, (await requireSession(request, env)).id);
  }
  if (method === "POST" && path === "/api/sessions/revoke-others") {
    return revokeOtherSessions(request, env, await requireSession(request, env));
  }
  const sessionRevoke = /^\/api\/sessions\/([a-f0-9-]{36})$/u.exec(path);
  if (method === "DELETE" && sessionRevoke?.[1]) {
    return revokeSession(request, env, await requireSession(request, env), sessionRevoke[1]);
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
  if (method === "POST" && path === "/api/repair/device/enroll") {
    return startRepairDeviceEnrollment(request, env);
  }
  if (method === "GET" && path === "/api/repair/device/status") {
    return repairDeviceStatus(request, env);
  }
  if (method === "GET" && path === "/api/repair/devices") {
    return listRepairDevices(env, (await requireSession(request, env)).id);
  }
  if (method === "POST" && path === "/api/repair/devices/approve") {
    return approveRepairDevice(request, env, (await requireSession(request, env)).id);
  }
  const revokeDevice = /^\/api\/repair\/devices\/([a-f0-9-]{36})$/u.exec(path);
  if (method === "DELETE" && revokeDevice?.[1]) {
    return revokeRepairDevice(request, env, (await requireSession(request, env)).id, revokeDevice[1]);
  }
  if (method === "GET" && path === "/api/repair/dispatches") {
    return listRepairDispatches(env, (await requireSession(request, env)).id);
  }
  if (method === "POST" && path === "/api/repair/dispatch") {
    return queueRepairDispatch(request, env, (await requireSession(request, env)).id);
  }
  if (method === "POST" && path === "/api/repair/dispatch/cancel") {
    return cancelRepairDispatch(request, env, (await requireSession(request, env)).id);
  }
  if (method === "POST" && path === "/api/repair/device/claim") {
    return claimRepairDispatch(request, env);
  }
  if (method === "POST" && path === "/api/repair/device/resume") {
    return resumeRepairDispatch(request, env);
  }
  if (method === "POST" && path === "/api/repair/device/decline") {
    return declineRepairDispatch(request, env);
  }
  if (method === "GET" && path === "/api/repair/drafts") {
    return listRepairDrafts(env, (await requireSession(request, env)).id);
  }
  if (method === "POST" && path === "/api/repair/preview") {
    return previewRepairRequest(request, env, (await requireSession(request, env)).id);
  }
  if (method === "POST" && path === "/api/repair/supplements") {
    return readSupplementEvidence(request, env, (await requireSession(request, env)).id);
  }
  if (method === "POST" && path === "/api/repair/drafts") {
    return createRepairDraft(request, env, (await requireSession(request, env)).id);
  }
  const cancelDraft = /^\/api\/repair\/drafts\/([a-f0-9-]{36})$/u.exec(path);
  if (method === "DELETE" && cancelDraft?.[1]) {
    return cancelRepairDraft(request, env, (await requireSession(request, env)).id, cancelDraft[1]);
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
  const accountExportPage = /^\/api\/account\/export\/page\/([0-9]{1,8})$/u.exec(path);
  if (method === "GET" && accountExportPage?.[1]) {
    return downloadAccountExportPage(env, (await requireSession(request, env)).id,
      Number(accountExportPage[1]));
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
    await purgeExpiredRepairDrafts(env);
    await purgeExpiredRepairDevices(env);
    await purgeExpiredDeletionReceipts(env);
    await reconcileUploadIntents(env);
    if (env.SERVICE_PROFILE === "maintenance") await reconcileOrphanExportObjects(env);
    if (env.ACCOUNT_KEY_MODE === "per_account") await rewrapAccountExportKeys(env);
  },
};
