import { describe, expect, it } from "vitest";
import { fileURLToPath } from "node:url";
import { readFileSync } from "node:fs";
import * as codec from "../src/profile-sync-v1-contract";
import { runConformance } from "../../../packages/contracts/profile-sync/v1/conformance.mjs";

describe("proposed profile-sync v1: real bounded parser + full portable semantics", () => {
  it("uses the shared content, lexical, metadata and source-scenario fixtures", async () => {
    const result = await runConformance(codec, fileURLToPath(new URL("../../..", import.meta.url)));
    expect(result.fixtures).toBe(10);
    expect(result.parserCases).toBe(257);
    expect(result.scenarios).toBe(30);
    expect(result.readRequests).toBe(6);
    expect(result.fixedErrors).toBe(11);
  });
  it("rejects missing or mistyped format arrays without asserting an unchecked field exists", async () => {
    for (const formats of [undefined, null, "json", false]) {
      const content = JSON.parse(readFileSync(new URL("../../../packages/contracts/profile-sync/v1/fixtures/apple-1.json", import.meta.url), "utf8"));
      if (formats === undefined) delete content.profile.export.formats;
      else content.profile.export.formats = formats;
      await expect(codec.ValidatedProfileSyncV1Content.parse(new TextEncoder().encode(JSON.stringify(content)))).rejects.toBeInstanceOf(codec.ProfileSyncV1Error);
    }
  });
  it("cannot fabricate a validated immutable content/reference from unchecked JSON", () => {
    expect(codec.ValidatedProfileSyncV1Content.isValidated({ contentJson: "{}", hash: "0".repeat(64) })).toBe(false);
    expect(codec.ValidatedProfileSyncV1Record.isValidated({ profileId: "psp_" + "1".repeat(32), objectRevision: 1 })).toBe(false);
    expect(codec.ValidatedProfileSyncV1Content.isValidated(Object.create(codec.ValidatedProfileSyncV1Content.prototype))).toBe(false);
    expect(codec.ValidatedProfileSyncV1Record.isValidated(Object.create(codec.ValidatedProfileSyncV1Record.prototype))).toBe(false);
  });
});
