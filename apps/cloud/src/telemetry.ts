import type { Env } from "./types";

type ServiceProfile = "ingest" | "account" | "maintenance";

function statusClass(status: number): string {
  if (status >= 200 && status < 300) return "2xx";
  if (status >= 300 && status < 400) return "3xx";
  if (status >= 400 && status < 500) return "4xx";
  return "5xx";
}

function durationBucket(durationMs: number): string {
  if (durationMs < 50) return "lt_50ms";
  if (durationMs < 250) return "50_249ms";
  if (durationMs < 1_000) return "250_999ms";
  if (durationMs < 5_000) return "1_4s";
  if (durationMs < 15_000) return "5_14s";
  return "gte_15s";
}

function sizeBucket(request: Request, profile: ServiceProfile): string {
  if (profile !== "ingest" || request.method !== "POST") return "not_applicable";
  const value = request.headers.get("Content-Length");
  if (value === null) return "unknown";
  const declared = Number(value);
  if (!Number.isSafeInteger(declared) || declared < 0) return "unknown";
  if (declared <= 64 * 1024) return "le_64k";
  if (declared <= 1024 * 1024) return "64k_1m";
  if (declared <= 5 * 1024 * 1024) return "1m_5m";
  if (declared <= 10 * 1024 * 1024) return "5m_10m";
  if (declared <= 25 * 1024 * 1024) return "10m_25m";
  return "gt_25m";
}

function routeClass(request: Request, profile: ServiceProfile): string {
  const path = new URL(request.url).pathname;
  if (profile === "ingest") {
    if (request.method === "GET" && path === "/health") return "health";
    if (request.method === "POST" && path === "/api/v1/exports") return "export_ingest";
    return "denied";
  }
  if (profile === "maintenance") return "http_denied";
  if (path === "/health") return "health";
  if (path.startsWith("/api/auth/")) return "authentication";
  if (path === "/api/account" || path.startsWith("/api/account/")) return "account";
  if (path.startsWith("/api/sessions")) return "sessions";
  if (path === "/api/security-events") return "security_activity";
  if (path.startsWith("/api/ingest-tokens")) return "ingest_tokens";
  if (path.startsWith("/api/agent-tokens")) return "agent_tokens";
  if (/^\/api\/exports\/[a-f0-9-]{36}\/download$/u.test(path)) return "export_download";
  if (path.startsWith("/api/exports") || path.startsWith("/api/days")) return "export_inventory";
  if (path.startsWith("/api/dashboard") || path.startsWith("/api/explore")) return "retained_views";
  if (path.startsWith("/api/repair")) return "repair";
  if (path.startsWith("/api/")) return "denied";
  return "static";
}

function write(env: Env, profile: ServiceProfile, event: string, outcome: string,
  duration: string, size: string): void {
  try {
    env.METRICS?.writeDataPoint({
      indexes: [profile],
      blobs: [event, outcome, duration, size],
      doubles: [1],
    });
  } catch {
    // Telemetry must never change health-data request behavior or log details.
  }
}

export function recordHttpMetric(
  env: Env,
  profile: ServiceProfile,
  request: Request,
  response: Response,
  startedAtMs: number,
): void {
  write(env, profile, routeClass(request, profile), statusClass(response.status),
    durationBucket(Math.max(0, Date.now() - startedAtMs)), sizeBucket(request, profile));
}

export function recordAccountSecurityMetric(
  env: Env,
  event: "email_budget_exhausted" | "magic_link_persistence_failed" | "magic_link_cleanup_pending",
): void {
  write(env, "account", event, "blocked", "not_applicable", "not_applicable");
}

export function recordMaintenanceMetric(
  env: Env,
  event: "scheduled" | "queue_batch",
  outcome: "ok" | "retry" | "failed",
  startedAtMs: number,
): void {
  write(env, "maintenance", event, outcome,
    durationBucket(Math.max(0, Date.now() - startedAtMs)), "not_applicable");
}
