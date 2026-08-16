import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { analyzeTestDeclarations, validateCatalogObservable } from "./test-declarations.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const load = async file => JSON.parse(await readFile(resolve(root, file), "utf8"));
const [policy, inventory, assertionCatalog] = await Promise.all([load("src/contracts/authorization-policy.json"), load("qualification/v1/security-inventory.json"), load("qualification/v1/assertions.json")]);
const failures = [];
const catalogById = new Map();
for (const observable of assertionCatalog.observables ?? []) {
  if (!observable.id || catalogById.has(observable.id)) failures.push(`assertion catalog has duplicate or missing observable ID: ${observable.id}`);
  else catalogById.set(observable.id, observable);
}
const matrixFacetForTitle = title => title.startsWith("public route") || title.startsWith("public operation") ? "publicAccess" : title.includes("positive matrix") || title.includes("preauthorizes every") ? "authorizedAccess" : title.includes("denies no session") ? "noSession" : title.includes("denies opposite role") || title.includes("denies wrong role") ? "wrongRole" : title.includes("tenant-B") || title.includes("foreign tenant") ? "tenantEvidence" : null;
const expectedControlTest = {
  csrf: "requires CSRF and ignores browser attempts to provide tenant/role", origin: "rejects %s", cache: "applies restrictive no-store headers without CORS", headers: "applies restrictive no-store headers without CORS", xss: "renders hostile content only as escaped text and has no axe violations", content_sniffing: "applies restrictive no-store headers without CORS", clickjacking: "applies restrictive no-store headers without CORS", open_redirect: "rejects open-redirect return URL and navigation payloads without a Location header", session_fixation: "sets a fixation-safe HttpOnly Secure Strict cookie and memory-only CSRF", rate_limit: "rate limits lookup and represents all search outcomes", redaction: "strictly rejects invalid audit pagination/category and redacts values",
};
const semanticMarkers = (facet, title) => {
  if (facet === "publicAccess") return title.startsWith("public route") ? ["publicHeadings[route]", "toBeVisible"] : ["authState", "mfa_required", "recovery_handoff"];
  if (facet === "authorizedAccess") return title.includes("positive matrix") ? ["protectedHeadings[route]", "Capability unavailable"] : ["preauthorizeOperation", "not.toThrow"];
  if (facet === "noSession") return title.includes("route") ? ["Clinician sign in", "toBeVisible"] : ["missing_session", "denial(", "operation_unavailable"];
  if (facet === "wrongRole") return title.includes("route") ? ["Capability unavailable", "toBeVisible"] : ["preauthorizeOperation(session", "denial(", "operation_unavailable"];
  if (facet === "tenantEvidence") return title.includes("tenant-B") ? ["not.toContain", "tenant_a"] : ["foreignPayload", "denial(", "operation_unavailable"];
  const control = facet.startsWith("control:") ? facet.slice("control:".length) : "";
  return ({
    csrf: ["session", "tenantId", "denied.status"], origin: ["response.status", "error: { code"], cache: ["Cache-Control", "no-store"], headers: ["Content-Security-Policy", "Strict-Transport-Security", "X-Frame-Options"], xss: ["getAllByText(hostile)", "querySelector(\"img\")", "toBeNull"], content_sniffing: ["X-Content-Type-Options", "nosniff"], clickjacking: ["X-Frame-Options", "DENY"], open_redirect: ["Location", "toBeNull"], session_fixation: ["attacker_fixed", "HttpOnly", "SameSite=Strict"], rate_limit: ["rate_limited", "relationshipSearch"], redaction: ["encoded", "not.toContain"],
  })[control] ?? [];
};
const evidenceValid = async (owner, evidence, requiredFacets, expectedFacetForItem) => {
  if (!Array.isArray(evidence) || evidence.length === 0) { failures.push(`${owner} lacks nonempty assertion-backed structural evidence`); return; }
  const covered = new Set();
  for (const item of evidence) {
    if (!item?.file || !item?.test || !item?.observableRef || !Array.isArray(item.assertionRefs) || item.assertionRefs.length === 0 || !Array.isArray(item.coveredFacets) || item.coveredFacets.length === 0) { failures.push(`${owner} has incomplete assertion/facet-catalog evidence`); continue; }
    const observable = catalogById.get(item.observableRef);
    if (!observable || observable.file !== item.file || observable.title !== item.test) { failures.push(`${owner} evidence does not resolve to its exact assertion catalog entry`); continue; }
    const assertionIds = observable.assertions.map(assertion => assertion.id);
    if (JSON.stringify(item.assertionRefs) !== JSON.stringify(assertionIds)) failures.push(`${owner} must bind the complete exact assertion set for its security declaration`);
    const expectedFacet = expectedFacetForItem(item);
    if (!expectedFacet || JSON.stringify(item.coveredFacets) !== JSON.stringify([expectedFacet])) failures.push(`${owner} has a self-asserted or mismatched security facet for ${item.test}`);
    else covered.add(expectedFacet);
    try {
      const source = await readFile(resolve(root, item.file), "utf8");
      const analysis = analyzeTestDeclarations(source, item.file);
      for (const error of validateCatalogObservable(observable, analysis)) failures.push(`${owner} assertion evidence invalid: ${error}`);
      const declaration = analysis.declarations.find(candidate => candidate.title === item.test);
      const assertionSemanticText = declaration?.assertions.map(assertion => assertion.semanticText).join("\n") ?? "";
      const markers = expectedFacet ? semanticMarkers(expectedFacet, item.test) : [];
      if (markers.length === 0 || markers.some(marker => !assertionSemanticText.includes(marker))) failures.push(`${owner} concrete assertion AST does not contain the governed semantic markers for ${expectedFacet}`);
    } catch { failures.push(`${owner} evidence file is missing: ${item.file}`); }
  }
  for (const facet of requiredFacets) if (!covered.has(facet)) failures.push(`${owner} lacks assertion-backed ${facet} evidence`);
};
const mirror = (kind, canonical, entries) => {
  const keys = kind === "route" ? ["route", "requiredCapability", "classification", "authorizedRoles", "noSessionTest", "wrongRoleTest", "tenantEvidence"] : ["operation", "requiredCapability", "classification", "authorizedRoles", "noSessionTest", "wrongRoleTest", "csrfRequired", "tenantEvidence"];
  const identity = kind === "route" ? "route" : "operation";
  if (entries.length !== canonical.length || new Set(entries.map(item => item[identity])).size !== entries.length) failures.push(`${kind} inventory count/uniqueness mismatch`);
  for (const expected of canonical) {
    const actual = entries.find(item => item[identity] === expected[identity]);
    if (!actual) { failures.push(`missing ${kind} ${expected[identity]}`); continue; }
    for (const key of keys) if (JSON.stringify(actual[key]) !== JSON.stringify(expected[key])) failures.push(`${kind} ${expected[identity]} does not mirror canonical ${key}`);
    for (const denial of [["noSession", expected.noSessionTest], ["wrongRole", expected.wrongRoleTest], ["tenantEvidence", expected.tenantEvidence !== "none"]]) {
      const text = actual.denialEvidence?.[denial[0]];
      if (typeof text !== "string" || !text || (denial[1] ? text.startsWith("not-applicable:") : !text.startsWith("not-applicable:"))) failures.push(`${kind} ${expected[identity]} has incorrect ${denial[0]} applicability/reason`);
    }
  }
};
mirror("route", policy.routes, inventory.routes); mirror("operation", policy.operations, inventory.operations);
if (policy.routes.find(entry => entry.route === "/")?.authorizedRoles.length !== 0) failures.push("public / must declare no authorized roles");
for (const entry of [...policy.routes, ...policy.operations]) {
  if (entry.requiredCapability === "public" && entry.authorizedRoles.length !== 0) failures.push(`${entry.route ?? entry.operation} public policy must not declare authorized roles`);
  if (entry.requiredCapability !== "public" && entry.authorizedRoles.length === 0) failures.push(`${entry.route ?? entry.operation} protected policy requires declared roles`);
  if (entry.requiredCapability !== "public" && entry.requiredCapability !== "authenticated") for (const role of entry.authorizedRoles) if (!policy.roleCapabilities[role]?.includes(entry.requiredCapability)) failures.push(`${entry.route ?? entry.operation} role ${role} lacks its canonical required capability`);
}
for (const entry of policy.operations) if (entry.csrfRequired !== !(entry.requiredCapability === "public" || entry.operation === "session_bootstrap")) failures.push(`${entry.operation} CSRF determination is inconsistent with canonical public/bootstrap policy`);
if (inventory.canonicalPolicy !== "src/contracts/authorization-policy.json" || inventory.routeCount !== policy.routes.length || inventory.operationCount !== policy.operations.length || inventory.routeScope !== policy.scope || JSON.stringify(inventory.fixedHttpSurfaces) !== JSON.stringify(policy.fixedHttpSurfaces)) failures.push("inventory canonical pointer, client-route scope, fixed HTTP surfaces, or counts are incorrect");
for (const entry of [...inventory.routes, ...inventory.operations]) {
  const requiredFacets = [entry.requiredCapability === "public" ? "publicAccess" : "authorizedAccess"];
  if (entry.noSessionTest) requiredFacets.push("noSession");
  if (entry.wrongRoleTest) requiredFacets.push("wrongRole");
  if (entry.tenantEvidence !== "none") requiredFacets.push("tenantEvidence");
  await evidenceValid(`${entry.route ?? entry.operation}`, entry.evidence, requiredFacets, item => matrixFacetForTitle(item.test));
}
const requiredControls = ["csrf", "origin", "cache", "headers", "xss", "content_sniffing", "clickjacking", "open_redirect", "session_fixation", "rate_limit", "redaction"];
if (JSON.stringify(inventory.controls.map(item => item.control).sort()) !== JSON.stringify([...requiredControls].sort())) failures.push("security control inventory is incomplete");
for (const item of inventory.controls) {
  if (item.evidence.length !== 1 || item.evidence[0]?.test !== expectedControlTest[item.control]) failures.push(`control ${item.control} does not use its governed assertion declaration`);
  await evidenceValid(`control ${item.control}`, item.evidence, [`control:${item.control}`], () => `control:${item.control}`);
}
const matrixSource = await readFile(resolve(root, "test/security-matrix.test.ts"), "utf8");
for (const marker of ["authorizationPolicy.operations.filter", "public operation matrix:", "canonical operation policy runtime:", "denies no session through canonical preauthorization", "denies wrong role through canonical preauthorization", "denies an existing foreign tenant resource", "filter matrix excludes seeded tenant-B rows", "relationship_unique_b", "template_default_b", "request_state_issued_b", "packet_complete_b", "membership_admin_b"]) if (!matrixSource.includes(marker)) failures.push(`canonical operation matrix lacks ${marker}`);
const routeSource = await readFile(resolve(root, "test/authorization-routes.test.tsx"), "utf8");
for (const marker of ["authorizationPolicy.routes.filter", "public route matrix:", "denies no session", "denies opposite role even with forged capabilities", "protected route positive matrix:"]) if (!routeSource.includes(marker)) failures.push(`canonical route matrix lacks ${marker}`);
if (failures.length) throw new Error(`Security inventory verification failed:\n${failures.join("\n")}`);
console.log(`Structural security traceability: ${policy.routes.length} canonical client-visible fixed page routes, ${policy.fixedHttpSurfaces.length} separately inventoried fixed HTTP surfaces, ${policy.operations.length} canonical operations, ${requiredControls.length} controls; exact executable test declarations validated (not execution attestation).`);
