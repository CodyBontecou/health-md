import { readFile, readdir } from "node:fs/promises";
import { join, resolve } from "node:path";
import { describe, expect, it } from "vitest";
// @ts-expect-error The provenance helper is executed directly as an ES module.
import { safeProvenanceMetadataPath } from "../scripts/provenance-metadata.mjs";

const root = resolve(import.meta.dirname, "..");
async function files(directory: string): Promise<string[]> {
  const result: string[] = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    if (["node_modules", "dist", ".wrangler", "test-results", "playwright-report"].includes(entry.name)) continue;
    const path = join(directory, entry.name); if (entry.isDirectory()) result.push(...await files(path)); else result.push(path);
  }
  return result;
}

describe("practice component and production-disabled runtime boundary", () => {
  it("owns required governance, lock, build, qualification, and deployment-boundary files", async () => {
    for (const path of [".env.example", "AGENTS.md", "README.md", "package.json", "package-lock.json", "tsconfig.json", "wrangler.toml", "scripts/build.mjs", "scripts/build-provenance.mjs", "scripts/dry-run.mjs", "qualification/v1/production-gate.json", "docs/architecture.md", "docs/threat-model.md"]) await expect(readFile(join(root, path), "utf8")).resolves.toBeTruthy();
    await expect(readFile(join(root, ".env.example"), "utf8")).resolves.toBe("# Local development accepts this exact non-secret value only.\n# Any missing, unknown, or production-like value fails closed.\nPRACTICE_RUNTIME_MODE=synthetic\n");
    const pkg = JSON.parse(await readFile(join(root, "package.json"), "utf8")) as { private: boolean; scripts: Record<string, string> };
    expect(pkg.private).toBe(true); expect(pkg.scripts.check).toContain("typecheck"); expect(pkg.scripts.check).toContain("npm test"); expect(pkg.scripts.check).toContain("npm run build"); expect(pkg.scripts["check:ci"]).toContain("test:e2e"); expect(pkg.scripts["check:ci"]).toContain("check:qualification"); expect(pkg.scripts["dry-run"]).toBeTruthy();
  });

  it("structurally defines focused mobile policy jobs without reusable full-workflow calls", async () => {
    const workflow = await readFile(resolve(root, "../..", ".github/workflows/practice-ci.yml"), "utf8");
    expect(workflow).toContain("pull_request:\n  push:\n    branches: [main]\n    paths:");
    expect(workflow).not.toMatch(/pull_request:\s*\n\s+paths:/);
    expect(workflow).toContain("- 'apps/apple/HealthMd.xcodeproj/**'");
    expect(workflow).toContain("- 'apps/android/app/build.gradle.kts'");
    expect(workflow).toContain("run: npm ci");
    expect(workflow).toContain("run: npm run check:ci");
    expect(workflow).toContain("practice-focused-apple-policy:");
    expect(workflow).toContain("practice-focused-android-policy:");
    expect(workflow).toContain("workflow_call:");
    expect(workflow).not.toContain("uses: ./.github/workflows/apple-ci.yml");
    expect(workflow).not.toContain("uses: ./.github/workflows/android-ci.yml");
    expect(workflow).not.toContain("xcodebuild");
    expect(workflow).toContain('plutil -convert json -o "$project_json" apps/apple/HealthMd.xcodeproj/project.pbxproj');
    expect(workflow).toContain('value.get("isa") == "PBXNativeTarget" and value.get("name") == "HealthMd"');
    expect(workflow).toContain('checked_configuration_names = {"Release", "Release-iOS"}');
    expect(workflow).toContain("if len(releases) != 2 or {name for name, _ in releases} != checked_configuration_names:");
    expect(workflow).toContain("baseConfigurationReference");
    expect(workflow).toContain("if marker in json.dumps(project, sort_keys=True):");
    expect(workflow).toContain('os.environ.get("XCODE_XCCONFIG_FILE")');
    expect(workflow).toContain("for variable, value in os.environ.items():");
    expect(workflow).toContain("swiftc \"$policy\" \"$harness\"");
    expect(workflow).toContain("swiftc -D HEALTHMD_PRACTICE_COMPILED_IN");
    expect(workflow).toContain("-Dhealthmd.practice.expectedCompiledIn=false");
    expect(workflow).toContain("-Dhealthmd.practice.expectedCompiledIn=true");
    expect(workflow).toContain("PRACTICE_COMPILED_IN: included");
    expect(workflow).toContain(":app:clean :app:testPlayDebugUnitTest --tests com.healthmd.domain.practice.PracticeFeaturePolicyTest");
    expect(workflow).toContain("needs: [validate, practice-focused-apple-policy, practice-focused-android-policy]");
    expect(workflow.match(/ref: \$\{\{ github\.sha \}\}/g)).toHaveLength(3);
  });

  it("has no website/legacy Worker dependency and no deployment route or persistence binding", async () => {
    const source = (await Promise.all((await files(root)).filter(path => /\.(?:ts|tsx|mjs|json|toml|md)$/.test(path)).map(path => readFile(path, "utf8")))).join("\n");
    expect(source).not.toMatch(/(?:from|import\s*)\s*["'][^"']*(?:apps\/website|\/worker\/)/);
    const wrangler = await readFile(join(root, "wrangler.toml"), "utf8"); expect(wrangler).toContain('PRACTICE_RUNTIME_MODE = "synthetic"'); expect(wrangler).toContain("workers_dev = false"); expect(wrangler).not.toMatch(/^routes?\s*=/m); expect(wrangler).not.toMatch(/^\[\[(?:d1_databases|kv_namespaces|r2_buckets|queues)\]\]/m);
  });

  it("configures PHI-free current-tree build provenance while operational evidence stays unimplemented", async () => {
    const script = await readFile(join(root, "scripts/build-provenance.mjs"), "utf8");
    expect(script).toContain('schema: "practice.synthetic.provenance/3"');
    expect(script).toContain("productionEnabled: false");
    expect(script).toContain("syntheticBoundaryFiles(root, repositoryRoot, { includeDist: false })");
    expect(script).toContain("candidateCommit: dirty ? null : sourceHeadCommit");
    expect(script).toContain("safeProvenanceMetadataPath");
    expect(script).toContain("statusDigest");
    expect(script).toContain("pathSha256: digest(item.display)");
    expect(script).not.toContain("status: statusLines");
    expect(script).not.toContain("sourceFiles.push({ path: item.display");
    const gate = JSON.parse(await readFile(join(root, "qualification/v1/production-gate.json"), "utf8")) as { operationalEvidence: Array<{ name: string; status: string }> };
    expect(gate.operationalEvidence).toEqual([
      { name: "migration", status: "not_implemented" },
      { name: "rollback", status: "not_implemented" },
      { name: "backup_restore", status: "not_implemented" },
      { name: "authoritative_purge", status: "not_implemented" },
    ]);
    expect(script).toContain("qualifiedTreeCommit: repositoryHead");
    expect(script).toContain("sourceHeadCommit");
  });

  it("rejects identity-like or raw-status path metadata before provenance serialization", () => {
    expect(safeProvenanceMetadataPath("src/synthetic/service.ts")).toBe(true);
    for (const path of ["patient.json", "src/patient/record.ts", "dob.json", "src/email/file.ts", "src/foo/fullname.ts", "src/foo/Avery", "src/foo/Avery.ts", "src/Patient-Jordan.json", "fixtures/record_dob2040.json", "status path with spaces", "contact_email1.txt", "Taylor-Fictional.ts"]) expect(safeProvenanceMetadataPath(path)).toBe(false);
  });

  it("keeps every production gate exactly false/pending and designates the runtime disabled", async () => {
    const gate = JSON.parse(await readFile(join(root, "qualification/v1/production-gate.json"), "utf8")) as { designation: string; productionEnabled: boolean; productionReady: boolean; syntheticRuntimeRequired: boolean; mandatoryProductionGates: Array<{ approved: boolean; status: string }>; operationalEvidence: Array<{ status: string }> };
    expect(gate).toMatchObject({ designation: "synthetic-qualification-only-not-production-ready", productionEnabled: false, productionReady: false, syntheticRuntimeRequired: true });
    expect(gate.mandatoryProductionGates.every(item => item.approved === false && item.status === "pending")).toBe(true); expect(gate.operationalEvidence.every(item => item.status === "not_implemented")).toBe(true);
  });
});
