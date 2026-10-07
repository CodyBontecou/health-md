const JWT_LIFETIME_SEC = 50 * 60;
let cachedJwt = null;

function base64urlEncode(bytes) {
  const arr = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let binary = "";
  for (let i = 0; i < arr.byteLength; i++)
    binary += String.fromCharCode(arr[i]);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
function base64urlEncodeJson(obj) {
  return base64urlEncode(new TextEncoder().encode(JSON.stringify(obj)));
}
function pemToPkcs8Bytes(pem) {
  const stripped = pem.replace(/-----BEGIN [^-]+-----/g, "").replace(/-----END [^-]+-----/g, "").replace(/\s+/g, "");
  const binary = atob(stripped);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++)
    out[i] = binary.charCodeAt(i);
  return out;
}
async function importEs256PrivateKey(pem) {
  const pkcs8 = pemToPkcs8Bytes(pem);
  return crypto.subtle.importKey(
    "pkcs8",
    pkcs8,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"]
  );
}
async function signApnsJwt(creds, nowSec = Math.floor(Date.now() / 1e3)) {
  if (cachedJwt && cachedJwt.keyId === creds.keyId && cachedJwt.teamId === creds.teamId && cachedJwt.authKey === creds.authKey && cachedJwt.expiresAt > nowSec + 60) {
    return cachedJwt.token;
  }
  const header = { alg: "ES256", kid: creds.keyId, typ: "JWT" };
  const payload = { iss: creds.teamId, iat: nowSec };
  const signingInput = `${base64urlEncodeJson(header)}.${base64urlEncodeJson(payload)}`;
  const key = await importEs256PrivateKey(creds.authKey);
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: { name: "SHA-256" } },
    key,
    new TextEncoder().encode(signingInput)
  );
  const token = `${signingInput}.${base64urlEncode(signature)}`;
  cachedJwt = {
    token,
    expiresAt: nowSec + JWT_LIFETIME_SEC,
    keyId: creds.keyId,
    teamId: creds.teamId,
    authKey: creds.authKey
  };
  return token;
}
async function sendSilentPush(creds, opts) {
  const jwt = await signApnsJwt(creds);
  const host = opts.host ?? "api.push.apple.com";
  const url = `https://${host}/3/device/${opts.apnsToken}`;
  const body = JSON.stringify({
    aps: { "content-available": 1 },
    ...opts.customPayload
  });
  const response = await fetch(url, {
    signal: AbortSignal.timeout(15000),
    method: "POST",
    headers: {
      "authorization": `bearer ${jwt}`,
      "apns-push-type": "background",
      "apns-priority": "5",
      "apns-topic": opts.bundleId,
      "apns-expiration": String(opts.expirationSec),
      "content-type": "application/json"
    },
    body
  });
  const apnsId = response.headers.get("apns-id") ?? void 0;
  if (response.status === 200) {
    return { status: 200, apnsId };
  }
  let reason;
  let timestamp;
  try {
    const text = await response.text();
    if (text) {
      const parsed = JSON.parse(text);
      reason = typeof parsed.reason === "string" ? parsed.reason : undefined;
      timestamp = typeof parsed.timestamp === "number" ? parsed.timestamp : undefined;
    }
  } catch {
  }
  return { status: response.status, reason, apnsId, timestamp };
}

export function apnsHost(environment) {
  return environment === "development" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
}

export { sendSilentPush };
