import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { analyzeTestDeclarations, validateCatalogObservable } from "./test-declarations.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const repositoryRoot = resolve(root, "../..");
const load = async name => JSON.parse(await readFile(resolve(root, `qualification/v1/${name}`), "utf8"));
const [requirements, assertionsCatalog, securityInventory, states, gate] = await Promise.all([load("requirements.json"), load("assertions.json"), load("security-inventory.json"), load("supported-state-matrix.json"), load("production-gate.json")]);
const failures = [];
const expectedSources = {
  "TODO-81774f3a": ["2026-08-06T12:16:12.091Z", 5, 4], "TODO-76d2aded": ["2026-08-06T12:16:12.092Z", 5, 4], "TODO-561b2d46": ["2026-08-06T12:16:12.092Z", 4, 4],
  "TODO-619d8dd9": ["2026-08-06T12:16:12.092Z", 5, 4], "TODO-a1c1ef99": ["2026-08-06T12:16:12.092Z", 5, 4], "TODO-4d128f47": ["2026-08-06T12:16:12.092Z", 5, 4],
  "TODO-b7108062": ["2026-08-06T12:16:12.092Z", 4, 4], "TODO-3d906a23": ["2026-08-06T12:16:12.092Z", 4, 4], "TODO-75609397": ["2026-08-06T12:16:12.092Z", 5, 4],
  "TODO-3bc0a95e": ["2026-08-06T12:16:12.092Z", 5, 4], "TODO-a273aaa2": ["2026-08-06T12:16:12.092Z", 4, 4], "TODO-ba61941d": ["2026-08-06T12:16:12.092Z", 5, 4],
  "TODO-a96e65bc": ["2026-08-06T12:16:12.092Z", 5, 4], "TODO-ffe95cf9": ["2026-08-06T12:14:09.311Z", 5, 4], "TODO-3ad095b3": ["2026-08-06T00:51:32.938Z", 5, 3],
  "TODO-e76646f8": ["2026-08-06T00:51:32.938Z", 6, 3],
};
const expectedSourceMetadataSha256 = "d9184848252e0fb797435dc3f2e38911c7e2e0f00f5f267d1fd3a858d773b944";
const expectedCriterionBodiesSha256 = "ef0f7fc7ff72a372d1d7291909719f961c97a154cccfbee4a82ac04177befeeb";
const immutableSourceDigest = createHash("sha256").update(JSON.stringify(requirements.sourceTodos ?? [])).digest("hex");
const immutableCriterionDigest = createHash("sha256").update(JSON.stringify((requirements.criteria ?? []).map(({ id, sourceTodoId, section, ordinal, text }) => ({ id, sourceTodoId, section, ordinal, text })))).digest("hex");
if (immutableSourceDigest !== expectedSourceMetadataSha256) failures.push("immutable source TODO titles/status/timestamps/parent metadata digest changed");
if (immutableCriterionDigest !== expectedCriterionBodiesSha256) failures.push("immutable exact 139 criterion text/source/section/ordinal digest changed");
const expectedIds = [];
for (const [source, [, first, acceptance]] of Object.entries(expectedSources)) {
  const section = source === "TODO-ffe95cf9" ? "required-boundaries" : "work";
  for (let i = 1; i <= first; i++) expectedIds.push(`${source}-${section}-${String(i).padStart(2, "0")}`);
  for (let i = 1; i <= acceptance; i++) expectedIds.push(`${source}-acceptance-${String(i).padStart(2, "0")}`);
}
if (requirements.criterionCount !== 139 || requirements.criteria?.length !== 139 || JSON.stringify(requirements.criteria.map(item => item.id).sort()) !== JSON.stringify(expectedIds.sort())) failures.push("criterion traceability must contain the exact 139 Work/Acceptance/boundary criterion IDs");
if (requirements.sourceTodos?.length !== 16 || new Set(requirements.sourceTodos.map(item => item.id)).size !== 16) failures.push("source TODO metadata must contain exactly 13 children, epic, and two parents");
for (const source of requirements.sourceTodos ?? []) {
  const expected = expectedSources[source.id]; if (!expected || source.createdAt !== expected[0] || source.sourceStatus !== "open" || !source.title) failures.push(`${source.id} source id/timestamp/status/title is not preserved`);
}
const evidenceLevels = new Set(["direct-automated", "proxy/service-only", "not-evidenced"]); const statuses = new Set(["partial", "pending"]); const ownership = new Set(["portal", "backend", "external/manual"]);
const catalogLayers = new Set(["browser-e2e", "rendered-ui", "final-http", "service-unit", "static-policy"]); const directLayers = new Set(["browser-e2e", "rendered-ui", "final-http"]);
const expectedCatalogLayer = observable => {
  if (observable.file.startsWith("e2e/")) return "browser-e2e";
  if (observable.file === "test/worker.test.ts") return "final-http";
  if (observable.file.endsWith(".test.tsx")) return observable.file === "test/foundation.test.tsx" && observable.title !== "escapes hostile fictional content and keeps boundary copy visible" ? "static-policy" : "rendered-ui";
  if (["test/clinical-boundary.test.ts", "test/component-runtime-boundary.test.ts"].includes(observable.file)) return "static-policy";
  return "service-unit";
};
const counts = { "direct-automated": 0, "proxy/service-only": 0, "not-evidenced": 0, partial: 0, pending: 0 };
const catalogById = new Map(); const catalogKeys = new Set();
if (assertionsCatalog.schema !== "healthmd.practice.qualification.assertions/v1" || assertionsCatalog.version !== 1 || assertionsCatalog.observableCount !== assertionsCatalog.observables?.length || !assertionsCatalog.semantics?.includes("not passing-execution or completion evidence")) failures.push("assertion catalog v1 metadata or structural-only disclaimer is invalid");
for (const observable of assertionsCatalog.observables ?? []) {
  if (!observable.id || catalogById.has(observable.id)) failures.push(`duplicate or missing assertion catalog ID: ${observable.id}`); else catalogById.set(observable.id, observable);
  const key = `${observable.file}\0${observable.title}`; if (catalogKeys.has(key)) failures.push(`duplicate file/title declaration in assertion catalog: ${observable.file} :: ${observable.title}`); catalogKeys.add(key);
  if (typeof observable.file !== "string" || observable.file.includes("\\") || observable.file.split("/").includes("..") || !/^(?:test|e2e)\/[^/]+\.(?:test|spec)\.tsx?$/.test(observable.file)) failures.push(`${observable.id} has path traversal or a file outside test/ and e2e/`);
  const expectedCommand = observable.file?.startsWith("test/") ? ["vitest", "npm test"] : ["playwright-isolated-engines", "npm run test:e2e"];
  if (observable.command?.id !== expectedCommand[0] || observable.command?.value !== expectedCommand[1]) failures.push(`${observable.id} command/file mismatch`);
  if (!catalogLayers.has(observable.evidenceLayer) || observable.evidenceLayer !== expectedCatalogLayer(observable)) failures.push(`${observable.id} evidence layer does not match its governed executable-test surface`);
  if (!Array.isArray(observable.assertions) || observable.assertions.length === 0 || new Set(observable.assertions.map(item => item.id)).size !== observable.assertions.length || observable.assertions.some(item => !item.id?.startsWith(`${observable.id}-assertion-`) || !item.kind || !/^[a-f0-9]{64}$/.test(item.normalizedAstSha256 ?? "") || !item.excerpt || !Number.isInteger(item.line))) failures.push(`${observable.id} must contain unique observable-scoped concrete hashed assertion observables`);
  try {
    const source = await readFile(resolve(root, observable.file), "utf8");
    const analysis = analyzeTestDeclarations(source, observable.file);
    for (const error of validateCatalogObservable(observable, analysis)) failures.push(`${observable.id}: ${error}`);
    const declaration = analysis.declarations.find(item => item.title === observable.title);
    const requiredSignal = observable.evidenceLayer === "browser-e2e" ? "browserInteraction" : observable.evidenceLayer === "rendered-ui" ? "renderedUiObservation" : observable.evidenceLayer === "final-http" ? "finalHttpResponse" : null;
    if (requiredSignal && !declaration?.surfaceSignals?.[requiredSignal]) failures.push(`${observable.id} lacks the governed ${requiredSignal} AST signal required by its direct evidence layer`);
  } catch { failures.push(`${observable.id} evidence file is missing or unreadable: ${observable.file}`); }
}
const seenObservableIds = new Set(); const seenGaps = new Set(); const referencedCatalogIds = new Set(); const auditCriteria = [];
for (const item of requirements.criteria ?? []) {
  if (!item.text?.trim() || !item.gap?.trim() || !expectedSources[item.sourceTodoId]) failures.push(`${item.id} lacks exact criterion text, source, or explicit gap`);
  if (!evidenceLevels.has(item.evidenceLevel) || !statuses.has(item.currentStatus) || !ownership.has(item.ownership)) failures.push(`${item.id} has invalid ownership/evidence/status`);
  if (!Array.isArray(item.evidence) || !Array.isArray(item.missingFacets) || item.missingFacets.length === 0 || item.missingFacets.some(facet => typeof facet !== "string" || facet.trim().length < 20)) failures.push(`${item.id} requires nonempty criterion-specific missingFacets`);
  if (item.missingFacets.some(facet => /remaining facets|not directly asserted for:/i.test(facet))) failures.push(`${item.id} missingFacets uses prohibited generic or criterion-repeating prose`);
  if (seenGaps.has(item.gap) || item.gap.length < 40 || !item.gap.includes(item.id)) failures.push(`${item.id} gap must be unique, substantive, and criterion-specific`); seenGaps.add(item.gap);
  counts[item.evidenceLevel]++; counts[item.currentStatus]++;
  const auditObservables = [];
  if (item.currentStatus === "pending") {
    if (item.evidence.length !== 0 || item.evidenceLevel !== "not-evidenced") failures.push(`${item.id} pending criterion must have empty/not-evidenced evidence`);
    if (!item.gap.includes("pending")) failures.push(`${item.id} pending criterion requires an explicit blocker`);
  } else if (!item.evidence.length || !["direct-automated", "proxy/service-only"].includes(item.evidenceLevel)) failures.push(`${item.id} partial criterion requires assertion-backed direct or proxy evidence`);
  for (const evidence of item.evidence) {
    if (!evidence.observableRef || !evidence.observableId || !evidence.observableDescription || evidence.observableDescription.length < 20 || !Array.isArray(evidence.assertionRefs) || evidence.assertionRefs.length === 0) { failures.push(`${item.id} evidence requires catalog/assertion references, a criterion-scoped ID, and substantive description`); continue; }
    if (seenObservableIds.has(evidence.observableId) || !evidence.observableId.startsWith(`${item.id}-observable-`)) failures.push(`${item.id} observable ID is duplicate or not criterion-scoped`); seenObservableIds.add(evidence.observableId);
    const observable = catalogById.get(evidence.observableRef); if (!observable) { failures.push(`${item.id} references missing catalog observable ${evidence.observableRef}`); continue; }
    referencedCatalogIds.add(observable.id);
    const description = evidence.observableDescription.trim(); const normalized = value => value.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
    if (normalized(description) === normalized(observable.title) || normalized(description).includes(normalized(observable.title)) || /exact test declaration asserts|description\s*[:=-]?\s*title/i.test(description)) failures.push(`${item.id} evidence description is title-echo boilerplate for ${observable.id}`);
    const assertionById = new Map(observable.assertions.map(assertion => [assertion.id, assertion]));
    if (new Set(evidence.assertionRefs).size !== evidence.assertionRefs.length || evidence.assertionRefs.some(ref => !assertionById.has(ref))) failures.push(`${item.id} has duplicate or missing assertion references for ${observable.id}`);
    const selectedAssertions = evidence.assertionRefs.map(ref => assertionById.get(ref)).filter(Boolean);
    if (selectedAssertions.some(assertion => !description.includes(assertion.excerpt))) failures.push(`${item.id} description must quote every selected assertion excerpt for independent inspection`);
    const isDirect = directLayers.has(observable.evidenceLayer);
    if (item.evidenceLevel === "proxy/service-only" && isDirect) failures.push(`${item.id} proxy evidence references direct-layer observable ${observable.id}`);
    auditObservables.push({ observableId: evidence.observableId, observableRef: observable.id, evidenceLayer: observable.evidenceLayer, file: observable.file, title: observable.title, assertions: selectedAssertions.map(({ id, kind, excerpt, line, normalizedAstSha256 }) => ({ assertionRef: id, kind, excerpt, line, normalizedAstSha256 })) });
  }
  if (item.currentStatus === "partial" && item.evidenceLevel === "direct-automated" && !auditObservables.some(entry => directLayers.has(entry.evidenceLayer))) failures.push(`${item.id} direct evidence lacks an explicitly cataloged browser/UI/final-HTTP observable`);
  auditCriteria.push({ criterionId: item.id, status: item.currentStatus, evidenceLevel: item.evidenceLevel, observables: auditObservables });
}
for (const entry of [...(securityInventory.routes ?? []), ...(securityInventory.operations ?? []), ...(securityInventory.controls ?? [])]) for (const evidence of entry.evidence ?? []) {
  const observable = catalogById.get(evidence.observableRef);
  if (!observable || observable.file !== evidence.file || observable.title !== evidence.test) failures.push(`security inventory evidence does not resolve to its exact assertion catalog observable: ${entry.route ?? entry.operation ?? entry.control}`);
  else referencedCatalogIds.add(observable.id);
}
if (referencedCatalogIds.size !== catalogById.size) failures.push(`assertion catalog must contain exactly the requirement/security referenced declarations: referenced=${referencedCatalogIds.size}, catalog=${catalogById.size}`);
const assertionAudit = { schema: "healthmd.practice.qualification.assertion-audit/v1", semantics: "Deterministic assertion-level structural traceability only; not passing-execution or completion evidence.", criterionCount: auditCriteria.length, catalogObservableCount: catalogById.size, criteria: auditCriteria };
await mkdir(resolve(root, "qualification/generated"), { recursive: true });
await writeFile(resolve(root, "qualification/generated/assertion-audit.json"), `${JSON.stringify(assertionAudit, null, 2)}\n`);
const criterionById = new Map(requirements.criteria.map(item => [item.id, item]));
for (const id of ["TODO-ffe95cf9-acceptance-01", "TODO-ffe95cf9-acceptance-02", "TODO-a96e65bc-acceptance-02", "TODO-b7108062-work-01", "TODO-3ad095b3-work-04"]) if (criterionById.get(id)?.currentStatus !== "pending") failures.push(`${id} must remain explicitly pending`);
if (!requirements.artifactSemantics?.includes("structural traceability") || !requirements.artifactSemantics.includes("not an execution attestation")) failures.push("requirements must identify structural traceability and disclaim execution attestation");
const expectedChildren = Object.keys(expectedSources).slice(0, 13); if (JSON.stringify(requirements.parentChildMapping?.children) !== JSON.stringify(expectedChildren) || requirements.parentChildMapping?.portalEpic !== "TODO-ffe95cf9" || JSON.stringify(requirements.parentChildMapping?.decomposedParents) !== JSON.stringify(["TODO-3ad095b3", "TODO-e76646f8"])) failures.push("parent-child/decomposition mapping is incorrect");
if (requirements.completionAttested !== false || requirements.manualAssistiveTechnologyQualification !== "pending" || !requirements.statement?.includes("No child TODO, epic, or decomposed parent completion is attested")) failures.push("traceability must explicitly remain partial and non-completion evidence");
if (states.runtime.mode !== "synthetic" || states.runtime.productionEnabled !== false || states.externalResources !== false) failures.push("supported state must be synthetic, production-disabled, and local-only");
if (JSON.stringify(states.browserProjects.map(item => item.name)) !== JSON.stringify(["chromium", "firefox", "webkit"]) || states.browserProjects.some(item => !item.realBrowserAutomation || !item.isolatedServiceProcess || item.manualLatestTwo)) failures.push("three isolated real engines are required without latest-two claims");
const expectedObservables = { axeRenderedStatesAutomated: true, keyboardDialogFocusAutomated: true, focusGeometryNotObscuredAutomated: true, viewport320ReflowAutomated: true, css400PercentEquivalentReflowAutomated: true, printCssDomAutomated: true, reducedMotionMatchMediaAndPropertyAutomated: true, forcedColorsMatchMediaAndPropertyWhereSupportedAutomated: true, actualBrowserZoom400Manual: false, nativePdfOutputManual: false, screenReaderManual: false };
if (JSON.stringify(states.accessibilityObservables) !== JSON.stringify(expectedObservables)) failures.push("supported-state accessibility observable names/values are not exact");
if (states.mobileContract.qrAndDeepLink !== "blocked_pending_approved_contract" || states.mobileContract.physicalDevice !== false) failures.push("mobile contract/device qualification must remain blocked");
const expectedSynthetic = [["locked_install_static_unit", "npm ci && npm run check"], ["isolated_real_browser_engines", "npm run test:e2e"], ["strict_security_qualification_provenance", "npm run check:qualification"], ["runtime_smoke_package_audit", "npm run test:smoke && npm run dry-run && npm audit --audit-level=moderate"]];
if (JSON.stringify(gate.syntheticGates?.map(item => [item.name, item.requiredCommand])) !== JSON.stringify(expectedSynthetic) || gate.syntheticGates.some(item => item.wiringStatus !== "configured-not-attested")) failures.push("synthetic gate names/commands/wiring statuses are not exact");
const pendingNames = ["authoritative_backend_and_persistence", "external_security_review_and_penetration_test", "compliance_and_privacy_review", "baa_and_subprocessor_approval", "mobile_contract_and_physical_device_qualification", "manual_screen_reader_and_assistive_technology", "pilot_practice_approval", "named_release_security_compliance_owners"];
if (JSON.stringify(gate.mandatoryProductionGates?.map(item => item.name)) !== JSON.stringify(pendingNames) || gate.mandatoryProductionGates.some(item => item.approved !== false || item.status !== "pending")) failures.push("exact eight mandatory production gates must remain pending/false");
const operational = ["migration", "rollback", "backup_restore", "authoritative_purge"]; if (JSON.stringify(gate.operationalEvidence?.map(item => item.name)) !== JSON.stringify(operational) || gate.operationalEvidence.some(item => item.status !== "not_implemented")) failures.push("exact operational not-implemented list is required");
if (gate.designation !== "synthetic-qualification-only-not-production-ready" || gate.productionEnabled !== false || gate.productionReady !== false) failures.push("production must explicitly remain disabled/not ready");
const packageJson = JSON.parse(await readFile(resolve(root, "package.json"), "utf8")); const workflow = await readFile(resolve(repositoryRoot, ".github/workflows/practice-ci.yml"), "utf8");
if (packageJson.scripts["test:e2e"] !== "playwright test --project=chromium && playwright test --project=firefox && playwright test --project=webkit" || !packageJson.scripts["check:ci"].includes("npm audit --audit-level=moderate") || !workflow.includes("run: npm run check:ci")) failures.push("package/workflow isolated-browser/full-gate wiring is not exact");
const provenance = JSON.parse(await readFile(resolve(root, "qualification/generated/provenance.json"), "utf8")); const sha = bytes => createHash("sha256").update(bytes).digest("hex");
const provenanceTimestamp = Date.parse(provenance.generatedAt);
const provenanceAge = Date.now() - provenanceTimestamp;
if (provenance.schema !== "practice.synthetic.provenance/2" || provenance.productionEnabled !== false || !Number.isFinite(provenanceTimestamp) || provenanceAge < 0 || provenanceAge > 10 * 60_000) failures.push("provenance timestamp must be valid, not future-dated, and no older than ten minutes; provenance must remain production-unsafe");
const filesUnder = async directory => { const output = []; try { for (const entry of await readdir(directory, { withFileTypes: true })) { const path = join(directory, entry.name); if (entry.isDirectory()) output.push(...await filesUnder(path)); else output.push(path); } } catch (error) { if (error.code !== "ENOENT") throw error; } return output; };
const provenanceRoots = ["src", "static", "fixtures", "qualification/v1", "scripts", "test", "e2e", "docs"]; const provenanceRootFiles = [".env.example", ".gitignore", "AGENTS.md", "LICENSE", "Makefile", "README.md", "package.json", "package-lock.json", "playwright.config.ts", "tsconfig.json", "vitest.config.ts", "wrangler.toml"];
const expectedProvenancePaths = (await Promise.all(provenanceRoots.map(path => filesUnder(resolve(root, path))))).flat().map(path => relative(root, path).replaceAll("\\", "/")); expectedProvenancePaths.push(...provenanceRootFiles, ".github/workflows/practice-ci.yml"); expectedProvenancePaths.sort();
if (JSON.stringify(provenance.sourceFiles?.map(file => file.pathSha256)) !== JSON.stringify(expectedProvenancePaths.map(path => sha(path))) || provenance.sourceFiles?.some(file => "path" in file)) failures.push("provenance path-digest set must exactly cover current Practice inputs without serializing raw source paths");
const treeHasher = createHash("sha256");
for (const [index, file] of (provenance.sourceFiles ?? []).entries()) { const display = expectedProvenancePaths[index]; if (!display) { failures.push("unexpected provenance source entry"); continue; } const path = display.startsWith(".github/") ? resolve(repositoryRoot, display) : resolve(root, display); try { const bytes = await readFile(path); if (file.pathSha256 !== sha(display) || !file.bytes || file.bytes !== bytes.length || file.sha256 !== sha(bytes)) failures.push(`stale source provenance digest at index ${index}`); treeHasher.update(display); treeHasher.update("\0"); treeHasher.update(bytes); treeHasher.update("\0"); } catch { failures.push(`missing provenance source at index ${index}`); } }
if (!provenance.sourceFiles?.length || provenance.currentTreeSha256 !== treeHasher.digest("hex") || provenance.lockSha256 !== sha(await readFile(resolve(root, "package-lock.json")))) failures.push("source/tree/lock provenance hashes must be nonempty/current");
for (const asset of provenance.buildAssets ?? []) { try { const bytes = await readFile(resolve(root, asset.path)); if (!asset.bytes || asset.bytes !== bytes.length || asset.sha256 !== sha(bytes)) failures.push(`stale/empty built asset provenance: ${asset.path}`); } catch { failures.push(`missing built asset: ${asset.path}`); } }
if (!provenance.buildAssets?.length) failures.push("nonempty built asset provenance is required");
const gitStatus = execFileSync("git", ["status", "--porcelain=v1", "--untracked-files=all", "--", "apps/practice", ".github/workflows/practice-ci.yml"], { cwd: repositoryRoot, encoding: "utf8" }).trim().split("\n").filter(Boolean);
if (provenance.git.repositoryHead !== execFileSync("git", ["rev-parse", "HEAD"], { cwd: repositoryRoot, encoding: "utf8" }).trim() || provenance.git.dirty !== (gitStatus.length > 0) || provenance.git.scopedChangeCount !== gitStatus.length || provenance.git.statusDigest !== sha(gitStatus.join("\n")) || "status" in provenance.git || (provenance.git.dirty && provenance.git.candidateCommit !== null)) failures.push("git HEAD/dirty/count/digest/candidate provenance is not truthful or exposes raw changed paths");
if (failures.length) throw new Error(`Qualification verification failed:\n${failures.join("\n")}`);
console.log(`Structural traceability counts only (not execution attestations): ${requirements.criteria.length} immutable exact criteria across ${requirements.sourceTodos.length} TODO sources; direct=${counts["direct-automated"]}, proxy=${counts["proxy/service-only"]}, not-evidenced=${counts["not-evidenced"]}, partial=${counts.partial}, pending=${counts.pending}.`);
console.log(`Production gate: ${gate.mandatoryProductionGates.length} mandatory approvals pending; ${gate.operationalEvidence.length} operational capabilities not implemented; productionReady=false.`);
