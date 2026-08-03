#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const DIST = path.join(ROOT, 'dist');

async function read(relative) {
  return fs.readFile(path.join(DIST, relative), 'utf8');
}

const [
  englishLanding,
  spanishLanding,
  spanishPrivacy,
  spanishTerms,
  englishDocsHome,
  spanishDocsHome,
  spanishIphone,
  spanishAndroid,
  spanishConfiguration,
  englishFallbackPeer,
  spanishFallback,
  rootSitemap,
  docsSitemap,
] = await Promise.all([
  read('index.html'),
  read('es/index.html'),
  read('es/privacy-policy.html'),
  read('es/terms-of-service.html'),
  read('docs/index.html'),
  read('es/docs/index.html'),
  read('es/docs/iphone-first-export/index.html'),
  read('es/docs/android/index.html'),
  read('es/docs/configuration/index.html'),
  read('docs/mcp/index.html'),
  read('es/docs/mcp/index.html'),
  read('sitemap.xml'),
  read('sitemap-0.xml'),
]);

assert.match(englishLanding, /<html lang="en">/);
assert.match(englishLanding, /hreflang="es" href="https:\/\/healthmd\.app\/es\/"/);
assert.match(spanishLanding, /<html lang="es" dir="ltr">/);
assert.match(spanishLanding, /<link rel="canonical" href="https:\/\/healthmd\.app\/es\/">/);
assert.match(spanishLanding, /<meta property="og:locale" content="es_ES">/);
assert.match(spanishLanding, /Impulsa<br>tu salud\./);
assert.match(spanishLanding, /assets\/store-badges\/es\/download-on-app-store\.svg/);
assert.match(spanishLanding, /assets\/store-badges\/es\/get-it-on-google-play\.png/);
assert.match(spanishLanding, /assets\/screenshots\/showcase\/es\/scheduled-exports\.png/);
assert.match(spanishLanding, /id="healthmd-landing-messages"/);
assert.match(spanishLanding, /aria-label="Archivo de muestra listo"/);
assert.match(spanishLanding, /Frecuencia cardíaca en reposo<\/td><td>58 lpm/);
assert.doesNotMatch(spanishLanding, /Move your<br>health forward|Your data\. Your rules\.|Download a sample/);

for (const [page, canonical] of [
  [spanishPrivacy, 'https://healthmd.app/es/privacy-policy.html'],
  [spanishTerms, 'https://healthmd.app/es/terms-of-service.html'],
]) {
  assert.match(page, /<html lang="es" dir="ltr">/);
  assert.ok(page.includes(`<link rel="canonical" href="${canonical}">`));
  assert.ok(page.includes(`<meta property="og:url" content="${canonical}">`));
  assert.match(page, /<meta property="og:locale" content="es_ES">/);
  assert.match(page, /<meta property="og:locale:alternate" content="en_US">/);
  assert.match(page, /hreflang="en"/);
  assert.match(page, /hreflang="es"/);
  assert.match(page, /La versión en inglés|versión en inglés/i);
}

assert.match(englishDocsHome, /<link rel="canonical" href="https:\/\/healthmd\.app\/docs\/"\/>/);
assert.match(englishDocsHome, /hreflang="es" href="https:\/\/healthmd\.app\/es\/docs\/"/);
for (const page of [spanishDocsHome, spanishIphone, spanishAndroid, spanishConfiguration]) {
  assert.match(page, /<html lang="es" dir="ltr"/);
  assert.doesNotMatch(page, /<meta name="robots" content="noindex,follow"/);
  assert.match(page, /hreflang="en"/);
  assert.match(page, /hreflang="es"/);
  assert.doesNotMatch(page, /Esta página aún no está disponible en tu idioma/);
}
assert.match(spanishDocsHome, /<link rel="canonical" href="https:\/\/healthmd\.app\/es\/docs\/"\/>/);
assert.match(spanishDocsHome, /https:\/\/healthmd\.app\/docs\/social\/docs-og-es\.png/);
assert.match(spanishDocsHome, /Seleccionar idioma/);
assert.match(spanishDocsHome, /Primeros pasos/);
assert.match(spanishDocsHome, /Ventana de terminal/);
assert.match(spanishDocsHome, /title="Copiar al portapapeles"/);
assert.match(spanishDocsHome, /data-copied="¡Copiado!"/);
assert.doesNotMatch(spanishDocsHome, /Terminal window|Copy to clipboard/);
assert.match(spanishIphone, /Primera exportación desde el iPhone/);
assert.match(spanishIphone, /\/docs\/assets\/docs\/es\/iphone-first-export\/metric-selection\.webp/);
assert.match(spanishAndroid, /play\.google\.com\/store\/apps\/details\?id=com\.healthmd\.android(?:&amp;|&#x26;)hl=es/);
assert.match(spanishConfiguration, /Configura tu agente/);

assert.doesNotMatch(englishFallbackPeer, /hreflang="es"/);
assert.match(spanishFallback, /<meta name="robots" content="noindex,follow"\/>/);
assert.match(spanishFallback, /<link rel="canonical" href="https:\/\/healthmd\.app\/docs\/mcp\/"\/>/);
assert.doesNotMatch(spanishFallback, /hreflang="es"/);
assert.match(spanishFallback, /Esta página aún no está disponible en tu idioma/);

for (const url of [
  'https://healthmd.app/es/',
  'https://healthmd.app/es/privacy-policy.html',
  'https://healthmd.app/es/terms-of-service.html',
]) {
  assert.ok(rootSitemap.includes(`<loc>${url}</loc>`), `Root sitemap must include ${url}`);
}
for (const url of [
  'https://healthmd.app/es/docs/',
  'https://healthmd.app/es/docs/iphone-first-export/',
  'https://healthmd.app/es/docs/android/',
  'https://healthmd.app/es/docs/configuration/',
]) {
  assert.ok(docsSitemap.includes(`<loc>${url}</loc>`), `Docs sitemap must include ${url}`);
}
assert.doesNotMatch(docsSitemap, /<loc>https:\/\/healthmd\.app\/es\/docs\/mcp\/<\/loc>/);
assert.doesNotMatch(rootSitemap, /https:\/\/healthmd\.app\/es\/visualizations\//);

const spanishHtml = [];
async function walk(directory) {
  for (const entry of await fs.readdir(directory, { withFileTypes: true })) {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) await walk(absolute);
    else if (entry.isFile() && entry.name.endsWith('.html')) spanishHtml.push(absolute);
  }
}
await walk(path.join(DIST, 'es'));
let indexable = 0;
for (const file of spanishHtml) {
  const html = await fs.readFile(file, 'utf8');
  assert.match(html, /<html lang="es"/);
  if (!/<meta name="robots" content="noindex,follow"\/?>(?:<\/meta>)?/.test(html)) indexable += 1;
}
assert.equal(indexable, 7, 'Spanish launch must expose exactly seven indexable pages');

await Promise.all([
  'assets/store-badges/es/download-on-app-store.svg',
  'assets/store-badges/es/get-it-on-google-play.png',
  'assets/samples/es/health-data-sample.md',
  'assets/samples/es/health-data-sample-obsidian.md',
  'assets/screenshots/showcase/es/scheduled-exports.png',
  'docs/assets/docs/es/iphone-first-export/metric-selection.webp',
  'docs/assets/docs/es/iphone-first-export/export-preview.webp',
  'docs/social/docs-og-es.png',
].map((relative) => fs.access(path.join(DIST, relative))));

console.log(`Built Spanish localization is valid: ${indexable} indexable pages and ${spanishHtml.length - indexable} noindex fallbacks.`);
