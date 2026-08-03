#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import dotenv from "dotenv";
import OpenAI, { toFile } from "openai";
import sharp from "sharp";

const __filename = fileURLToPath(import.meta.url);
const toolDir = path.dirname(__filename);
const repoRoot = path.resolve(toolDir, "../..");

const OPENAI_KEYCHAIN_SERVICE = "appstore-ai-images.openai-api-key";
const OPENAI_KEYCHAIN_ACCOUNT = "default";
const MODEL = "gpt-image-2";
const QUALITY = "medium" as const;
const API_OUTPUT_SIZE = "1280x2768";

type SlideNumber = 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9;

type SlideConfig = {
  captureFile: string;
  headline: string;
  subheadline: string;
  headlineLines: string[];
  subheadlineLines: string[];
  headlineFontSize: number;
  subheadlineFontSize: number;
  mask: {
    textX: number;
    textY: number;
    textWidth: number;
    textHeight: number;
    textCleanup?: { x: number; y: number; width: number; height: number };
    phoneX: number;
    phoneY: number;
    phoneWidth: number;
    phoneHeight?: number;
    phoneRadius: number;
  };
  phoneComposite?: {
    x: number;
    y: number;
    width: number;
    height: number;
    radius: number;
  };
};

type MarketingCopySlide = {
  headline: string;
  subheadline: string;
  headlineLines: string[];
  subheadlineLines: string[];
  headlineFontSize?: number;
  subheadlineFontSize?: number;
};

type MarketingCopyConfig = {
  locale: string;
  languageName: string;
  slides: Record<string, MarketingCopySlide>;
};

const SLIDES: Record<SlideNumber, SlideConfig> = {
  1: {
    captureFile: "01-export-top.png",
    headline: "Controla tus datos de salud",
    subheadline: "Convierte tu historial de Apple Health en archivos privados bajo tu control.",
    headlineLines: ["Controla tus", "datos de salud"],
    subheadlineLines: ["Convierte tu historial de Apple Health", "en archivos privados bajo tu control."],
    headlineFontSize: 92,
    subheadlineFontSize: 48,
    mask: { textX: 0.072, textY: 0.111, textWidth: 0.56, textHeight: 0.137, phoneX: 0.151, phoneY: 0.267, phoneWidth: 0.698, phoneRadius: 0.061 },
    phoneComposite: { x: 0.151, y: 0.267, width: 0.698, height: 0.736, radius: 0.061 },
  },
  2: {
    captureFile: "02-export-formats.png",
    headline: "Conserva el registro completo",
    subheadline: "Guarda los registros originales en JSON y CSV, con Markdown y Bases fáciles de leer.",
    headlineLines: ["Conserva el registro", "completo"],
    subheadlineLines: ["Guarda los registros originales en", "JSON y CSV, con Markdown y", "Bases fáciles de leer."],
    headlineFontSize: 82,
    subheadlineFontSize: 43,
    mask: { textX: 0.058, textY: 0.133, textWidth: 0.625, textHeight: 0.175, phoneX: 0.122, phoneY: 0.381, phoneWidth: 0.709, phoneRadius: 0.055 },
    phoneComposite: { x: 0.122, y: 0.381, width: 0.709, height: 0.622, radius: 0.055 },
  },
  3: {
    captureFile: "03-daily-note-injection.png",
    headline: "Lleva tu salud a tus notas",
    subheadline: "Actualiza tus notas diarias de Obsidian con las métricas de salud que elijas.",
    headlineLines: ["Lleva tu salud", "a tus notas"],
    subheadlineLines: ["Actualiza tus notas diarias", "de Obsidian con las métricas", "de salud que elijas."],
    headlineFontSize: 88,
    subheadlineFontSize: 46,
    mask: { textX: 0.066, textY: 0.105, textWidth: 0.555, textHeight: 0.166, phoneX: 0.162, phoneY: 0.294, phoneWidth: 0.664, phoneRadius: 0.052 },
    phoneComposite: { x: 0.162, y: 0.294, width: 0.664, height: 0.709, radius: 0.052 },
  },
  4: {
    captureFile: "04-health-metrics.png",
    headline: "Elige lo que importa",
    subheadline: "Selecciona entre más de 225 datos de salud en 21 categorías.",
    headlineLines: ["Elige lo que", "importa"],
    subheadlineLines: ["Selecciona entre más de 225 datos", "de salud en 21 categorías."],
    headlineFontSize: 92,
    subheadlineFontSize: 44,
    mask: { textX: 0.072, textY: 0.119, textWidth: 0.58, textHeight: 0.158, phoneX: 0.182, phoneY: 0.312, phoneWidth: 0.636, phoneHeight: 0.67, phoneRadius: 0.074 },
    phoneComposite: { x: 0.182, y: 0.312, width: 0.636, height: 0.67, radius: 0.074 },
  },
  5: {
    captureFile: "05-format-customization.png",
    headline: "Formato a tu manera",
    subheadline: "Controla fechas, horas, unidades, frontmatter y la presentación en Markdown.",
    headlineLines: ["Formato a tu", "manera"],
    subheadlineLines: ["Controla fechas, horas,", "unidades, frontmatter", "y la presentación en Markdown."],
    headlineFontSize: 92,
    subheadlineFontSize: 43,
    mask: { textX: 0.07, textY: 0.092, textWidth: 0.51, textHeight: 0.174, phoneX: 0.181, phoneY: 0.283, phoneWidth: 0.636, phoneHeight: 0.695, phoneRadius: 0.074 },
    phoneComposite: { x: 0.181, y: 0.283, width: 0.636, height: 0.695, radius: 0.074 },
  },
  6: {
    captureFile: "06-export-preview.png",
    headline: "Previsualiza antes de exportar",
    subheadline: "Revisa primero los archivos, formatos, el destino y el tamaño estimado.",
    headlineLines: ["Previsualiza antes", "de exportar"],
    subheadlineLines: ["Revisa primero los archivos, formatos,", "el destino y el tamaño estimado."],
    headlineFontSize: 82,
    subheadlineFontSize: 43,
    mask: { textX: 0.078, textY: 0.116, textWidth: 0.61, textHeight: 0.145, phoneX: 0.152, phoneY: 0.29, phoneWidth: 0.7, phoneHeight: 0.703, phoneRadius: 0.078 },
    phoneComposite: { x: 0.152, y: 0.29, width: 0.7, height: 0.703, radius: 0.078 },
  },
  7: {
    captureFile: "07-individual-tracking.png",
    headline: "Conserva cada momento importante",
    subheadline: "Crea entradas con fecha y hora para entrenamientos, estados de ánimo, síntomas y signos vitales.",
    headlineLines: ["Conserva cada", "momento importante"],
    subheadlineLines: ["Crea entradas con fecha y hora para", "entrenamientos, estados de ánimo,", "síntomas y signos vitales."],
    headlineFontSize: 82,
    subheadlineFontSize: 42,
    mask: { textX: 0.07, textY: 0.095, textWidth: 0.72, textHeight: 0.155, phoneX: 0.217, phoneY: 0.269, phoneWidth: 0.661, phoneHeight: 0.69, phoneRadius: 0.074 },
    phoneComposite: { x: 0.217, y: 0.269, width: 0.661, height: 0.69, radius: 0.074 },
  },
  8: {
    captureFile: "08-scheduled-exports.png",
    headline: "Mantén tu archivo al día",
    subheadline: "Programa exportaciones y actualiza automáticamente tus datos recientes.",
    headlineLines: ["Mantén tu archivo", "al día"],
    subheadlineLines: ["Programa exportaciones y actualiza", "automáticamente tus datos recientes."],
    headlineFontSize: 82,
    subheadlineFontSize: 43,
    mask: {
      textX: 0.055, textY: 0.098, textWidth: 0.685, textHeight: 0.172,
      textCleanup: { x: 0.725, y: 0.15, width: 0.095, height: 0.06 },
      phoneX: 0.167, phoneY: 0.29, phoneWidth: 0.653, phoneHeight: 0.703, phoneRadius: 0.074,
    },
    phoneComposite: { x: 0.167, y: 0.29, width: 0.653, height: 0.703, radius: 0.074 },
  },
  9: {
    captureFile: "09-mac-destination.png",
    headline: "Exporta directamente a tu Mac",
    subheadline: "Envía archivos preparados en el iPhone mediante una conexión directa y cifrada.",
    headlineLines: ["Exporta directamente", "a tu Mac"],
    subheadlineLines: ["Envía archivos preparados en el", "iPhone mediante una conexión", "directa y cifrada."],
    headlineFontSize: 82,
    subheadlineFontSize: 39,
    mask: {
      textX: 0.055, textY: 0.105, textWidth: 0.66, textHeight: 0.05,
      textCleanup: { x: 0.055, y: 0.145, width: 0.465, height: 0.12 },
      phoneX: 0.159, phoneY: 0.281, phoneWidth: 0.68, phoneHeight: 0.7, phoneRadius: 0.078,
    },
    phoneComposite: { x: 0.159, y: 0.281, width: 0.68, height: 0.7, radius: 0.078 },
  },
};

function parseSlideNumber(): SlideNumber {
  const index = process.argv.indexOf("--slide");
  if (index === -1) return 1;
  const value = Number(process.argv[index + 1]);
  if (![1, 2, 3, 4, 5, 6, 7, 8, 9].includes(value)) {
    throw new Error("--slide must be an integer from 1 through 9.");
  }
  return value as SlideNumber;
}

function parseLocale(): string {
  const index = process.argv.indexOf("--locale");
  const value = index === -1 ? "es-ES" : process.argv[index + 1];
  if (!value || !/^[A-Za-z]{2,3}(?:-[A-Za-z]{2,4})?$/.test(value)) {
    throw new Error("--locale must be a locale code such as es-ES, ja, or zh-Hans.");
  }
  return value;
}

function estimatedGlyphUnits(value: string): number {
  return Array.from(value).reduce((total, character) => {
    if (/\p{Script=Han}|\p{Script=Hiragana}|\p{Script=Katakana}|\p{Script=Hangul}/u.test(character)) return total + 1;
    if (/\s/u.test(character)) return total + 0.32;
    if (/\p{Lu}/u.test(character)) return total + 0.64;
    return total + 0.54;
  }, 0);
}

function fittedFontSize(baseSize: number, lines: string[], availableWidth: number, minimum: number): number {
  const longest = Math.max(...lines.map(estimatedGlyphUnits), 1);
  return Math.min(baseSize, Math.max(minimum, Math.floor(availableWidth / longest)));
}

function loadMarketingCopy(locale: string): MarketingCopyConfig {
  const copyPath = path.join(repoRoot, "app-store-input/localizations", `marketing-${locale}.json`);
  if (fs.existsSync(copyPath)) {
    const parsed = JSON.parse(fs.readFileSync(copyPath, "utf8")) as MarketingCopyConfig;
    if (parsed.locale !== locale || !parsed.languageName || !parsed.slides) {
      throw new Error(`Invalid marketing copy config: ${relativePath(copyPath)}`);
    }
    return parsed;
  }
  if (locale === "es-ES") {
    return {
      locale,
      languageName: "Spanish",
      slides: Object.fromEntries(
        Object.entries(SLIDES).map(([number, value]) => [number, {
          headline: value.headline,
          subheadline: value.subheadline,
          headlineLines: value.headlineLines,
          subheadlineLines: value.subheadlineLines,
          headlineFontSize: value.headlineFontSize,
          subheadlineFontSize: value.subheadlineFontSize,
        }]),
      ),
    };
  }
  throw new Error(`Marketing copy config not found: ${relativePath(copyPath)}`);
}

const slideNumber = parseSlideNumber();
const locale = parseLocale();
const marketingCopy = loadMarketingCopy(locale);
const baseSlide = SLIDES[slideNumber];
const localizedCopy = marketingCopy.slides[String(slideNumber)];
if (!localizedCopy?.headline || !localizedCopy?.subheadline || localizedCopy.headlineLines.length === 0 || localizedCopy.subheadlineLines.length === 0) {
  throw new Error(`Marketing copy for slide ${slideNumber} is missing in locale ${locale}.`);
}
const headlineWidth = baseSlide.mask.textWidth * 1284 - 80;
const subheadlineMaskWidth = slideNumber === 9 && baseSlide.mask.textCleanup
  ? baseSlide.mask.textCleanup.width
  : baseSlide.mask.textWidth;
const subheadlineWidth = subheadlineMaskWidth * 1284 - 45;
const slide: SlideConfig = {
  ...baseSlide,
  ...localizedCopy,
  headlineFontSize: localizedCopy.headlineFontSize
    ?? fittedFontSize(baseSlide.headlineFontSize, localizedCopy.headlineLines, headlineWidth, 52),
  subheadlineFontSize: localizedCopy.subheadlineFontSize
    ?? fittedFontSize(baseSlide.subheadlineFontSize, localizedCopy.subheadlineLines, subheadlineWidth, 29),
};
const baseImagePath = path.join(repoRoot, `apps/apple/fastlane/screenshots/en-US/appstore-ios-slide-${slideNumber}.png`);
const localizedScreenshotPath = path.join(
  repoRoot,
  "app-store-output/simulator-captures",
  locale,
  slide.captureFile,
);
const outputDir = path.join(repoRoot, `app-store-output/ai-edits/${locale}-slide-${slideNumber}-reference-swap`);
const referenceDir = path.join(outputDir, "references");
const rawOutputPath = path.join(outputDir, `slide-${slideNumber}-ai-edit-raw.png`);
const finalOutputPath = path.join(outputDir, `slide-${slideNumber}-ai-edit-final.png`);
const apiMaskPath = path.join(referenceDir, `slide-${slideNumber}-api-mask.png`);
const localEditMaskPath = path.join(referenceDir, `slide-${slideNumber}-local-edit-mask.png`);
const textReferencePath = path.join(referenceDir, `slide-${slideNumber}-${locale}-copy-reference.png`);
const manifestPath = path.join(outputDir, "manifest.json");

const headline = slide.headline;
const subheadline = slide.subheadline;
const referenceFontFamily = locale === "ja"
  ? "'Hiragino Sans', sans-serif"
  : locale === "ko"
    ? "'Apple SD Gothic Neo', sans-serif"
    : locale === "zh-Hans"
      ? "'Hiragino Sans GB', sans-serif"
      : "-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif";
const headlineLetterSpacing = ["ja", "ko", "zh-Hans"].includes(locale) ? -1 : -3;
const generate = process.argv.includes("--generate");
const rebuild = process.argv.includes("--rebuild");
const force = process.argv.includes("--force");
if (generate && rebuild) throw new Error("Use either --generate or --rebuild, not both.");
const artworkConstraint = slideNumber === 8
  ? " Keep every headline letter left of the clock illustration. Remove every remaining English headline letter. Preserve the original clock, hands, dotted path, arrow, and document icon exactly; the small cleanup mask exists only to erase the final English letters, not to redesign artwork."
  : slideNumber === 9
    ? " Preserve the original illustrated iPhone, heart, cable lines, lock, laptop, and folder exactly; the L-shaped copy mask deliberately avoids that artwork."
    : "";

const prompt = `INPUT ORDER IS IMPORTANT.

Image 1 is the exact English App Store master artwork and must remain the design source. Image 2 is the exact ${marketingCopy.languageName} app screenshot that must appear inside the existing iPhone display. Image 3 is a visual reference containing the exact ${marketingCopy.languageName} marketing copy.

Edit Image 1 only inside the transparent mask regions. Preserve every unmasked pixel and preserve the original composition, white and lavender background art, crystal heart, document illustration, connecting lines, device size, device position, metallic frame, bezel, lighting, shadows, spacing, and overall style.

Replace the English marketing copy with this exact ${marketingCopy.languageName} copy, preserving every character and diacritic verbatim:
Headline: “${headline}”
Subheadline: “${subheadline}”
Use these exact visual line breaks for the headline:
${slide.headlineLines.join("\n")}
Use these exact visual line breaks for the subheadline:
${slide.subheadlineLines.join("\n")}
Match the original English typography, black/gray colors, hierarchy, alignment, line spacing, and placement. Do not paraphrase, translate differently, add labels, truncate words, or invent any other text.${artworkConstraint}

Inside the existing iPhone screen, use Image 2 as the exact visual source. Copy its real ${marketingCopy.languageName} UI faithfully, including wording, icons, controls, spacing, status bar, and colors. Fit the full width of Image 2 inside the display opening; do not crop the left or right edges and do not clip the first or last characters of any label. Crop only the bottom as needed. Do not redesign, summarize, translate, hallucinate, or stylize the app UI. Keep the existing hardware frame and bezel from Image 1.

The result must look like Image 1 localized to ${marketingCopy.languageName}, not like a newly designed advertisement. Change only the marketing copy and the pixels inside the phone display.`;

function relativePath(filePath: string): string {
  return path.relative(repoRoot, filePath) || ".";
}

function escapeXml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;");
}

function ensureInputs(): void {
  for (const inputPath of [baseImagePath, localizedScreenshotPath]) {
    if (!fs.existsSync(inputPath)) throw new Error(`Required input not found: ${relativePath(inputPath)}`);
  }
  fs.mkdirSync(referenceDir, { recursive: true });
}

async function createReferenceFiles(width: number, height: number): Promise<void> {
  const textX = Math.round(width * slide.mask.textX);
  const textY = Math.round(height * slide.mask.textY);
  const textWidth = Math.round(width * slide.mask.textWidth);
  const textHeight = Math.round(height * slide.mask.textHeight);
  const cleanup = slide.mask.textCleanup
    ? {
        x: Math.round(width * slide.mask.textCleanup.x),
        y: Math.round(height * slide.mask.textCleanup.y),
        width: Math.round(width * slide.mask.textCleanup.width),
        height: Math.round(height * slide.mask.textCleanup.height),
      }
    : undefined;
  const phoneX = Math.round(width * slide.mask.phoneX);
  const phoneY = Math.round(height * slide.mask.phoneY);
  const phoneWidth = Math.round(width * slide.mask.phoneWidth);
  const phoneHeight = slide.mask.phoneHeight
    ? Math.round(height * slide.mask.phoneHeight)
    : height - phoneY + 8;
  const phoneRadius = Math.round(width * slide.mask.phoneRadius);

  const apiMaskSvg = Buffer.from(`
    <svg width="${width}" height="${height}" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <mask id="preserveMask">
          <rect width="${width}" height="${height}" fill="#fff"/>
          <rect x="${textX}" y="${textY}" width="${textWidth}" height="${textHeight}" rx="8" fill="#000"/>
          ${cleanup ? `<rect x="${cleanup.x}" y="${cleanup.y}" width="${cleanup.width}" height="${cleanup.height}" rx="8" fill="#000"/>` : ""}
          <rect x="${phoneX}" y="${phoneY}" width="${phoneWidth}" height="${phoneHeight}" rx="${phoneRadius}" fill="#000"/>
        </mask>
      </defs>
      <rect width="${width}" height="${height}" fill="#000" mask="url(#preserveMask)"/>
    </svg>
  `);

  const localMaskSvg = Buffer.from(`
    <svg width="${width}" height="${height}" xmlns="http://www.w3.org/2000/svg">
      <rect width="${width}" height="${height}" fill="transparent"/>
      <rect x="${textX}" y="${textY}" width="${textWidth}" height="${textHeight}" rx="8" fill="#fff"/>
      ${cleanup ? `<rect x="${cleanup.x}" y="${cleanup.y}" width="${cleanup.width}" height="${cleanup.height}" rx="8" fill="#fff"/>` : ""}
      <rect x="${phoneX}" y="${phoneY}" width="${phoneWidth}" height="${phoneHeight}" rx="${phoneRadius}" fill="#fff"/>
    </svg>
  `);

  const headlineStartY = 205;
  const headlineLineHeight = Math.round(slide.headlineFontSize * 1.12);
  const subheadlineStartY = 475;
  const subheadlineLineHeight = Math.round(slide.subheadlineFontSize * 1.32);
  const textReferenceSvg = Buffer.from(`
    <svg width="1284" height="700" xmlns="http://www.w3.org/2000/svg">
      <rect width="1284" height="700" fill="#fff"/>
      ${slide.headlineLines.map((line, index) => `<text x="110" y="${headlineStartY + index * headlineLineHeight}" font-family="${referenceFontFamily}" font-size="${slide.headlineFontSize}" font-weight="700" letter-spacing="${headlineLetterSpacing}" fill="#171717">${escapeXml(line)}</text>`).join("\n")}
      ${slide.subheadlineLines.map((line, index) => `<text x="112" y="${subheadlineStartY + index * subheadlineLineHeight}" font-family="${referenceFontFamily}" font-size="${slide.subheadlineFontSize}" font-weight="400" fill="#5A5A5A">${escapeXml(line)}</text>`).join("\n")}
    </svg>
  `);

  await Promise.all([
    sharp(apiMaskSvg).png().toFile(apiMaskPath),
    sharp(localMaskSvg).png().toFile(localEditMaskPath),
    sharp(textReferenceSvg).png().toFile(textReferencePath),
  ]);
}

function loadApiKey(): { key: string; source: "env" | "keychain" } {
  if (process.env.OPENAI_API_KEY?.trim()) {
    return { key: process.env.OPENAI_API_KEY.trim(), source: "env" };
  }

  try {
    const key = execFileSync(
      "security",
      ["find-generic-password", "-a", OPENAI_KEYCHAIN_ACCOUNT, "-s", OPENAI_KEYCHAIN_SERVICE, "-w"],
      { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] },
    ).trim();
    if (key) return { key, source: "keychain" };
  } catch {
    // The error below explains how to restore credentials.
  }

  throw new Error(
    "OPENAI_API_KEY is missing and no appstore-ai-images key was found in macOS Keychain.",
  );
}

async function extractImage(result: unknown): Promise<Buffer> {
  const record = result as Record<string, unknown>;
  const data = Array.isArray(record.data) ? record.data : [];
  const image = data[0] as Record<string, unknown> | undefined;
  if (typeof image?.b64_json === "string") return Buffer.from(image.b64_json, "base64");
  if (typeof image?.url === "string") {
    const response = await fetch(image.url);
    if (!response.ok) throw new Error(`Generated image download failed: ${response.status}`);
    return Buffer.from(await response.arrayBuffer());
  }
  throw new Error("OpenAI returned no image data.");
}

async function buildFinalFromMaskedEdit(width: number, height: number): Promise<void> {
  const resizedEdit = await sharp(rawOutputPath)
    .resize(width, height, { fit: "fill" })
    .png()
    .toBuffer();
  const editableLayer = await sharp(resizedEdit)
    .composite([{ input: localEditMaskPath, blend: "dest-in" }])
    .png()
    .toBuffer();

  let finalBuffer = await sharp(baseImagePath)
    .composite([{ input: editableLayer, left: 0, top: 0 }])
    .png()
    .toBuffer();

  if (slide.phoneComposite) {
    const phoneX = Math.round(width * slide.mask.phoneX);
    const phoneY = Math.round(height * slide.mask.phoneY);
    const phoneWidth = Math.round(width * slide.mask.phoneWidth);
    const phoneHeight = slide.mask.phoneHeight
      ? Math.round(height * slide.mask.phoneHeight)
      : height - phoneY + 8;
    const phoneRadius = Math.round(width * slide.mask.phoneRadius);
    const screenshot = await sharp(localizedScreenshotPath)
      .resize(phoneWidth, phoneHeight, { fit: "fill" })
      .png()
      .toBuffer();
    const roundedMask = Buffer.from(`
      <svg width="${phoneWidth}" height="${phoneHeight}" xmlns="http://www.w3.org/2000/svg">
        <rect width="${phoneWidth}" height="${phoneHeight}" rx="${phoneRadius}" fill="#fff"/>
      </svg>
    `);
    const localizedPhoneLayer = await sharp(screenshot)
      .composite([{ input: roundedMask, blend: "dest-in" }])
      .png()
      .toBuffer();
    finalBuffer = await sharp(finalBuffer)
      .composite([{ input: localizedPhoneLayer, left: phoneX, top: phoneY }])
      .png()
      .toBuffer();
  }

  await sharp(finalBuffer).png().toFile(finalOutputPath);
}

async function main(): Promise<void> {
  dotenv.config({ path: path.join(repoRoot, ".env"), override: false });
  dotenv.config({ path: path.join(toolDir, ".env"), override: false });
  ensureInputs();

  const metadata = await sharp(baseImagePath).metadata();
  if (!metadata.width || !metadata.height) throw new Error("Could not read base image dimensions.");
  await createReferenceFiles(metadata.width, metadata.height);

  const manifest = {
    timestamp: new Date().toISOString(),
    mode: generate ? "generate" : rebuild ? "rebuild" : "dry-run",
    provider: "openai-direct-images-edit",
    locale,
    languageName: marketingCopy.languageName,
    slideNumber,
    headline,
    subheadline,
    model: MODEL,
    quality: QUALITY,
    plannedImageEdits: rebuild ? 0 : 1,
    inputFidelity: "model-default; constrained by edit mask and local pixel preservation",
    deterministicLocalizedPhoneComposite: Boolean(slide.phoneComposite),
    apiOutputSize: API_OUTPUT_SIZE,
    finalOutputSize: `${metadata.width}x${metadata.height}`,
    uploadedInputsWhenGenerated: [
      relativePath(baseImagePath),
      relativePath(localizedScreenshotPath),
      relativePath(textReferencePath),
    ],
    mask: relativePath(apiMaskPath),
    prompt,
    paid: false,
    filesCreated: [
      relativePath(apiMaskPath),
      relativePath(localEditMaskPath),
      relativePath(textReferencePath),
    ],
  };

  if (!generate && !rebuild) {
    fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
    console.log("Reference-swap edit plan");
    console.log("========================");
    console.log("Mode: dry-run (no paid AI call)");
    console.log(`Base design: ${relativePath(baseImagePath)}`);
    console.log(`Localized UI: ${relativePath(localizedScreenshotPath)}`);
    console.log(`Localized copy reference: ${relativePath(textReferencePath)}`);
    console.log(`Mask: ${relativePath(apiMaskPath)}`);
    console.log(`Model: ${MODEL}; quality: ${QUALITY}; planned edits: 1`);
    console.log(`Manifest: ${relativePath(manifestPath)}`);
    return;
  }

  if (rebuild) {
    if (!fs.existsSync(rawOutputPath)) {
      throw new Error(`Cannot rebuild without existing paid raw edit: ${relativePath(rawOutputPath)}`);
    }
    await buildFinalFromMaskedEdit(metadata.width, metadata.height);
    const rebuiltManifest = {
      ...manifest,
      timestamp: new Date().toISOString(),
      paid: true,
      reusedPaidRawEdit: true,
      filesCreated: [
        ...manifest.filesCreated,
        relativePath(rawOutputPath),
        relativePath(finalOutputPath),
      ],
    };
    fs.writeFileSync(manifestPath, `${JSON.stringify(rebuiltManifest, null, 2)}\n`);
    console.log(`Rebuilt locally from existing raw edit: ${relativePath(finalOutputPath)}`);
    return;
  }

  if (!force) {
    for (const outputPath of [rawOutputPath, finalOutputPath]) {
      if (fs.existsSync(outputPath)) {
        throw new Error(`Refusing to overwrite ${relativePath(outputPath)} without --force.`);
      }
    }
  }

  const credential = loadApiKey();
  const client = new OpenAI({ apiKey: credential.key });
  const [baseUpload, localizedUpload, textUpload, maskUpload] = await Promise.all([
    toFile(fs.readFileSync(baseImagePath), path.basename(baseImagePath), { type: "image/png" }),
    toFile(fs.readFileSync(localizedScreenshotPath), path.basename(localizedScreenshotPath), { type: "image/png" }),
    toFile(fs.readFileSync(textReferencePath), path.basename(textReferencePath), { type: "image/png" }),
    toFile(fs.readFileSync(apiMaskPath), path.basename(apiMaskPath), { type: "image/png" }),
  ]);
  console.log(`Submitting one ${MODEL} image edit with three references and one mask...`);
  const result = await client.images.edit({
    model: MODEL,
    image: [baseUpload, localizedUpload, textUpload],
    mask: maskUpload,
    prompt,
    quality: QUALITY,
    size: API_OUTPUT_SIZE,
    output_format: "png",
    background: "opaque",
    n: 1,
  });

  fs.writeFileSync(rawOutputPath, await extractImage(result));
  await buildFinalFromMaskedEdit(metadata.width, metadata.height);

  const completedManifest = {
    ...manifest,
    timestamp: new Date().toISOString(),
    credentialSource: credential.source,
    paid: true,
    filesCreated: [
      ...manifest.filesCreated,
      relativePath(rawOutputPath),
      relativePath(finalOutputPath),
    ],
  };
  fs.writeFileSync(manifestPath, `${JSON.stringify(completedManifest, null, 2)}\n`);
  console.log(`Raw edit: ${relativePath(rawOutputPath)}`);
  console.log(`Masked final: ${relativePath(finalOutputPath)}`);
  console.log(`Manifest: ${relativePath(manifestPath)}`);
}

main().catch((error) => {
  console.error(error instanceof Error ? `Error: ${error.message}` : error);
  process.exit(1);
});
