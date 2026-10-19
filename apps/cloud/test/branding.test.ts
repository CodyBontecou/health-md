import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { parseHTML } from "linkedom";
import { VmAssets } from "../vm/storage";

const publicDirectory = resolve(import.meta.dirname, "../public");
const asset = (name: string) => readFileSync(resolve(publicDirectory, name));
const icons = [
  ["app-icon.png", "image/png"],
  ["favicon.png", "image/png"],
  ["favicon.ico", "image/x-icon"],
] as const;

describe("first-party app branding", () => {
  it.each(["dashboard", "explore", "repair", "login", "deletion-status"])(
    "uses the app artwork for the brand and browser icons on %s", (page) => {
      const { document } = parseHTML(readFileSync(resolve(publicDirectory, `${page}.html`), "utf8"));
      const brand = document.querySelector(".brand")!;
      const mark = brand.querySelector(".brand-mark")!;
      expect(mark.tagName).toBe("IMG");
      expect(mark.getAttribute("src")).toBe("/app-icon.png");
      expect(mark.getAttribute("alt")).toBe(""); // The link already has an accessible name.
      expect(mark.getAttribute("width")).toBe("27");
      expect(mark.getAttribute("height")).toBe("27");
      expect(brand.getAttribute("aria-label")).toBe("Health.md Cloud overview");
      expect(brand.textContent).not.toContain("✳");
      expect(document.querySelector('link[rel="icon"][href="/favicon.ico"]')).not.toBeNull();
      expect(document.querySelector('link[rel="icon"][type="image/png"][sizes="32x32"]')
        ?.getAttribute("href")).toBe("/favicon.png");
      expect(document.querySelector('link[rel="apple-touch-icon"][sizes="180x180"]')
        ?.getAttribute("href")).toBe("/app-icon.png");
    },
  );

  it.each([["app-icon.png", 180], ["favicon.png", 32]] as const)(
    "ships %s at its declared square resolution", (name, size) => {
      const bytes = asset(name);
      expect(bytes.subarray(0, 8)).toEqual(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
      const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
      expect(view.getUint32(16)).toBe(size);
      expect(view.getUint32(20)).toBe(size);
    },
  );

  it("ships a multi-resolution ICO fallback including 16px and 32px", () => {
    const bytes = asset("favicon.ico");
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    expect(view.getUint16(0, true)).toBe(0);
    expect(view.getUint16(2, true)).toBe(1);
    const count = view.getUint16(4, true);
    const sizes = Array.from({ length: count }, (_, index) => bytes[6 + index * 16] || 256);
    expect(sizes).toEqual(expect.arrayContaining([16, 32]));
  });

  it.each(icons)("serves exact %s bytes with the correct VM MIME type", async (name, type) => {
    const response = await new VmAssets(publicDirectory).fetch(new Request(`https://account.example.test/${name}`));
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toBe(type);
    expect(Buffer.from(await response.arrayBuffer())).toEqual(asset(name));
  });
});
