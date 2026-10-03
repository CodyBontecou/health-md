/** RFC-0005 wake worker policy tests.
 *
 * The HMAC vector is pinned cross-language: the same raw key ([7;32]), nonce
 * ("aa"), and timestamp are pinned in apps/cli/crates/healthmd-client/src/wake.rs
 * so the Rust client and this worker can never drift apart.
 */

import { describe, expect, it } from "vitest";
import { hexDecode, hexEncode, sha256 } from "./crypto";
import {
  DEDUPE_WINDOW_SEC,
  HOURLY_DELIVERY_LIMIT,
  decideDelivery,
  notificationBody,
  notificationPayload,
  parseTimestampSeconds,
  sanitizePeerLabel,
  timestampWithinWindow,
  verifyWakeHmac,
  WAKE_HMAC_DOMAIN,
  type CounterRow,
} from "./state";

const RAW_KEY = new Uint8Array(32).fill(7);
const PINNED_NONCE = "aa";
const PINNED_TIMESTAMP = "2026-09-03T00:00:00Z";
// Computed independently (Python hashlib): HMAC-SHA256(key = SHA-256(raw key), domain‖nonce‖timestamp).
const PINNED_HMAC = "b7575fa94db932357824b886ac6b23d17eaed58048ee346622fa2add58d2138f";
const PINNED_KEY_HASH_HEX = "4bb06f8e4e3a7715d201d573d0aa423762e55dabd61a2c02278fa56cc6d294e0";

async function hmacHex(
  key: Uint8Array,
  nonce: string,
  timestamp: string,
): Promise<string> {
  const { hmacSha256 } = await import("./crypto");
  const message = new TextEncoder().encode(WAKE_HMAC_DOMAIN + nonce + timestamp);
  return hexEncode(await hmacSha256(key, message));
}

describe("pinned wake HMAC (cross-language vector)", () => {
  it("SHA-256 of the raw key equals the registered verification hash", async () => {
    expect(hexEncode(await sha256(RAW_KEY))).toBe(PINNED_KEY_HASH_HEX);
  });

  it("verifies the exact Rust-pinned vector", async () => {
    expect(await hmacHex(await sha256(RAW_KEY), PINNED_NONCE, PINNED_TIMESTAMP))
      .toBe(PINNED_HMAC);
    expect(
      await verifyWakeHmac(PINNED_KEY_HASH_HEX, PINNED_NONCE, PINNED_TIMESTAMP, PINNED_HMAC),
    ).toBe(true);
  });

  it("rejects wrong domain, nonce, timestamp, key, and malformed hmac", async () => {
    expect(
      await verifyWakeHmac(PINNED_KEY_HASH_HEX, "bb", PINNED_TIMESTAMP, PINNED_HMAC),
    ).toBe(false);
    expect(
      await verifyWakeHmac(PINNED_KEY_HASH_HEX, PINNED_NONCE, "2026-09-03T00:00:01Z", PINNED_HMAC),
    ).toBe(false);
    const otherKey = hexEncode(await sha256(new Uint8Array(32).fill(8)));
    expect(
      await verifyWakeHmac(otherKey, PINNED_NONCE, PINNED_TIMESTAMP, PINNED_HMAC),
    ).toBe(false);
    expect(
      await verifyWakeHmac(PINNED_KEY_HASH_HEX, PINNED_NONCE, PINNED_TIMESTAMP, "zz"),
    ).toBe(false);
    expect(
      await verifyWakeHmac(PINNED_KEY_HASH_HEX, PINNED_NONCE, PINNED_TIMESTAMP, "00"),
    ).toBe(false);
  });
});

describe("delivery policy", () => {
  const now = 1_800_000_000;

  it("delivers when no counter exists", () => {
    expect(decideDelivery(null, now)).toEqual({
      kind: "deliver",
      deliveredThisHour: 0,
      hourBucket: Math.floor(now / 3600),
    });
  });

  it("deduplicates a second request inside the 30 s window", () => {
    const counter: CounterRow = {
      hour_bucket: Math.floor(now / 3600),
      delivered_this_hour: 1,
      last_delivered_at: now - (DEDUPE_WINDOW_SEC - 1),
    };
    expect(decideDelivery(counter, now)).toEqual({ kind: "deduplicated" });
  });

  it("delivers again once the dedupe window has passed", () => {
    const counter: CounterRow = {
      hour_bucket: Math.floor(now / 3600),
      delivered_this_hour: 1,
      last_delivered_at: now - DEDUPE_WINDOW_SEC,
    };
    expect(decideDelivery(counter, now).kind).toBe("deliver");
  });

  it("allows at most six deliveries per hour bucket", () => {
    const counter: CounterRow = {
      hour_bucket: Math.floor(now / 3600),
      delivered_this_hour: HOURLY_DELIVERY_LIMIT,
      last_delivered_at: now - DEDUPE_WINDOW_SEC,
    };
    const decision = decideDelivery(counter, now);
    expect(decision.kind).toBe("rate_limited");
    if (decision.kind === "rate_limited") {
      const nextHourStart = (Math.floor(now / 3600) + 1) * 3600;
      expect(decision.retryAfterSeconds).toBe(nextHourStart - now);
    }
  });

  it("resets the budget in a fresh hour bucket", () => {
    const counter: CounterRow = {
      hour_bucket: Math.floor(now / 3600) - 1,
      delivered_this_hour: HOURLY_DELIVERY_LIMIT,
      last_delivered_at: now - DEDUPE_WINDOW_SEC - 1,
    };
    expect(decideDelivery(counter, now).kind).toBe("deliver");
  });
});

describe("timestamp window", () => {
  it("parses RFC 3339 seconds and rejects junk", () => {
    expect(parseTimestampSeconds("2026-09-03T00:00:00Z")).toBe(Date.parse("2026-09-03T00:00:00Z") / 1000);
    expect(parseTimestampSeconds("not a time")).toBeNull();
    expect(parseTimestampSeconds(12345)).toBeNull();
  });

  it("accepts ±120 s and rejects beyond", () => {
    const now = 1_800_000_000;
    expect(timestampWithinWindow(now - 120, now)).toBe(true);
    expect(timestampWithinWindow(now + 120, now)).toBe(true);
    expect(timestampWithinWindow(now - 121, now)).toBe(false);
    expect(timestampWithinWindow(now + 121, now)).toBe(false);
  });
});

describe("peer label and notification copy", () => {
  it("sanitizes control characters and enforces the byte budget", () => {
    expect(sanitizePeerLabel("  Cody's MacBook\u0007 ")).toBe("Cody's MacBook");
    expect(sanitizePeerLabel(undefined)).toBeNull();
    expect(sanitizePeerLabel("   ")).toBeNull();
    expect(sanitizePeerLabel(42)).toBeNull();
    expect(sanitizePeerLabel("x".repeat(129))).toBeNull();
    expect(sanitizePeerLabel("x".repeat(128))).toBe("x".repeat(128));
  });

  it("renders the spec notification copy with fallback", () => {
    expect(notificationBody("Pixel CLI")).toBe("Pixel CLI is requesting data. Tap to continue.");
    expect(notificationBody(null)).toBe(
      "A paired computer is requesting data. Tap to continue.",
    );
    const payload = notificationPayload("Pixel CLI") as {
      aps: { alert: { title: string; body: string }; sound: string; category: string };
      healthmd: { kind: string };
    };
    expect(payload.aps.alert.title).toBe("Health.md");
    expect(payload.aps.sound).toBe("default");
    expect(payload.aps.category).toBe("HEALTHMD_DIRECT_WAKE");
    expect(payload.healthmd.kind).toBe("direct-cli-wake");
    // No-PII allowlist: the payload carries no health data, dates, or request contents.
    const serialized = JSON.stringify(payload);
    expect(serialized).not.toMatch(/heart|step|sleep|metric|export|query/i);
  });
});

describe("hex helpers", () => {
  it("round-trips and rejects malformed hex", () => {
    expect(hexEncode(hexDecode("00ff10")!)).toBe("00ff10");
    expect(hexDecode("0g")).toBeNull();
    expect(hexDecode("abc")).toBeNull();
  });
});
