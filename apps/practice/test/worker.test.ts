import { describe, expect, it } from "vitest";
import worker, { type PracticeWorkerEnv } from "../src/worker";

function assetFetcher(): Fetcher {
  return {
    fetch: async (input: RequestInfo | URL): Promise<Response> => {
      const url = new URL(input instanceof Request ? input.url : input.toString());
      const contentType = url.pathname.endsWith(".js")
        ? "text/javascript"
        : url.pathname.endsWith(".css")
          ? "text/css"
          : "text/html";
      return new Response(`asset:${url.pathname}`, {
        headers: { "Content-Type": contentType, "Access-Control-Allow-Origin": "*" },
      });
    },
    connect: () => {
      throw new Error("not implemented in synthetic tests");
    },
  } as unknown as Fetcher;
}

function env(mode: string | undefined): PracticeWorkerEnv {
  return { PRACTICE_RUNTIME_MODE: mode, ASSETS: assetFetcher() };
}

async function fetchPath(
  path: string,
  init?: RequestInit,
  runtime = env("synthetic"),
): Promise<Response> {
  return worker.fetch(new Request(`https://practice.invalid${path}`, init), runtime);
}

describe("Practice Worker boundary", () => {
  it("returns deterministic synthetic metadata with security headers", async () => {
    const response = await fetchPath("/api/v1/meta");
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      mode: "synthetic",
      productionEnabled: false,
      protocolVersion: "1.0-draft.4",
    });
    expect(response.headers.get("Cache-Control")).toBe("no-store");
    expect(response.headers.get("Access-Control-Allow-Origin")).toBeNull();
  });

  it("fails closed for missing, unknown, and production runtime modes", async () => {
    for (const mode of [undefined, "", "production", "synthetic "]) {
      const response = await fetchPath("/api/v1/meta", undefined, env(mode));
      expect(response.status).toBe(503);
      await expect(response.json()).resolves.toEqual({
        error: {
          code: "configuration_unavailable",
          message: "Practice runtime is unavailable",
        },
      });
    }
  });

  it("rejects queries, mutations, and unknown API routes without disclosing data", async () => {
    expect((await fetchPath("/api/v1/catalog?packet=packet_synthetic_apple")).status).toBe(404);
    expect((await fetchPath("/api/v1/catalog", { method: "POST" })).status).toBe(405);
    const missing = await fetchPath("/api/v1/patient/fictional");
    expect(missing.status).toBe(404);
    expect(await missing.text()).not.toContain("Fictional");
  });

  it("rejects open-redirect return URL and navigation payloads without a Location header", async () => {
    for (const path of ["/sign-in?returnUrl=https%3A%2F%2Fevil.invalid", "/portal?navigation=%2F%2Fevil.invalid", "/%2F%2Fevil.invalid"]) {
      const response = await fetchPath(path);
      expect(response.status).toBe(404); expect(response.headers.get("Location")).toBeNull();
    }
  });

  it("serves only allowlisted fixed portal routes and same-origin assets through headers", async () => {
    const portal = await fetchPath("/portal/inbox");
    expect(portal.status).toBe(200);
    expect(await portal.text()).toBe("asset:/");
    expect(portal.headers.get("Cache-Control")).toBe("no-store");

    const asset = await fetchPath("/assets/app.js");
    expect(asset.status).toBe(200);
    expect(asset.headers.get("Access-Control-Allow-Origin")).toBeNull();

    const dynamic = await fetchPath("/portal/report/packet_synthetic_apple");
    expect(dynamic.status).toBe(404);
    expect(await dynamic.text()).toBe("Not found");
  });
});
