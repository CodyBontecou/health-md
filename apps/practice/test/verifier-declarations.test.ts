import { describe, expect, it } from "vitest";
// @ts-expect-error The verifier helper is executed directly as an ES module.
import { analyzeTestDeclarations, declaredTests, validateCatalogObservable } from "../scripts/test-declarations.mjs";

const analyze = (source: string) => analyzeTestDeclarations(source, "canary.test.ts");

describe("verifier test declaration AST canary", () => {
  it("recognizes nested and parameterized declarations but rejects comment, string, and interpolated-title fakes", () => {
    const source = `
      // it("line-comment fake", () => expect(true).toBe(false));
      /* test.each([[1]])("block-comment fake", () => expect(true).toBe(false)); */
      const fake = 'it("string fake", () => expect(true).toBe(false))';
      describe("nested", () => {
        it("real nested", () => expect(true).toBe(true));
        test.each([[1]])(\`parameterized $value\`, value => expect(value).toBe(1));
        test(\`template title\`, () => expect(true).toBe(true));
        test(\`interpolated ${"${value}"}\`, () => expect(true).toBe(true));
      });
    `;
    const result = analyze(source);
    expect([...declaredTests(source)].sort()).toEqual(["parameterized $value", "real nested", "template title"]);
    expect(result.invalidTitles).toHaveLength(1);
  });

  it("preserves duplicate file/title declarations for rejection rather than deduplicating", () => {
    const result = analyze(`it("duplicate", () => expect(1).toBe(1)); test("duplicate", () => expect(2).toBe(2));`);
    expect(result.declarations.filter((item: { title: string }) => item.title === "duplicate")).toHaveLength(2);
  });

  it("rejects a valid literal title whose callback has no assertion observable", () => {
    const result = analyze(`it("title only", () => { const value = 1; void value; });`);
    expect(result.declarations[0].assertions).toEqual([]);
  });

  it("normalizes trivia while making declaration and assertion hashes sensitive to behavior", () => {
    const first = analyze(`it("hash",()=>{ expect(1).toBe(1); });`).declarations[0];
    const trivia = analyze(`// comment\nit( "hash" , () => {\n expect(1).toBe(1);\n} ) ;`).declarations[0];
    const changed = analyze(`it("hash",()=>{ expect(1).toBe(2); });`).declarations[0];
    expect(first.declarationSha256).toBe(trivia.declarationSha256);
    expect(first.assertions[0].sha256).toBe(trivia.assertions[0].sha256);
    expect(changed.declarationSha256).not.toBe(first.declarationSha256);
    expect(changed.assertions[0].sha256).not.toBe(first.assertions[0].sha256);
    const assertion = { id: "observable-assertion-001", kind: "expect-matcher", normalizedAstSha256: first.assertions[0].sha256, excerpt: first.assertions[0].excerpt, line: first.assertions[0].line };
    const stale = { id: "observable", title: "hash", declaration: { normalizedAstSha256: first.declarationSha256 }, assertions: [assertion] };
    expect(validateCatalogObservable(stale, analyze(`it("hash",()=>{ expect(1).toBe(2); });`))).toContain("stale normalized declaration AST SHA-256");
    expect(validateCatalogObservable({ ...stale, assertions: [assertion, assertion] }, analyze(`it("hash",()=>{ expect(1).toBe(1); });`))).toContain("assertion IDs must be unique and observable-scoped");
  });

  it("binds it.each declaration hashes to parameterization data", () => {
    const one = analyze(`it.each([[1], [2]])("row %s", value => expect(value).toBeGreaterThan(0));`).declarations[0];
    const drift = analyze(`it.each([[1], [3]])("row %s", value => expect(value).toBeGreaterThan(0));`).declarations[0];
    expect(one.parameterizationSha256).not.toBe(drift.parameterizationSha256);
    expect(one.declarationSha256).not.toBe(drift.declarationSha256);
  });

  it("extracts concrete matchers, implicit findBy queries, and invoked local assertion helpers only", () => {
    const result = analyze(`
      function expectSafe(value: string) { expect(value).toBe("safe"); }
      function neverInvoked() { expect(false).toBe(true); }
      function unreachable() { if (false) expect(false).toBe(true); }
      const attacker = { expectSafe };
      it("observable", async () => {
        expect(1).toBe(1);
        await screen.findByRole("main");
        screen.findByText("unobserved promise is not evidence");
        expectSafe("safe");
      });
      it("helper is not evidence until invoked", () => { void neverInvoked; });
      it("property and unreachable helper calls are not evidence", () => { attacker.expectSafe("safe"); attacker.assert(false); unreachable(); if (false) expect(true).toBe(true); if (0) expect(true).toBe(true); if (false as boolean) expect(true).toBe(true); false && expect(true).toBe(true); (false === true) && expect(true).toBe(true); (false && true) && expect(true).toBe(true); ((false && true) === true) && expect(true).toBe(true); (1 > 2) && expect(true).toBe(true); });
      it("shadowed helper names are not evidence", (expectSafe: (value: string) => void) => { expectSafe("safe"); });
      it("catch and loop shadowed helper names are not evidence", () => { try { throw new Error(); } catch (expectSafe) { expectSafe("safe"); } for (const expectSafe of []) expectSafe("safe"); });
    `);
    expect(result.declarations[0].assertions.map((item: { kind: string }) => item.kind)).toEqual(["expect-matcher", "implicit-find-query", "local-assertion-helper"]);
    expect(result.declarations[1].assertions).toEqual([]);
    expect(result.declarations[2].assertions).toEqual([]);
    expect(result.declarations[3].assertions).toEqual([]);
    expect(result.declarations[4].assertions).toEqual([]);
  });

  it("binds invoked helper evidence to the full helper control-flow body", () => {
    const first = analyze(`function check(value: boolean) { if (value) expect(value).toBe(true); } it("helper", () => check(true));`).declarations[0].assertions[0];
    const changed = analyze(`function check(value: boolean) { if (!value) expect(value).toBe(true); } it("helper", () => check(true));`).declarations[0].assertions[0];
    expect(first.sha256).not.toBe(changed.sha256);
  });

  it("derives direct evidence surface signals from imported fixtures and trusted response flow rather than paths or local names", () => {
    const result = analyze(`
      import { render, screen } from "@testing-library/react";
      import worker from "../src/worker";
      async function fetchPath(path: string) { return worker.fetch(new Request(path), {}); }
      it("browser", async ({ page }) => { await expect(page.getByRole("main")).toBeVisible(); });
      it("rendered", () => { render("main"); expect(screen.getByRole("main")).toBeVisible(); });
      it("http", async () => { const response = await fetchPath("/"); expect(response.status).toBe(200); });
      it("plain", () => { expect(true).toBe(true); });
    `);
    expect(result.declarations.map((item: { surfaceSignals: object }) => item.surfaceSignals)).toEqual([
      { browserInteraction: true, renderedUiObservation: false, finalHttpResponse: false },
      { browserInteraction: false, renderedUiObservation: true, finalHttpResponse: false },
      { browserInteraction: false, renderedUiObservation: false, finalHttpResponse: true },
      { browserInteraction: false, renderedUiObservation: false, finalHttpResponse: false },
    ]);
    const spoofed = analyze(`
      import { cleanup, render } from "@testing-library/react";
      import worker from "../src/worker";
      async function fetchPath(path: string) { return worker.fetch(new Request(path), {}); }
      async function fakeResponse(useWorker: boolean) { if (useWorker) return worker.fetch(new Request("/"), {}); return { status: 200 }; }
      it("spoof", async () => { const page = { click() {} }; const screen = { getByText() {} }; const realResponse = await fetchPath("/"); { const realResponse = { status: 200 }; expect(realResponse.status).toBe(200); } page.click(); screen.getByText(); render.toString(); cleanup(); expect(render).toBeDefined(); const response = await fakeResponse(false); expect(response.status).toBe(200); });
    `).declarations[0];
    expect(spoofed.surfaceSignals).toEqual({ browserInteraction: false, renderedUiObservation: false, finalHttpResponse: false });
    const inertMarkers = analyze(`function inert() { void "session tenantId denied.status"; expect(true).toBe(true); } it("inert", () => inert());`).declarations[0];
    expect(inertMarkers.assertions[0].semanticText).not.toContain("tenantId");
  });
});
