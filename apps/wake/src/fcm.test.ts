import { afterEach, expect, it, vi } from "vitest";
import worker from "./index";
import { TestD1 } from "./test-support.mjs";
import { NOW, TIMESTAMP, FCM_TOKEN, enrollment, jsonRequest, ringBody, syntheticPem } from "./test-helpers";

afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); });

it("dispatches a verified v2 wake via a signed OAuth assertion and a fixed visible FCM notification", async () => {
  vi.spyOn(Date, "now").mockReturnValue(NOW);
  const DB = new TestD1(["0001_init.sql", "0002_fcm_v2.sql"]);
  const { pem, publicKey } = await syntheticPem("fcm");
  const credentials = {
    type: "service_account", project_id: "synthetic-project",
    client_email: "synthetic-worker@synthetic-project.iam.gserviceaccount.com",
    private_key: pem, private_key_id: "synthetic-key-id", token_uri: "https://oauth2.googleapis.com/token",
  };
  const env = { DB, FCM_SERVICE_ACCOUNT_JSON: JSON.stringify(credentials) };
  const fetchMock = vi.fn<typeof fetch>().mockImplementation(async (url, options) => {
    expect(options?.redirect).toBe("manual");
    expect(options?.signal).toBeDefined();
    if (url === "https://oauth2.googleapis.com/token") {
      const form = new URLSearchParams(String(options?.body));
      expect(form.get("grant_type")).toBe("urn:ietf:params:oauth:grant-type:jwt-bearer");
      const jwt = form.get("assertion")!;
      const [header, payload, signature] = jwt.split(".");
      const decode = (part: string) => atob(part.replace(/-/g, "+").replace(/_/g, "/"));
      expect(JSON.parse(decode(header))).toEqual({ alg: "RS256", typ: "JWT", kid: "synthetic-key-id" });
      expect(JSON.parse(decode(payload))).toEqual({
        iss: credentials.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging",
        aud: "https://oauth2.googleapis.com/token", iat: NOW / 1000, exp: NOW / 1000 + 3600,
      });
      expect(await crypto.subtle.verify("RSASSA-PKCS1-v1_5", publicKey,
        Uint8Array.from(decode(signature), (char) => char.charCodeAt(0)), new TextEncoder().encode(`${header}.${payload}`))).toBe(true);
      return Response.json({ access_token: "synthetic-oauth-token", token_type: "Bearer", expires_in: 3600 });
    }
    expect(url).toBe("https://fcm.googleapis.com/v1/projects/synthetic-project/messages:send");
    expect(options?.headers).toMatchObject({ authorization: "Bearer synthetic-oauth-token" });
    expect(JSON.parse(String(options?.body))).toEqual({ message: {
      token: FCM_TOKEN,
      notification: { title: "Health.md", body: "A paired computer is requesting data. Tap to continue." },
      android: {
        priority: "HIGH", ttl: "300s", restricted_package_name: "com.healthmd.android",
        notification: { channel_id: "healthmd_direct_wake", click_action: "com.healthmd.DIRECT_CLI_WAKE",
          visibility: "PRIVATE", tag: "healthmd-direct-wake", sound: "default" },
      },
    } });
    return Response.json({ name: "projects/synthetic-project/messages/synthetic-message" });
  });
  vi.stubGlobal("fetch", fetchMock);
  const body = await enrollment();
  expect((await worker.fetch(jsonRequest("/wake/v2/register", body), env)).status).toBe(200);
  const ring = await ringBody(body.wakeId, "cd".repeat(16));
  expect(ring.hmac).toBe("01f561ffd63763181697f2186419f2487e48e9b0947f5b2986812e1b866f9819");
  const response = await worker.fetch(jsonRequest("/wake/v2/request", ring), env);
  expect(response.status).toBe(200);
  expect(await response.json()).toEqual({ status: "delivered" });
  expect(fetchMock).toHaveBeenCalledTimes(2);
  expect(JSON.stringify(fetchMock.mock.calls[1][1]?.body)).not.toContain(TIMESTAMP);
  DB.sqlite.close();
});

it("keeps OAuth tokens request-local rather than reusing one across Worker requests", async () => {
  const DB = new TestD1(["0001_init.sql", "0002_fcm_v2.sql"]);
  let clock = NOW;
  vi.spyOn(Date, "now").mockImplementation(() => clock);
  const config = JSON.stringify({ type: "service_account", project_id: "synthetic-project",
    private_key: (await syntheticPem("fcm")).pem, client_email: "synthetic-worker@synthetic-project.iam.gserviceaccount.com" });
  let oauthCalls = 0;
  const headers: string[] = [];
  const mocked = vi.fn<typeof fetch>().mockImplementation(async (url, options) => {
    if (url === "https://oauth2.googleapis.com/token") {
      oauthCalls++;
      return Response.json({ access_token: `synthetic-access-${oauthCalls}`, token_type: "Bearer", expires_in: 3600 });
    }
    headers.push(new Headers(options?.headers).get("authorization") ?? "");
    return Response.json({ name: "projects/synthetic-project/messages/synthetic-message" });
  });
  vi.stubGlobal("fetch", mocked);
  try {
    const body = await enrollment();
    const env = { DB, FCM_SERVICE_ACCOUNT_JSON: config };
    await worker.fetch(jsonRequest("/wake/v2/register", body), env);
    for (let index = 0; index < 2; index++) {
      clock = NOW + index * 30_000;
      const timestamp = new Date(clock).toISOString().replace(".000Z", "Z");
      expect(await (await worker.fetch(jsonRequest("/wake/v2/request", await ringBody(body.wakeId, String(index).repeat(32), undefined, timestamp)), env)).json())
        .toEqual({ status: "delivered" });
    }
    expect(headers).toEqual(["Bearer synthetic-access-1", "Bearer synthetic-access-2"]);
    expect(mocked).toHaveBeenCalledTimes(4);
  } finally { DB.sqlite.close(); }
});
