#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { defaultLocale, enabledLocales, localeFor } from '../i18n/locales.mjs';
import { routes, translatedDocSlugs } from '../i18n/routes.mjs';
import { assertCatalogParity, loadCatalog, renderLanding } from './build-localized-pages.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const english = await loadCatalog('en');
const spanish = await loadCatalog('es');
assertCatalogParity(english, spanish);
assert.equal(defaultLocale, 'en');
assert.deepEqual(enabledLocales, ['en', 'es']);
assert.equal(localeFor('es').lang, 'es');
assert.equal(localeFor('es').dir, 'ltr');

const routePaths = Object.values(routes).flatMap((route) => Object.values(route));
assert.equal(new Set(routePaths).size, routePaths.length, 'Localized routes must be unique');
assert.deepEqual(translatedDocSlugs, [
  'docs',
  'docs/iphone-first-export',
  'docs/android',
  'docs/configuration',
]);

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

const englishStrings = new Map(stringsAt(english.landing));
const spanishStrings = new Map(stringsAt(spanish.landing));
for (const [key, source] of englishStrings) {
  const translation = spanishStrings.get(key);
  assert.equal(typeof translation, 'string', `Missing Spanish string ${key}`);
  assert.ok(translation.trim(), `Empty Spanish string ${key}`);
  assert.deepEqual(placeholders(translation), placeholders(source), `Placeholder mismatch for ${key}`);
}

const landingSource = await fs.readFile(path.join(ROOT, 'index.html'), 'utf8');
const spanishLanding = renderLanding(landingSource, 'es', english, spanish);
assert.match(spanishLanding, /<html lang="es" dir="ltr">/);
assert.match(spanishLanding, /<h1 id="hero-title">Impulsa<br>tu salud\.<\/h1>/);
assert.match(spanishLanding, /href="\/es\/docs\/"[^>]*>Documentación<\/a>/);
assert.match(spanishLanding, /hreflang="en" lang="en">English<\/a>/);
assert.match(spanishLanding, /aria-label="Archivo de muestra listo"/);
assert.match(spanishLanding, /Frecuencia cardíaca en reposo<\/td><td>58 lpm/);
assert.match(spanishLanding, /https:\/\/healthmd\.app\/es\//);
assert.doesNotMatch(spanishLanding, /Move your<br>health forward|Your data\. Your rules\.|Download a sample/);

const requiredFiles = [
  'assets/store-badges/es/download-on-app-store.svg',
  'assets/store-badges/es/get-it-on-google-play.png',
  'assets/samples/es/health-data-sample.md',
  'assets/samples/es/health-data-sample-obsidian.md',
  'assets/screenshots/showcase/es/scheduled-exports.png',
  'docs-src/public/assets/docs/es/iphone-first-export/metric-selection.webp',
  'docs-src/public/assets/docs/es/iphone-first-export/export-preview.webp',
  'docs-src/public/social/docs-og-es.png',
  'es/privacy-policy.html',
  'es/terms-of-service.html',
  'docs-src/src/content/docs/es/index.md',
  'docs-src/src/content/docs/es/iphone-first-export.md',
  'docs-src/src/content/docs/es/android.md',
  'docs-src/src/content/docs/es/configuration.md',
];
await Promise.all(requiredFiles.map((relative) => fs.access(path.join(ROOT, relative))));

function countTag(html, tag) {
  return (html.match(new RegExp(`<${tag}\\b`, 'gi')) ?? []).length;
}

for (const filename of ['privacy-policy.html', 'terms-of-service.html']) {
  const [source, translation] = await Promise.all([
    fs.readFile(path.join(ROOT, filename), 'utf8'),
    fs.readFile(path.join(ROOT, 'es', filename), 'utf8'),
  ]);
  assert.equal(countTag(translation, 'h2'), countTag(source, 'h2'), `${filename} must preserve every legal section`);
  assert.equal(countTag(translation, 'li'), countTag(source, 'li'), `${filename} must preserve every legal list item`);
  assert.match(translation, /<html lang="es" dir="ltr">/);
  assert.match(translation, /Aviso sobre la traducción/);
  assert.match(translation, /versión en inglés/i);
  assert.match(translation, new RegExp(`https://healthmd\\.app/es/${filename.replace('.', '\\.')}`));
  assert.doesNotMatch(translation, /\b(?:TODO|TBD)\b/);
}

function fencedBlocks(markdown) {
  return [...markdown.matchAll(/```[^\n]*\n[\s\S]*?```/g)].map((match) => match[0]);
}

for (const filename of ['index.md', 'iphone-first-export.md', 'android.md', 'configuration.md']) {
  const [source, translation] = await Promise.all([
    fs.readFile(path.join(ROOT, 'docs-src/src/content/docs', filename), 'utf8'),
    fs.readFile(path.join(ROOT, 'docs-src/src/content/docs/es', filename), 'utf8'),
  ]);
  assert.deepEqual(fencedBlocks(translation), fencedBlocks(source), `${filename} must preserve fenced technical examples`);
  assert.match(translation, /^---[\s\S]*?title:\s*[^\n]+/);
  assert.doesNotMatch(translation, /\]\(\/docs\/(?:iphone-first-export|android|configuration)\/\)/, `${filename} must link translated peers through /es/docs/`);
}

console.log('Website Spanish locale catalogs, routes, assets, and protected documentation examples are valid.');
