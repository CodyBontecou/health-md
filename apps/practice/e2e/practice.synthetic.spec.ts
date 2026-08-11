import AxeBuilder from "@axe-core/playwright";
import { expect, test, type BrowserContext, type Page, type Request } from "@playwright/test";

const genericTitle = "Health.md Practice";
const unsafeAddressData = /(?:packet_|request_|relationship_|membership_|invitation_|claimant_|csrf|token|secret|systolic|diastolic|pulse)/i;
const allowlistedPaths = new Set(["/", "/sign-in", "/verify", "/recovery", "/signed-out", "/access-denied", "/session-expired", "/unavailable", "/portal", "/portal/relationships", "/portal/relationship", "/portal/templates", "/portal/template", "/portal/template/edit", "/portal/requests", "/portal/request", "/portal/request/build", "/portal/request/preview", "/portal/invitation", "/portal/inbox", "/portal/report", "/portal/report/history", "/portal/report/print", "/portal/admin/members", "/portal/admin/retention", "/portal/admin/audit", "/api/v1/meta", "/api/v1/operation", "/styles.css", "/assets/app.js"]);

async function signIn(page: Page, login: "clinician" | "admin" = "clinician") {
  await page.goto("/sign-in");
  await expect(page).toHaveTitle(genericTitle);
  await page.getByLabel("Fictional login").selectOption(login);
  await page.getByRole("button", { name: "Continue to MFA" }).click();
  await expect(page).toHaveURL(/\/verify$/);
  await page.getByLabel("Fictional verification code").fill("246810");
  await page.getByRole("button", { name: "Verify synthetic account" }).click();
  await expect(page.getByRole("heading", { name: "Practice portal overview" })).toBeVisible();
}

async function assertAxe(page: Page) {
  const results = await new AxeBuilder({ page }).analyze();
  expect(results.violations, results.violations.map(item => `${item.id}: ${item.help}`).join("\n")).toEqual([]);
}

async function assertEphemeralBrowserState(context: BrowserContext, page: Page, persistenceMutations: string[]) {
  await page.waitForTimeout(0);
  expect(persistenceMutations).toEqual([]);
  expect(await page.evaluate(() => ({ local: localStorage.length, session: sessionStorage.length }))).toEqual({ local: 0, session: 0 });
  expect(await page.evaluate(async () => typeof indexedDB.databases === "function" ? (await indexedDB.databases()).length : 0)).toBe(0);
  expect(await page.evaluate(async () => "caches" in globalThis ? (await caches.keys()).length : 0)).toBe(0);
  expect(await page.evaluate(async () => "serviceWorker" in navigator ? (await navigator.serviceWorker.getRegistrations()).length : 0)).toBe(0);
  expect(await page.evaluate(() => document.cookie)).toBe("");
  for (const cookie of await context.cookies()) {
    expect(cookie.httpOnly).toBe(true);
    expect(cookie.secure).toBe(true);
    expect(cookie.sameSite).toBe("Strict");
  }
}

async function observePage(context: BrowserContext, page: Page) {
  const configuredOrigin = new URL(String(test.info().project.use.baseURL)).origin;
  const persistenceMutations: string[] = [];
  await context.exposeBinding("__recordPracticePersistenceMutation", (_source, value: string) => { persistenceMutations.push(value); });
  await context.addInitScript(() => {
    const target = globalThis as typeof globalThis & { __recordPracticePersistenceMutation?: (value: string) => Promise<void>; __practiceBlobFacts?: { type: string; size: number }[]; __practicePrintCalls?: number };
    target.__practiceBlobFacts = []; target.__practicePrintCalls = 0;
    const record = (value: string) => { void target.__recordPracticePersistenceMutation?.(value); };
    const wrapMutation = (object: object, method: string, label: string) => { const methods = object as unknown as Record<string, (...args: unknown[]) => unknown>; const original = methods[method]!; Object.defineProperty(object, method, { configurable: true, value: function (this: unknown, ...args: unknown[]) { record(label); return Reflect.apply(original, this, args); } }); };
    for (const method of ["setItem", "removeItem", "clear"]) wrapMutation(Storage.prototype, method, `storage.${method}`);
    for (const method of ["open", "deleteDatabase"]) wrapMutation(IDBFactory.prototype, method, `indexedDB.${method}`);
    if ("caches" in target) for (const method of ["open", "delete"]) wrapMutation(target.caches, method, `caches.${method}`);
    if ("serviceWorker" in navigator) { const serviceWorker = navigator.serviceWorker; const original = serviceWorker.register.bind(serviceWorker); Object.defineProperty(serviceWorker, "register", { configurable: true, value: (...args: Parameters<ServiceWorkerContainer["register"]>) => { record("serviceWorker.register"); return original(...args); } }); }
    const createObjectURL = URL.createObjectURL.bind(URL); URL.createObjectURL = (object: Blob | MediaSource) => { if (object instanceof Blob) target.__practiceBlobFacts!.push({ type: object.type, size: object.size }); return createObjectURL(object); };
    window.print = () => { target.__practicePrintCalls = (target.__practicePrintCalls ?? 0) + 1; };
  });
  const paths: string[] = []; const consoleOutput: string[] = []; const pageErrors: string[] = [];
  page.on("console", message => consoleOutput.push(`${message.type()}: ${message.text()}`));
  page.on("pageerror", error => pageErrors.push(error.message));
  page.on("request", (request: Request) => {
    const url = new URL(request.url());
    if (!["http:", "https:", "blob:", "data:"].includes(url.protocol)) throw new Error(`Unexpected network scheme: ${url.protocol}`);
    if (["http:", "https:"].includes(url.protocol)) {
      expect(url.origin).toBe(configuredOrigin); expect(url.username).toBe(""); expect(url.password).toBe(""); expect(url.search).toBe(""); expect(url.hash).toBe("");
      const decodedPath = decodeURIComponent(url.pathname); expect(decodedPath).toBe(url.pathname); expect(allowlistedPaths.has(decodedPath), `allowlisted path ${decodedPath}`).toBe(true); expect(decodedPath).not.toMatch(unsafeAddressData);
      const referrer = request.headers()["referer"] ?? "";
      if (referrer) { const parsed = new URL(referrer); expect(parsed.origin).toBe(configuredOrigin); expect(parsed.username).toBe(""); expect(parsed.password).toBe(""); expect(parsed.search).toBe(""); expect(parsed.hash).toBe(""); const decodedReferrer = decodeURIComponent(parsed.pathname); expect(decodedReferrer).toBe(parsed.pathname); expect(allowlistedPaths.has(decodedReferrer)).toBe(true); expect(decodedReferrer).not.toMatch(unsafeAddressData); }
      paths.push(decodedPath);
    }
  });
  return { paths, consoleOutput, pageErrors, persistenceMutations };
}

async function chooseRelationship(page: Page) {
  await page.getByRole("link", { name: "Relationships" }).click();
  await page.getByLabel("Synthetic scenario").selectOption("zero");
  await page.getByRole("button", { name: "Search relationships" }).click();
  await expect(page.getByText("No matching relationships")).toBeVisible();
  await page.getByLabel("Synthetic scenario").selectOption("ambiguous");
  await page.getByRole("button", { name: "Search relationships" }).click();
  await expect(page.getByText("Multiple possible relationships")).toBeVisible();
  await expect(page.getByRole("button", { name: "Select this relationship" })).toHaveCount(2);
  await expect(page).toHaveURL(/\/portal\/relationships$/);
  await page.getByLabel("Synthetic scenario").selectOption("unique");
  await page.getByRole("button", { name: "Search relationships" }).click();
  await page.getByRole("button", { name: "Select this relationship" }).click();
  await expect(page.getByRole("heading", { name: "Relationship provenance" })).toBeVisible();
}

async function startBuilder(page: Page) {
  await page.getByRole("link", { name: "Requests" }).click();
  await page.getByRole("button", { name: "Start new request" }).click();
  await expect(page.getByRole("heading", { name: "Build a synthetic request" })).toBeVisible();
}

async function previewContext(page: Page, context: "pre_visit" | "medication_follow_up" | "recurring_collection") {
  const templateId = context === "pre_visit" ? "template_default_a" : context === "medication_follow_up" ? "template_synthetic_medication_a" : "template_synthetic_recurring_a";
  await page.getByLabel("Active template revision").selectOption(templateId);
  await expect(page.getByRole("radio", { name: "Use preset unchanged" })).toBeChecked();
  await expect(page.getByRole("region", { name: "Exact read-only preset summary" })).toContainText(context.replaceAll("_", " "));
  await page.getByRole("button", { name: "Validate and preview" }).click();
  await expect(page.getByRole("heading", { name: "Review before issue" })).toBeVisible();
  const table = page.getByRole("table", { name: "Canonical request fields" });
  await expect(table).toContainText(context);
  await expect(table).toContainText("all_readings");
  await expect(table).toContainText("at_period_end");
}

test.describe("serial real local Wrangler qualification", () => {
  test("clinician document workflow, browser privacy, rendered accessibility, download, and print", async ({ context, page, browserName }) => {
    const observed = await observePage(context, page);
    await signIn(page);
    await assertAxe(page);
    await page.evaluate(() => { history.pushState(null, "", "/portal/admin/members"); dispatchEvent(new PopStateEvent("popstate")); });
    await expect(page.getByText("Capability unavailable")).toBeVisible();
    await page.getByLabel("Health.md Practice synthetic portal home").click();
    await chooseRelationship(page);
    await startBuilder(page);
    await page.setViewportSize({ width: 320, height: 720 }); const builderReflow = await page.evaluate(() => ({ body: document.body.scrollWidth, document: document.documentElement.scrollWidth, viewport: document.documentElement.clientWidth })); expect(builderReflow.body).toBeLessThanOrEqual(builderReflow.viewport); expect(builderReflow.document).toBeLessThanOrEqual(builderReflow.viewport); await assertAxe(page); await page.setViewportSize({ width: 1280, height: 720 });

    await page.getByLabel("Active template revision").selectOption("template_default_a");
    await page.getByRole("radio", { name: "Constrained customization" }).click();
    await page.getByRole("radio", { name: /Relative completed days/ }).click();
    await page.getByRole("button", { name: "Validate and preview" }).click();
    await expect(page.getByRole("alert")).toContainText("relative_acceptance_unresolved");
    await page.getByLabel("Collection schedule").selectOption("once_daily");
    await page.getByLabel("Submission cadence").selectOption("every_n_days");
    await page.getByRole("button", { name: "Validate and preview" }).click();
    await expect(page.getByRole("alert")).toContainText("dst_materialization_unresolved");
    await expect(page.getByRole("alert")).toContainText("cadence_anchor_unresolved");
    await expect(page.getByRole("button", { name: "Issue this exact preview" })).toHaveCount(0); await assertAxe(page);

    await startBuilder(page);
    await previewContext(page, "pre_visit");
    await startBuilder(page);
    await previewContext(page, "medication_follow_up");
    await startBuilder(page);
    await previewContext(page, "recurring_collection");
    const issueResponses: string[] = [];
    page.on("request", request => {
      if (request.url().endsWith("/api/v1/operation") && request.postData()?.includes('"operation":"request_issue"')) issueResponses.push(request.postData() ?? "");
    });
    await page.getByRole("button", { name: "Issue this exact preview" }).click();
    await expect(page.getByRole("heading", { name: "One-time synthetic invitation" })).toBeVisible(); await assertAxe(page);
    const secret = await page.locator(".secret-display").textContent();
    expect(secret).toMatch(/^invitation_synthetic_/);
    await expect(page).toHaveURL(/\/portal\/invitation$/);
    expect(page.url()).not.toContain(secret!);
    await page.getByRole("button", { name: "Synthetic claim" }).click();
    await expect(page.getByText(/Original one-time token cleared/)).toBeVisible();
    await expect(page.locator("body")).not.toContainText(secret!);
    await page.getByRole("button", { name: "Accept these exact instructions" }).click();
    await expect(page.getByText(/Claimant receipt cleared/)).toBeVisible();
    expect(issueResponses).toHaveLength(1);
    await page.getByRole("link", { name: "Requests" }).click();
    await page.goBack();
    await expect(page.locator("body")).not.toContainText(secret!);
    await expect(page.getByText(/One-time invitation selection expired/)).toBeVisible();

    await page.getByRole("link", { name: "Requests" }).click();
    const acceptedRecurring = page.getByRole("row").filter({ hasText: "recurring collection" }).filter({ hasText: "accepted" }).last();
    await acceptedRecurring.getByRole("button", { name: "Open" }).click();
    await page.getByRole("button", { name: "Start explicit successor" }).click();
    await page.getByLabel("Inclusive start date").fill("2040-01-08");
    await page.getByLabel("Exclusive end date").fill("2040-01-15");
    await page.getByRole("button", { name: "Validate and preview" }).click();
    await expect(page.getByRole("table", { name: "Canonical request fields" })).toContainText("recurring_collection");
    await page.getByRole("button", { name: "Issue this exact preview" }).click();
    await page.getByRole("button", { name: "Synthetic claim" }).click();
    await page.getByRole("button", { name: "Accept these exact instructions" }).click();
    await page.getByRole("link", { name: "Requests" }).click();
    const successor = page.getByRole("row").filter({ hasText: "recurring collection" }).filter({ hasText: "accepted" }).last();
    await successor.getByRole("button", { name: "Open" }).click();
    await page.getByRole("button", { name: "Cancel request" }).click();
    await expect(page.getByRole("table", { name: "Separate lifecycle facts" })).toContainText("canceled");

    await page.getByRole("link", { name: "Packet inbox" }).click();
    await expect(page.getByRole("heading", { name: "Packet inbox" })).toBeVisible(); await expect(page.getByRole("table", { name: "Synthetic packet metadata" })).toBeVisible();
    let appliedInboxRequests = 0; page.on("request", request => { if (request.postData()?.includes('"operation":"inbox"')) appliedInboxRequests += 1; });
    await page.getByLabel("Opaque request code").fill("request_fixture"); await page.getByLabel("Received sort").selectOption("received_asc"); await page.waitForTimeout(50); expect(appliedInboxRequests).toBe(0);
    await page.getByRole("button", { name: "Apply filters" }).focus(); await page.keyboard.press("Enter"); await expect.poll(() => appliedInboxRequests).toBe(1); await expect(page.getByRole("table", { name: "Synthetic packet metadata" })).toBeVisible();
    await page.getByRole("button", { name: "Clear filters" }).click(); await expect.poll(() => appliedInboxRequests).toBe(2);
    await page.getByRole("button", { name: "Next page" }).click();
    await expect(page.getByText(/Page 2/)).toBeVisible();
    await page.getByRole("button", { name: "Previous page" }).click();
    for (const shape of ["complete", "partial", "empty", "manual_source", "missing_pulse"]) {
      await page.getByLabel("Document shape").selectOption(shape); await page.getByRole("button", { name: "Apply filters" }).click();
      await expect(page.getByRole("table", { name: "Synthetic packet metadata" })).toBeVisible();
    }
    for (const fixture of [
      { shape: "partial", text: "health connect" },
      { shape: "empty", text: "0 paired readings" },
      { shape: "manual_source", text: "manual" },
      { shape: "missing_pulse", text: "No associated pulse" },
    ]) {
      await page.getByLabel("Document shape").selectOption(fixture.shape); await page.getByRole("button", { name: "Apply filters" }).click();
      await page.getByRole("button", { name: "Open report" }).first().click();
      await expect(page.locator("article")).toContainText(fixture.text);
      await page.getByRole("link", { name: "Packet inbox" }).click();
    }
    await page.getByLabel("Document shape").selectOption("complete"); await page.getByRole("button", { name: "Apply filters" }).click();
    await page.getByRole("button", { name: "Open report" }).first().click();
    await expect(page.getByRole("heading", { name: "Blood-pressure document report" })).toBeVisible();
    await expect(page.getByRole("table", { name: /Complete reading table/ })).toContainText("apple health");
    await expect(page.getByRole("img", { name: /Neutral systolic trend/ })).toBeVisible();
    await expect(page.getByText("Apple Health synthetic provenance")).toBeVisible();
    await expect(page.getByRole("table", { name: "Document provenance and exact periods" })).toContainText("packet_superseded");
    await assertAxe(page);

    const workflowFacts = page.getByRole("table", { name: "Separate workflow facts" });
    const freshFacts = await workflowFacts.textContent(); expect(freshFacts).toContain("actor_clinician"); expect(freshFacts?.match(/Not recorded/g)).toHaveLength(2);
    await page.getByRole("button", { name: "Print" }).click();
    expect(await page.evaluate(() => (globalThis as typeof globalThis & { __practicePrintCalls?: number }).__practicePrintCalls)).toBe(1);
    expect(await workflowFacts.textContent()).toBe(freshFacts);

    const downloadPromise = page.waitForEvent("download");
    await page.getByRole("button", { name: "Download canonical JSON" }).click();
    const download = await downloadPromise;
    expect(download.suggestedFilename()).toBe("practice-document.json");
    const stream = await download.createReadStream(); expect(stream).not.toBeNull();
    const chunks: Buffer[] = []; for await (const chunk of stream!) chunks.push(Buffer.from(chunk)); const downloadedBytes = Buffer.concat(chunks);
    expect(downloadedBytes.byteLength).toBeGreaterThan(100); const json = downloadedBytes.toString("utf8"); const artifact = JSON.parse(json);
    expect(artifact).toMatchObject({ schema: "practice.synthetic.packet/1.0-draft.2", id: "packet_complete_apple", shape: "complete", revision: 1 }); expect(artifact.readings).toHaveLength(2);
    expect(await page.evaluate(() => (globalThis as typeof globalThis & { __practiceBlobFacts?: { type: string; size: number }[] }).__practiceBlobFacts)).toEqual([{ type: "application/json", size: downloadedBytes.byteLength }]);
    expect(await workflowFacts.textContent()).toBe(freshFacts);

    const acknowledge = page.getByRole("button", { name: "Acknowledge receipt" });
    await acknowledge.focus();
    await page.keyboard.press("Enter");
    const dialog = page.getByRole("dialog");
    await expect(dialog).toBeVisible();
    const focusedCancel = dialog.getByRole("button", { name: "Keep current state" }); await expect(focusedCancel).toBeFocused();
    const focusGeometry = await focusedCancel.evaluate(element => { const rect = element.getBoundingClientRect(); const visible = document.elementFromPoint(rect.left + rect.width / 2, rect.top + rect.height / 2); return { top: rect.top, bottom: rect.bottom, height: innerHeight, unobscured: visible === element || element.contains(visible) }; });
    expect(focusGeometry.top).toBeGreaterThanOrEqual(0); expect(focusGeometry.bottom).toBeLessThanOrEqual(focusGeometry.height); expect(focusGeometry.unobscured).toBe(true);
    await page.setViewportSize({ width: 320, height: 720 }); const dialogReflow = await page.evaluate(() => ({ body: document.body.scrollWidth, document: document.documentElement.scrollWidth, viewport: document.documentElement.clientWidth })); expect(dialogReflow.body).toBeLessThanOrEqual(dialogReflow.viewport); expect(dialogReflow.document).toBeLessThanOrEqual(dialogReflow.viewport); await assertAxe(page); await page.setViewportSize({ width: 1280, height: 720 });
    await page.keyboard.press("Escape");
    await expect(acknowledge).toBeFocused();
    await acknowledge.click();
    await dialog.getByRole("button", { name: "Acknowledge receipt" }).click();
    await expect(page.getByText("Explicit receipt acknowledgment recorded.")).toBeVisible();
    await page.getByRole("button", { name: "Attest review separately" }).click();
    await dialog.getByRole("button", { name: "Attest review" }).click();
    await expect(page.getByText("Separate review attestation recorded.")).toBeVisible();
    await page.getByRole("link", { name: "View immutable history" }).click();
    const historyRows = page.getByRole("table", { name: "Exact revision, actor, and server-time history" }).getByRole("row");
    await expect(historyRows).toHaveCount(4);
    for (const [index, fact] of ["opened", "acknowledged", "reviewed"].entries()) { const row = historyRows.nth(index + 1); await expect(row).toContainText(fact); await expect(row).toContainText("actor_clinician"); await expect(row).toContainText("1"); }
    await page.goBack();

    await page.evaluate(() => { history.pushState(null, "", "/portal/report/print"); dispatchEvent(new PopStateEvent("popstate")); });
    await page.emulateMedia({ media: "print" });
    await expect(page.locator("article.print-view")).toBeVisible();
    await expect(page.locator("nav[aria-label='Practice portal']")).toHaveCSS("display", "none");
    await expect(page.locator(".screen-only")).toHaveCount(0);
    await expect(page.getByRole("table", { name: /Complete reading table/ })).toBeVisible();
    await expect(page.getByRole("img", { name: /Neutral systolic trend/ })).toBeVisible();
    await page.emulateMedia({ media: "screen", reducedMotion: "no-preference", forcedColors: "none" });
    expect(await page.evaluate(() => matchMedia("(prefers-reduced-motion: reduce)").matches)).toBe(false);
    await expect(page.getByLabel("Health.md Practice synthetic portal home")).toHaveCSS("transition-duration", "0s");
    const baselineMotion = await page.getByRole("button", { name: "Sign out" }).evaluate(element => getComputedStyle(element).transitionDuration); expect(baselineMotion).not.toBe("0s");
    await page.emulateMedia({ reducedMotion: "reduce" });
    expect(await page.evaluate(() => matchMedia("(prefers-reduced-motion: reduce)").matches)).toBe(true); await expect(page.getByRole("button", { name: "Sign out" })).toHaveCSS("transition-duration", "0s");
    const baselineBorder = await page.getByRole("button", { name: "Sign out" }).evaluate(element => getComputedStyle(element).borderTopWidth);
    await page.emulateMedia({ forcedColors: "active" });
    const forcedActive = await page.evaluate(() => matchMedia("(forced-colors: active)").matches); if (forcedActive) expect(await page.getByRole("button", { name: "Sign out" }).evaluate(element => getComputedStyle(element).borderTopWidth)).not.toBe(baselineBorder);
    await page.setViewportSize({ width: 320, height: 720 });
    const reflow = await page.evaluate(() => ({ body: document.body.scrollWidth, document: document.documentElement.scrollWidth, viewport: document.documentElement.clientWidth }));
    expect(reflow.body).toBeLessThanOrEqual(reflow.viewport); expect(reflow.document).toBeLessThanOrEqual(reflow.viewport); await assertAxe(page);

    await assertEphemeralBrowserState(context, page, observed.persistenceMutations);
    expect(observed.paths).toContain("/api/v1/operation");
    expect(observed.paths.every(path => !unsafeAddressData.test(path))).toBe(true);
    expect(observed.consoleOutput, `${browserName} non-allowlisted console output`).toEqual([]);
    expect(observed.pageErrors, `${browserName} page errors`).toEqual([]);
    await expect(page).toHaveTitle(genericTitle);
  });

  test("authenticated session-expired direct route and Back cannot restore protected content", async ({ context, page, browserName }) => {
    const observed = await observePage(context, page); await signIn(page, "admin");
    await page.getByRole("link", { name: "View safe expired state" }).click(); await expect(page.getByRole("heading", { name: "Session expired" })).toBeVisible();
    await page.reload(); await expect(page.getByRole("heading", { name: "Session expired" })).toBeVisible(); await expect(page.getByRole("navigation", { name: "Practice portal" })).toHaveCount(0);
    await page.getByLabel("Health.md Practice synthetic portal home").click(); await expect(page.getByRole("heading", { name: "Clinician sign in" })).toBeVisible();
    await page.goBack(); await expect(page.getByRole("heading", { name: "Session expired" })).toBeVisible(); await expect(page.getByRole("navigation", { name: "Practice portal" })).toHaveCount(0);
    await expect(page.getByRole("heading", { name: "Practice portal overview" })).toHaveCount(0); await page.goto("/sign-in"); await expect(page.getByRole("heading", { name: "Clinician sign in" })).toBeVisible();
    await assertEphemeralBrowserState(context, page, observed.persistenceMutations); expect(observed.consoleOutput, `${browserName} non-allowlisted console output`).toEqual([]); expect(observed.pageErrors).toEqual([]);
  });

  test("admin capability, step-up mutation, retention/audit, and logout/back clearing", async ({ context, page, browserName }) => {
    const observed = await observePage(context, page);
    await signIn(page, "admin");
    await page.getByRole("link", { name: "Templates" }).click(); await page.getByRole("button", { name: "Create synthetic template" }).click(); await expect(page.getByRole("heading", { name: "Create template" })).toBeVisible(); await assertAxe(page); await page.getByRole("button", { name: "Create active template" }).click(); await expect(page.getByRole("heading", { name: "Template details" })).toBeVisible(); await expect(page.getByRole("table", { name: "Template revision metadata" })).toContainText("active");
    await page.evaluate(() => { history.pushState(null, "", "/portal/inbox"); dispatchEvent(new PopStateEvent("popstate")); });
    await expect(page.getByText("Capability unavailable")).toBeVisible();
    await page.getByRole("link", { name: "Members" }).click(); await assertAxe(page);
    const clinicianRow = page.getByRole("row", { name: /^actor_clinician clinician / });
    const revoke = clinicianRow.getByRole("button", { name: "Revoke sessions" });
    await revoke.click();
    const dialog = page.getByRole("dialog");
    await expect(dialog.getByLabel("Fictional step-up code")).toHaveValue("246810"); await assertAxe(page);
    await dialog.getByRole("button", { name: "Verify and confirm" }).click();
    await expect(page.getByText(/Step-up succeeded; revoke recorded/)).toBeVisible();
    await expect(clinicianRow).not.toContainText("No"); await expect(clinicianRow).toContainText(/2040|20\d\d-/);
    await page.getByRole("link", { name: "Retention" }).click();
    await expect(page.getByText("Legal approval: no")).toBeVisible(); const initialRetention = page.getByRole("row").filter({ hasText: "artifact_partial_android" }); await expect(initialRetention).toContainText("scheduled"); await expect(initialRetention).toContainText("unacknowledged max"); await expect(initialRetention).toContainText("2040-04-08");
    await page.getByRole("link", { name: "Audit" }).click();
    await page.getByLabel("Category filter").selectOption("revocation");
    const revokeAudit = page.getByRole("row").filter({ hasText: "member_revoke_sessions" }); await expect(revokeAudit).toHaveCount(1); await expect(revokeAudit).toContainText("actor_admin"); await expect(revokeAudit).toContainText("success"); await expect(revokeAudit).toContainText("revocation");
    await assertAxe(page);
    await page.getByRole("button", { name: "Sign out" }).click();
    await expect(page.getByRole("heading", { name: "Signed out" })).toBeVisible();
    await page.goBack();
    await expect(page.locator("body")).not.toContainText("actor_clinician");
    await page.getByRole("link", { name: "Return to entry" }).click();
    await page.reload();
    await expect(page.getByRole("heading", { name: "Clinician sign in" })).toBeVisible();
    await assertEphemeralBrowserState(context, page, observed.persistenceMutations);
    expect(observed.consoleOutput, `${browserName} non-allowlisted console output`).toEqual([]);
    expect(observed.pageErrors, `${browserName} page errors`).toEqual([]);
  });
});
