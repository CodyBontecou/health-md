import { describe, expect, it } from "vitest";
import { encodeBase64 } from "../src/crypto";
import { derivePasswordVerifier, normalizeUsername, passwordIterations, verifyPassword } from "../src/password";

const pepper = encodeBase64(new Uint8Array(32).fill(17));
const otherPepper = encodeBase64(new Uint8Array(32).fill(19));
const salt = new Uint8Array(32).fill(23);
const password = "synthetic-password-for-tests-only";

describe("single-user password verifier", () => {
  it("normalizes usernames and rejects weak passwords", async () => {
    expect(normalizeUsername("  Pilot.User  ")).toBe("pilot.user");
    expect(() => normalizeUsername("p")).toThrow();
    await expect(derivePasswordVerifier("short", pepper, salt)).rejects.toThrow();
  });

  it("uses a salted peppered verifier and rejects wrong inputs", async () => {
    const hash = await derivePasswordVerifier(password, pepper, salt);
    expect(passwordIterations).toBeGreaterThanOrEqual(600_000);
    expect(hash).not.toContain(password);
    expect(await verifyPassword(password, pepper, encodeBase64(salt), hash, passwordIterations)).toBe(true);
    expect(await verifyPassword("synthetic-password-for-tests-else", pepper,
      encodeBase64(salt), hash, passwordIterations)).toBe(false);
    expect(await verifyPassword(password, otherPepper, encodeBase64(salt), hash, passwordIterations)).toBe(false);
    expect(await verifyPassword("short", pepper, encodeBase64(salt), hash, passwordIterations)).toBe(false);
  });
});
