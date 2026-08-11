#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  authoredDocSlugs,
  defaultLocale,
  enabledLocales,
  localeFor,
  publishedLocales,
} from '../i18n/locales.mjs';
import { docsSidebar } from '../i18n/docs-ui.mjs';
import { routePath, routes } from '../i18n/routes.mjs';
import {
  assertCatalogParity,
  loadCatalog,
  renderLanding,
} from './build-localized-pages.mjs';
import { renderLocalizedSitemap } from './build-localized-sitemap.mjs';
import { expectedVercelConfig, VERCEL_CONFIG } from './build-vercel-config.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const DOCS_SOURCE_ROOT = path.join(ROOT, 'docs-src/src/content/docs');
const authoredDocFilenames = (await fs.readdir(DOCS_SOURCE_ROOT, { withFileTypes: true }))
  .filter((entry) => entry.isFile() && entry.name.endsWith('.md'))
  .map(({ name }) => name)
  .sort();
const discoveredAuthoredDocSlugs = authoredDocFilenames.map((filename) => (
  filename === 'index.md' ? 'docs' : `docs/${path.basename(filename, '.md')}`
)).sort();
assert.deepEqual(
  [...authoredDocSlugs].sort(),
  discoveredAuthoredDocSlugs,
  'authoredDocSlugs must cover every authored top-level documentation file',
);
const authoredDocSlugSet = new Set(authoredDocSlugs);
const authoredSidebarSlugs = docsSidebar
  .flatMap(({ items }) => items)
  .map(({ slug }) => ['docs', slug].filter(Boolean).join('/'))
  .filter((slug) => authoredDocSlugSet.has(slug));
assert.deepEqual(
  [...new Set(authoredSidebarSlugs)].sort(),
  [...authoredDocSlugs].sort(),
  'Every authored documentation guide must appear in the localized sidebar',
);
assert.equal(authoredSidebarSlugs.length, authoredDocSlugs.length, 'Authored sidebar entries must be unique');
const expectedLocales = ['en', 'es', 'de', 'fr', 'pt-br', 'it', 'nl', 'ja', 'ko', 'zh-hans'];
assert.equal(defaultLocale, 'en');
assert.deepEqual(enabledLocales, expectedLocales);
assert.deepEqual(publishedLocales('landing').map(({ code }) => code), expectedLocales);
assert.deepEqual(publishedLocales('docs').map(({ code }) => code), expectedLocales);
assert.deepEqual(publishedLocales('legal').map(({ code }) => code), expectedLocales);
assert.deepEqual(
  publishedLocales('redirect').map(({ code }) => code),
  expectedLocales.filter((code) => code !== defaultLocale),
);

function parseCsv(source) {
  const rows = [];
  let row = [];
  let field = '';
  let quoted = false;
  for (let index = 0; index < source.length; index += 1) {
    const character = source[index];
    if (character === '"') {
      if (quoted && source[index + 1] === '"') {
        field += '"';
        index += 1;
      } else quoted = !quoted;
    } else if (character === ',' && !quoted) {
      row.push(field);
      field = '';
    } else if (character === '\n' && !quoted) {
      row.push(field.replace(/\r$/, ''));
      rows.push(row);
      row = [];
      field = '';
    } else field += character;
  }
  if (field || row.length) {
    row.push(field.replace(/\r$/, ''));
    rows.push(row);
  }
  assert.equal(quoted, false, 'Glossary CSV has an unterminated quoted field');
  return rows;
}

const glossaryRows = parseCsv(await fs.readFile(path.join(ROOT, 'i18n/glossary.csv'), 'utf8'));
const glossaryHeader = ['source', 'context', 'translate', ...expectedLocales.filter((code) => code !== defaultLocale)];
assert.deepEqual(glossaryRows[0], glossaryHeader, 'Glossary must cover every non-English locale');
for (const [index, row] of glossaryRows.slice(1).entries()) {
  assert.equal(row.length, glossaryHeader.length, `Glossary row ${index + 2} has the wrong column count`);
  assert.ok(row.every((value) => value.trim()), `Glossary row ${index + 2} contains an empty value`);
  if (row[2] === 'no') {
    for (const value of row.slice(3)) assert.equal(value, row[0], `Glossary row ${index + 2} must preserve ${row[0]}`);
  }
}
const bpmGlossaryRow = glossaryRows.find((row) => row[0] === 'bpm');
assert.ok(bpmGlossaryRow, 'Glossary must define the human-facing heart-rate unit');

const localeConfigs = enabledLocales.map(localeFor);
for (const group of docsSidebar) {
  for (const locale of localeConfigs) {
    assert.ok(group.labels[locale.code]?.trim(), `Missing ${locale.code} documentation sidebar group label`);
    for (const entry of group.items) {
      assert.ok(entry.labels[locale.code]?.trim(), `Missing ${locale.code} documentation sidebar label for ${entry.slug || 'docs'}`);
    }
  }
}
for (const field of ['code', 'lang', 'intlLocale', 'ogLocale', 'label']) {
  const values = localeConfigs.map((locale) => locale[field]);
  assert.equal(new Set(values).size, values.length, `Locale ${field} values must be unique`);
}
const localizedPaths = localeConfigs.filter(({ path }) => path).map(({ path }) => path);
assert.equal(new Set(localizedPaths).size, localizedPaths.length, 'Locale URL paths must be unique');
const browserExactOwners = new Map();
for (const locale of localeConfigs) {
  assert.ok(locale.browser.exact.length > 0, `${locale.code} must declare exact browser language tags`);
  for (const value of locale.browser.exact) {
    const normalized = value.toLowerCase().replaceAll('_', '-');
    const owner = browserExactOwners.get(normalized);
    assert.ok(!owner || owner === locale.code, `Browser language ${value} is claimed by ${owner} and ${locale.code}`);
    browserExactOwners.set(normalized, locale.code);
  }
}
const browserAliasOwners = new Map();
for (const locale of localeConfigs) {
  for (const value of locale.browser.aliases) {
    const normalized = value.toLowerCase().replaceAll('_', '-');
    const exactOwner = browserExactOwners.get(normalized);
    assert.ok(!exactOwner || exactOwner === locale.code, `Browser alias ${value} conflicts with ${exactOwner}'s exact tag`);
    const aliasOwner = browserAliasOwners.get(normalized);
    assert.ok(!aliasOwner || aliasOwner === locale.code, `Browser alias ${value} is claimed by ${aliasOwner} and ${locale.code}`);
    browserAliasOwners.set(normalized, locale.code);
  }
}
const firstExportScreenshotFields = [
  'firstExportOnboardingScreenshot',
  'firstExportMetricScreenshot',
  'firstExportPreviewScreenshot',
];
const defaultAssets = localeFor(defaultLocale).assets;
const requiredLocalizedAssetFields = [
  'appStoreBadge',
  'playStoreBadge',
  'scheduleScreenshot',
  'firstExportMetricScreenshot',
  'firstExportPreviewScreenshot',
  'docsOgImage',
];
for (const locale of localeConfigs) {
  assert.ok(['ltr', 'rtl'].includes(locale.dir), `${locale.code} has an invalid direction`);
  assert.equal(locale.surfaces.docs, locale.surfaces.landing, `${locale.code} docs and landing publication must move together`);
  assert.deepEqual(
    [...locale.translatedDocSlugs].sort(),
    [...authoredDocSlugs].sort(),
    `${locale.code} must publish every authored documentation guide`,
  );
  for (const fallback of locale.assetFallbacks) {
    assert.ok(fallback in locale.assets, `${locale.code} declares an unknown asset fallback: ${fallback}`);
    assert.equal(
      locale.assets[fallback],
      defaultAssets[fallback],
      `${locale.code} fallback ${fallback} must use the canonical English asset`,
    );
  }
  for (const [field, expectedHost] of [['appleUrl', 'apps.apple.com'], ['googleUrl', 'play.google.com']]) {
    const marketplaceUrl = new URL(locale.marketplace[field]);
    assert.equal(marketplaceUrl.protocol, 'https:', `${locale.code} ${field} must use HTTPS`);
    assert.equal(marketplaceUrl.hostname, expectedHost, `${locale.code} ${field} must use ${expectedHost}`);
  }
  if (locale.code !== defaultLocale) {
    for (const field of requiredLocalizedAssetFields) {
      assert.notEqual(locale.assets[field], defaultAssets[field], `${locale.code} must provide a localized ${field}`);
    }
    assert.ok(
      locale.assetFallbacks.includes('firstExportOnboardingScreenshot'),
      `${locale.code} must disclose the onboarding screenshot's English foreground UI`,
    );
  }
  for (const field of firstExportScreenshotFields) {
    if (locale.code !== defaultLocale && locale.assets[field] === defaultAssets[field]) {
      assert.ok(locale.assetFallbacks.includes(field), `${locale.code} must explicitly approve its English ${field} fallback`);
    }
  }
}

const routePaths = Object.values(routes).flatMap((route) => Object.values(route));
assert.equal(new Set(routePaths).size, routePaths.length, 'Localized routes must be unique');

function stringsAt(value, prefix = '') {
  if (typeof value === 'string') return [[prefix, value]];
  if (Array.isArray(value)) return value.flatMap((child, index) => stringsAt(child, `${prefix}[${index}]`));
  if (value && typeof value === 'object') {
    return Object.entries(value).flatMap(([key, child]) => stringsAt(child, prefix ? `${prefix}.${key}` : key));
  }
  return [];
}

function placeholders(value) {
  return [...value.matchAll(/\{([a-zA-Z][a-zA-Z0-9_]*)\}/g)].map((match) => match[1]).sort();
}

const englishProseMarkers = /\b(?:the|and|with|from|your|you|for|this|that|when|where|into|without|uses?|can|will|is|are|of|to)\b/gi;

const english = await loadCatalog(defaultLocale);
const landingSource = await fs.readFile(path.join(ROOT, 'index.html'), 'utf8');
const landingLocales = publishedLocales('landing');
for (const locale of landingLocales) {
  const catalog = await loadCatalog(locale.code);
  if (locale.code !== defaultLocale) assertCatalogParity(english, catalog);
  assert.equal(catalog.landing.runtime.intlLocale, locale.intlLocale, `${locale.code} Intl locale drift`);
  const samplePrefix = locale.path ? `/assets/samples/${locale.path}` : '/assets/samples';
  assert.equal(
    catalog.landing.runtime.sampleMarkdownHref,
    `${samplePrefix}/health-data-sample.md`,
    `${locale.code} Markdown sample route drift`,
  );
  assert.equal(
    catalog.landing.runtime.sampleObsidianHref,
    `${samplePrefix}/health-data-sample-obsidian.md`,
    `${locale.code} Obsidian sample route drift`,
  );

  const sourceStrings = new Map(stringsAt(english.landing));
  const translatedStrings = new Map(stringsAt(catalog.landing));
  for (const [key, source] of sourceStrings) {
    const translation = translatedStrings.get(key);
    assert.equal(typeof translation, 'string', `Missing ${locale.code} string ${key}`);
    assert.ok(translation.trim(), `Empty ${locale.code} string ${key}`);
    assert.deepEqual(placeholders(translation), placeholders(source), `Placeholder mismatch for ${locale.code}:${key}`);
    if (locale.code !== defaultLocale && source.length >= 25) {
      const markerCount = (source.match(englishProseMarkers) ?? []).length;
      assert.ok(
        translation !== source || markerCount < 2,
        `${locale.code} landing string ${key} contains unchanged English prose`,
      );
    }
  }

  const html = renderLanding(landingSource, locale.code, english, catalog);
  const homePath = locale.path ? `/${locale.path}/` : '/';
  const canonical = `https://healthmd.app${homePath}`;
  assert.match(html, new RegExp(`<html lang="${locale.lang}" dir="${locale.dir}">`));
  assert.ok(html.includes(`<link rel="canonical" href="${canonical}">`));
  assert.ok(html.includes(`<meta property="og:locale" content="${locale.ogLocale}">`));
  assert.ok(html.includes(`aria-label="${locale.ui.languageSelector}"`));
  assert.ok(html.includes(`aria-current="page" lang="${locale.lang}">${locale.label}</span>`));
  assert.ok(html.includes(locale.assets.appStoreBadge));
  assert.ok(html.includes(locale.assets.playStoreBadge));
  assert.ok(html.includes(`href="${locale.marketplace.appleUrl.replaceAll('&', '&amp;')}"`));
  assert.ok(html.includes(`href="${locale.marketplace.googleUrl.replaceAll('&', '&amp;')}"`));
  assert.ok(html.includes(locale.assets.scheduleScreenshot));
  assert.ok(
    html.includes(`href="${catalog.landing.runtime.sampleMarkdownHref}" download data-sample-download`),
    `${locale.code} landing must expose its localized Markdown sample without JavaScript`,
  );
  const legalLocale = locale.surfaces.legal ? locale.code : defaultLocale;
  assert.ok(
    html.includes(`href="${routePath('privacy', legalLocale)}">${catalog.landing.static.privacy}</a>`),
    `${locale.code} landing must link to its published privacy policy`,
  );
  assert.ok(
    html.includes(`href="${routePath('terms', legalLocale)}">${catalog.landing.static.terms}</a>`),
    `${locale.code} landing must link to its published terms`,
  );
  for (const alternate of landingLocales) {
    const alternatePath = alternate.path ? `/${alternate.path}/` : '/';
    assert.ok(
      html.includes(`hreflang="${alternate.lang}" href="https://healthmd.app${alternatePath}"`),
      `${locale.code} landing is missing ${alternate.lang} hreflang`,
    );
  }
  assert.ok(html.includes('hreflang="x-default" href="https://healthmd.app/"'));
}

const requiredSharedFiles = [
  'assets/screenshots/showcase/scheduled-exports.png',
  'docs-src/public/social/docs-og.png',
];
const requiredLocaleFiles = landingLocales.flatMap((locale) => {
  const files = [
    locale.assets.appStoreBadge.replace(/^\//, ''),
    locale.assets.playStoreBadge.replace(/^\//, ''),
    locale.assets.scheduleScreenshot.replace(/^\//, ''),
    locale.assets.docsOgImage.replace(/^\/docs\//, 'docs-src/public/'),
    ...firstExportScreenshotFields.map((field) => (
      locale.assets[field].replace(/^\/docs\//, 'docs-src/public/')
    )),
  ];
  if (locale.code !== defaultLocale) {
    files.push(
      `assets/samples/${locale.path}/health-data-sample.md`,
      `assets/samples/${locale.path}/health-data-sample-obsidian.md`,
      ...authoredDocFilenames
        .map((filename) => `docs-src/src/content/docs/${locale.path}/${filename}`),
    );
  }
  return files;
});
await Promise.all([...new Set([...requiredSharedFiles, ...requiredLocaleFiles])]
  .map((relative) => fs.access(path.join(ROOT, relative))));

async function pngDimensions(relative) {
  const bytes = await fs.readFile(path.join(ROOT, relative));
  assert.equal(bytes.subarray(0, 8).toString('hex'), '89504e470d0a1a0a', `${relative} must be a PNG`);
  return [bytes.readUInt32BE(16), bytes.readUInt32BE(20)];
}

async function webpDimensions(relative) {
  const bytes = await fs.readFile(path.join(ROOT, relative));
  assert.equal(bytes.subarray(0, 4).toString('ascii'), 'RIFF', `${relative} must be a RIFF WebP`);
  assert.equal(bytes.subarray(8, 12).toString('ascii'), 'WEBP', `${relative} must be a WebP`);
  const chunk = bytes.subarray(12, 16).toString('ascii');
  if (chunk === 'VP8X') {
    const width = bytes[24] | (bytes[25] << 8) | (bytes[26] << 16);
    const height = bytes[27] | (bytes[28] << 8) | (bytes[29] << 16);
    return [width + 1, height + 1];
  }
  if (chunk === 'VP8 ') return [bytes.readUInt16LE(26) & 0x3fff, bytes.readUInt16LE(28) & 0x3fff];
  if (chunk === 'VP8L') {
    const bits = bytes.readUInt32LE(21);
    return [(bits & 0x3fff) + 1, ((bits >>> 14) & 0x3fff) + 1];
  }
  throw new Error(`${relative} uses unsupported WebP chunk ${JSON.stringify(chunk)}`);
}

for (const locale of landingLocales) {
  const appStoreBadgePath = locale.assets.appStoreBadge.replace(/^\//, '');
  const appStoreBadge = await fs.readFile(path.join(ROOT, appStoreBadgePath), 'utf8');
  assert.match(appStoreBadge, /<svg\b[^>]*\bheight="40"/i, `${locale.code} App Store badge must use official 40px SVG artwork`);
  assert.doesNotMatch(appStoreBadge, /<script\b/i, `${locale.code} App Store badge must not contain scripts`);
  assert.deepEqual(
    await pngDimensions(locale.assets.scheduleScreenshot.replace(/^\//, '')),
    [1206, 2622],
    `${locale.code} schedule capture must be a full-size authentic app screenshot`,
  );
  assert.deepEqual(
    await pngDimensions(locale.assets.docsOgImage.replace(/^\/docs\//, 'docs-src/public/')),
    [1200, 630],
    `${locale.code} docs social card must be 1200×630`,
  );
  assert.deepEqual(
    await pngDimensions(locale.assets.playStoreBadge.replace(/^\//, '')),
    [646, 250],
    `${locale.code} Google Play badge must preserve the official artwork dimensions`,
  );
  for (const field of firstExportScreenshotFields) {
    assert.deepEqual(
      await webpDimensions(locale.assets[field].replace(/^\/docs\//, 'docs-src/public/')),
      [1206, 2622],
      `${locale.code} ${field} must preserve the full app-capture dimensions`,
    );
  }
}

const [englishSample, englishObsidianSample] = await Promise.all([
  fs.readFile(path.join(ROOT, 'assets/samples/health-data-sample.md'), 'utf8'),
  fs.readFile(path.join(ROOT, 'assets/samples/health-data-sample-obsidian.md'), 'utf8'),
]);
const englishObsidianFrontmatter = englishObsidianSample.match(/^---\n[\s\S]*?\n---/)?.[0];
assert.ok(englishObsidianFrontmatter, 'English Obsidian sample must have frontmatter');
for (const locale of localeConfigs.filter(({ code }) => code !== defaultLocale)) {
  const [sample, obsidianSample] = await Promise.all([
    fs.readFile(path.join(ROOT, `assets/samples/${locale.path}/health-data-sample.md`), 'utf8'),
    fs.readFile(path.join(ROOT, `assets/samples/${locale.path}/health-data-sample-obsidian.md`), 'utf8'),
  ]);
  assert.notEqual(sample, englishSample, `${locale.code} Markdown sample must be translated`);
  assert.notEqual(obsidianSample, englishObsidianSample, `${locale.code} Obsidian sample must be translated`);
  assert.ok(!sample.includes('August 2, 2026'), `${locale.code} Markdown sample must localize its visible date`);
  assert.equal(
    (sample.match(/^\|.*\|$/gm) ?? []).length,
    (englishSample.match(/^\|.*\|$/gm) ?? []).length,
    `${locale.code} Markdown sample must preserve its table structure`,
  );
  assert.equal(
    (obsidianSample.match(/^-\s+/gm) ?? []).length,
    (englishObsidianSample.match(/^-\s+/gm) ?? []).length,
    `${locale.code} Obsidian sample must preserve its metric list`,
  );
  assert.equal(
    obsidianSample.match(/^---\n[\s\S]*?\n---/)?.[0],
    englishObsidianFrontmatter,
    `${locale.code} Obsidian sample must preserve technical frontmatter`,
  );
  for (const [name, content] of [['Markdown', sample], ['Obsidian', obsidianSample]]) {
    assert.match(content, /8(?:[.,\u00a0\u202f ]?421)/u, `${locale.code} ${name} sample must preserve 8,421 steps`);
    assert.match(content, /7\D{0,20}42/u, `${locale.code} ${name} sample must preserve 7 hours 42 minutes`);
    const localizedBpm = bpmGlossaryRow[glossaryHeader.indexOf(locale.code)];
    const heartRatePattern = new RegExp(`58\\s*(?:bpm|${escapeRegExp(localizedBpm)})`, 'iu');
    assert.match(content, heartRatePattern, `${locale.code} ${name} sample must preserve 58 beats per minute`);
    assert.match(content, /4[.,]1\s*mi\b/iu, `${locale.code} ${name} sample must preserve 4.1 miles`);
    assert.doesNotMatch(content, /\b(?:6[.,]6|6[.,]60)\s*km\b/iu, `${locale.code} ${name} sample must not convert miles`);
    assert.doesNotMatch(content, /\b(?:steps|hr)\b/i, `${locale.code} ${name} sample must localize human-facing unit labels`);
  }
  assert.ok(!obsidianSample.includes('[[Health Dashboard]]'), `${locale.code} Obsidian sample must localize its wiki label`);

  const localizedEntries = await fs.readdir(path.join(DOCS_SOURCE_ROOT, locale.path), { withFileTypes: true });
  assert.deepEqual(
    localizedEntries.filter((entry) => entry.isFile() && entry.name.endsWith('.md')).map(({ name }) => name).sort(),
    authoredDocFilenames,
    `${locale.code} must translate exactly the authored guide set`,
  );
  assert.ok(
    localizedEntries.every((entry) => !entry.isDirectory()),
    `${locale.code} must not localize generated reference directories`,
  );
}

function countTag(html, tag) {
  return (html.match(new RegExp(`<${tag}\\b`, 'gi')) ?? []).length;
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function tagBlocks(html, tag) {
  return [...html.matchAll(new RegExp(`<${tag}\\b[^>]*>([\\s\\S]*?)<\\/${tag}>`, 'gi'))]
    .map((match) => match[1]);
}

function tagText(html, tag) {
  return tagBlocks(html, tag)[0]?.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
}

function legalSectionIds(html) {
  return [...html.matchAll(/<section\b[^>]*\bid="([^"]+)"/gi)].map((match) => match[1]);
}

for (const locale of localeConfigs.filter(({ code }) => code !== defaultLocale)) {
  for (const filename of ['privacy-policy.html', 'terms-of-service.html']) {
    const [source, translation] = await Promise.all([
      fs.readFile(path.join(ROOT, filename), 'utf8'),
      fs.readFile(path.join(ROOT, locale.path, filename), 'utf8'),
    ]);
    if (locale.surfaces.legal) {
      assert.equal(countTag(translation, 'h2'), countTag(source, 'h2'), `${locale.code}/${filename} must preserve every legal section`);
      assert.equal(countTag(translation, 'li'), countTag(source, 'li'), `${locale.code}/${filename} must preserve every legal list item`);
      assert.deepEqual(legalSectionIds(translation), legalSectionIds(source), `${locale.code}/${filename} must preserve every legal section id`);
      assert.deepEqual(tagBlocks(translation, 'style'), tagBlocks(source, 'style'), `${locale.code}/${filename} must preserve inline styles`);
      assert.deepEqual(tagBlocks(translation, 'script'), tagBlocks(source, 'script'), `${locale.code}/${filename} must preserve inline scripts`);
    }
    assert.notEqual(tagText(translation, 'title'), tagText(source, 'title'), `${locale.code}/${filename} must translate its title`);
    assert.notEqual(tagText(translation, 'h1'), tagText(source, 'h1'), `${locale.code}/${filename} must translate its heading`);
    assert.match(
      translation,
      new RegExp(`<html\\b(?=[^>]*\\blang="${locale.lang}")(?=[^>]*\\bdir="${locale.dir}")[^>]*>`),
    );
    assert.match(
      translation,
      new RegExp(`<nav\\b(?=[^>]*\\bclass="language-selector")(?=[^>]*\\baria-label="${locale.ui.languageSelector}")[^>]*>`),
      `${locale.code}/${filename} must expose its localized language selector`,
    );
    const legalCanonical = `https://healthmd.app/${locale.path}/${filename}`;
    assert.match(
      translation,
      new RegExp(`<link\\b(?=[^>]*\\brel="canonical")(?=[^>]*\\bhref="${escapeRegExp(legalCanonical)}")[^>]*>`),
      `${locale.code}/${filename} must keep its self canonical`,
    );
    assert.match(
      translation,
      new RegExp(`<meta\\b(?=[^>]*\\bproperty="og:url")(?=[^>]*\\bcontent="${escapeRegExp(legalCanonical)}")[^>]*>`),
      `${locale.code}/${filename} must keep its Open Graph URL`,
    );
    assert.match(
      translation,
      new RegExp(`<meta\\b(?=[^>]*\\bproperty="og:locale")(?=[^>]*\\bcontent="${escapeRegExp(locale.ogLocale)}")[^>]*>`),
      `${locale.code}/${filename} must keep its Open Graph locale`,
    );
    assert.ok(
      translation.includes('.language-selector {') || translation.includes('assets/legal.css'),
      `${locale.code}/${filename} must style its language selector`,
    );
    assert.match(
      translation,
      new RegExp(`<meta\\b(?=[^>]*\\bname="robots")(?=[^>]*\\bcontent="${locale.surfaces.legal ? 'index,follow' : 'noindex,follow'}")[^>]*>`),
      `${locale.code}/${filename} must reflect its legal publication state`,
    );
    assert.match(
      translation,
      /<a\b(?=[^>]*href="\.\.\/(?:privacy-policy|terms-of-service)\.html")(?=[^>]*hreflang="en")[^>]*>/i,
    );
    assert.doesNotMatch(translation, /<!DOCTYPE html>\s*html\s*<html/i);
    assert.doesNotMatch(translation, /\b(?:TODO|TBD)\b/);
  }
}

function fencedBlocks(markdown) {
  return [...markdown.matchAll(/```[^\n]*\n[\s\S]*?```/g)].map((match) => match[0]);
}

function withoutFencedBlocks(markdown) {
  return markdown.replace(/```[^\n]*\n[\s\S]*?```/g, '');
}

function inlineCode(markdown) {
  return [...markdown.matchAll(/(?<!`)`([^`\n]+)`(?!`)/g)].map((match) => match[1]);
}

function htmlCode(markdown) {
  return [...markdown.matchAll(/<code(?:\s[^>]*)?>([\s\S]*?)<\/code>/gi)].map((match) => match[1]);
}

function markdownDestinations(markdown) {
  return [...markdown.matchAll(/!?\[[^\]]*\]\(\s*(?:<([^>]+)>|([^\s)]+))(?:\s+["'][^)]*["'])?\s*\)/g)]
    .map((match) => match[1] ?? match[2]);
}

function htmlDestinations(markdown) {
  return [...markdown.matchAll(/\b(?:href|src)=(["'])(.*?)\1/gi)].map((match) => match[2]);
}

function localizedDocDestination(destination, locale) {
  const match = destination.match(/^(\/docs(?:\/[^?#]*)?)([?#].*)?$/);
  if (!match) return destination;
  const pathname = match[1].replace(/\/+$/, '');
  if (path.posix.extname(pathname)) return destination;
  return `/${locale.path}${match[1]}${match[2] ?? ''}`;
}

function expectedLocalizedDestination(destination, locale) {
  for (const field of firstExportScreenshotFields) {
    if (destination === defaultAssets[field]) return locale.assets[field];
  }
  return localizedDocDestination(destination, locale);
}

function frontmatterKeys(markdown) {
  const frontmatter = markdown.match(/^---\n([\s\S]*?)\n---/);
  assert.ok(frontmatter, 'documentation must start with YAML frontmatter');
  return [...frontmatter[1].matchAll(/^([A-Za-z][A-Za-z0-9_-]*):/gm)].map((match) => match[1]);
}

function frontmatterValue(markdown, key) {
  const frontmatter = markdown.match(/^---\n([\s\S]*?)\n---/);
  assert.ok(frontmatter, 'documentation must start with YAML frontmatter');
  return frontmatter[1].match(new RegExp(`^${key}:\\s*(.+)$`, 'm'))?.[1]?.trim();
}

function structuralSignature(markdown) {
  const prose = withoutFencedBlocks(markdown);
  return {
    headingLevels: [...prose.matchAll(/^(#{1,6})\s+/gm)].map((match) => match[1].length),
    unorderedItems: [...prose.matchAll(/^\s*[-+*]\s+/gm)].length,
    orderedItems: [...prose.matchAll(/^\s*\d+[.)]\s+/gm)].length,
    blockquotes: [...prose.matchAll(/^\s*>/gm)].length,
    tableRows: [...prose.matchAll(/^\s*\|.*\|\s*$/gm)].length,
    details: [...prose.matchAll(/<details\b/gi)].length,
    summaries: [...prose.matchAll(/<summary\b/gi)].length,
    images: [...prose.matchAll(/!\[[^\]]*\]\([^)]+\)/g)].length,
    htmlImages: [...prose.matchAll(/<img\b/gi)].length,
    htmlListItems: [...prose.matchAll(/<li\b/gi)].length,
  };
}

const protectedProductNames = ['Health.md', 'Apple Health', 'Health Connect', 'HealthKit', 'MCP', 'CLI', 'Full Access'];
const minimumTranslationSizeRatio = Object.freeze({ ja: 0.45, ko: 0.55, 'zh-hans': 0.35 });
const maximumTranslationSizeRatio = Object.freeze({ ja: 1.8, ko: 1.8, 'zh-hans': 1.6 });
const englishDisclosureMarkers = Object.freeze({
  es: /inglés/i,
  de: /englisch/i,
  fr: /anglais/i,
  'pt-br': /inglês/i,
  it: /inglese/i,
  nl: /engels/i,
  ja: /英語/,
  ko: /영어/,
  'zh-hans': /(?:英文|英语)/,
});

function likelyEnglishProseSegments(markdown) {
  return withoutFencedBlocks(markdown)
    .split('\n')
    .map((line) => line
      .replace(/`[^`\n]+`/g, '')
      .replace(/\]\([^)]*\)/g, ']')
      .replace(/<[^>]+>/g, ' ')
      .replace(/https?:\/\/\S+/g, ' ')
      .replace(/[*_#>|-]/g, ' ')
      .replace(/\s+/g, ' ')
      .trim())
    .filter((line) => line.length >= 35 && (line.match(englishProseMarkers) ?? []).length >= 2);
}

for (const locale of localeConfigs.filter(({ code }) => code !== defaultLocale)) {
  for (const filename of authoredDocFilenames) {
    const [source, translation] = await Promise.all([
      fs.readFile(path.join(DOCS_SOURCE_ROOT, filename), 'utf8'),
      fs.readFile(path.join(DOCS_SOURCE_ROOT, locale.path, filename), 'utf8'),
    ]);
    assert.notEqual(translation, source, `${locale.code}/${filename} must contain a real translation`);
    const sizeRatio = translation.length / source.length;
    assert.ok(
      sizeRatio >= (minimumTranslationSizeRatio[locale.code] ?? 0.9)
        && sizeRatio <= (maximumTranslationSizeRatio[locale.code] ?? 1.5),
      `${locale.code}/${filename} translation size ratio ${sizeRatio.toFixed(2)} suggests truncated or duplicated content`,
    );
    assert.deepEqual(frontmatterKeys(translation), frontmatterKeys(source), `${locale.code}/${filename} must preserve frontmatter keys`);
    assert.notEqual(
      frontmatterValue(translation, 'description'),
      frontmatterValue(source, 'description'),
      `${locale.code}/${filename} must translate its frontmatter description`,
    );
    assert.deepEqual(fencedBlocks(translation), fencedBlocks(source), `${locale.code}/${filename} must preserve fenced technical examples`);
    assert.deepEqual(inlineCode(translation), inlineCode(source), `${locale.code}/${filename} must preserve inline technical literals`);
    assert.deepEqual(htmlCode(translation), htmlCode(source), `${locale.code}/${filename} must preserve HTML code literals`);
    assert.deepEqual(structuralSignature(translation), structuralSignature(source), `${locale.code}/${filename} must preserve document structure`);
    const translatedSegments = new Set(likelyEnglishProseSegments(translation));
    const unchangedEnglish = likelyEnglishProseSegments(source).filter((segment) => translatedSegments.has(segment));
    assert.deepEqual(unchangedEnglish, [], `${locale.code}/${filename} contains likely untranslated English prose`);
    for (const literal of protectedProductNames) {
      if (source.includes(literal)) {
        assert.ok(translation.includes(literal), `${locale.code}/${filename} must preserve the ${literal} product name`);
      }
    }

    const sourceProse = withoutFencedBlocks(source);
    const translatedProse = withoutFencedBlocks(translation);
    assert.deepEqual(
      markdownDestinations(translatedProse),
      markdownDestinations(sourceProse).map((destination) => expectedLocalizedDestination(destination, locale)),
      `${locale.code}/${filename} must preserve and localize Markdown destinations`,
    );
    assert.deepEqual(
      htmlDestinations(translatedProse),
      htmlDestinations(sourceProse).map((destination) => expectedLocalizedDestination(destination, locale)),
      `${locale.code}/${filename} must preserve and localize HTML destinations`,
    );

    assert.match(translation, /^---[\s\S]*?title:\s*[^\n]+/);
    if (filename === 'iphone-first-export.md') {
      const disclosureMarker = englishDisclosureMarkers[locale.code];
      assert.ok(
        (translatedProse.match(new RegExp(disclosureMarker.source, `${disclosureMarker.flags}g`)) ?? []).length >= 2,
        `${locale.code}/${filename} must disclose both shared captures' English UI`,
      );
      assert.match(translatedProse, /\b217\b/, `${locale.code}/${filename} must describe the localized metric capture accurately`);
      assert.match(translatedProse, /\b219\b/, `${locale.code}/${filename} must describe the localized metric total accurately`);
      for (const field of firstExportScreenshotFields) {
        assert.ok(
          translation.includes(locale.assets[field]),
          `${locale.code}/${filename} must use its configured ${field}`,
        );
      }
    }
  }
}

const sitemapSource = await fs.readFile(path.join(ROOT, 'sitemap.xml'), 'utf8');
assert.equal(renderLocalizedSitemap(sitemapSource), sitemapSource, 'Localized sitemap blocks are stale; run npm run i18n:sitemap');
const [vercelSource, expectedVercel] = await Promise.all([
  fs.readFile(VERCEL_CONFIG, 'utf8'),
  expectedVercelConfig(),
]);
assert.equal(vercelSource, expectedVercel, 'Vercel locale redirects are stale; run npm run i18n:vercel');

console.log(`Website locale catalogs, routes, assets, legal drafts, and all ${authoredDocSlugs.length} authored documentation translations are valid for ${enabledLocales.join(', ')}.`);
