import { execFileSync } from "node:child_process";
import { rm, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { afterEach, describe, expect, it } from "vitest";

const root = resolve(import.meta.dirname, "..");
const probe = resolve(import.meta.dirname, `.synthetic-boundary-probe-${process.pid}.txt`);
afterEach(async () => { await rm(probe, { force: true }); });

function scannerFailure(): string {
  try { execFileSync(process.execPath, ["scripts/check-synthetic-only.mjs"], { cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }); }
  catch (error) { const failure = error as { stdout?: string; stderr?: string }; return `${failure.stdout ?? ""}\n${failure.stderr ?? ""}`; }
  throw new Error("scanner unexpectedly accepted the prohibited probe");
}

describe("synthetic boundary scanner coverage", () => {
  it("rejects a real-person marker added under the test root", async () => {
    const prohibited = ["Morgan Ac", "tual DOB 1980-01-02 and ", ["123", "45", "6789"].join("-")].join("");
    await writeFile(probe, prohibited);
    expect(scannerFailure()).toContain("real-person/identity marker");
  });

  it("rejects an unexpected binary rather than silently skipping its extension", async () => {
    await writeFile(probe, Uint8Array.from([0, 1, 2, 3, 4]));
    expect(scannerFailure()).toContain("unexpected binary or invalid UTF-8 content");
  });
});
