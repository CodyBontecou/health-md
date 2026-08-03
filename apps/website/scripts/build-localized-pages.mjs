#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { defaultLocale, localeFor } from '../i18n/locales.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const MESSAGE_DIR = path.join(ROOT, 'i18n', 'messages');
const LANDING_SOURCE = path.join(ROOT, 'index.html');

function flattenKeys(value, prefix = '') {
  if (Array.isArray(value)) return [[prefix, 'array', value.length]];
  if (value && typeof value === 'object') {
    return Object.entries(value).flatMap(([key, child]) =>
      flattenKeys(child, prefix ? `${prefix}.${key}` : key),
    );
  }
  return [[prefix, typeof value, null]];
}

export function assertCatalogParity(english, translation) {
  const englishShape = flattenKeys(english).filter(([key]) => key !== 'locale');
  const translatedShape = flattenKeys(translation).filter(([key]) => key !== 'locale');
  if (JSON.stringify(englishShape) !== JSON.stringify(translatedShape)) {
    throw new Error(`Translation catalog ${translation.locale ?? '<unknown>'} does not match the English key/type shape`);
  }
  if (translation.locale === defaultLocale) {
    throw new Error('A translation catalog must not reuse the default locale code');
  }
}

export async function loadCatalog(locale) {
  localeFor(locale);
  const raw = await fs.readFile(path.join(MESSAGE_DIR, `${locale}.json`), 'utf8');
  const catalog = JSON.parse(raw);
  if (catalog.locale !== locale) {
    throw new Error(`${locale}.json declares locale ${catalog.locale ?? '<missing>'}`);
  }
  return catalog;
}

function replaceStaticMessages(html, english, translation) {
  const entries = Object.keys(english.landing.static)
    .map((key) => [key, english.landing.static[key], translation.landing.static[key]])
    .sort((left, right) => right[1].length - left[1].length);

  const pending = [];
  for (const [index, [key, source, target]] of entries.entries()) {
    if (source === target) continue;
    if (!html.includes(source)) {
      throw new Error(`Landing source no longer contains i18n message ${key}: ${JSON.stringify(source)}`);
    }
    const marker = `___HEALTHMD_I18N_${index}___`;
    html = html.replaceAll(source, marker);
    pending.push([marker, target]);
  }
  for (const [marker, target] of pending) html = html.replaceAll(marker, target);
  return html;
}

function makeRootRelativeAssetsAbsolute(html) {
  return html.replace(
    /\b(href|src)="(?!#|\/|[a-z][a-z0-9+.-]*:)([^"]+)"/gi,
    (_match, attribute, value) => `${attribute}="/${value}"`,
  );
}

function injectRuntimeMessages(html, catalog) {
  const payload = JSON.stringify(catalog.landing.runtime)
    .replaceAll('<', '\\u003c')
    .replaceAll('\u2028', '\\u2028')
    .replaceAll('\u2029', '\\u2029');
  const script = `  <script id="healthmd-landing-messages" type="application/json">${payload}</script>\n`;
  const marker = /  <script src="(?:\/)?assets\/landing\.js" defer><\/script>\n/;
  if (!marker.test(html)) throw new Error('Landing source is missing the landing.js marker');
  return html.replace(marker, `${script}$&`);
}

function localizeLandingRoutes(html, locale) {
  if (locale === defaultLocale) return html;

  const config = localeFor(locale);
  html = makeRootRelativeAssetsAbsolute(html);
  html = html
    .replace('<html lang="en">', `<html lang="${config.lang}" dir="${config.dir}">`)
    .replace('<link rel="canonical" href="https://healthmd.app/">', '<link rel="canonical" href="https://healthmd.app/es/">')
    .replace('<meta property="og:url" content="https://healthmd.app/">', '<meta property="og:url" content="https://healthmd.app/es/">')
    .replace('"url": "https://healthmd.app/",', '"url": "https://healthmd.app/es/",')
    .replace('"inLanguage": "en",', '"inLanguage": "es",')
    .replace('<meta property="og:locale" content="en_US">', '<meta property="og:locale" content="es_ES">')
    .replace('<meta property="og:locale:alternate" content="es_ES">', '<meta property="og:locale:alternate" content="en_US">')
    .replace(/href="\/docs\//g, 'href="/es/docs/')
    .replace('href="/es/" hreflang="es" lang="es">English</a>', 'href="/" hreflang="en" lang="en">English</a>')
    .replaceAll('https://apps.apple.com/us/app/health-md/id6757763969', 'https://apps.apple.com/app/health-md/id6757763969?l=es')
    .replaceAll('https://play.google.com/store/apps/details?id=com.healthmd.android', 'https://play.google.com/store/apps/details?id=com.healthmd.android&hl=es')
    .replace('href="https://play.google.com/store/apps/details?id=com.healthmd.android&hl=es"', 'href="https://play.google.com/store/apps/details?id=com.healthmd.android&amp;hl=es"')
    .replace('/assets/store-badges/download-on-app-store.svg', '/assets/store-badges/es/download-on-app-store.svg')
    .replace('/assets/store-badges/get-it-on-google-play.png', '/assets/store-badges/es/get-it-on-google-play.png')
    .replace('/assets/screenshots/showcase/scheduled-exports.png', '/assets/screenshots/showcase/es/scheduled-exports.png');

  return html;
}

export function renderLanding(source, locale, english, translation) {
  let html = source;
  if (locale !== defaultLocale) {
    assertCatalogParity(english, translation);
    html = replaceStaticMessages(html, english, translation);
  }
  html = localizeLandingRoutes(html, locale);
  return injectRuntimeMessages(html, translation);
}

export async function buildLocalizedLanding({ outputRoot, locale = 'es' }) {
  const [source, english, translation] = await Promise.all([
    fs.readFile(LANDING_SOURCE, 'utf8'),
    loadCatalog(defaultLocale),
    loadCatalog(locale),
  ]);
  const destination = locale === defaultLocale
    ? path.join(outputRoot, 'index.html')
    : path.join(outputRoot, locale, 'index.html');
  await fs.mkdir(path.dirname(destination), { recursive: true });
  await fs.writeFile(destination, renderLanding(source, locale, english, translation));
  return destination;
}

const isDirectRun = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isDirectRun) {
  const outputFlag = process.argv.indexOf('--output');
  const outputRoot = outputFlag >= 0 && process.argv[outputFlag + 1]
    ? path.resolve(ROOT, process.argv[outputFlag + 1])
    : path.join(ROOT, 'dist');
  const localeFlag = process.argv.indexOf('--locale');
  const locale = localeFlag >= 0 && process.argv[localeFlag + 1] ? process.argv[localeFlag + 1] : 'es';
  const destination = await buildLocalizedLanding({ outputRoot, locale });
  console.log(`Built ${locale} landing page at ${path.relative(ROOT, destination)}`);
}
