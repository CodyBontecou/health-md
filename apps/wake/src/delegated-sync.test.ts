/** Delegated sync doorbell and FCM transport tests (RFC-0005 clinic sync amendment). */

import { describe, expect, it } from "vitest";
import doorbellFixtures from "../../../packages/contracts/clinic-sponsorship/v1/sync-doorbell-fixtures.json";
import { hexEncode, sha256 } from "./crypto";
import {
  fcmMessageBody,
  parseServiceAccount,
  signServiceAccountAssertion,
} from "./delegated-fcm";
import {
  parseRegistrationTarget,
  SYNC_REQUEST_CATEGORY,
  SYNC_REQUEST_KIND,
  syncRequestApnsPayload,
  syncRequestFcmData,
  verifyWakeHmac,
} from "./state";

const APNS_TOKEN = "a".repeat(64);
const FCM_TOKEN = `cX1:APA91b${"Q".repeat(140)}`;
const WAKE_ID = "0123456789abcdef0123456789abcdef";

function decodeBase64url(value: string): Uint8Array {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(value.length / 4) * 4, "=");
  const binary = atob(padded);
  return Uint8Array.from(binary, (c) => c.charCodeAt(0));
}

describe("registration target", () => {
  it("defaults legacy registrations to an APNs Direct CLI pairing", () => {
    expect(parseRegistrationTarget(undefined, undefined, APNS_TOKEN))
      .toEqual({ ok: true, platform: "apns", purpose: "direct-cli" });
  });

  it("accepts delegated sync on both transports", () => {
    expect(parseRegistrationTarget("apns", "delegated-sync", APNS_TOKEN))
      .toEqual({ ok: true, platform: "apns", purpose: "delegated-sync" });
    expect(parseRegistrationTarget("fcm", "delegated-sync", FCM_TOKEN))
      .toEqual({ ok: true, platform: "fcm", purpose: "delegated-sync" });
  });

  it("keeps Android Direct CLI wake unavailable", () => {
    expect(parseRegistrationTarget("fcm", "direct-cli", FCM_TOKEN).ok).toBe(false);
    expect(parseRegistrationTarget("fcm", undefined, FCM_TOKEN).ok).toBe(false);
  });

  it("validates the token shape per transport and rejects unknown values", () => {
    expect(parseRegistrationTarget("apns", "delegated-sync", FCM_TOKEN).ok).toBe(false);
    expect(parseRegistrationTarget("fcm", "delegated-sync", "short").ok).toBe(false);
    expect(parseRegistrationTarget("webpush", "delegated-sync", APNS_TOKEN).ok).toBe(false);
    expect(parseRegistrationTarget("apns", "clinic", APNS_TOKEN).ok).toBe(false);
    expect(parseRegistrationTarget("apns", "delegated-sync", 42).ok).toBe(false);
  });
});

describe("delegated sync notification payloads", () => {
  it("APNs copy is a device-localized key with no holder-supplied text", () => {
    const payload = syncRequestApnsPayload(WAKE_ID) as {
      aps: { alert: Record<string, string>; category: string; sound: string };
      healthmd: { kind: string; wakeId: string };
    };
    expect(payload.aps.alert).toEqual({
      "title-loc-key": "HEALTHMD_SYNC_REQUEST_TITLE",
      "loc-key": "HEALTHMD_SYNC_REQUEST_BODY",
    });
    expect(payload.aps.category).toBe(SYNC_REQUEST_CATEGORY);
    expect(payload.healthmd).toEqual({ kind: SYNC_REQUEST_KIND, wakeId: WAKE_ID });
  });

  it("FCM data carries only the kind and opaque wakeId", () => {
    expect(syncRequestFcmData(WAKE_ID)).toEqual({ kind: SYNC_REQUEST_KIND, wakeId: WAKE_ID });
    expect(fcmMessageBody(FCM_TOKEN, syncRequestFcmData(WAKE_ID), 300)).toEqual({
      message: {
        token: FCM_TOKEN,
        data: { kind: SYNC_REQUEST_KIND, wakeId: WAKE_ID },
        android: { priority: "HIGH", ttl: "300s" },
      },
    });
  });

  it("no payload names a clinic, metric, or health value", () => {
    const serialized = JSON.stringify([
      syncRequestApnsPayload(WAKE_ID),
      fcmMessageBody(FCM_TOKEN, syncRequestFcmData(WAKE_ID), 300),
    ]);
    expect(serialized).not.toMatch(/clinic|heart|step|sleep|metric|export|query|endpoint/i);
  });
});

describe("FCM service account", () => {
  it("parses only complete service-account JSON", () => {
    expect(parseServiceAccount(undefined)).toBeNull();
    expect(parseServiceAccount("not json")).toBeNull();
    expect(parseServiceAccount(JSON.stringify({ project_id: "p", client_email: "e" }))).toBeNull();
    expect(parseServiceAccount(JSON.stringify({
      project_id: "healthmd", client_email: "sender@healthmd.iam.gserviceaccount.com",
      private_key: "-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----\n",
    }))).toEqual({
      projectId: "healthmd",
      clientEmail: "sender@healthmd.iam.gserviceaccount.com",
      privateKey: "-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----\n",
    });
  });

  it("signs a verifiable RS256 messaging-scoped assertion", async () => {
    const pair = await crypto.subtle.generateKey(
      {
        name: "RSASSA-PKCS1-v1_5", modulusLength: 2048,
        publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256",
      },
      true,
      ["sign", "verify"],
    ) as CryptoKeyPair;
    const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey) as ArrayBuffer);
    const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...pkcs8))}\n-----END PRIVATE KEY-----\n`;
    const now = 1_800_000_000;
    const jwt = await signServiceAccountAssertion(
      { projectId: "healthmd", clientEmail: "sender@example.test", privateKey: pem },
      now,
    );
    const [header, claims, signature] = jwt.split(".");
    expect(JSON.parse(new TextDecoder().decode(decodeBase64url(header))))
      .toEqual({ alg: "RS256", typ: "JWT" });
    expect(JSON.parse(new TextDecoder().decode(decodeBase64url(claims)))).toEqual({
      iss: "sender@example.test",
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    });
    expect(await crypto.subtle.verify(
      "RSASSA-PKCS1-v1_5", pair.publicKey, decodeBase64url(signature) as BufferSource,
      new TextEncoder().encode(`${header}.${claims}`),
    )).toBe(true);
  });
});

describe("clinic sync doorbell contract fixture", () => {
  it("the delivered wakeKey hashes to the registered hash and signs the fixture request", async () => {
    const enroll = doorbellFixtures.enrollMessage.body;
    const rawKey = decodeBase64url(enroll.wakeKey);
    expect(rawKey.byteLength).toBe(32);
    const hash = hexEncode(await sha256(rawKey));
    expect(hash).toBe(doorbellFixtures.wakeRequest.wakeKeyVerificationHash);
    const request = doorbellFixtures.wakeRequest.body;
    expect(request.wakeId).toBe(enroll.wakeId);
    expect(await verifyWakeHmac(hash, request.nonce, request.timestamp, request.hmac)).toBe(true);
  });

  it("fixture notifications match the worker's payload builders", () => {
    const wakeId = doorbellFixtures.enrollMessage.body.wakeId;
    expect(syncRequestApnsPayload(wakeId)).toEqual(doorbellFixtures.notification.apns);
    expect(syncRequestFcmData(wakeId)).toEqual(doorbellFixtures.notification.fcmData);
  });
});
