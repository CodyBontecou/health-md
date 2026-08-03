#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  defaultLocale,
  localeFor,
  publishedLocales,
} from '../i18n/locales.mjs';
import { routePath } from '../i18n/routes.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const MESSAGE_DIR = path.join(ROOT, 'i18n', 'messages');
const LANDING_SOURCE = path.join(ROOT, 'index.html');
const SITE_ORIGIN = 'https://healthmd.app';
const APP_STORE_URL = 'https://apps.apple.com/us/app/health-md/id6757763969';
const PLAY_STORE_URL = 'https://play.google.com/store/apps/details?id=com.healthmd.android';

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

export function assertUniqueStaticMessages(english) {
  const owners = new Map();
  for (const [key, value] of Object.entries(english.landing.static)) {
    if (owners.has(value)) {
      throw new Error(`Landing i18n messages ${owners.get(value)} and ${key} use the same English source string`);
    }
    owners.set(value, key);
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

function htmlAttribute(value) {
  return String(value).replaceAll('&', '&amp;').replaceAll('"', '&quot;');
}

function absoluteUrl(pathname) {
  return new URL(pathname, SITE_ORIGIN).href;
}

function renderLandingLanguageSelector(locale, variantClass = '') {
  const current = localeFor(locale);
  const menuClass = ['language-menu', variantClass].filter(Boolean).join(' ');
  const entries = publishedLocales('landing').map((candidate) => {
    if (candidate.code === locale) {
      return `            <span aria-current="page" lang="${candidate.lang}">${candidate.label}</span>`;
    }
    return `            <a href="${routePath('home', candidate.code)}" hreflang="${candidate.lang}" lang="${candidate.lang}">${candidate.label}</a>`;
  });
  return [
    `        <details class="${menuClass}">`,
    `          <summary aria-label="${current.ui.languageSelector}"><span>${current.label}</span><span aria-hidden="true">⌄</span></summary>`,
    `          <nav class="language-selector" aria-label="${current.ui.languageSelector}">`,
    entries.join('\n'),
    '          </nav>',
    '        </details>',
  ].join('\n');
}

function localeRedirectBootstrap() {
  const localeManifest = publishedLocales('landing').map((locale) => ({
    code: locale.code,
    path: locale.path,
    exact: locale.browser.exact.map((value) => value.toLowerCase().replaceAll('_', '-')),
    aliases: locale.browser.aliases.map((value) => value.toLowerCase().replaceAll('_', '-')),
  }));
  const serialized = JSON.stringify(localeManifest).replaceAll('<', '\\u003c');

  return `    (() => {
      const { location, navigator } = window;
      if (!["http:", "https:"].includes(location.protocol)) return;

      const localeSessionKey = "healthmd-locale-detected";
      const locales = ${serialized};
      const normalizedPath = location.pathname.replace(/\\/index\\.html$/, "/");
      const localizedEntry = locales.find(({ path }) => path && normalizedPath === \`/\${path}/\`);
      let localeWasDetected = false;

      try {
        localeWasDetected = window.sessionStorage.getItem(localeSessionKey) === "1";
        if (localizedEntry) window.sessionStorage.setItem(localeSessionKey, "1");
      } catch {
        // Language detection still works when browser storage is unavailable.
      }

      if (localizedEntry) return;
      if (normalizedPath !== "/" || localeWasDetected) return;

      try {
        window.sessionStorage.setItem(localeSessionKey, "1");
      } catch {
        // Keep the default locale behavior when browser storage is unavailable.
      }

      const matchLanguage = (language) => {
        const normalized = String(language || "").toLowerCase().replaceAll("_", "-");
        const exact = locales.find((locale) => locale.exact.includes(normalized));
        if (exact) return exact;
        const base = normalized.split("-", 1)[0];
        return locales.find((locale) => locale.aliases.includes(normalized) || locale.aliases.includes(base));
      };
      const browserLanguages = navigator.languages?.length
        ? navigator.languages
        : [navigator.language];
      const preferredLocale = browserLanguages.map(matchLanguage).find(Boolean);

      if (preferredLocale?.path) {
        location.replace(\`/\${preferredLocale.path}/\${location.search}\${location.hash}\`);
      }
    })();`;
}

function injectLocaleRedirect(html) {
  const script = `<script id="healthmd-locale-redirect">\n${localeRedirectBootstrap()}\n  </script>`;
  const marker = /<script id="healthmd-locale-redirect">[\s\S]*?<\/script>/;
  if (!marker.test(html)) throw new Error('Landing source is missing the locale redirect marker');
  return html.replace(marker, script);
}

function replaceAlternateLinks(html, locale, routeId) {
  const alternates = publishedLocales('landing').map((candidate) =>
    `  <link rel="alternate" hreflang="${candidate.lang}" href="${absoluteUrl(routePath(routeId, candidate.code))}">`,
  );
  alternates.push(`  <link rel="alternate" hreflang="x-default" href="${absoluteUrl(routePath(routeId, defaultLocale))}">`);
  html = html.replace(/\n?  <link rel="alternate" hreflang="[^"]+" href="[^"]+">/g, '');
  const canonical = absoluteUrl(routePath(routeId, locale));
  return html.replace(
    /  <link rel="canonical" href="[^"]+">/,
    `  <link rel="canonical" href="${canonical}">\n${alternates.join('\n')}`,
  );
}

function replaceOpenGraphLocales(html, locale) {
  const current = localeFor(locale);
  const alternates = publishedLocales('landing')
    .filter(({ code }) => code !== locale)
    .map(({ ogLocale }) => `  <meta property="og:locale:alternate" content="${ogLocale}">`);
  html = html.replace(/\n?  <meta property="og:locale:alternate" content="[^"]+">/g, '');
  return html.replace(
    /  <meta property="og:locale" content="[^"]+">/,
    `  <meta property="og:locale" content="${current.ogLocale}">${alternates.length ? `\n${alternates.join('\n')}` : ''}`,
  );
}

function localizeLandingRoutes(html, locale, catalog) {
  const config = localeFor(locale);
  const homeUrl = absoluteUrl(routePath('home', locale));
  const legalLocale = config.surfaces.legal ? locale : defaultLocale;

  html = makeRootRelativeAssetsAbsolute(html);
  html = replaceAlternateLinks(html, locale, 'home');
  html = replaceOpenGraphLocales(html, locale);
  html = html
    .replace(/<html lang="[^"]+"(?: dir="[^"]+")?>/, `<html lang="${config.lang}" dir="${config.dir}">`)
    .replace(/<meta property="og:url" content="[^"]+">/, `<meta property="og:url" content="${homeUrl}">`)
    .replace('"url": "https://healthmd.app/",', `"url": "${homeUrl}",`)
    .replace('"inLanguage": "en",', `"inLanguage": "${config.lang}",`)
    .replace(/href="\/docs\//g, `href="${routePath('docsHome', locale)}`)
    .replaceAll('href="/privacy-policy.html"', `href="${routePath('privacy', legalLocale)}"`)
    .replaceAll('href="/terms-of-service.html"', `href="${routePath('terms', legalLocale)}"`)
    .replaceAll(APP_STORE_URL, config.marketplace.appleUrl)
    .replaceAll(PLAY_STORE_URL, config.marketplace.googleUrl)
    .replaceAll(`href="${config.marketplace.appleUrl}"`, `href="${htmlAttribute(config.marketplace.appleUrl)}"`)
    .replaceAll(`href="${config.marketplace.googleUrl}"`, `href="${htmlAttribute(config.marketplace.googleUrl)}"`)
    .replaceAll('/assets/store-badges/download-on-app-store.svg', config.assets.appStoreBadge)
    .replaceAll('/assets/store-badges/get-it-on-google-play.png', config.assets.playStoreBadge)
    .replace('/assets/screenshots/showcase/scheduled-exports.png', config.assets.scheduleScreenshot)
    .replace(
      'href="/assets/samples/health-data-sample.md" download data-sample-download',
      `href="${htmlAttribute(catalog.landing.runtime.sampleMarkdownHref)}" download data-sample-download`,
    );

  const languageMarker = /\s*<!-- HEALTHMD_LANGUAGE_SELECTOR -->/;
  if (!languageMarker.test(html)) throw new Error('Landing source is missing the language selector marker');
  html = html.replace(languageMarker, `\n${renderLandingLanguageSelector(locale)}`);

  const footerLanguageMarker = /\s*<!-- HEALTHMD_FOOTER_LANGUAGE_SELECTOR -->/;
  if (!footerLanguageMarker.test(html)) throw new Error('Landing source is missing the footer language selector marker');
  html = html.replace(
    footerLanguageMarker,
    `\n${renderLandingLanguageSelector(locale, 'footer-language-menu')}`,
  );
  return injectLocaleRedirect(html);
}

export function renderLanding(source, locale, english, translation) {
  assertUniqueStaticMessages(english);
  let html = source;
  if (locale !== defaultLocale) {
    assertCatalogParity(english, translation);
    html = replaceStaticMessages(html, english, translation);
  }
  html = localizeLandingRoutes(html, locale, translation);
  return injectRuntimeMessages(html, translation);
}

export async function buildLocalizedLanding({ outputRoot, locale = defaultLocale }) {
  const [source, english, translation] = await Promise.all([
    fs.readFile(LANDING_SOURCE, 'utf8'),
    loadCatalog(defaultLocale),
    loadCatalog(locale),
  ]);
  const destination = locale === defaultLocale
    ? path.join(outputRoot, 'index.html')
    : path.join(outputRoot, localeFor(locale).path, 'index.html');
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
  const locale = localeFlag >= 0 && process.argv[localeFlag + 1]
    ? process.argv[localeFlag + 1]
    : defaultLocale;
  const destination = await buildLocalizedLanding({ outputRoot, locale });
  console.log(`Built ${locale} landing page at ${path.relative(ROOT, destination)}`);
}
