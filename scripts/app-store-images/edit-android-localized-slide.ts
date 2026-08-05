#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import dotenv from "dotenv";
import OpenAI, { toFile } from "openai";
import sharp from "sharp";

const toolDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(toolDir, "../..");
const androidRoot = path.join(repoRoot, "apps/android");
const MODEL = "gpt-image-2";
const QUALITY = "medium" as const;
const OUTPUT_SIZE = "1088x1920";
const KEYCHAIN_SERVICE = "appstore-ai-images.openai-api-key";
const KEYCHAIN_ACCOUNT = "default";

type SlideNumber = 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8;
type Point = readonly [number, number];
type Slide = {
  id: string;
  file: string;
  text: readonly [number, number, number, number];
  screen: readonly [Point, Point, Point, Point];
};

const SLIDES: Record<SlideNumber, Slide> = {
  1: { id: "core-export", file: "1-core-export.png", text: [35, 255, 790, 420], screen: [[250, 585], [850, 565], [825, 1919], [230, 1919]] },
  2: { id: "export-formats", file: "2-export-formats.png", text: [120, 225, 840, 300], screen: [[250, 505], [825, 505], [825, 1770], [250, 1770]] },
  3: { id: "health-metrics", file: "3-health-metrics.png", text: [35, 225, 780, 390], screen: [[280, 555], [890, 520], [900, 1919], [230, 1919]] },
  4: { id: "private-by-design", file: "4-private-by-design.png", text: [35, 225, 760, 380], screen: [[365, 545], [910, 515], [900, 1870], [330, 1830]] },
  5: { id: "scheduled-exports", file: "5-scheduled-exports.png", text: [35, 225, 730, 390], screen: [[250, 575], [820, 575], [820, 1900], [250, 1900]] },
  6: { id: "file-preview", file: "6-file-preview.png", text: [35, 225, 760, 390], screen: [[255, 620], [835, 620], [835, 1919], [255, 1919]] },
  7: { id: "home-screen-widgets", file: "7-home-screen-widgets.png", text: [35, 225, 650, 380], screen: [[555, 430], [970, 470], [835, 1780], [420, 1710]] },
  8: { id: "direct-cli", file: "8-direct-cli.png", text: [35, 215, 760, 410], screen: [[355, 650], [880, 650], [880, 1919], [355, 1919]] },
};

const LANGUAGE_NAMES: Record<string, string> = {
  ar: "Arabic", "bn-BD": "Bengali", "de-DE": "German", "es-ES": "Spanish",
  "fr-FR": "French", "hi-IN": "Hindi", "ja-JP": "Japanese", kk: "Kazakh",
  "nl-NL": "Dutch", pa: "Punjabi", "pt-BR": "Brazilian Portuguese", ro: "Romanian",
  "ru-RU": "Russian", uk: "Ukrainian", "zh-CN": "Simplified Chinese",
};

function argument(name: string): string | undefined {
  const index = process.argv.indexOf(name);
  return index === -1 ? undefined : process.argv[index + 1];
}

const locale = argument("--locale");
if (!locale || !LANGUAGE_NAMES[locale]) throw new Error("--locale must be a supported draft Play locale.");
const slideNumber = Number(argument("--slide") ?? "1") as SlideNumber;
if (!(slideNumber in SLIDES)) throw new Error("--slide must be an integer from 1 through 8.");
const generate = process.argv.includes("--generate");
const rebuild = process.argv.includes("--rebuild");
const force = process.argv.includes("--force");
if (generate && rebuild) throw new Error("Use either --generate or --rebuild, not both.");
const slide = SLIDES[slideNumber];
const languageName = LANGUAGE_NAMES[locale];

const masterPath = path.join(androidRoot, "play-console/screenshots/en-US/phone", slide.file);
const capturePath = path.join(androidRoot, "build/play-screenshot-captures", locale, slide.file);
const copyPath = path.join(androidRoot, "play-store-screenshots/locales", `${locale}.json`);
const outputDir = path.join(repoRoot, "app-store-output/android-ai-edits", locale, slide.id);
const referencesDir = path.join(outputDir, "references");
const maskPath = path.join(referencesDir, "edit-mask.png");
const localMaskPath = path.join(referencesDir, "local-edit-mask.png");
const copyReferencePath = path.join(referencesDir, "localized-copy.png");
const rawPath = path.join(outputDir, "ai-edit-raw.png");
const finalPath = path.join(outputDir, slide.file);
const manifestPath = path.join(outputDir, "manifest.json");

for (const required of [masterPath, capturePath, copyPath]) {
  if (!fs.existsSync(required)) throw new Error(`Required input not found: ${path.relative(repoRoot, required)}`);
}
fs.mkdirSync(referencesDir, { recursive: true });

const copyConfig = JSON.parse(fs.readFileSync(copyPath, "utf8")) as {
  direction: "ltr" | "rtl";
  slides: Array<{ id: string; headline: string; supportingLine: string }>;
};
const foundCopy = copyConfig.slides.find((candidate) => candidate.id === slide.id);
if (!foundCopy) throw new Error(`Missing ${locale} copy for ${slide.id}.`);
const copy: { id: string; headline: string; supportingLine: string } = foundCopy;

function escapeXml(value: string): string {
  return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;");
}

function polygon(points: readonly Point[]): string {
  return points.map(([x, y]) => `${x},${y}`).join(" ");
}

function wrapReferenceText(value: string, maximumUnits: number): string[] {
  const cjk = locale === "ja-JP" || locale === "zh-CN";
  const tokens = cjk ? Array.from(value) : value.split(/\s+/u);
  const lines: string[] = [];
  let current = "";
  for (const token of tokens) {
    const candidate = cjk ? `${current}${token}` : current ? `${current} ${token}` : token;
    if (current && Array.from(candidate).length > maximumUnits) {
      lines.push(current);
      current = token;
    } else {
      current = candidate;
    }
  }
  if (current) lines.push(current);
  return lines;
}

async function createReferences(): Promise<void> {
  const [x, y, width, height] = slide.text;
  const quad = polygon(slide.screen);
  const apiMask = Buffer.from(`<svg width="1080" height="1920" xmlns="http://www.w3.org/2000/svg">
    <defs><mask id="m"><rect width="1080" height="1920" fill="white"/><rect x="${x}" y="${y}" width="${width}" height="${height}" rx="10" fill="black"/><polygon points="${quad}" fill="black"/></mask></defs>
    <rect width="1080" height="1920" fill="black" mask="url(#m)"/>
  </svg>`);
  const localMask = Buffer.from(`<svg width="1080" height="1920" xmlns="http://www.w3.org/2000/svg">
    <rect width="1080" height="1920" fill="transparent"/><rect x="${x}" y="${y}" width="${width}" height="${height}" rx="10" fill="white"/><polygon points="${quad}" fill="white"/>
  </svg>`);
  const rtl = copyConfig.direction === "rtl";
  const anchor = "start";
  const copyX = rtl ? 1010 : 70;
  const direction = rtl ? 'direction="rtl"' : "";
  const headlineLines = wrapReferenceText(copy.headline, 22);
  const supportLines = wrapReferenceText(copy.supportingLine, 45);
  const headlineSvg = headlineLines.map((line, index) => `<text x="${copyX}" y="${170 + index * 86}" text-anchor="${anchor}" ${direction} font-family="Arial Unicode MS, Noto Sans, sans-serif" font-size="72" font-weight="700" fill="#111">${escapeXml(line)}</text>`).join("\n");
  const supportStart = 230 + headlineLines.length * 86;
  const supportSvg = supportLines.map((line, index) => `<text x="${copyX}" y="${supportStart + index * 52}" text-anchor="${anchor}" ${direction} font-family="Arial Unicode MS, Noto Sans, sans-serif" font-size="36" fill="#555">${escapeXml(line)}</text>`).join("\n");
  const copyReference = Buffer.from(`<svg width="1080" height="700" xmlns="http://www.w3.org/2000/svg">
    <rect width="1080" height="700" fill="white"/>
    ${headlineSvg}
    ${supportSvg}
  </svg>`);
  await Promise.all([
    sharp(apiMask).png().toFile(maskPath),
    sharp(localMask).png().toFile(localMaskPath),
    sharp(copyReference).png().toFile(copyReferencePath),
  ]);
}

function loadApiKey(): { key: string; source: "env" | "keychain" } {
  try {
    const key = execFileSync("security", ["find-generic-password", "-a", KEYCHAIN_ACCOUNT, "-s", KEYCHAIN_SERVICE, "-w"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
    if (key) return { key, source: "keychain" };
  } catch {}
  if (process.env.OPENAI_API_KEY?.trim()) return { key: process.env.OPENAI_API_KEY.trim(), source: "env" };
  throw new Error("OPENAI_API_KEY is missing and no appstore-ai-images key was found in macOS Keychain.");
}

async function extractImage(result: unknown): Promise<Buffer> {
  const data = (result as { data?: Array<{ b64_json?: string; url?: string }> }).data ?? [];
  const image = data[0];
  if (image?.b64_json) return Buffer.from(image.b64_json, "base64");
  if (image?.url) {
    const response = await fetch(image.url);
    if (!response.ok) throw new Error(`Generated image download failed: ${response.status}`);
    return Buffer.from(await response.arrayBuffer());
  }
  throw new Error("OpenAI returned no image data.");
}

async function buildFinal(): Promise<void> {
  // Keep the model's seamless regenerated result intact. The API edit mask constrains the
  // requested changes; no screenshot or typography layer is composited over this output.
  await sharp(rawPath).resize(1080, 1920, { fit: "fill" }).png().toFile(finalPath);
}

const prompt = `INPUT ORDER IS IMPORTANT.

Image 1 is the exact English Google Play marketing master and is the sole design source. Image 2 is the exact genuine ${languageName} Android app screenshot. Image 3 contains the exact ${languageName} marketing copy.

Edit Image 1 only in the transparent mask regions. Preserve every unmasked pixel exactly, including the white and lavender background, crystal heart, document illustrations, connecting lines, Android device frame, bezel, lighting, shadows, perspective, size, position, and overall style.

Replace the English marketing copy with this exact copy, preserving every character and diacritic verbatim:
Headline: “${copy.headline}”
Supporting line: “${copy.supportingLine}”
Match the original typography, black/gray colors, hierarchy, alignment, spacing, and placement. Use natural line breaks that fit the original copy area. ${copyConfig.direction === "rtl" ? "Typeset the copy right-to-left and right-align it." : "Preserve the original alignment."} Do not paraphrase, translate differently, truncate words, or invent text.

Inside the existing Android phone display, recreate Image 2 faithfully in the perspective and geometry of Image 1. Preserve the real ${languageName} UI wording, icons, controls, status bar, spacing, colors, and right-to-left layout where applicable. Do not retain any English UI from Image 1. Do not redesign, summarize, hallucinate, or stylize the app UI. Keep the original hardware frame and bezel unchanged.

The result must look like Image 1 genuinely regenerated for ${languageName}, changing only the marketing-copy area and pixels inside the phone display.`;

async function main(): Promise<void> {
  dotenv.config({ path: path.join(repoRoot, ".env"), override: false });
  dotenv.config({ path: path.join(toolDir, ".env"), override: false });
  await createReferences();

  const manifest = {
    timestamp: new Date().toISOString(), mode: generate ? "generate" : rebuild ? "rebuild" : "dry-run",
    provider: "openai-direct-images-edit", model: MODEL, quality: QUALITY, outputSize: OUTPUT_SIZE,
    locale, languageName, slide: slideNumber, slideId: slide.id,
    headline: copy.headline, supportingLine: copy.supportingLine,
    paid: false, plannedImageEdits: 1,
    uploadedInputsWhenGenerated: [path.relative(repoRoot, masterPath), path.relative(repoRoot, capturePath), path.relative(repoRoot, copyReferencePath)],
    mask: path.relative(repoRoot, maskPath), prompt,
  };

  if (!generate && !rebuild) {
    fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
    console.log(`Planned Android reference swap: ${locale} slide ${slideNumber}`);
    return;
  }
  if (rebuild) {
    if (!fs.existsSync(rawPath)) throw new Error(`Cannot rebuild without ${path.relative(repoRoot, rawPath)}.`);
    await buildFinal();
    const prior = fs.existsSync(manifestPath) ? JSON.parse(fs.readFileSync(manifestPath, "utf8")) : {};
    fs.writeFileSync(manifestPath, `${JSON.stringify({ ...manifest, paid: prior.paid === true, reusedPaidRawEdit: true, raw: path.relative(repoRoot, rawPath), final: path.relative(repoRoot, finalPath) }, null, 2)}\n`);
    console.log(`Rebuilt: ${path.relative(repoRoot, finalPath)}`);
    return;
  }
  if (!force && (fs.existsSync(rawPath) || fs.existsSync(finalPath))) throw new Error(`Refusing to overwrite ${path.relative(repoRoot, outputDir)} without --force.`);

  const credential = loadApiKey();
  const client = new OpenAI({ apiKey: credential.key });
  const [master, capture, copyReference, mask] = await Promise.all([
    toFile(fs.readFileSync(masterPath), path.basename(masterPath), { type: "image/png" }),
    toFile(fs.readFileSync(capturePath), path.basename(capturePath), { type: "image/png" }),
    toFile(fs.readFileSync(copyReferencePath), path.basename(copyReferencePath), { type: "image/png" }),
    toFile(fs.readFileSync(maskPath), path.basename(maskPath), { type: "image/png" }),
  ]);
  console.log(`Submitting ${locale} slide ${slideNumber} to ${MODEL}...`);
  const result = await client.images.edit({
    model: MODEL, image: [master, capture, copyReference], mask, prompt,
    quality: QUALITY, size: OUTPUT_SIZE, output_format: "png", background: "opaque", n: 1,
  });
  fs.writeFileSync(rawPath, await extractImage(result));
  await buildFinal();
  fs.writeFileSync(manifestPath, `${JSON.stringify({ ...manifest, timestamp: new Date().toISOString(), paid: true, credentialSource: credential.source, raw: path.relative(repoRoot, rawPath), final: path.relative(repoRoot, finalPath) }, null, 2)}\n`);
  console.log(`Generated: ${path.relative(repoRoot, finalPath)}`);
}

main().catch((error) => { console.error(error instanceof Error ? `Error: ${error.message}` : error); process.exit(1); });
