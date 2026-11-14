import { expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const repo = resolve(import.meta.dirname, "../../..");
const vectors = JSON.parse(readFileSync(resolve(repo,
  "packages/contracts/cloud-repair/v1/fixtures/link-v1.json"), "utf8")) as {
    accepted: string[]; rejected: string[];
  };
it("keeps a single static cross-platform link without request details", () => {
  expect(vectors.accepted).toEqual(["healthmd://cloud/requests"]);
  for (const link of vectors.rejected) expect(link).not.toBe(vectors.accepted[0]);
  const swift = readFileSync(resolve(repo, "apps/apple/HealthMd/iOS/CloudRepairLink.swift"), "utf8");
  const kotlin = readFileSync(resolve(repo,
    "apps/android/app/src/main/java/com/healthmd/presentation/CloudRepairLink.kt"), "utf8");
  const manifest = readFileSync(resolve(repo, "apps/android/app/src/main/AndroidManifest.xml"), "utf8");
  const panel = readFileSync(resolve(repo, "apps/cloud/public/repair-panel.html"), "utf8");
  expect(swift).toContain(`static let rawValue = "${vectors.accepted[0]}"`);
  expect(kotlin).toContain(`const val URI = "${vectors.accepted[0]}"`);
  expect(manifest).toContain('android:scheme="healthmd" android:host="cloud" android:path="/requests"');
  expect(panel).not.toContain('href="healthmd:'); // No launch until verified supplemental receipts.
});
