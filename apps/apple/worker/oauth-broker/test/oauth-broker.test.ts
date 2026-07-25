import assert from "node:assert/strict";
import test from "node:test";

import worker, { type Env } from "../src/index.ts";

const brokerURL = "https://broker.example.com";
const redirectURI = "healthmd://oauth/callback";

function environment(overrides: Partial<Env> = {}): Env {
  return {
    BROKER_CLIENT_TOKEN: "broker-client-token",
    ALLOWED_REDIRECT_URIS: redirectURI,
    WHOOP_CLIENT_ID: "whoop-client-id",
    WHOOP_CLIENT_SECRET: "whoop-client-secret",
    ...overrides,
  };
}

async function brokerPost(path: string, body: Record<string, unknown>, env = environment()): Promise<Response> {
  return worker.fetch(new Request(`${brokerURL}${path}`, {
    method: "POST",
    headers: {
      "Authorization": "Bearer broker-client-token",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  }), env);
}

async function jsonBody(response: Response): Promise<Record<string, unknown>> {
  return await response.json() as Record<string, unknown>;
}

test("WHOOP authorization URL uses exact endpoint, allowlisted redirect, scopes, and eight-character state", async () => {
  const response = await brokerPost("/v1/oauth/authorize-url", {
    provider: "whoop",
    redirect_uri: redirectURI,
    state: "aB3dE6gH",
    scope: "offline read:cycles read:recovery read:sleep read:workout read:body_measurement",
  });

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store");
  const body = await jsonBody(response);
  const authorizationURL = new URL(body.authorization_url as string);
  assert.equal(authorizationURL.origin + authorizationURL.pathname, "https://api.prod.whoop.com/oauth/oauth2/auth");
  assert.equal(authorizationURL.searchParams.get("response_type"), "code");
  assert.equal(authorizationURL.searchParams.get("client_id"), "whoop-client-id");
  assert.equal(authorizationURL.searchParams.get("redirect_uri"), redirectURI);
  assert.equal(authorizationURL.searchParams.get("state"), "aB3dE6gH");
  assert.equal(
    authorizationURL.searchParams.get("scope"),
    "offline read:cycles read:recovery read:sleep read:workout read:body_measurement",
  );
  assert.equal(authorizationURL.searchParams.has("client_secret"), false);
});

test("WHOOP authorization rejects invalid state, redirect, and scope", async (t) => {
  await t.test("state must be exactly eight characters", async () => {
    const response = await brokerPost("/v1/oauth/authorize-url", {
      provider: "whoop",
      redirect_uri: redirectURI,
      state: "too-long-state",
    });
    assert.equal(response.status, 400);
    assert.equal((await jsonBody(response)).error, "whoop_state_must_be_8_characters");
  });

  await t.test("redirect must be exactly allowlisted", async () => {
    const response = await brokerPost("/v1/oauth/authorize-url", {
      provider: "whoop",
      redirect_uri: "healthmd://oauth/other",
      state: "12345678",
    });
    assert.equal(response.status, 400);
    assert.equal((await jsonBody(response)).error, "redirect_uri_not_allowed");
  });

  await t.test("scope cannot exceed the provider allowlist", async () => {
    const response = await brokerPost("/v1/oauth/authorize-url", {
      provider: "whoop",
      redirect_uri: redirectURI,
      state: "12345678",
      scope: "offline write:anything",
    });
    assert.equal(response.status, 400);
    assert.equal((await jsonBody(response)).error, "scope_not_allowed");
  });
});

test("WHOOP authorization code exchange sends form credentials and normalizes token response", async () => {
  const originalFetch = globalThis.fetch;
  let upstreamURL: string | undefined;
  let upstreamInit: RequestInit | undefined;
  globalThis.fetch = (async (input: string | URL | Request, init?: RequestInit) => {
    upstreamURL = String(input);
    upstreamInit = init;
    return new Response(JSON.stringify({
      access_token: "access-1",
      refresh_token: "refresh-1",
      token_type: "bearer",
      expires_in: 3600,
      scope: "offline read:cycles",
    }), { status: 200, headers: { "Content-Type": "application/json" } });
  }) as typeof fetch;

  try {
    const response = await brokerPost("/v1/oauth/token", {
      provider: "whoop",
      grant_type: "authorization_code",
      code: "authorization-code",
      redirect_uri: redirectURI,
    });
    assert.equal(response.status, 200);
    assert.equal(upstreamURL, "https://api.prod.whoop.com/oauth/oauth2/token");
    assert.equal(upstreamInit?.method, "POST");
    const form = new URLSearchParams(upstreamInit?.body as string);
    assert.equal(form.get("grant_type"), "authorization_code");
    assert.equal(form.get("code"), "authorization-code");
    assert.equal(form.get("redirect_uri"), redirectURI);
    assert.equal(form.get("client_id"), "whoop-client-id");
    assert.equal(form.get("client_secret"), "whoop-client-secret");

    const body = await jsonBody(response);
    assert.equal(body.access_token, "access-1");
    assert.equal(body.refresh_token, "refresh-1");
    assert.equal(body.expires_in, 3600);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("WHOOP refresh requests offline scope and returns the rotated refresh token", async () => {
  const originalFetch = globalThis.fetch;
  let upstreamForm: URLSearchParams | undefined;
  globalThis.fetch = (async (_input: string | URL | Request, init?: RequestInit) => {
    upstreamForm = new URLSearchParams(init?.body as string);
    return new Response(JSON.stringify({
      access_token: "access-2",
      refresh_token: "refresh-2",
      token_type: "bearer",
      expires_in: 3600,
      scope: "offline read:cycles",
    }), { status: 200 });
  }) as typeof fetch;

  try {
    const response = await brokerPost("/v1/oauth/refresh", {
      provider: "whoop",
      grant_type: "refresh_token",
      refresh_token: "refresh-1",
    });
    assert.equal(response.status, 200);
    assert.equal(upstreamForm?.get("grant_type"), "refresh_token");
    assert.equal(upstreamForm?.get("refresh_token"), "refresh-1");
    assert.equal(upstreamForm?.get("scope"), "offline");
    assert.equal((await jsonBody(response)).refresh_token, "refresh-2");
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("WHOOP refresh rejects a response missing the mandatory rotated refresh token", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = (async () => new Response(JSON.stringify({
    access_token: "access-2",
    token_type: "bearer",
    expires_in: 3600,
  }), { status: 200 })) as typeof fetch;

  try {
    const response = await brokerPost("/v1/oauth/refresh", {
      provider: "whoop",
      grant_type: "refresh_token",
      refresh_token: "refresh-1",
    });
    assert.equal(response.status, 502);
    assert.equal((await jsonBody(response)).error, "whoop_response_missing_rotated_refresh_token");
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("provider OAuth errors are normalized without returning upstream descriptions", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = (async () => new Response(JSON.stringify({
    error: "invalid_grant",
    error_description: "raw upstream details that should not be returned",
  }), { status: 400 })) as typeof fetch;

  try {
    const response = await brokerPost("/v1/oauth/refresh", {
      provider: "whoop",
      grant_type: "refresh_token",
      refresh_token: "revoked-refresh-token",
    });
    assert.equal(response.status, 400);
    const body = await jsonBody(response);
    assert.equal(body.error, "invalid_grant");
    assert.equal(body.message, "WHOOP authorization expired or was revoked. Reconnect the account.");
    assert.equal(JSON.stringify(body).includes("raw upstream details"), false);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("broker client authentication protects every v1 endpoint", async () => {
  const authorizeResponse = await worker.fetch(new Request(`${brokerURL}/v1/oauth/authorize-url`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ provider: "whoop", redirect_uri: redirectURI, state: "12345678" }),
  }), environment());
  const providersResponse = await worker.fetch(
    new Request(`${brokerURL}/v1/providers`),
    environment(),
  );

  assert.equal(authorizeResponse.status, 401);
  assert.equal((await jsonBody(authorizeResponse)).error, "unauthorized");
  assert.equal(providersResponse.status, 401);
  assert.equal((await jsonBody(providersResponse)).error, "unauthorized");
});

test("broker fails closed when its client authentication secret is absent", async () => {
  const response = await brokerPost(
    "/v1/oauth/authorize-url",
    { provider: "whoop", redirect_uri: redirectURI, state: "12345678" },
    environment({ BROKER_CLIENT_TOKEN: undefined }),
  );

  assert.equal(response.status, 503);
  assert.equal((await jsonBody(response)).error, "broker_auth_not_configured");
});
