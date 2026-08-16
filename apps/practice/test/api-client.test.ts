import { describe, expect, it, vi } from "vitest";
import { SYNTHETIC_OPERATION_VERSION } from "../src/contracts/clinical";
import { createSyntheticOperationClient, PracticeClientError } from "../src/web/api-client";

describe("synthetic operation client", () => {
  it("keeps CSRF only in closure memory and clears it on logout", async () => {
    const bodies: Array<Record<string, unknown>> = [];
    const fetcher = vi.fn(async (_input: RequestInfo | URL, init?: RequestInit) => {
      bodies.push(JSON.parse(String(init?.body)) as Record<string, unknown>);
      const csrfToken = bodies.length === 1 ? "csrf_memory_only" : undefined;
      return new Response(JSON.stringify({ version: SYNTHETIC_OPERATION_VERSION, ok: true, data: {}, ...(csrfToken ? { csrfToken } : {}) }), { status: 200, headers: { "Content-Type": "application/json" } });
    }) as unknown as typeof fetch;
    const client = createSyntheticOperationClient(fetcher);
    await client.invoke("verify_mfa", { challengeId: "challenge", code: "246810" });
    await client.invoke("session");
    await client.invoke("logout");
    await client.invoke("sign_in", { login: "clinician" });
    expect(bodies[0]).not.toHaveProperty("csrfToken");
    expect(bodies[1]).toHaveProperty("csrfToken", "csrf_memory_only");
    expect(bodies[2]).toHaveProperty("csrfToken", "csrf_memory_only");
    expect(bodies[3]).not.toHaveProperty("csrfToken");
  });

  it("rejects malformed success envelopes with a stable client error", async () => {
    for (const body of [{ ok: true, data: {} }, { version: "wrong", ok: true, data: {} }, { version: SYNTHETIC_OPERATION_VERSION, ok: false, data: {} }, { version: SYNTHETIC_OPERATION_VERSION, ok: true }]) {
      const fetcher = vi.fn(async () => new Response(JSON.stringify(body), { status: 200 })) as unknown as typeof fetch;
      const caught = await createSyntheticOperationClient(fetcher).invoke("session").catch(error => error);
      expect(caught).toBeInstanceOf(PracticeClientError);
      expect((caught as PracticeClientError).code).toBe("invalid_response");
    }
  });

  it("preserves stable server error codes and validation issues without exposing server text", async () => {
    const fetcher = vi.fn(async () => new Response(JSON.stringify({ error: { code: "request_validation_failed", message: "ignored detail", issues: [{ code: "relative_acceptance_unresolved", field: "period" }] } }), { status: 422, headers: { "Content-Type": "application/json" } })) as unknown as typeof fetch;
    const caught = await createSyntheticOperationClient(fetcher).invoke("request_preview").catch(error => error);
    expect(caught).toBeInstanceOf(PracticeClientError);
    const failure = caught as PracticeClientError;
    expect(failure.code).toBe("request_validation_failed");
    expect(failure.status).toBe(422);
    expect(failure.issues).toEqual([{ code: "relative_acceptance_unresolved", field: "period" }]);
    expect(failure.message).toBe("The requested operation is unavailable");
  });
});
