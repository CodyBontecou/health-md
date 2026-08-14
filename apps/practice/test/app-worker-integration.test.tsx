// @vitest-environment jsdom
import { cleanup, render, screen } from "@testing-library/react";
import "@testing-library/jest-dom/vitest";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { syntheticClinicalService } from "../src/http/clinical-api";
import { App } from "../src/web/App";
import { createSyntheticOperationClient } from "../src/web/api-client";
import worker, { type PracticeWorkerEnv } from "../src/worker";

const origin = "https://practice.synthetic.invalid";

function workerFetcher(): typeof fetch {
  let cookie = "";
  const env: PracticeWorkerEnv = {
    PRACTICE_RUNTIME_MODE: "synthetic",
    ASSETS: { fetch: async () => new Response("unused") } as unknown as Fetcher,
  };
  return (async (input: RequestInfo | URL, init?: RequestInit) => {
    const path = typeof input === "string" ? input : input.toString();
    const headers = new Headers(init?.headers); headers.set("Origin", origin); if (cookie) headers.set("Cookie", cookie);
    const response = await worker.fetch(new Request(new URL(path, origin), { ...init, headers }), env);
    const setCookie = response.headers.get("Set-Cookie"); if (setCookie) cookie = setCookie.split(";", 1)[0] ?? "";
    return response;
  }) as typeof fetch;
}

beforeEach(() => { syntheticClinicalService.reset(); history.replaceState(null, "", "/sign-in"); });
afterEach(cleanup);

describe("App through operation client and Worker handler", () => {
  it("signs in, verifies MFA, bootstraps server truth, and performs a protected operation without persistence", async () => {
    const storage = vi.spyOn(Storage.prototype, "setItem"); const user = userEvent.setup();
    render(<App initialPath="/sign-in" client={createSyntheticOperationClient(workerFetcher())} />);
    await user.click(screen.getByRole("button", { name: "Continue to MFA" }));
    await user.click(await screen.findByRole("button", { name: "Verify synthetic account" }));
    expect(await screen.findByRole("heading", { name: "Practice portal overview" })).toBeVisible();
    expect(screen.getByText("Synthetic workspace · clinician")).toBeVisible();
    expect(screen.getByText("Fictional Practice A")).toBeVisible(); expect(screen.queryByText("Fictional Practice B")).toBeNull();
    await user.click(screen.getByRole("link", { name: "Relationships" }));
    await user.click(screen.getByRole("button", { name: "Search relationships" }));
    expect(await screen.findByText("Avery Fiction — synthetic")).toBeVisible();
    expect(storage).not.toHaveBeenCalled();
    expect(location.search).toBe(""); expect(location.hash).toBe("");
  });

  it("renders only the authenticated tenant-B practice identity from server bootstrap truth", async () => {
    const user = userEvent.setup();
    render(<App initialPath="/sign-in" client={createSyntheticOperationClient(workerFetcher())} />);
    await user.selectOptions(screen.getByLabelText("Fictional login"), "other");
    await user.click(screen.getByRole("button", { name: "Continue to MFA" }));
    await user.click(await screen.findByRole("button", { name: "Verify synthetic account" }));
    expect(await screen.findByRole("heading", { name: "Practice portal overview" })).toBeVisible();
    expect(screen.getByText("Fictional Practice B")).toBeVisible();
    expect(screen.queryByText("Fictional Practice A")).toBeNull();
  });
});
