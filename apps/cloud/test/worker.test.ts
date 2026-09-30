import { describe, expect, it } from "vitest";
import worker from "../src/index";
import type { Env } from "../src/types";
import { assertSameOrigin, HttpError, readBoundedBody } from "../src/http";

const production = {
  ENVIRONMENT: "production",
  PUBLIC_ORIGIN: "https://cloud.health.md",
  AUTH_SIGNUP_MODE: "closed",
  RESEND_API_KEY: "synthetic-unusable",
  AUTH_EMAIL_FROM: "Health.md Cloud <cloud@health.md>",
  CURRENT_EXPORT_KEY_ID: "v1",
} as Env;

const development = {
  ENVIRONMENT: "development",
  PUBLIC_ORIGIN: "http://localhost:8787",
  AUTH_SIGNUP_MODE: "closed",
} as Env;

describe("Worker deployment and request policy", () => {
  it("refuses production traffic without an explicit post-review gate", async () => {
    const response = await worker.fetch(new Request("https://cloud.health.md/health"), production);
    expect(response.status).toBe(500);
    expect(await response.json()).toEqual({
      error: "internal_error", message: "The request could not be completed.",
    });
  });

  it("fails closed for upload and token creation in a tailnet synthetic preview", async () => {
    const preview = { ...development, SYNTHETIC_PREVIEW_ONLY: "1" } as Env;
    const upload = await worker.fetch(new Request("http://localhost:8787/api/v1/exports", {
      method: "POST", headers: { "Content-Type": "application/json" }, body: "{}",
    }), preview);
    expect(upload.status).toBe(403);
    expect((await upload.json() as { error: string }).error).toBe("preview_no_ingest");
    const token = await worker.fetch(new Request("http://localhost:8787/api/ingest-tokens", {
      method: "POST", headers: { Origin: "http://localhost:8787", "Content-Type": "application/json" }, body: "{}",
    }), preview);
    expect(token.status).toBe(403);
    const runtime = await worker.fetch(new Request("http://localhost:8787/api/runtime"), preview);
    expect(runtime.status).toBe(200);
    expect(await runtime.json()).toEqual({ syntheticPreviewOnly: true, unbackedPersonalMvp: false,
      authMode: "email_link", exportEndpoint: "http://localhost:8787/api/v1/exports" });
  });

  it("accepts only the expected HTTPS tailnet proxy headers for a synthetic preview", async () => {
    const env = { ...development,
      PUBLIC_ORIGIN: "https://preview.tailnet.test:18787",
      SYNTHETIC_PREVIEW_ONLY: "1",
    } as Env;
    const target = "http://preview.tailnet.test:18787/health";
    const approved = await worker.fetch(new Request(target, { headers: {
      "X-Forwarded-Proto": "https", "X-Forwarded-Host": "preview.tailnet.test:18787",
    } }), env);
    expect(approved.status).toBe(200);
    const noProxy = await worker.fetch(new Request(target), env);
    expect(noProxy.status).toBe(421);
    const wrongHost = await worker.fetch(new Request(target, { headers: {
      "X-Forwarded-Proto": "https", "X-Forwarded-Host": "other.tailnet.test:18787",
    } }), env);
    expect(wrongHost.status).toBe(421);
  });

  it("requires dashboard intent on synthetic Tailscale's rewritten Origin", () => {
    const env = { ...development,
      PUBLIC_ORIGIN: "https://preview.tailnet.test:18787",
      SYNTHETIC_PREVIEW_ONLY: "1",
    } as Env;
    const url = "http://preview.tailnet.test:18787/api/auth/logout";
    const headers = {
      Origin: "http://preview.tailnet.test:18787",
      "X-Forwarded-Proto": "https",
      "X-Forwarded-Host": "preview.tailnet.test:18787",
    };
    expect(() => assertSameOrigin(new Request(url, { method: "POST", headers }), env))
      .toThrow(HttpError);
    expect(() => assertSameOrigin(new Request(url, { method: "POST", headers: {
      ...headers, "X-HealthMd-Intent": "dashboard",
    } }), env)).not.toThrow();
  });

  it("never accepts a different host just because it reaches this Worker", async () => {
    const response = await worker.fetch(new Request("http://other.test/health"), development);
    expect(response.status).toBe(421);
    expect(response.headers.get("cache-control")).toBe("no-store");
  });

  it("requires same-origin browser mutations in production", () => {
    expect(() => assertSameOrigin(new Request("https://cloud.health.md/api/auth/logout", {
      method: "POST", headers: { Origin: "https://attacker.test" },
    }), production)).toThrow(HttpError);
  });

  it("enforces request limits even without Content-Length", async () => {
    const request = new Request("http://localhost:8787/api/v1/exports", {
      method: "POST", body: "too-large-body",
    });
    await expect(readBoundedBody(request, 4)).rejects.toMatchObject({ status: 413 });
  });
});
