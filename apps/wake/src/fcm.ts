/** Firebase HTTP-v1, notification-only. All OAuth state is request-local. */
import { isObject, providerJson } from "./http";
import { FALLBACK_NOTIFICATION_BODY, NOTIFICATION_TITLE } from "./state";

export const OAUTH_TOKEN_URL = "https://oauth2.googleapis.com/token";
export const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
const PROJECT_ID_RE = /^[a-z][a-z0-9-]{4,28}[a-z0-9]$/;
const MAX_CONFIG_BYTES = 16 * 1024;

export type FcmResult =
  | { kind: "delivered" }
  | { kind: "authorization_changed" }
  | { kind: "unavailable"; code: "fcm_not_configured" | "fcm_config_invalid" }
  | { kind: "undeliverable"; code: "fcm_oauth_failed" | "fcm_provider_failed" | "fcm_response_invalid" | "fcm_transport_failed" };

interface Credentials {
  projectId: string;
  clientEmail: string;
  privateKey: CryptoKey;
  keyId?: string;
}

function base64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
function encodedJson(value: unknown): string {
  return base64url(new TextEncoder().encode(JSON.stringify(value)));
}

async function credentialsFromJson(json: string): Promise<Credentials | null> {
  try {
    if (new TextEncoder().encode(json).byteLength > MAX_CONFIG_BYTES) return null;
    const value: unknown = JSON.parse(json);
    if (!isObject(value)) return null;
    const { type, project_id, client_email, private_key, private_key_id, token_uri } = value;
    if (
      type !== "service_account" || typeof project_id !== "string" || !PROJECT_ID_RE.test(project_id)
      || typeof client_email !== "string" || client_email.length > 254
      || !new RegExp(`^[a-z0-9-]{1,64}@${project_id}\\.iam\\.gserviceaccount\\.com$`).test(client_email)
      || typeof private_key !== "string" || private_key.length > 8192
      || (token_uri !== undefined && token_uri !== OAUTH_TOKEN_URL)
      || (private_key_id !== undefined && (typeof private_key_id !== "string" || !/^[A-Za-z0-9_-]{1,128}$/.test(private_key_id)))
    ) return null;
    const pem = /^-----BEGIN PRIVATE KEY-----\s+([A-Za-z0-9+/=\s]+)\s+-----END PRIVATE KEY-----\s*$/.exec(private_key);
    if (!pem) return null;
    const decoded = atob(pem[1].replace(/\s/g, ""));
    const bytes = Uint8Array.from(decoded, (character) => character.charCodeAt(0));
    const privateKey = await crypto.subtle.importKey("pkcs8", bytes,
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
    const algorithm = privateKey.algorithm;
    if (!("modulusLength" in algorithm) || typeof algorithm.modulusLength !== "number"
      || algorithm.modulusLength < 2048 || algorithm.modulusLength > 4096) return null;
    return { projectId: project_id, clientEmail: client_email, privateKey, keyId: private_key_id };
  } catch { return null; }
}

async function assertion(credentials: Credentials, now: number): Promise<string> {
  const header = { alg: "RS256", typ: "JWT", ...(credentials.keyId ? { kid: credentials.keyId } : {}) };
  const payload = { iss: credentials.clientEmail, scope: FCM_SCOPE, aud: OAUTH_TOKEN_URL, iat: now, exp: now + 3600 };
  const input = `${encodedJson(header)}.${encodedJson(payload)}`;
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", credentials.privateKey, new TextEncoder().encode(input));
  return `${input}.${base64url(new Uint8Array(signature))}`;
}

/** No data messages, dates, labels, IDs, images, URLs, analytics, or service-start directives. */
export function fcmNotificationPayload(deliveryToken: string): Record<string, unknown> {
  return { message: {
    token: deliveryToken,
    notification: { title: NOTIFICATION_TITLE, body: FALLBACK_NOTIFICATION_BODY },
    android: {
      priority: "HIGH", ttl: "300s", restricted_package_name: "com.healthmd.android",
      notification: {
        channel_id: "healthmd_direct_wake", click_action: "com.healthmd.DIRECT_CLI_WAKE",
        visibility: "PRIVATE", tag: "healthmd-direct-wake", sound: "default",
      },
    },
  } };
}

/** Admission is non-wire and mandatory: OAuth/key work is not notification
 * authority. The caller must inspect its existing current private records.
 */
export async function sendFcmWake(
  config: string | undefined, deliveryToken: string, now: number,
  authorizeSend: () => Promise<boolean>,
): Promise<FcmResult> {
  if (!config) return { kind: "unavailable", code: "fcm_not_configured" };
  const credentials = await credentialsFromJson(config);
  if (!credentials) return { kind: "unavailable", code: "fcm_config_invalid" };
  let sendUrl: string;
  let sendOptions: RequestInit;
  try {
    const form = new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: await assertion(credentials, now) });
    const oauth = await providerJson(OAUTH_TOKEN_URL, {
      method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form.toString(),
    });
    if (oauth.status !== 200) return { kind: "undeliverable", code: "fcm_oauth_failed" };
    if (
      !isObject(oauth.body) || oauth.body.token_type !== "Bearer"
      || typeof oauth.body.expires_in !== "number" || !Number.isInteger(oauth.body.expires_in)
      || oauth.body.expires_in < 1 || oauth.body.expires_in > 3600
      || typeof oauth.body.access_token !== "string" || oauth.body.access_token.length > 4096
      || !/^[A-Za-z0-9._~+/-]+=*$/.test(oauth.body.access_token)
    ) return { kind: "undeliverable", code: "fcm_response_invalid" };
    sendUrl = `https://fcm.googleapis.com/v1/projects/${credentials.projectId}/messages:send`;
    sendOptions = {
      method: "POST", headers: { authorization: `Bearer ${oauth.body.access_token}`, "content-type": "application/json" },
      body: JSON.stringify(fcmNotificationPayload(deliveryToken)),
    };
  } catch {
    return { kind: "undeliverable", code: "fcm_transport_failed" };
  }
  // After signing/OAuth/serialization, before starting the FCM request. Storage
  // failures propagate to the router's fixed storage error, not provider errors.
  if (!await authorizeSend()) return { kind: "authorization_changed" };
  try {
    const delivery = await providerJson(sendUrl, sendOptions);
    if (delivery.status !== 200) return { kind: "undeliverable", code: "fcm_provider_failed" };
    if (!isObject(delivery.body) || typeof delivery.body.name !== "string"
      || !new RegExp(`^projects/${credentials.projectId}/messages/[A-Za-z0-9%:_-]{1,512}$`).test(delivery.body.name)) {
      return { kind: "undeliverable", code: "fcm_response_invalid" };
    }
    // Provider acceptance only, not proof of display, tap, unlock, or read authorization.
    return { kind: "delivered" };
  } catch {
    return { kind: "undeliverable", code: "fcm_transport_failed" };
  }
}
