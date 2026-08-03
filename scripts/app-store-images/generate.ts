#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import dotenv from "dotenv";
import type sharpDefault from "sharp";

const __filename = fileURLToPath(import.meta.url);
const toolDir = path.dirname(__filename);
const repoRoot = path.resolve(toolDir, "../..");

dotenv.config({ path: path.join(repoRoot, ".env"), override: false });
dotenv.config({ path: path.join(toolDir, ".env"), override: false });

const DEFAULT_TARGET_SIZE = "1320x2868";
const DEFAULT_AI_BACKGROUND_SIZE = "1024x1536";
const ABSOLUTE_MAX_IMAGES = 6;
const ABSOLUTE_MAX_VARIANTS_PER_SCREEN = 2;
const DEFAULT_RETRIES_PER_IMAGE = 1;
const OPENAI_KEYCHAIN_SERVICE = "appstore-ai-images.openai-api-key";
const OPENAI_KEYCHAIN_ACCOUNT = "default";
let cachedOpenAIApiKey: string | undefined;

const TARGET_SIZES: Record<string, TargetSize> = {
  "1320x2868": { width: 1320, height: 2868, label: "iPhone 6.9-inch portrait" },
  "1290x2796": { width: 1290, height: 2796, label: "iPhone 6.9-inch portrait alternate" },
  "1260x2736": { width: 1260, height: 2736, label: "iPhone 6.7-inch portrait" },
};

const IMAGE_EXTENSIONS = new Set([".png", ".jpg", ".jpeg", ".webp"]);

type TargetSize = {
  width: number;
  height: number;
  label: string;
};

type CliOptions = {
  dryRun: boolean;
  generate: boolean;
  model: string;
  quality: string;
  maxImages: number;
  maxVariantsPerScreen: number;
  targetSizeKey: string;
  targetSize: TargetSize;
  inputScreenshots: string;
  outputDir: string;
  brandFile: string;
  brandFileWasExplicit: boolean;
  campaignFile?: string;
  seed?: number;
  force: boolean;
};

type BrandConfig = {
  appName?: string;
  primaryColor?: string;
  secondaryColor?: string;
  accentColor?: string;
  fontFamily?: string;
  category?: string;
  tone?: string;
};

type BrandColors = {
  primaryColor: string;
  secondaryColor: string;
  accentColor: string;
  backgroundColor: string;
  detected: Array<{ name: string; value: string; source: string }>;
};

type CampaignScreen = {
  slug: string;
  title: string;
  feature: string;
  headline: string;
  subheadline: string;
  mood: string;
  screenshot: string;
  prompt?: string;
  visualDirection?: string;
  phonePresentation?: "standard" | "large-minimal";
};

type CampaignConfig = {
  locale?: string;
  screens: CampaignScreen[];
};

type DetectedFeature = {
  title: string;
  description: string;
  source: string;
};

type RepoInsights = {
  appName: string;
  appNameSource: string;
  category: string;
  brandColors: BrandColors;
  typographyHints: string[];
  designLanguage: string[];
  features: DetectedFeature[];
  screenshots: string[];
  screenshotSearchPaths: string[];
  brandConfigPath?: string;
};

type ScreenPlan = {
  index: number;
  slug: string;
  kind: "hero" | "feature";
  title: string;
  feature: string;
  headline: string;
  subheadline: string;
  mood: string;
  prompt: string;
  screenshotPath: string | null;
  screenshotSource: string;
  targetSize: TargetSize;
  outputBackgroundPath: string;
  outputFinalPath: string;
  draftOnly: boolean;
  phonePresentation?: "standard" | "large-minimal";
};

type Manifest = {
  timestamp: string;
  appName: string;
  appNameSource: string;
  repoRoot: string;
  detectedFeatures: DetectedFeature[];
  detectedBrandColors: BrandColors;
  typographyHints: string[];
  designLanguage: string[];
  selectedScreenshotSources: Array<{ screen: string; path: string | null; source: string }>;
  generatedPrompts: Array<{ screen: string; prompt: string }>;
  model: string;
  quality: string;
  aiGeneration: {
    provider: string;
    credentialSource: "env" | "keychain" | "missing";
    dryRun: boolean;
    paid: boolean;
    plannedImageGenerations: number;
    aiBackgroundSize: string;
    aiBackgroundAspectRatio: string;
    maxImages: number;
    maxVariantsPerScreen: number;
    retriesPerImage: number;
    seed?: number;
  };
  outputDimensions: TargetSize;
  supportedTargetSizes: string[];
  draftOnly: boolean;
  assumptions: string[];
  filesCreated: string[];
};

function parseArgs(argv: string[]): CliOptions {
  const defaults = {
    model: "gpt-image-2",
    quality: "medium",
    maxImages: 3,
    maxVariantsPerScreen: 1,
    targetSizeKey: DEFAULT_TARGET_SIZE,
    inputScreenshots: "app-store-input/screenshots",
    outputDir: "app-store-output",
    brandFile: "app-store-input/brand.json",
  };

  let dryRunFlag = false;
  let generateFlag = false;
  let model = defaults.model;
  let quality = defaults.quality;
  let maxImages = defaults.maxImages;
  let maxVariantsPerScreen = defaults.maxVariantsPerScreen;
  let targetSizeKey = defaults.targetSizeKey;
  let inputScreenshots = defaults.inputScreenshots;
  let outputDir = defaults.outputDir;
  let brandFile = defaults.brandFile;
  let brandFileWasExplicit = false;
  let campaignFile: string | undefined;
  let seed: number | undefined;
  let force = false;

  const args = argv.slice(2);

  for (let i = 0; i < args.length; i += 1) {
    const token = args[i];
    const [flag, inlineValue] = token.includes("=") ? token.split(/=(.*)/s, 2) : [token, undefined];
    const readValue = () => {
      if (inlineValue !== undefined) return inlineValue;
      i += 1;
      if (i >= args.length || args[i].startsWith("--")) {
        throw new Error(`Missing value for ${flag}`);
      }
      return args[i];
    };

    switch (flag) {
      case "--help":
      case "-h":
        printHelpAndExit();
        break;
      case "--dry-run":
        dryRunFlag = true;
        break;
      case "--generate":
        generateFlag = true;
        break;
      case "--model":
        model = readValue();
        break;
      case "--quality":
        quality = readValue();
        break;
      case "--max-images":
        maxImages = parsePositiveInteger(readValue(), "--max-images");
        break;
      case "--max-variants-per-screen":
        maxVariantsPerScreen = parsePositiveInteger(readValue(), "--max-variants-per-screen");
        break;
      case "--target-size":
        targetSizeKey = readValue();
        break;
      case "--input-screenshots":
        inputScreenshots = readValue();
        break;
      case "--output-dir":
        outputDir = readValue();
        break;
      case "--brand-file":
        brandFile = readValue();
        brandFileWasExplicit = true;
        break;
      case "--campaign-file":
        campaignFile = readValue();
        break;
      case "--seed":
        seed = parsePositiveInteger(readValue(), "--seed");
        break;
      case "--force":
        force = true;
        break;
      default:
        throw new Error(`Unknown flag: ${token}. Run with --help for usage.`);
    }
  }

  if (dryRunFlag && generateFlag) {
    throw new Error("Use either --dry-run or --generate, not both.");
  }

  if (maxImages > ABSOLUTE_MAX_IMAGES) {
    throw new Error(`--max-images may not exceed ${ABSOLUTE_MAX_IMAGES} in this first draft.`);
  }

  if (maxVariantsPerScreen > ABSOLUTE_MAX_VARIANTS_PER_SCREEN) {
    throw new Error(
      `--max-variants-per-screen may not exceed ${ABSOLUTE_MAX_VARIANTS_PER_SCREEN} in this first draft.`,
    );
  }

  const targetSize = TARGET_SIZES[targetSizeKey];
  if (!targetSize) {
    throw new Error(
      `Unsupported --target-size "${targetSizeKey}". Supported sizes: ${Object.keys(TARGET_SIZES).join(", ")}`,
    );
  }

  const dryRun = !generateFlag || dryRunFlag;

  return {
    dryRun,
    generate: generateFlag,
    model,
    quality,
    maxImages,
    maxVariantsPerScreen,
    targetSizeKey,
    targetSize,
    inputScreenshots: resolveRepoPath(inputScreenshots),
    outputDir: resolveRepoPath(outputDir),
    brandFile: resolveRepoPath(brandFile),
    brandFileWasExplicit,
    campaignFile: campaignFile ? resolveRepoPath(campaignFile) : undefined,
    seed,
    force,
  };
}

function parsePositiveInteger(value: string, flag: string): number {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1) {
    throw new Error(`${flag} must be a positive integer.`);
  }
  return parsed;
}

function resolveRepoPath(value: string): string {
  return path.isAbsolute(value) ? value : path.resolve(repoRoot, value);
}

function printHelpAndExit(): never {
  console.log(`Repo-aware App Store draft image generator\n\nUsage:\n  npm --prefix scripts/app-store-images run plan\n  npm --prefix scripts/app-store-images run store-key\n  npm --prefix scripts/app-store-images run generate -- --max-images 3\n  npm --prefix scripts/app-store-images exec -- tsx scripts/app-store-images/generate.ts --dry-run\n\nFlags:\n  --dry-run                         Plan only; no paid AI calls. Default.\n  --generate                        Enable OpenAI image generation and final PNG compositing.\n  --model <id>                      OpenAI image model. Default: gpt-image-2\n  --quality <quality>               OpenAI image quality. Default: medium\n  --max-images <n>                  Hard cap. Default: 3, absolute max: ${ABSOLUTE_MAX_IMAGES}\n  --max-variants-per-screen <n>     Safety cap. Default: 1, absolute max: ${ABSOLUTE_MAX_VARIANTS_PER_SCREEN}\n  --target-size <WxH>               ${Object.keys(TARGET_SIZES).join(" | ")}\n  --input-screenshots <dir>         Default: app-store-input/screenshots\n  --output-dir <dir>                Default: app-store-output\n  --brand-file <file>               Default: app-store-input/brand.json\n  --campaign-file <file>            Optional explicit copy, prompts, and screenshot order\n  --seed <number>                   Passed to OpenAI if supported by the selected model.\n  --force                           Overwrite existing background/final PNG files.\n\nCredentials:\n  Set OPENAI_API_KEY in the environment, or run the store-key script once to save it in macOS Keychain.\n`);
  process.exit(0);
}

async function main() {
  const options = parseArgs(process.argv);

  ensureDirectory(options.inputScreenshots);
  ensureDirectory(path.resolve(repoRoot, "app-store-input/reference"));
  ensureDirectory(options.outputDir);
  ensureDirectory(path.join(options.outputDir, "backgrounds"));
  ensureDirectory(path.join(options.outputDir, "final"));
  ensureBrandExample();

  const brandConfig = loadBrandConfig(options.brandFile, options.brandFileWasExplicit);
  const campaign = loadCampaignConfig(options.campaignFile);
  const insights = inspectRepo(brandConfig, options);
  const plan = buildScreenshotPlan(insights, options, campaign);
  const plannedImageGenerations = plan.length;

  printPlan(insights, plan, options, plannedImageGenerations);
  validateCostControls(plan, options, plannedImageGenerations);

  const manifest = buildManifest(insights, plan, options, plannedImageGenerations, []);

  if (options.dryRun) {
    const manifestPath = writeManifest(options.outputDir, manifest);
    console.log(`\nDry run complete. No AI calls were made.`);
    console.log(`Manifest written to ${relativePath(manifestPath)}`);
    return;
  }

  if (!getOpenAIApiKey(false)) {
    throw new Error(
      "--generate was requested, but OPENAI_API_KEY is missing and no appstore-ai-images key was found in macOS Keychain. Export OPENAI_API_KEY or run `npm --prefix scripts/app-store-images run store-key` first.",
    );
  }

  preflightOutputFiles(plan, options.force);

  const filesCreated: string[] = [];
  for (const screen of plan) {
    console.log(`\nGenerating background ${screen.index}/${plan.length}: ${screen.title}`);
    const backgroundBuffer = await generateBackground(screen.prompt, options);
    fs.writeFileSync(screen.outputBackgroundPath, backgroundBuffer);
    filesCreated.push(relativePath(screen.outputBackgroundPath));

    console.log(`Compositing final PNG: ${relativePath(screen.outputFinalPath)}`);
    await compositeFinalImage(screen, insights, options);
    filesCreated.push(relativePath(screen.outputFinalPath));
  }

  const finalManifest = buildManifest(insights, plan, options, plannedImageGenerations, filesCreated);
  const manifestPath = writeManifest(options.outputDir, finalManifest);
  console.log(`\nGeneration complete. Manifest written to ${relativePath(manifestPath)}`);
}

function loadBrandConfig(brandFile: string, explicit: boolean): BrandConfig {
  if (!fs.existsSync(brandFile)) {
    if (explicit) {
      throw new Error(`Brand file not found: ${brandFile}`);
    }
    return {};
  }

  try {
    return JSON.parse(fs.readFileSync(brandFile, "utf8")) as BrandConfig;
  } catch (error) {
    throw new Error(`Could not parse brand file ${brandFile}: ${error instanceof Error ? error.message : String(error)}`);
  }
}

function loadCampaignConfig(campaignFile?: string): CampaignConfig | undefined {
  if (!campaignFile) return undefined;
  if (!fs.existsSync(campaignFile)) {
    throw new Error(`Campaign file not found: ${campaignFile}`);
  }

  try {
    const campaign = JSON.parse(fs.readFileSync(campaignFile, "utf8")) as CampaignConfig;
    if (!Array.isArray(campaign.screens) || campaign.screens.length === 0) {
      throw new Error("campaign must contain a non-empty screens array");
    }
    return campaign;
  } catch (error) {
    throw new Error(`Could not parse campaign file ${campaignFile}: ${error instanceof Error ? error.message : String(error)}`);
  }
}

function inspectRepo(brandConfig: BrandConfig, options: CliOptions): RepoInsights {
  const appNameInfo = detectAppName(brandConfig);
  const brandColors = detectBrandColors(brandConfig);
  const typographyHints = detectTypographyHints(brandConfig);
  const designLanguage = detectDesignLanguage();
  const features = detectFeatures();
  const screenshotsInfo = discoverScreenshots(options.inputScreenshots);

  return {
    appName: appNameInfo.name,
    appNameSource: appNameInfo.source,
    category: brandConfig.category ?? inferCategory(features),
    brandColors,
    typographyHints,
    designLanguage,
    features,
    screenshots: screenshotsInfo.files,
    screenshotSearchPaths: screenshotsInfo.searchPaths,
    brandConfigPath: fs.existsSync(options.brandFile) ? relativePath(options.brandFile) : undefined,
  };
}

function detectAppName(brandConfig: BrandConfig): { name: string; source: string } {
  if (brandConfig.appName) {
    return { name: brandConfig.appName, source: "app-store-input/brand.json" };
  }

  for (const plistPath of discoverInfoPlists()) {
    const infoPlist = readTextIfExists(plistPath);
    if (!infoPlist) continue;
    const plistName = plistStringValue(infoPlist, "CFBundleDisplayName") ?? plistStringValue(infoPlist, "CFBundleName");
    if (plistName && !plistName.includes("$(")) {
      return { name: plistName, source: relativePath(plistPath) };
    }
  }

  const projectYmlPath = path.join(repoRoot, "project.yml");
  const projectYml = readTextIfExists(projectYmlPath);
  if (projectYml) {
    const iosProductName = productNameFromXcodeGen(projectYml);
    if (iosProductName) {
      return { name: iosProductName, source: "project.yml iOS PRODUCT_NAME" };
    }

    const rootNameMatch = projectYml.match(/^name:\s*"?([^"\n]+)"?/m);
    if (rootNameMatch?.[1]?.trim()) {
      return { name: rootNameMatch[1].trim(), source: "project.yml name" };
    }
  }

  const pbxproj = discoverFilesByName("project.pbxproj", 5)[0];
  const pbxprojText = pbxproj ? readTextIfExists(pbxproj) : undefined;
  const pbxProductName = pbxprojText?.match(/PRODUCT_NAME\s*=\s*"?([^";\n]+)"?;/)?.[1]?.trim();
  if (pbxProductName && !pbxProductName.includes("$(")) {
    return { name: pbxProductName, source: relativePath(pbxproj) };
  }

  const packageJson = readJsonIfExists<{ name?: string; productName?: string }>(path.join(repoRoot, "package.json"));
  const packageName = packageJson?.productName ?? packageJson?.name;
  if (packageName) {
    return { name: humanizePackageName(packageName), source: "package.json" };
  }

  const readme = readTextIfExists(path.join(repoRoot, "README.md"));
  const readmeTitle = readme?.match(/^#\s+(.+)$/m)?.[1]?.trim();
  if (readmeTitle) {
    return { name: readmeTitle, source: "README.md title" };
  }

  return { name: humanizePackageName(path.basename(repoRoot)), source: "repository folder name" };
}

function discoverInfoPlists(): string[] {
  const files = discoverFilesByName("Info.plist", 6);
  return files.sort((a, b) => plistPriority(a) - plistPriority(b));
}

function plistPriority(filePath: string): number {
  const lower = relativePath(filePath).toLowerCase();
  if (lower.includes("/ios/") || lower.includes("iphone")) return 0;
  if (lower.includes("app")) return 1;
  return 2;
}

function productNameFromXcodeGen(projectYml: string): string | undefined {
  const lines = projectYml.split(/\r?\n/);
  let inTargets = false;
  let insideTarget = false;
  let currentIsIos = false;
  let currentProductName: string | undefined;

  const finishTarget = () => {
    const productName = currentIsIos ? currentProductName : undefined;
    insideTarget = false;
    currentIsIos = false;
    currentProductName = undefined;
    return productName;
  };

  for (const line of lines) {
    if (/^targets:\s*$/.test(line)) {
      inTargets = true;
      continue;
    }

    if (inTargets && /^[A-Za-z0-9_]+:\s*$/.test(line)) {
      const productName = finishTarget();
      if (productName) return productName;
      inTargets = false;
    }

    if (!inTargets) continue;

    if (/^  \S[^:\n]*:\s*$/.test(line)) {
      const productName = insideTarget ? finishTarget() : undefined;
      if (productName) return productName;
      insideTarget = true;
      continue;
    }

    if (!insideTarget) continue;

    if (/^\s*platform:\s*iOS\b/i.test(line)) {
      currentIsIos = true;
    }

    const productName = line.match(/^\s*PRODUCT_NAME:\s*"?([^"\n]+)"?/m)?.[1]?.trim();
    if (productName) {
      currentProductName = productName;
    }
  }

  return finishTarget();
}

function humanizePackageName(name: string): string {
  return name
    .replace(/^@[^/]+\//, "")
    .replace(/[-_]+/g, " ")
    .replace(/\b\w/g, (letter) => letter.toUpperCase())
    .trim();
}

function plistStringValue(plist: string, key: string): string | undefined {
  const escapedKey = key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = plist.match(new RegExp(`<key>${escapedKey}</key>\\s*<string>([^<]+)</string>`));
  return match?.[1]?.trim();
}

function detectBrandColors(brandConfig: BrandConfig): BrandColors {
  const detected: BrandColors["detected"] = [];
  const seen = new Set<string>();
  const addColor = (name: string, value: string, source: string) => {
    const normalized = normalizeHex(value);
    const key = `${name}:${normalized}:${source}`;
    if (seen.has(key)) return;
    seen.add(key);
    detected.push({ name, value: normalized, source });
  };

  for (const file of discoverDesignFiles()) {
    const text = readTextIfExists(file);
    if (!text) continue;
    const source = relativePath(file);

    const cssVariableRegex = /--([a-zA-Z0-9-]+):\s*(#[0-9a-fA-F]{3,8})\b/g;
    for (const match of text.matchAll(cssVariableRegex)) {
      addColor(match[1], match[2], source);
    }

    const namedTokenRegex = /(?:\.|\b)([a-zA-Z][a-zA-Z0-9_-]{1,40})\s*[:=]\s*"(#[0-9a-fA-F]{6,8})"/g;
    for (const match of text.matchAll(namedTokenRegex)) {
      addColor(match[1], match[2], source);
    }

    if (detected.length < 80) {
      const looseHexRegex = /#[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?\b/g;
      for (const match of text.matchAll(looseHexRegex)) {
        addColor(`detected-${detected.length + 1}`, match[0], source);
        if (detected.length >= 80) break;
      }
    }
  }

  const pick = (patterns: RegExp[], fallback: string): string => {
    for (const pattern of patterns) {
      const exact = detected.find((color) => pattern.test(color.name.toLowerCase()));
      if (exact) return exact.value;
    }
    return fallback;
  };

  const primaryColor = brandConfig.primaryColor ?? pick([/^(primary|ink|text|foreground|fg)$/, /primary/, /ink/, /foreground/, /text/], "#111111");
  const secondaryColor = brandConfig.secondaryColor ?? pick([/^(secondary|paper|background|bg|surface)$/, /paper/, /background/, /surface/], "#ffffff");
  const accentColor = brandConfig.accentColor ?? pick([/^(accent|brand|orange|blue|purple|pink|teal|green)$/, /accent/, /brand/, /orange/, /blue/, /purple/], "#4F46E5");
  const backgroundColor = pick([/^(background|bg|paper|surface)$/, /background/, /paper/, /surface/], secondaryColor);

  return {
    primaryColor,
    secondaryColor,
    accentColor,
    backgroundColor,
    detected: detected.slice(0, 80),
  };
}

function discoverDesignFiles(): string[] {
  const commonPaths = [
    "Website/styles.css",
    "website/styles.css",
    "src/styles.css",
    "src/index.css",
    "src/globals.css",
    "app/globals.css",
    "styles/globals.css",
    "tailwind.config.js",
    "tailwind.config.ts",
    "theme.json",
    "tokens.json",
  ].map((file) => path.join(repoRoot, file));

  const discovered = walkFiles(repoRoot, 5).filter(isDesignCandidateFile);
  return Array.from(new Set([...commonPaths.filter((file) => fs.existsSync(file)), ...discovered])).slice(0, 50);
}

function isDesignCandidateFile(file: string): boolean {
  const relative = relativePath(file).toLowerCase();
  const basename = path.basename(relative);
  const extension = path.extname(relative);
  if (relative.includes("node_modules/") || relative.includes("app-store-output/") || relative.includes("build/")) return false;
  if ([".css", ".scss", ".sass", ".less"].includes(extension)) return true;
  if ([".html", ".swift", ".tsx", ".jsx", ".ts", ".js", ".json"].includes(extension)) {
    return /theme|design|token|color|style|brand|tailwind|globals|index\.html|asset|font/.test(relative) && !basename.includes("package-lock");
  }
  return false;
}

function normalizeHex(value: string): string {
  if (value.length === 4) {
    return `#${value[1]}${value[1]}${value[2]}${value[2]}${value[3]}${value[3]}`.toUpperCase();
  }
  return value.toUpperCase();
}

function detectTypographyHints(brandConfig: BrandConfig): string[] {
  const hints = new Set<string>();
  if (brandConfig.fontFamily) hints.add(`brand.json fontFamily: ${brandConfig.fontFamily}`);

  const designText = discoverDesignFiles()
    .map((file) => readTextIfExists(file) ?? "")
    .join("\n")
    .slice(0, 500_000);

  if (/Geist Sans/i.test(designText)) hints.add("Geist Sans / Geist Mono tokens detected");
  if (/SF Pro|San Francisco|-apple-system|BlinkMacSystemFont/i.test(designText)) hints.add("Apple system typography detected");
  if (/ui-monospace|font-mono|monospace|SFMono/i.test(designText)) hints.add("monospace typography hints detected");
  if (/Inter\b/i.test(designText)) hints.add("Inter typography detected");

  if (hints.size === 0) hints.add("system font stack");
  return Array.from(hints);
}

function detectDesignLanguage(): string[] {
  const language = new Set<string>();
  const designText = discoverDesignFiles()
    .map((file) => readTextIfExists(file) ?? "")
    .join("\n")
    .slice(0, 500_000)
    .toLowerCase();

  if (/geist/.test(designText)) language.add("Geist-inspired tokens, neutral panels, rounded controls, and precise spacing");
  if (/paper|ink/.test(designText)) language.add("paper-and-ink palette with editorial contrast");
  if (/pixel|8bit|retro/.test(designText)) language.add("retro or pixel-inspired visual cues");
  if (/gradient/.test(designText)) language.add("gradient-backed marketing treatments");
  if (/rounded|radius|corner/.test(designText)) language.add("rounded cards, panels, or controls");
  if (/mockup|phone-frame|device|product-card/.test(designText)) language.add("device or product mockup composition cues");

  return Array.from(language);
}

function isIgnoredFeatureTitle(title: string): boolean {
  return /^(build|use|usage|targets?|install|installation|requirements?|development|tests?|testing|license|contributing|changelog|release|setup)$/i.test(
    title.trim(),
  );
}

function detectFeatures(): DetectedFeature[] {
  const features: DetectedFeature[] = [];
  const seen = new Set<string>();
  const add = (title: string, description: string, source: string) => {
    const cleanTitle = stripMarkdown(stripHtml(title)).replace(/\s+/g, " ").trim();
    const cleanDescription = stripMarkdown(stripHtml(description)).replace(/\s+/g, " ").trim();
    const key = cleanTitle.toLowerCase();
    if (!cleanTitle || !cleanDescription || seen.has(key)) return;
    if (isIgnoredFeatureTitle(cleanTitle)) return;
    if (/```|xcodebuild|npm install|yarn install|pnpm install|swift build/i.test(cleanDescription)) return;
    seen.add(key);
    features.push({ title: cleanTitle, description: cleanDescription, source });
  };

  const marketingFiles = discoverMarketingTextFiles();
  const marketingTextChunks: string[] = [];

  for (const file of marketingFiles) {
    const text = readTextIfExists(file);
    if (!text) continue;
    const source = relativePath(file);
    marketingTextChunks.push(stripMarkdown(stripHtml(text)));

    const firstParagraph = firstMeaningfulParagraph(text);
    if (firstParagraph) add("Core value proposition", firstParagraph, source);

    const metaDescription = text.match(/<meta\s+name=["']description["']\s+content=["']([^"']+)["']/i)?.[1];
    if (metaDescription) add("Product description", metaDescription, source);

    const articleRegex = /<article[\s\S]*?<h[23][^>]*>([\s\S]*?)<\/h[23]>[\s\S]*?<p[^>]*>([\s\S]*?)<\/p>[\s\S]*?<\/article>/g;
    for (const match of text.matchAll(articleRegex)) {
      add(match[1], match[2], source);
    }

    const markdownSectionRegex = /^#{2,3}\s+(.+)\n+([^#\n][\s\S]{40,500}?)(?=\n#{1,3}\s+|\n\n#{1,3}\s+|$)/gm;
    for (const match of text.matchAll(markdownSectionRegex)) {
      add(match[1], firstSentence(match[2]) ?? match[2], source);
      if (features.length >= 12) break;
    }
  }

  const combinedMarketingText = marketingTextChunks.join(" ");
  const keywordHints: Array<{ title: string; pattern: RegExp }> = [
    { title: "Fast setup", pattern: /\b(set ?up|onboard|pair|connect|sign in|scan|start)\b/i },
    { title: "Customization", pattern: /\b(custom|customize|profile|template|theme|layout|settings|personalize)\b/i },
    { title: "Sync and sharing", pattern: /\b(sync|share|export|import|backup|collaborate)\b/i },
    { title: "Automation", pattern: /\b(cli|api|automation|workflow|shortcut|script|integrat)\b/i },
    { title: "Privacy-minded", pattern: /\b(private|privacy|local|offline|secure|encrypted|auth)\b/i },
    { title: "Insights", pattern: /\b(analytics|insight|track|history|report|dashboard|metric)\b/i },
    { title: "Creative tools", pattern: /\b(create|edit|generate|capture|record|media|video|photo|image)\b/i },
  ];

  for (const hint of keywordHints) {
    const sentence = firstSentenceMatching(combinedMarketingText, hint.pattern);
    if (sentence) add(hint.title, sentence, "repo marketing text keyword scan");
    if (features.length >= 12) break;
  }

  return features.slice(0, 12);
}

function discoverMarketingTextFiles(): string[] {
  const commonPaths = [
    "README.md",
    "readme.md",
    "Website/index.html",
    "website/index.html",
    "public/index.html",
    "docs/README.md",
  ].map((file) => path.join(repoRoot, file));

  const discovered = walkFiles(repoRoot, 4).filter((file) => {
    const relative = relativePath(file).toLowerCase();
    const basename = path.basename(relative);
    const extension = path.extname(relative);
    if (relative.includes("node_modules/") || relative.includes("build/") || relative.includes("app-store-output/")) return false;
    if (basename.startsWith("readme") && extension === ".md") return true;
    if (basename === "index.html" || basename.endsWith(".strings")) return true;
    return (relative.includes("docs/") || relative.includes("website/") || relative.includes("marketing/")) && [".md", ".html", ".mdx"].includes(extension);
  });

  return Array.from(new Set([...commonPaths.filter((file) => fs.existsSync(file)), ...discovered])).slice(0, 30);
}

function inferCategory(features: DetectedFeature[]): string {
  const allText = features.map((feature) => `${feature.title} ${feature.description}`).join(" ").toLowerCase();
  if (/\b(game|gaming|controller|play)\b/.test(allText)) return "games and entertainment utility";
  if (/health|medical|wellness|fitness/.test(allText)) return "health and wellness";
  if (/finance|invoice|budget|receipt|payment/.test(allText)) return "finance";
  if (/photo|video|camera|media|recording|screen capture/.test(allText)) return "photo and video";
  if (/learn|course|education|language|study/.test(allText)) return "education";
  if (/developer|code|cli|api|terminal/.test(allText)) return "developer tool";
  if (/task|todo|note|calendar|schedule|workflow|shortcut|productivity/.test(allText)) return "productivity";
  if (/social|community|chat|message/.test(allText)) return "social networking";
  return "iOS app";
}

function discoverScreenshots(inputScreenshots: string): { files: string[]; searchPaths: string[] } {
  const candidatePaths = [
    inputScreenshots,
    path.join(repoRoot, "screenshots"),
    path.join(repoRoot, "Screenshots"),
    path.join(repoRoot, "screenshot"),
    path.join(repoRoot, "Screenshot"),
    path.join(repoRoot, "fastlane/screenshots"),
    path.join(repoRoot, "fastlane/metadata"),
    path.join(repoRoot, "metadata"),
    path.join(repoRoot, "app-store"),
    path.join(repoRoot, "marketing"),
    path.join(repoRoot, "docs"),
    path.join(repoRoot, ".github"),
  ];

  const uniquePaths = Array.from(new Set(candidatePaths.map((candidate) => path.resolve(candidate))));
  const files: string[] = [];
  const seenRealPaths = new Set<string>();

  for (const candidate of uniquePaths) {
    if (!fs.existsSync(candidate)) continue;
    for (const file of walkFiles(candidate, 4)) {
      if (!IMAGE_EXTENSIONS.has(path.extname(file).toLowerCase())) continue;
      if (isLikelyNonScreenshot(file)) continue;
      const realPath = safeRealPath(file);
      if (seenRealPaths.has(realPath)) continue;
      seenRealPaths.add(realPath);
      files.push(realPath);
    }
  }

  return {
    files: files.sort(),
    searchPaths: uniquePaths.map(relativePath),
  };
}

function safeRealPath(file: string): string {
  try {
    return fs.realpathSync.native(file);
  } catch {
    return file;
  }
}

function isLikelyNonScreenshot(file: string): boolean {
  const lower = relativePath(file).toLowerCase();
  const basename = path.basename(lower);
  if (lower.includes("app-icons-")) return true;
  if (basename.includes("appicon") || basename.includes("app-icon") || basename.includes("favicon")) return true;
  if (/^icon[_-]?\d/.test(basename)) return true;
  return false;
}

function walkFiles(root: string, maxDepth: number): string[] {
  const results: string[] = [];
  const visit = (current: string, depth: number) => {
    if (depth > maxDepth) return;
    const entries = fs.readdirSync(current, { withFileTypes: true });
    for (const entry of entries) {
      const fullPath = path.join(current, entry.name);
      if (entry.isDirectory()) {
        if ([".git", "build", "node_modules", "app-store-output"].includes(entry.name)) continue;
        visit(fullPath, depth + 1);
      } else if (entry.isFile()) {
        results.push(fullPath);
      }
    }
  };

  visit(root, 0);
  return results;
}

function buildScreenshotPlan(
  insights: RepoInsights,
  options: CliOptions,
  campaign?: CampaignConfig,
): ScreenPlan[] {
  if (campaign) {
    return campaign.screens.map((screen, index) => {
      const screenshotPath = resolveRepoPath(screen.screenshot);
      if (!fs.existsSync(screenshotPath)) {
        throw new Error(`Campaign screenshot not found: ${screenshotPath}`);
      }
      for (const [field, value] of Object.entries({
        slug: screen.slug,
        title: screen.title,
        feature: screen.feature,
        headline: screen.headline,
        subheadline: screen.subheadline,
        mood: screen.mood,
      })) {
        if (typeof value !== "string" || value.trim().length === 0) {
          throw new Error(`Campaign screen ${index + 1} is missing ${field}`);
        }
      }

      const slug = slugify(screen.slug);
      const prompt = screen.prompt?.trim() || [
        buildBackgroundPrompt({ feature: screen.feature, mood: screen.mood }, insights),
        screen.visualDirection?.trim(),
      ].filter(Boolean).join(" ");

      return {
        kind: index === 0 ? "hero" : "feature",
        title: screen.title,
        feature: screen.feature,
        headline: screen.headline,
        subheadline: screen.subheadline,
        mood: screen.mood,
        index: index + 1,
        slug,
        prompt,
        screenshotPath,
        screenshotSource: relativePath(screenshotPath),
        targetSize: options.targetSize,
        outputBackgroundPath: path.join(options.outputDir, "backgrounds", `${slug}-${options.targetSizeKey}-background.png`),
        outputFinalPath: path.join(options.outputDir, "final", `${slug}-${options.targetSizeKey}.png`),
        draftOnly: false,
        phonePresentation: screen.phonePresentation,
      };
    });
  }

  const selectedFeatures = selectPlanFeatures(insights);
  const screenSeeds = [
    {
      kind: "hero" as const,
      title: "Hero / core value proposition",
      feature: selectedFeatures[0],
      mood: "premium, clear, product-focused, modern",
    },
    {
      kind: "feature" as const,
      title: `Key feature 1 / ${selectedFeatures[1].title}`,
      feature: selectedFeatures[1],
      mood: "focused, polished, legible, modern",
    },
    {
      kind: "feature" as const,
      title: `Key feature 2 / ${selectedFeatures[2].title}`,
      feature: selectedFeatures[2],
      mood: "confident, energetic, clean, modern",
    },
  ];

  return screenSeeds.map((screen, index) => {
    const screenshotPath = insights.screenshots.length > 0 ? insights.screenshots[index % insights.screenshots.length] : null;
    const copy = buildScreenCopy(screen.feature, insights, screen.kind, index);
    const slug = slugify(`${index + 1}-${screen.title}`);
    const prompt = buildBackgroundPrompt(
      {
        feature: screen.feature.title,
        mood: screen.mood,
      },
      insights,
    );
    return {
      kind: screen.kind,
      title: screen.title,
      feature: screen.feature.title,
      headline: copy.headline,
      subheadline: copy.subheadline,
      mood: screen.mood,
      index: index + 1,
      slug,
      prompt,
      screenshotPath,
      screenshotSource: screenshotPath ? relativePath(screenshotPath) : "placeholder: app-store-input/screenshots is empty",
      targetSize: options.targetSize,
      outputBackgroundPath: path.join(options.outputDir, "backgrounds", `${slug}-${options.targetSizeKey}-background.png`),
      outputFinalPath: path.join(options.outputDir, "final", `${slug}-${options.targetSizeKey}.png`),
      draftOnly: screenshotPath === null,
    };
  });
}

function selectPlanFeatures(insights: RepoInsights): DetectedFeature[] {
  const fallbacks: DetectedFeature[] = [
    {
      title: insights.appName,
      description: `Draft marketing image for ${insights.appName}. Add product copy to README.md, docs, or app-store-input/brand.json for a more specific plan.`,
      source: "fallback",
    },
    {
      title: "Key feature",
      description: "Highlight one concrete feature from the app with a real UI screenshot.",
      source: "fallback",
    },
    {
      title: "Designed for iPhone",
      description: "Show the app experience using real screenshots and short App Store-safe copy.",
      source: "fallback",
    },
  ];

  const usable = insights.features.length > 0 ? insights.features : fallbacks;
  const hero = usable[0] ?? fallbacks[0];
  const featureCandidates = usable
    .slice(1)
    .filter((feature) => !/^(core value proposition|product description|overview)$/i.test(feature.title))
    .filter((feature) => !isIgnoredFeatureTitle(feature.title))
    .filter((feature) => !/```|xcodebuild|npm install|swift build|deriveddata/i.test(feature.description))
    .sort((left, right) => featurePlanScore(right) - featurePlanScore(left));

  return [
    hero,
    featureCandidates[0] ?? usable[1] ?? hero ?? fallbacks[1],
    featureCandidates[1] ?? usable[2] ?? featureCandidates[0] ?? hero ?? fallbacks[2],
  ];
}

function featurePlanScore(feature: DetectedFeature): number {
  const text = `${feature.title} ${feature.description}`.toLowerCase();
  let score = 0;
  if (/website|marketing|app-store/.test(feature.source.toLowerCase())) score += 3;
  if (/keyword scan/.test(feature.source.toLowerCase())) score += 1;
  if (/custom|personal|profile|template|theme|layout|sync|share|export|import|connect|pair|secure|private|offline|automation|workflow|shortcut|dashboard|insight|fast|realtime|low latency|controller/.test(text)) score += 4;
  if (/\bios\b|iphone|mobile|app/.test(text)) score += 2;
  if (/macos|desktop|helper/.test(text)) score -= 1;
  if (/core value proposition|product description/.test(feature.title.toLowerCase())) score += 2;
  if (feature.description.length > 220) score -= 1;
  return score;
}

function buildScreenCopy(
  feature: DetectedFeature,
  insights: RepoInsights,
  kind: ScreenPlan["kind"],
  index: number,
): { headline: string; subheadline: string } {
  const descriptionSentence = firstSentence(feature.description) ?? feature.description;
  const genericTitle = /^(core value proposition|product description|overview)$/i.test(feature.title);
  const headlineSource = genericTitle ? headlineFromSentence(descriptionSentence, insights.appName) : feature.title;
  const fallbackHeadline = kind === "hero" ? `${insights.appName}, ready to share.` : `Feature ${index + 1}`;

  return {
    headline: sentenceCase(trimCopy(headlineSource, 64) || fallbackHeadline),
    subheadline: trimCopy(descriptionSentence, 104) || `Add a short, concrete benefit for ${insights.appName}.`,
  };
}

function headlineFromSentence(sentence: string, appName: string): string {
  const turnsMatch = sentence.match(new RegExp(`^${escapeRegExp(appName)}\\s+turns\\s+(.+?)\\s+into\\s+(.+?)(?:[.!?]|$)`, "i"));
  if (turnsMatch?.[1] && turnsMatch?.[2]) {
    return `Turn ${turnsMatch[1]} into ${turnsMatch[2]}`;
  }

  const withoutAppName = sentence
    .replace(new RegExp(`^${escapeRegExp(appName)}\\s+(is|helps|lets|gives|brings|makes)?\\s*`, "i"), "")
    .trim();
  const cleaned = withoutAppName || sentence;
  const beforeComma = cleaned.split(/[,.;:]/)[0]?.trim() ?? cleaned;
  return beforeComma;
}

function buildBackgroundPrompt(
  screen: Pick<ScreenPlan, "feature" | "mood">,
  insights: RepoInsights,
): string {
  const colors = [
    insights.brandColors.primaryColor,
    insights.brandColors.secondaryColor,
    insights.brandColors.accentColor,
  ].join(", ");
  const design = insights.designLanguage.length > 0 ? insights.designLanguage.join("; ") : "clean modern iOS utility design";
  const tone = insights.brandConfigPath ? "match the provided brand settings" : "repo-aware first draft";

  return [
    `Abstract premium iOS App Store marketing background for a ${insights.category} app called ${insights.appName}.`,
    `Feature focus: ${screen.feature}.`,
    `Use brand colors ${colors}.`,
    `Visual direction: ${design}.`,
    `Mood: ${screen.mood}; ${tone}; soft depth; subtle gradients; clean modern composition; tasteful geometric/decorative elements.`,
    "Leave clear space for a phone mockup and headline.",
    "No text, no letters, no numbers, no logos, no app UI, no phone UI, no screens.",
    "High quality, portrait mobile marketing background.",
  ].join(" ");
}

function printPlan(
  insights: RepoInsights,
  plan: ScreenPlan[],
  options: CliOptions,
  plannedImageGenerations: number,
): void {
  console.log("Repo-aware App Store image plan");
  console.log("=================================");
  console.log(`Mode: ${options.dryRun ? "dry-run (no paid AI calls)" : "generate (paid AI calls enabled)"}`);
  console.log(`App: ${insights.appName} (${insights.appNameSource})`);
  console.log(`Category: ${insights.category}`);
  console.log(
    `Brand colors: primary ${insights.brandColors.primaryColor}, secondary ${insights.brandColors.secondaryColor}, accent ${insights.brandColors.accentColor}`,
  );
  console.log(`Screenshots found: ${insights.screenshots.length}`);
  if (insights.screenshots.length === 0) {
    console.log("No real app screenshots found. Final generated images will be marked draft-only with placeholders.");
  }
  console.log(`Planned image generations: ${plannedImageGenerations}`);
  console.log("Provider: OpenAI direct Images API");
  console.log(`Model: ${options.model}`);
  console.log(`Quality: ${options.quality}`);
  console.log(`AI background size: ${DEFAULT_AI_BACKGROUND_SIZE}`);
  console.log(`Output target: ${options.targetSizeKey} (${options.targetSize.label})`);
  console.log(`Max images: ${options.maxImages}`);
  console.log(`Max variants per screen: ${options.maxVariantsPerScreen}`);

  console.log("\nDetected feature hints:");
  for (const feature of insights.features.slice(0, 6)) {
    console.log(`- ${feature.title}: ${feature.description} (${feature.source})`);
  }

  console.log("\nScreens:");
  for (const screen of plan) {
    console.log(`\n${screen.index}. ${screen.title}`);
    console.log(`   Headline: ${screen.headline}`);
    console.log(`   Subheadline: ${screen.subheadline}`);
    console.log(`   Screenshot: ${screen.screenshotSource}`);
    console.log(`   Prompt: ${screen.prompt}`);
  }
}

function validateCostControls(plan: ScreenPlan[], options: CliOptions, plannedImageGenerations: number): void {
  if (plannedImageGenerations > options.maxImages) {
    throw new Error(
      `Refusing to continue: planned image generations (${plannedImageGenerations}) exceed --max-images (${options.maxImages}).`,
    );
  }

  const variantsPerScreen = 1;
  if (variantsPerScreen > options.maxVariantsPerScreen) {
    throw new Error(
      `Refusing to continue: planned variants per screen (${variantsPerScreen}) exceed --max-variants-per-screen (${options.maxVariantsPerScreen}).`,
    );
  }

  const duplicateOutputs = new Set<string>();
  for (const screen of plan) {
    for (const outputPath of [screen.outputBackgroundPath, screen.outputFinalPath]) {
      if (duplicateOutputs.has(outputPath)) {
        throw new Error(`Duplicate output path in plan: ${relativePath(outputPath)}`);
      }
      duplicateOutputs.add(outputPath);
    }
  }
}

function preflightOutputFiles(plan: ScreenPlan[], force: boolean): void {
  if (force) return;
  const existing = plan
    .flatMap((screen) => [screen.outputBackgroundPath, screen.outputFinalPath])
    .filter((outputPath) => fs.existsSync(outputPath));

  if (existing.length > 0) {
    throw new Error(
      `Refusing to overwrite existing output files without --force:\n${existing.map((file) => `- ${relativePath(file)}`).join("\n")}`,
    );
  }
}

function getOpenAIApiKey(required: true): string;
function getOpenAIApiKey(required?: false): string | undefined;
function getOpenAIApiKey(required = false): string | undefined {
  if (process.env.OPENAI_API_KEY?.trim()) {
    return process.env.OPENAI_API_KEY.trim();
  }

  if (cachedOpenAIApiKey) {
    return cachedOpenAIApiKey;
  }

  try {
    const key = execFileSync(
      "security",
      ["find-generic-password", "-a", OPENAI_KEYCHAIN_ACCOUNT, "-s", OPENAI_KEYCHAIN_SERVICE, "-w"],
      { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] },
    ).trim();
    if (key) {
      cachedOpenAIApiKey = key;
      return key;
    }
  } catch {
    // Missing keychain item, locked keychain, or non-macOS environment. The caller handles the missing key.
  }

  if (required) {
    throw new Error(
      "OPENAI_API_KEY is missing and no appstore-ai-images key was found in macOS Keychain. Export OPENAI_API_KEY or run `npm --prefix scripts/app-store-images run store-key` first.",
    );
  }
  return undefined;
}

function getOpenAICredentialSource(): "env" | "keychain" | "missing" {
  if (process.env.OPENAI_API_KEY?.trim()) return "env";
  return getOpenAIApiKey(false) ? "keychain" : "missing";
}

async function generateBackground(prompt: string, options: CliOptions): Promise<Buffer> {
  const { default: OpenAI } = await import("openai");
  const apiKey = getOpenAIApiKey(true);
  const client = new OpenAI({ apiKey });

  let lastError: unknown;
  for (let attempt = 0; attempt <= DEFAULT_RETRIES_PER_IMAGE; attempt += 1) {
    try {
      const request: Record<string, unknown> = {
        model: options.model,
        prompt,
        size: DEFAULT_AI_BACKGROUND_SIZE,
        n: 1,
        quality: options.quality,
      };
      if (options.seed !== undefined) request.seed = options.seed;

      const result = await client.images.generate(request as never);
      return await extractOpenAIImageBuffer(result);
    } catch (error) {
      lastError = error;
      if (attempt < DEFAULT_RETRIES_PER_IMAGE) {
        console.warn(`OpenAI image generation failed; retrying once. Reason: ${error instanceof Error ? error.message : String(error)}`);
      }
    }
  }

  throw new Error(`OpenAI image generation failed: ${lastError instanceof Error ? lastError.message : String(lastError)}`);
}

async function extractOpenAIImageBuffer(result: unknown): Promise<Buffer> {
  const record = result as Record<string, unknown>;
  const data = Array.isArray(record.data) ? record.data : [];
  const firstImage = data[0] as Record<string, unknown> | undefined;
  if (!firstImage) {
    throw new Error("OpenAI image generation returned no image data.");
  }

  if (typeof firstImage.b64_json === "string") {
    return Buffer.from(firstImage.b64_json, "base64");
  }

  if (typeof firstImage.url === "string") {
    const response = await fetch(firstImage.url);
    if (!response.ok) {
      throw new Error(`OpenAI returned an image URL, but download failed: ${response.status} ${response.statusText}`);
    }
    return Buffer.from(await response.arrayBuffer());
  }

  throw new Error("Could not extract b64_json or url from OpenAI image response.");
}

async function compositeFinalImage(screen: ScreenPlan, insights: RepoInsights, options: CliOptions): Promise<void> {
  const sharpModule = await import("sharp");
  const sharp = sharpModule.default;
  const { width, height } = options.targetSize;

  const textOverlay = Buffer.from(renderTextOverlaySvg(screen, insights, options.targetSize));
  const phoneLayer = await createPhoneLayer(sharp, screen, insights, options.targetSize);

  await sharp(screen.outputBackgroundPath)
    .resize(width, height, { fit: "cover", position: "center" })
    .composite([
      { input: textOverlay, left: 0, top: 0 },
      { input: phoneLayer.buffer, left: phoneLayer.left, top: phoneLayer.top },
    ])
    .png()
    .toFile(screen.outputFinalPath);
}

type SharpFactory = typeof sharpDefault;

async function createPhoneLayer(
  sharp: SharpFactory,
  screen: ScreenPlan,
  insights: RepoInsights,
  targetSize: TargetSize,
): Promise<{ buffer: Buffer; left: number; top: number }> {
  let isLandscape = false;
  if (screen.screenshotPath) {
    const metadata = await sharp(screen.screenshotPath).metadata();
    if (metadata.width && metadata.height) {
      isLandscape = metadata.width > metadata.height * 1.12;
    }
  }

  const useLargeMinimalPhone = !isLandscape && screen.phonePresentation === "large-minimal";
  const frameWidth = isLandscape
    ? Math.round(targetSize.width * 0.84)
    : Math.round(targetSize.width * (useLargeMinimalPhone ? 0.79 : 0.62));
  const frameHeight = isLandscape ? Math.round(frameWidth * 0.56) : Math.round(frameWidth * 2.04);
  const padding = useLargeMinimalPhone ? Math.max(6, Math.round(frameWidth * 0.008)) : Math.round(frameWidth * 0.045);
  const innerWidth = frameWidth - padding * 2;
  const innerHeight = frameHeight - padding * 2;
  const outerRadius = Math.round(frameWidth * (useLargeMinimalPhone ? 0.073 : 0.09));
  const innerRadius = Math.max(1, outerRadius - padding);
  const shadowPadding = Math.round(frameWidth * (useLargeMinimalPhone ? 0.04 : 0.055));
  const layerWidth = frameWidth + shadowPadding * 2;
  const layerHeight = frameHeight + shadowPadding * 2;

  const outerSvg = useLargeMinimalPhone
    ? Buffer.from(`
      <svg width="${layerWidth}" height="${layerHeight}" viewBox="0 0 ${layerWidth} ${layerHeight}" xmlns="http://www.w3.org/2000/svg">
        <defs>
          <filter id="phoneShadow" x="-20%" y="-20%" width="140%" height="150%">
            <feDropShadow dx="0" dy="18" stdDeviation="20" flood-color="#2B1838" flood-opacity="0.24"/>
          </filter>
        </defs>
        <rect x="${shadowPadding}" y="${shadowPadding}" width="${frameWidth}" height="${frameHeight}" rx="${outerRadius}" fill="#2A2230" filter="url(#phoneShadow)"/>
        <rect x="${shadowPadding}" y="${shadowPadding}" width="${frameWidth}" height="${frameHeight}" rx="${outerRadius}" fill="#2A2230" stroke="#FFFFFF" stroke-opacity="0.38" stroke-width="2"/>
        <rect x="${shadowPadding + padding}" y="${shadowPadding + padding}" width="${innerWidth}" height="${innerHeight}" rx="${innerRadius}" fill="${insights.brandColors.secondaryColor}"/>
      </svg>
    `)
    : Buffer.from(`
      <svg width="${layerWidth}" height="${layerHeight}" viewBox="0 0 ${layerWidth} ${layerHeight}" xmlns="http://www.w3.org/2000/svg">
        <rect x="${shadowPadding + 18}" y="${shadowPadding + 28}" width="${frameWidth - 36}" height="${frameHeight - 22}" rx="${outerRadius}" fill="#000000" opacity="0.28"/>
        <rect x="${shadowPadding}" y="${shadowPadding}" width="${frameWidth}" height="${frameHeight}" rx="${outerRadius}" fill="#11110F"/>
        <rect x="${shadowPadding + padding}" y="${shadowPadding + padding}" width="${innerWidth}" height="${innerHeight}" rx="${innerRadius}" fill="${insights.brandColors.secondaryColor}"/>
      </svg>
    `);

  const base = sharp(outerSvg).png();
  const innerLeft = shadowPadding + padding;
  const innerTop = shadowPadding + padding;
  const screenBuffer = screen.screenshotPath
    ? await roundedScreenshot(sharp, screen.screenshotPath, innerWidth, innerHeight, innerRadius)
    : await placeholderScreenshot(sharp, innerWidth, innerHeight, innerRadius, insights);

  const composites: Array<{ input: Buffer; left: number; top: number }> = [
    { input: screenBuffer, left: innerLeft, top: innerTop },
  ];

  if (screen.draftOnly) {
    composites.push({
      input: Buffer.from(renderDraftBadgeSvg(frameWidth, insights.brandColors.accentColor)),
      left: shadowPadding + Math.round(frameWidth * 0.06),
      top: shadowPadding + frameHeight - 92,
    });
  }

  const buffer = await base.composite(composites).png().toBuffer();
  const left = Math.round((targetSize.width - layerWidth) / 2);
  const top = isLandscape
    ? Math.round(targetSize.height * 0.47)
    : Math.round(targetSize.height * (useLargeMinimalPhone ? 0.305 : 0.36));

  return { buffer, left, top };
}

async function roundedScreenshot(
  sharp: SharpFactory,
  screenshotPath: string,
  width: number,
  height: number,
  radius: number,
): Promise<Buffer> {
  const screenshot = await sharp(screenshotPath).resize(width, height, { fit: "cover", position: "center" }).png().toBuffer();
  const mask = Buffer.from(`
    <svg width="${width}" height="${height}" xmlns="http://www.w3.org/2000/svg">
      <rect x="0" y="0" width="${width}" height="${height}" rx="${radius}" fill="#fff"/>
    </svg>
  `);
  return sharp(screenshot).composite([{ input: mask, blend: "dest-in" }]).png().toBuffer();
}

async function placeholderScreenshot(
  sharp: SharpFactory,
  width: number,
  height: number,
  radius: number,
  insights: RepoInsights,
): Promise<Buffer> {
  const background = insights.brandColors.secondaryColor;
  const ink = insights.brandColors.primaryColor;
  const accent = insights.brandColors.accentColor;
  const svg = `
    <svg width="${width}" height="${height}" xmlns="http://www.w3.org/2000/svg">
      <rect width="100%" height="100%" rx="${radius}" fill="${background}"/>
      <pattern id="grid" width="36" height="36" patternUnits="userSpaceOnUse">
        <path d="M 36 0 L 0 0 0 36" fill="none" stroke="${ink}" stroke-opacity="0.08" stroke-width="1"/>
      </pattern>
      <rect width="100%" height="100%" rx="${radius}" fill="url(#grid)"/>
      <rect x="${Math.round(width * 0.12)}" y="${Math.round(height * 0.28)}" width="${Math.round(width * 0.76)}" height="${Math.round(height * 0.28)}" rx="28" fill="#FFFFFF" opacity="0.5" stroke="${ink}" stroke-opacity="0.18"/>
      <circle cx="${Math.round(width * 0.32)}" cy="${Math.round(height * 0.68)}" r="${Math.round(width * 0.075)}" fill="${accent}"/>
      <circle cx="${Math.round(width * 0.50)}" cy="${Math.round(height * 0.68)}" r="${Math.round(width * 0.075)}" fill="${ink}" fill-opacity="0.88"/>
      <circle cx="${Math.round(width * 0.68)}" cy="${Math.round(height * 0.68)}" r="${Math.round(width * 0.075)}" fill="${accent}" fill-opacity="0.78"/>
      <text x="50%" y="${Math.round(height * 0.42)}" text-anchor="middle" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="${Math.round(width * 0.075)}" font-weight="700" fill="${ink}">Add app</text>
      <text x="50%" y="${Math.round(height * 0.50)}" text-anchor="middle" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="${Math.round(width * 0.075)}" font-weight="700" fill="${ink}">screenshot here</text>
      <text x="50%" y="${Math.round(height * 0.60)}" text-anchor="middle" font-family="-apple-system, BlinkMacSystemFont, sans-serif" font-size="${Math.round(width * 0.033)}" fill="${ink}" opacity="0.62">draft-only placeholder</text>
    </svg>
  `;
  return sharp(Buffer.from(svg)).png().toBuffer();
}

function renderTextOverlaySvg(screen: ScreenPlan, insights: RepoInsights, targetSize: TargetSize): string {
  const margin = Math.round(targetSize.width * 0.075);
  const panelX = margin;
  const panelY = Math.round(targetSize.height * 0.045);
  const panelWidth = targetSize.width - margin * 2;
  const panelHeight = Math.round(targetSize.height * 0.255);
  const headlineFont = Math.round(targetSize.width * 0.066);
  const subheadlineFont = Math.round(targetSize.width * 0.029);
  const eyebrowFont = Math.round(targetSize.width * 0.023);
  const maxHeadlineChars = Math.max(12, Math.floor(panelWidth / (headlineFont * 0.52)));
  const maxSubheadlineChars = Math.max(22, Math.floor(panelWidth / (subheadlineFont * 0.52)));
  const headlineLines = wrapWords(screen.headline, maxHeadlineChars).slice(0, 3);
  const subheadlineLines = wrapWords(screen.subheadline, maxSubheadlineChars).slice(0, 2);
  const headlineLineHeight = Math.round(headlineFont * 1.05);
  const subheadlineLineHeight = Math.round(subheadlineFont * 1.28);
  const headlineStartY = panelY + Math.round(panelHeight * 0.31);
  const subheadlineStartY = headlineStartY + headlineLines.length * headlineLineHeight + Math.round(targetSize.height * 0.025);
  const accent = insights.brandColors.accentColor;
  const paper = insights.brandColors.secondaryColor;

  return `
    <svg width="${targetSize.width}" height="${targetSize.height}" viewBox="0 0 ${targetSize.width} ${targetSize.height}" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="fade" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="#000000" stop-opacity="0.36"/>
          <stop offset="1" stop-color="#000000" stop-opacity="0"/>
        </linearGradient>
      </defs>
      <rect x="0" y="0" width="${targetSize.width}" height="${Math.round(targetSize.height * 0.56)}" fill="url(#fade)"/>
      <rect x="${panelX}" y="${panelY}" width="${panelWidth}" height="${panelHeight}" rx="48" fill="#11110F" opacity="0.72"/>
      <rect x="${panelX + 34}" y="${panelY + 34}" width="72" height="8" rx="4" fill="${accent}"/>
      <text x="${panelX + 34}" y="${panelY + 88}" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="${eyebrowFont}" font-weight="700" letter-spacing="4" fill="${accent}">${escapeXml(insights.appName.toUpperCase())}</text>
      ${headlineLines
        .map(
          (line, lineIndex) =>
            `<text x="${panelX + 34}" y="${headlineStartY + lineIndex * headlineLineHeight}" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="${headlineFont}" font-weight="750" letter-spacing="-3" fill="${paper}">${escapeXml(line)}</text>`,
        )
        .join("\n")}
      ${subheadlineLines
        .map(
          (line, lineIndex) =>
            `<text x="${panelX + 38}" y="${subheadlineStartY + lineIndex * subheadlineLineHeight}" font-family="-apple-system, BlinkMacSystemFont, sans-serif" font-size="${subheadlineFont}" font-weight="500" fill="${paper}" opacity="0.86">${escapeXml(line)}</text>`,
        )
        .join("\n")}
    </svg>
  `;
}

function renderDraftBadgeSvg(frameWidth: number, accent: string): string {
  const width = Math.round(frameWidth * 0.52);
  const height = 54;
  return `
    <svg width="${width}" height="${height}" xmlns="http://www.w3.org/2000/svg">
      <rect x="0" y="0" width="${width}" height="${height}" rx="27" fill="#11110F" opacity="0.84"/>
      <circle cx="28" cy="27" r="9" fill="${accent}"/>
      <text x="48" y="35" font-family="-apple-system, BlinkMacSystemFont, sans-serif" font-size="21" font-weight="700" fill="#fff">DRAFT ONLY</text>
    </svg>
  `;
}

function buildManifest(
  insights: RepoInsights,
  plan: ScreenPlan[],
  options: CliOptions,
  plannedImageGenerations: number,
  filesCreated: string[],
): Manifest {
  const noScreenshots = insights.screenshots.length === 0;
  const assumptions = [
    "AI is used only for abstract backgrounds and visual treatments; app UI is either a real screenshot or a draft placeholder.",
    "Marketing copy was derived from repo product copy and feature names where available, and avoids unverifiable ranking claims.",
  ];
  if (noScreenshots) {
    assumptions.push("No real app screenshots were found, so final images are draft-only placeholders and should not be submitted as-is.");
  }
  if (!fs.existsSync(options.brandFile)) {
    assumptions.push("No app-store-input/brand.json was found; detected repo colors and design hints were used.");
  }

  return {
    timestamp: new Date().toISOString(),
    appName: insights.appName,
    appNameSource: insights.appNameSource,
    repoRoot,
    detectedFeatures: insights.features,
    detectedBrandColors: insights.brandColors,
    typographyHints: insights.typographyHints,
    designLanguage: insights.designLanguage,
    selectedScreenshotSources: plan.map((screen) => ({
      screen: screen.title,
      path: screen.screenshotPath ? relativePath(screen.screenshotPath) : null,
      source: screen.screenshotSource,
    })),
    generatedPrompts: plan.map((screen) => ({ screen: screen.title, prompt: screen.prompt })),
    model: options.model,
    quality: options.quality,
    aiGeneration: {
      provider: "openai-direct",
      credentialSource: getOpenAICredentialSource(),
      dryRun: options.dryRun,
      paid: !options.dryRun,
      plannedImageGenerations,
      aiBackgroundSize: DEFAULT_AI_BACKGROUND_SIZE,
      aiBackgroundAspectRatio: aspectRatio(DEFAULT_AI_BACKGROUND_SIZE),
      maxImages: options.maxImages,
      maxVariantsPerScreen: options.maxVariantsPerScreen,
      retriesPerImage: DEFAULT_RETRIES_PER_IMAGE,
      seed: options.seed,
    },
    outputDimensions: options.targetSize,
    supportedTargetSizes: Object.keys(TARGET_SIZES),
    draftOnly: noScreenshots,
    assumptions,
    filesCreated: [...filesCreated, relativePath(path.join(options.outputDir, "manifest.json"))],
  };
}

function writeManifest(outputDir: string, manifest: Manifest): string {
  const manifestPath = path.join(outputDir, "manifest.json");
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
  return manifestPath;
}

function aspectRatio(size: string): string {
  const [width, height] = size.split("x").map(Number);
  if (!width || !height) return "unknown";
  const divisor = gcd(width, height);
  return `${width / divisor}:${height / divisor}`;
}

function gcd(a: number, b: number): number {
  return b === 0 ? a : gcd(b, a % b);
}

function ensureDirectory(directory: string): void {
  fs.mkdirSync(directory, { recursive: true });
}

function ensureBrandExample(): void {
  const examplePath = path.join(repoRoot, "app-store-input/brand.example.json");
  if (fs.existsSync(examplePath)) return;
  const example = {
    appName: "App Name",
    primaryColor: "#000000",
    secondaryColor: "#ffffff",
    accentColor: "#4F46E5",
    fontFamily: "system",
    category: "productivity",
    tone: "premium, calm, modern",
  };
  fs.writeFileSync(examplePath, `${JSON.stringify(example, null, 2)}\n`);
}

function readTextIfExists(filePath: string): string | undefined {
  try {
    if (!fs.existsSync(filePath)) return undefined;
    const stat = fs.statSync(filePath);
    if (stat.size > 1_500_000) return undefined;
    return fs.readFileSync(filePath, "utf8");
  } catch {
    return undefined;
  }
}

function readJsonIfExists<T>(filePath: string): T | undefined {
  const text = readTextIfExists(filePath);
  if (!text) return undefined;
  try {
    return JSON.parse(text) as T;
  } catch {
    return undefined;
  }
}

function discoverFilesByName(name: string, maxDepth: number): string[] {
  return walkFiles(repoRoot, maxDepth).filter((file) => path.basename(file) === name);
}

function relativePath(filePath: string): string {
  return path.relative(repoRoot, filePath) || ".";
}

function slugify(value: string): string {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80);
}

function wrapWords(text: string, maxChars: number): string[] {
  const words = text.split(/\s+/).filter(Boolean);
  const lines: string[] = [];
  let current = "";

  for (const word of words) {
    const candidate = current ? `${current} ${word}` : word;
    if (candidate.length > maxChars && current) {
      lines.push(current);
      current = word;
    } else {
      current = candidate;
    }
  }

  if (current) lines.push(current);
  return lines.length > 0 ? lines : [text];
}

function firstMeaningfulParagraph(text: string): string | undefined {
  return text
    .split(/\n\s*\n/)
    .map((block) => stripMarkdown(stripHtml(block)).replace(/\s+/g, " ").trim())
    .find((block) => block.length > 35 && !/^#+\s/.test(block));
}

function firstSentence(text: string): string | undefined {
  const clean = stripMarkdown(stripHtml(text)).replace(/\s+/g, " ").trim();
  const match = clean.match(/^(.{20,220}?[.!?])(?:\s|$)/);
  return (match?.[1] ?? clean.slice(0, 220)).trim() || undefined;
}

function firstSentenceMatching(text: string, pattern: RegExp): string | undefined {
  const clean = stripMarkdown(stripHtml(text)).replace(/\s+/g, " ").trim();
  const sentences = clean.match(/[^.!?]{20,220}[.!?]/g) ?? [];
  return sentences.find((sentence) => pattern.test(sentence));
}

function trimCopy(value: string, maxChars: number): string {
  const clean = value.replace(/\s+/g, " ").trim().replace(/[.!?:;,]+$/g, "");
  if (clean.length <= maxChars) return clean;
  const truncated = clean.slice(0, maxChars - 1);
  return `${truncated.slice(0, Math.max(0, truncated.lastIndexOf(" "))).trim()}…`;
}

function sentenceCase(value: string): string {
  const clean = value.trim();
  if (!clean) return clean;
  if (clean.length > 1 && /[A-Z]/.test(clean[1])) return clean;
  if (/^[a-z]+[A-Z]/.test(clean.split(/\s+/)[0] ?? "")) return clean;
  if (/[a-z]/.test(clean.slice(1))) return `${clean[0].toUpperCase()}${clean.slice(1)}`;
  return clean;
}

function stripMarkdown(value: string): string {
  return value
    .replace(/```[\s\S]*?```/g, " ")
    .replace(/`([^`]+)`/g, "$1")
    .replace(/^#{1,6}\s+/gm, "")
    .replace(/!\[[^\]]*\]\([^)]*\)/g, " ")
    .replace(/\[([^\]]+)\]\([^)]*\)/g, "$1")
    .replace(/[>*_~]/g, " ");
}

function stripHtml(value: string): string {
  return value.replace(/<[^>]+>/g, " ").replace(/&nbsp;/g, " ").replace(/&amp;/g, "&").replace(/&quot;/g, '"');
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function escapeXml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

main().catch((error) => {
  console.error(`\nError: ${error instanceof Error ? error.message : String(error)}`);
  process.exit(1);
});
