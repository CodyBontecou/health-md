import { readFile, readdir } from "node:fs/promises";
import { extname, join, resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { practiceApiPaths } from "../src/contracts/api";
import { SyntheticClinicalService, type SyntheticFactories } from "../src/synthetic/service";

async function sourceFiles(directory: string): Promise<string[]> {
  const output: string[] = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) output.push(...await sourceFiles(path));
    else if ([".ts", ".tsx", ".html", ".css"].includes(extname(path))) output.push(path);
  }
  return output;
}

describe("clinical source and fixture boundary", () => {
  it("has no unrestricted HTML sink, remote destination, telemetry, browser persistence, or identifier-bearing API URL", async () => {
    const root = resolve(import.meta.dirname, "../src");
    const staticRoot = resolve(import.meta.dirname, "../static");
    const files = [...await sourceFiles(root), ...await sourceFiles(staticRoot)];
    const source = (await Promise.all(files.map(file => readFile(file, "utf8")))).join("\n");
    expect(source).not.toMatch(/dangerouslySetInnerHTML|\.innerHTML\b|document\.write\s*\(/);
    expect(source).not.toMatch(/https?:\/\/|google-analytics|hotjar|mixpanel|session.?replay/i);
    expect(source).not.toMatch(/localStorage|sessionStorage|indexedDB|serviceWorker/);
    expect(source).not.toMatch(/console\.(?:log|debug|info|warn|error)/);
    for (const path of Object.values(practiceApiPaths)) {
      expect(path).not.toContain("?"); expect(path).not.toMatch(/packet_|request_|relationship_|patient/i);
    }
  });

  it("keeps audit events free of health values, tokens, resource identifiers, and cross-tenant actor data", () => {
    let id = 0;
    const factories: SyntheticFactories = { clock: () => "2040-01-01T00:00:00.000Z", id: kind => `${kind}_${++id}`, token: kind => `${kind}_${++id}_synthetic_secret_material_1234567890` };
    const service = new SyntheticClinicalService(factories);
    const challenge = service.signIn("clinician"); const auth = service.verifyMfa(challenge.challengeId, "246810");
    service.inbox(auth.sessionId, {});
    const encoded = JSON.stringify(service.auditSnapshotForTest("tenant_a"));
    for (const prohibited of ["systolic", "diastolic", "pulse", "token", "secret", "packet_", "request_", "relationship_", "actor_other"]) expect(encoded).not.toContain(prohibited);
  });

  it("contains no prohibited clinical interpretation or response promise", async () => {
    const ui = [
      await readFile(resolve(import.meta.dirname, "../src/web/App.tsx"), "utf8"),
      await readFile(resolve(import.meta.dirname, "../src/synthetic/catalog.ts"), "utf8"),
    ].join("\n");
    expect(ui).not.toMatch(/diagnos(?:e|is)|adherence|non-?compliant|urgent result|we will respond|response within/i);
  });
});
