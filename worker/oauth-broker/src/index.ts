export interface Env {
  BROKER_CLIENT_TOKEN?: string;
  ALLOWED_REDIRECT_URIS?: string;

  FITBIT_CLIENT_ID?: string;
  FITBIT_CLIENT_SECRET?: string;
  OURA_CLIENT_ID?: string;
  OURA_CLIENT_SECRET?: string;
  WHOOP_CLIENT_ID?: string;
  WHOOP_CLIENT_SECRET?: string;
  WITHINGS_CLIENT_ID?: string;
  WITHINGS_CLIENT_SECRET?: string;
  STRAVA_CLIENT_ID?: string;
  STRAVA_CLIENT_SECRET?: string;
}

type ProviderID = "fitbit" | "oura" | "whoop" | "withings" | "strava";

type ProviderConfig = {
  id: ProviderID;
  clientIdEnv: keyof Env;
  clientSecretEnv: keyof Env;
  authorizeURL: string;
  tokenURL: string;
  defaultScopes: string[];
  tokenAuth: "body" | "basic";
  extraAuthorizeParams?: Record<string, string>;
  extraTokenParams?: Record<string, string>;
};

const MAX_BODY_BYTES = 16 * 1024;
const PROVIDERS: Record<ProviderID, ProviderConfig> = {
  fitbit: {
    id: "fitbit",
    clientIdEnv: "FITBIT_CLIENT_ID",
    clientSecretEnv: "FITBIT_CLIENT_SECRET",
    authorizeURL: "https://www.fitbit.com/oauth2/authorize",
    tokenURL: "https://api.fitbit.com/oauth2/token",
    defaultScopes: ["activity", "heartrate", "sleep", "weight", "location"],
    tokenAuth: "basic",
  },
  oura: {
    id: "oura",
    clientIdEnv: "OURA_CLIENT_ID",
    clientSecretEnv: "OURA_CLIENT_SECRET",
    authorizeURL: "https://cloud.ouraring.com/oauth/authorize",
    tokenURL: "https://api.ouraring.com/oauth/token",
    defaultScopes: ["daily", "heartrate", "workout", "spo2Daily"],
    tokenAuth: "body",
  },
  whoop: {
    id: "whoop",
    clientIdEnv: "WHOOP_CLIENT_ID",
    clientSecretEnv: "WHOOP_CLIENT_SECRET",
    authorizeURL: "https://api.prod.whoop.com/oauth/oauth2/auth",
    tokenURL: "https://api.prod.whoop.com/oauth/oauth2/token",
    defaultScopes: ["offline", "read:recovery", "read:cycles", "read:sleep", "read:workout", "read:body_measurement"],
    tokenAuth: "body",
  },
  withings: {
    id: "withings",
    clientIdEnv: "WITHINGS_CLIENT_ID",
    clientSecretEnv: "WITHINGS_CLIENT_SECRET",
    authorizeURL: "https://account.withings.com/oauth2_user/authorize2",
    tokenURL: "https://wbsapi.withings.net/v2/oauth2",
    defaultScopes: ["user.info", "user.metrics", "user.activity", "user.sleepevents"],
    tokenAuth: "body",
    extraTokenParams: { action: "requesttoken" },
  },
  strava: {
    id: "strava",
    clientIdEnv: "STRAVA_CLIENT_ID",
    clientSecretEnv: "STRAVA_CLIENT_SECRET",
    authorizeURL: "https://www.strava.com/oauth/mobile/authorize",
    tokenURL: "https://www.strava.com/oauth/token",
    defaultScopes: ["read", "activity:read"],
    tokenAuth: "body",
    extraAuthorizeParams: { approval_prompt: "auto" },
  },
};

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const pathname = normalizedPathname(url.pathname);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }

    if (request.method === "GET" && pathname === "/health") {
      return json({ ok: true, service: "health-md-oauth-broker" });
    }

    if (request.method === "GET" && pathname === "/v1/providers") {
      return json({ ok: true, providers: Object.keys(PROVIDERS) });
    }

    const authError = authorize(request, env);
    if (authError) return authError;

    try {
      if (request.method === "POST" && pathname === "/v1/oauth/authorize-url") {
        return await authorizeURL(request, env);
      }

      if (request.method === "POST" && pathname === "/v1/oauth/token") {
        return await exchangeToken(request, env, "authorization_code");
      }

      if (request.method === "POST" && pathname === "/v1/oauth/refresh") {
        return await exchangeToken(request, env, "refresh_token");
      }
    } catch (error) {
      const status = typeof (error as { status?: unknown }).status === "number" ? (error as { status: number }).status : 500;
      const message = error instanceof Error ? error.message : "internal_error";
      return json({ ok: false, error: message }, status);
    }

    return json({ ok: false, error: "not_found" }, 404);
  },
};

async function authorizeURL(request: Request, env: Env): Promise<Response> {
  const body = await readJSONBody(request);
  const provider = requireProvider(body.provider);
  const config = PROVIDERS[provider];
  const clientId = requireString(env[config.clientIdEnv], `${config.clientIdEnv} is not configured`);
  const redirectURI = requireRedirectURI(body.redirect_uri, env);
  const state = requireString(body.state, "state is required");
  const scope = optionalString(body.scope) || config.defaultScopes.join(" ");

  const url = new URL(config.authorizeURL);
  url.searchParams.set("response_type", "code");
  url.searchParams.set("client_id", clientId);
  url.searchParams.set("redirect_uri", redirectURI);
  url.searchParams.set("scope", scope);
  url.searchParams.set("state", state);
  for (const [key, value] of Object.entries(config.extraAuthorizeParams ?? {})) {
    url.searchParams.set(key, value);
  }
  const codeChallenge = optionalString(body.code_challenge);
  if (codeChallenge) {
    url.searchParams.set("code_challenge", codeChallenge);
    url.searchParams.set("code_challenge_method", "S256");
  }

  return json({ ok: true, provider, authorization_url: url.toString() });
}

async function exchangeToken(request: Request, env: Env, expectedGrantType: "authorization_code" | "refresh_token"): Promise<Response> {
  const body = await readJSONBody(request);
  const provider = requireProvider(body.provider);
  const config = PROVIDERS[provider];
  const grantType = requireString(body.grant_type, "grant_type is required");
  if (grantType !== expectedGrantType) throw httpError(400, "invalid_grant_type");

  const clientId = requireString(env[config.clientIdEnv], `${config.clientIdEnv} is not configured`);
  const clientSecret = requireString(env[config.clientSecretEnv], `${config.clientSecretEnv} is not configured`);

  const form = new URLSearchParams();
  form.set("grant_type", grantType);
  if (config.tokenAuth === "body") {
    form.set("client_id", clientId);
    form.set("client_secret", clientSecret);
  }
  for (const [key, value] of Object.entries(config.extraTokenParams ?? {})) {
    form.set(key, value);
  }

  if (grantType === "authorization_code") {
    form.set("code", requireString(body.code, "code is required"));
    form.set("redirect_uri", requireRedirectURI(body.redirect_uri, env));
    const verifier = optionalString(body.code_verifier);
    if (verifier) form.set("code_verifier", verifier);
  } else {
    form.set("refresh_token", requireString(body.refresh_token, "refresh_token is required"));
  }

  const headers = new Headers({
    "Accept": "application/json",
    "Content-Type": "application/x-www-form-urlencoded",
    "User-Agent": "Health.md OAuth Broker",
  });
  if (config.tokenAuth === "basic") {
    headers.set("Authorization", `Basic ${btoa(`${clientId}:${clientSecret}`)}`);
  }

  const response = await fetch(config.tokenURL, {
    method: "POST",
    headers,
    body: form.toString(),
  });
  const raw = await response.text();
  const parsed = parseProviderResponse(raw);

  if (!response.ok || providerStatusIsFailure(parsed)) {
    return json({ ok: false, error: providerError(parsed) ?? `provider_http_${response.status}` }, response.ok ? 400 : response.status);
  }

  const normalized = normalizeTokenResponse(provider, parsed);
  return json({ ok: true, ...normalized });
}

function normalizeTokenResponse(provider: ProviderID, raw: unknown): Record<string, unknown> {
  const source = provider === "withings" && isObject(raw) && isObject(raw.body) ? raw.body : raw;
  if (!isObject(source)) throw httpError(502, "invalid_provider_response");

  const nowSeconds = Math.floor(Date.now() / 1000);
  const expiresIn = numeric(source.expires_in)
    ?? (numeric(source.expires_at) ? Math.max(0, numeric(source.expires_at)! - nowSeconds) : undefined);

  return {
    access_token: requireString(source.access_token, "provider response missing access_token"),
    refresh_token: optionalString(source.refresh_token),
    token_type: optionalString(source.token_type) ?? "Bearer",
    expires_in: expiresIn,
    scope: optionalString(source.scope),
    provider_user_id: providerUserID(provider, raw, source),
  };
}

function providerUserID(provider: ProviderID, raw: unknown, source: Record<string, unknown>): string | undefined {
  switch (provider) {
    case "fitbit": return optionalString(source.user_id);
    case "withings": return optionalString(source.userid) ?? optionalString(source.user_id);
    case "strava": {
      if (isObject(raw) && isObject(raw.athlete)) return optionalString(raw.athlete.id);
      return optionalString(source.athlete_id);
    }
    case "oura": return optionalString(source.user_id);
    case "whoop": return optionalString(source.user_id);
  }
}

async function readJSONBody(request: Request): Promise<Record<string, unknown>> {
  const contentLength = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(contentLength) && contentLength > MAX_BODY_BYTES) {
    throw httpError(413, "body_too_large");
  }
  const raw = await request.text();
  if (new TextEncoder().encode(raw).byteLength > MAX_BODY_BYTES) {
    throw httpError(413, "body_too_large");
  }
  try {
    const parsed = JSON.parse(raw);
    if (!isObject(parsed)) throw new Error("not object");
    return parsed;
  } catch {
    throw httpError(400, "invalid_json");
  }
}

function authorize(request: Request, env: Env): Response | null {
  if (!env.BROKER_CLIENT_TOKEN) return null;
  const header = request.headers.get("authorization") ?? "";
  if (header !== `Bearer ${env.BROKER_CLIENT_TOKEN}`) {
    return json({ ok: false, error: "unauthorized" }, 401);
  }
  return null;
}

function requireProvider(value: unknown): ProviderID {
  const provider = requireString(value, "provider is required") as ProviderID;
  if (!(provider in PROVIDERS)) throw httpError(400, "unsupported_provider");
  return provider;
}

function requireRedirectURI(value: unknown, env: Env): string {
  const redirectURI = requireString(value, "redirect_uri is required");
  const allowed = (env.ALLOWED_REDIRECT_URIS || "healthmd://oauth/callback")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
  if (!allowed.includes(redirectURI)) throw httpError(400, "redirect_uri_not_allowed");
  return redirectURI;
}

function requireString(value: unknown, message: string): string {
  const string = optionalString(value);
  if (!string) throw httpError(400, message);
  return string;
}

function optionalString(value: unknown): string | undefined {
  if (typeof value === "string") {
    const trimmed = value.trim();
    return trimmed ? trimmed : undefined;
  }
  if (typeof value === "number" && Number.isFinite(value)) return String(value);
  return undefined;
}

function numeric(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : undefined;
  }
  return undefined;
}

function parseProviderResponse(raw: string): unknown {
  if (!raw.trim()) return {};
  try { return JSON.parse(raw); } catch { return { raw }; }
}

function providerStatusIsFailure(value: unknown): boolean {
  return isObject(value) && typeof value.status === "number" && value.status !== 0;
}

function providerError(value: unknown): string | undefined {
  if (!isObject(value)) return undefined;
  if (typeof value.error === "string") return value.error;
  if (typeof value.error_description === "string") return value.error_description;
  if (typeof value.status === "number") return `provider_status_${value.status}`;
  return undefined;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function normalizedPathname(pathname: string): string {
  if (pathname.length > 1 && pathname.endsWith("/")) return pathname.slice(0, -1);
  return pathname;
}

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value, null, 2), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      ...corsHeaders(),
    },
  });
}

function corsHeaders(): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
    "Access-Control-Allow-Headers": "Authorization,Content-Type",
    "Access-Control-Max-Age": "86400",
  };
}

function httpError(status: number, message: string): Error & { status?: number } {
  const error = new Error(message) as Error & { status?: number };
  error.status = status;
  return error;
}
