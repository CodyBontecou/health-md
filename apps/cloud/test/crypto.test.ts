import { describe, expect, it } from "vitest";
import {
  decodeBase64, decryptExport, decryptIdentity, encodeBase64, encryptExport,
  encryptIdentity, keyedLookup, parseExportKeyring, randomToken, sha256Hex,
  unwrapAccountExportKey, wrapAccountExportKey,
} from "../src/crypto";

const key = encodeBase64(new Uint8Array(32).fill(7));
const secondKey = encodeBase64(new Uint8Array(32).fill(8));
const bytes = new TextEncoder().encode('{"synthetic":"health-data"}');

describe("private storage cryptography", () => {
  it("round-trips ciphertext with a different salt/nonce per envelope", async () => {
    const first = await encryptExport(bytes, key, "account-1", "export-1");
    const second = await encryptExport(bytes, key, "account-1", "export-1");
    expect(first).not.toEqual(second);
    expect(await decryptExport(first, key, "account-1", "export-1")).toEqual(bytes);
    expect(await sha256Hex(await decryptExport(first, key, "account-1", "export-1")))
      .toBe(await sha256Hex(bytes));
  });

  it("binds ciphertext to account, export, key, and exact bytes", async () => {
    const ciphertext = await encryptExport(bytes, key, "account-1", "export-1");
    await expect(decryptExport(ciphertext, key, "account-2", "export-1")).rejects.toThrow();
    await expect(decryptExport(ciphertext, key, "account-1", "export-2")).rejects.toThrow();
    await expect(decryptExport(ciphertext, secondKey, "account-1", "export-1")).rejects.toThrow();
    const tampered = ciphertext.slice();
    tampered[tampered.length - 1]! ^= 1;
    await expect(decryptExport(tampered, key, "account-1", "export-1")).rejects.toThrow();
  });

  it("wraps account export keys with account and key-version authenticated data", async () => {
    const wrapped = await wrapAccountExportKey(key, secondKey, "account-1", "data-key-1", "kek-v1");
    expect(wrapped.wrappedKey).not.toBe(key);
    expect(await unwrapAccountExportKey(wrapped.wrappedKey, wrapped.iv, secondKey,
      "account-1", "data-key-1", "kek-v1")).toBe(key);
    await expect(unwrapAccountExportKey(wrapped.wrappedKey, wrapped.iv, secondKey,
      "account-2", "data-key-1", "kek-v1")).rejects.toThrow();
    await expect(unwrapAccountExportKey(wrapped.wrappedKey, wrapped.iv, key,
      "account-1", "data-key-1", "kek-v1")).rejects.toThrow();
  });

  it("encrypts account identities and separates lookup purposes", async () => {
    const identity = await encryptIdentity("user@example.test", key, "account-1");
    expect(identity.ciphertext).not.toContain("user@example.test");
    expect(await decryptIdentity(identity.ciphertext, identity.iv, key, "account-1"))
      .toBe("user@example.test");
    await expect(decryptIdentity(identity.ciphertext, identity.iv, key, "account-2")).rejects.toThrow();
    expect(await keyedLookup("user@example.test", key, "email-lookup-v1"))
      .not.toBe(await keyedLookup("user@example.test", key, "other-v1"));
  });

  it("refuses missing or malformed keyring values", () => {
    expect(parseExportKeyring(JSON.stringify({ v1: key })).get("v1")).toBe(key);
    expect(() => parseExportKeyring("{}")).toThrow();
    expect(() => parseExportKeyring(JSON.stringify({ v1: "short" }))).toThrow();
    expect(() => parseExportKeyring(JSON.stringify({ "../evil": key }))).toThrow();
    expect(decodeBase64(encodeBase64(new Uint8Array(32)))).toHaveLength(32);
    expect(randomToken()).toMatch(/^[A-Za-z0-9_-]{40,50}$/u);
  });
});
