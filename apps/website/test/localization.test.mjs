import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { hasSpanishDocTranslation, docsEntryId } from '../i18n/routes.mjs';
import { assertCatalogParity, loadCatalog, renderLanding } from '../scripts/build-localized-pages.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const [source, english, spanish] = await Promise.all([
  readFile(path.join(ROOT, 'index.html'), 'utf8'),
  loadCatalog('en'),
  loadCatalog('es'),
]);

test('Spanish catalog matches English and renders a fully localized landing route', () => {
  assert.doesNotThrow(() => assertCatalogParity(english, spanish));
  const html = renderLanding(source, 'es', english, spanish);
  assert.match(html, /<html lang="es" dir="ltr">/);
  assert.match(html, /<link rel="canonical" href="https:\/\/healthmd\.app\/es\/">/);
  assert.match(html, /hreflang="x-default" href="https:\/\/healthmd\.app\/">/);
  assert.match(html, /Impulsa<br>tu salud\./);
  assert.match(html, /Health\.md no almacena tus datos de salud/);
  assert.match(html, /href="\/es\/docs\/configuration\/"/);
  assert.match(html, /id="healthmd-locale-redirect"/);
  assert.doesNotMatch(html, /header-language-link|>English<\/a>/);
  assert.match(html, /assets\/store-badges\/es\/download-on-app-store\.svg/);
  assert.match(html, /assets\/screenshots\/showcase\/es\/scheduled-exports\.png/);
  assert.match(html, /"intlLocale":"es"/);
  const schema = JSON.parse(html.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/)[1]);
  const runtime = JSON.parse(html.match(/<script id="healthmd-landing-messages" type="application\/json">([\s\S]*?)<\/script>/)[1]);
  assert.equal(schema.inLanguage, 'es');
  assert.equal(schema.url, 'https://healthmd.app/es/');
  assert.equal(runtime.intlLocale, 'es');
  assert.equal(runtime.downloadNone, 'Descargar muestras');
  assert.equal(runtime.heartRateUnit, 'lpm');
  assert.match(html, /aria-label="Archivo de muestra listo"/);
  assert.match(html, /Frecuencia cardíaca en reposo<\/td><td>58 lpm/);
  assert.doesNotMatch(html, /Move your<br>health forward|Your data\. Your rules\.|Choose when Health\.md exports/);
});

test('docs IDs preserve English routes and place Spanish before the docs segment', () => {
  assert.equal(docsEntryId('index.md'), 'docs');
  assert.equal(docsEntryId('configuration.md'), 'docs/configuration');
  assert.equal(docsEntryId('reference/generated/index.md'), 'docs/reference/generated');
  assert.equal(docsEntryId('es/index.md'), 'es/docs');
  assert.equal(docsEntryId('es/configuration.md'), 'es/docs/configuration');
});

test('only the Spanish first-success docs are treated as real translations', () => {
  for (const pathname of [
    '/docs/',
    '/es/docs/',
    '/docs/iphone-first-export/',
    '/es/docs/android/',
    '/es/docs/configuration/',
  ]) {
    assert.equal(hasSpanishDocTranslation(pathname), true, pathname);
  }
  assert.equal(hasSpanishDocTranslation('/docs/mcp/'), false);
  assert.equal(hasSpanishDocTranslation('/es/docs/reference/'), false);
});

test('Spanish first-success docs use localized assets and current Android limits', async () => {
  const [englishAndroid, spanishAndroid, spanishIphone] = await Promise.all([
    readFile(path.join(ROOT, 'docs-src/src/content/docs/android.md'), 'utf8'),
    readFile(path.join(ROOT, 'docs-src/src/content/docs/es/android.md'), 'utf8'),
    readFile(path.join(ROOT, 'docs-src/src/content/docs/es/iphone-first-export.md'), 'utf8'),
  ]);

  assert.match(englishAndroid, /<strong>10<\/strong><span>free manual export actions/);
  assert.match(spanishAndroid, /<strong>10<\/strong><span>acciones gratuitas de exportación manual/);
  assert.match(spanishAndroid, /Alarmas y recordatorios de Android/);
  assert.match(spanishAndroid, /WorkManager como respaldo duradero/);
  assert.doesNotMatch(spanishAndroid, /3 acciones (?:gratuitas )?de exportación/);
  assert.match(spanishIphone, /\/docs\/assets\/docs\/es\/iphone-first-export\/metric-selection\.webp/);
  assert.match(spanishIphone, /\*\*Carpeta local del iPhone\*\*/);
});
