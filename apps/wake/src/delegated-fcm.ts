/** FCM HTTP v1 push for delegated sync doorbells on Android.
 *
 * Service-account OAuth (RS256 JWT bearer grant) mints a short-lived access
 * token; messages are data-only with high priority, and the app posts the
 * visible notification itself.
 */

export interface FcmServiceAccount {
  projectId: string;
  clientEmail: string;
  privateKey: string;
}

export interface SendFcmResult {
  status: number;
  reason?: string;
}

const OAUTH_TOKEN_URL = "https://oauth2.googleapis.com/token";
const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
const ASSERTION_LIFETIME_SEC = 3600;
let cachedAccessToken: { token: string; expiresAt: number; clientEmail: string } | null = null;

function base64urlEncode(bytes: ArrayBuffer | Uint8Array): string {
  const arr = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let binary = "";
  for (let i = 0; i < arr.byteLength; i += 1) binary += String.fromCharCode(arr[i]);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64urlEncodeJson(obj: unknown): string {
  return base64urlEncode(new TextEncoder().encode(JSON.stringify(obj)));
}

function pemToPkcs8(pem: string): ArrayBuffer {
  const stripped = pem
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s+/g, "");
  const binary = atob(stripped);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) out[i] = binary.charCodeAt(i);
  return out.buffer;
}

/** Parse the service-account JSON secret; `null` when absent or incomplete. */
export function parseServiceAccount(json: string | undefined): FcmServiceAccount | null {
  if (!json) return null;
  try {
    const value = JSON.parse(json) as {
      project_id?: unknown;
      client_email?: unknown;
      private_key?: unknown;
    };
    if (
      typeof value.project_id !== "string" || value.project_id.length === 0
      || typeof value.client_email !== "string" || value.client_email.length === 0
      || typeof value.private_key !== "string" || value.private_key.length === 0
    ) {
      return null;
    }
    return {
      projectId: value.project_id,
      clientEmail: value.client_email,
      privateKey: value.private_key,
    };
  } catch {
    return null;
  }
}

/** Signed RS256 assertion for the OAuth JWT bearer grant. */
export async function signServiceAccountAssertion(
  account: FcmServiceAccount,
  nowSec: number,
): Promise<string> {
  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: account.clientEmail,
    scope: FCM_SCOPE,
    aud: OAUTH_TOKEN_URL,
    iat: nowSec,
    exp: nowSec + ASSERTION_LIFETIME_SEC,
  };
  const signingInput = `${base64urlEncodeJson(header)}.${base64urlEncodeJson(claims)}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(account.privateKey),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64urlEncode(signature)}`;
}

async function accessToken(account: FcmServiceAccount, nowSec: number): Promise<string | null> {
  if (
    cachedAccessToken
    && cachedAccessToken.clientEmail === account.clientEmail
    && cachedAccessToken.expiresAt > nowSec + 60
  ) {
    return cachedAccessToken.token;
  }
  const assertion = await signServiceAccountAssertion(account, nowSec);
  const response = await fetch(OAUTH_TOKEN_URL, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }).toString(),
  });
  if (response.status !== 200) return null;
  const body = (await response.json()) as { access_token?: unknown; expires_in?: unknown };
  if (typeof body.access_token !== "string") return null;
  const lifetime = typeof body.expires_in === "number" ? body.expires_in : 3600;
  cachedAccessToken = {
    token: body.access_token,
    expiresAt: nowSec + lifetime,
    clientEmail: account.clientEmail,
  };
  return body.access_token;
}

/** FCM HTTP v1 message body for one data-only, high-priority push. */
export function fcmMessageBody(
  fcmToken: string,
  data: Record<string, string>,
  ttlSec: number,
): Record<string, unknown> {
  return {
    message: {
      token: fcmToken,
      data,
      android: { priority: "HIGH", ttl: `${ttlSec}s` },
    },
  };
}

export async function sendFcmData(
  account: FcmServiceAccount,
  fcmToken: string,
  data: Record<string, string>,
  ttlSec: number,
  nowSec: number = Math.floor(Date.now() / 1000),
): Promise<SendFcmResult> {
  const token = await accessToken(account, nowSec);
  if (!token) return { status: 503, reason: "oauth_unavailable" };

  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(account.projectId)}/messages:send`,
    {
      method: "POST",
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: JSON.stringify(fcmMessageBody(fcmToken, data, ttlSec)),
    },
  );
  if (response.status === 200) return { status: 200 };

  let reason: string | undefined;
  try {
    const body = (await response.json()) as { error?: { status?: string } };
    reason = body.error?.status;
  } catch {
    // Non-JSON FCM response body; leave reason unset.
  }
  return { status: response.status, reason };
}
