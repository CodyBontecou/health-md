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
const SITE_ORIGIN = 'https://healthmd.app';
const LEGAL_ROUTES = Object.freeze({
  privacy: 'privacy-policy.html',
  terms: 'terms-of-service.html',
});

function absoluteRoute(routeId, locale) {
  return new URL(routePath(routeId, locale), SITE_ORIGIN).href;
}

function relativeRoute(routeId, fromLocale, toLocale) {
  const from = routePath(routeId, fromLocale).replace(/^\//, '');
  const to = routePath(routeId, toLocale).replace(/^\//, '');
  return path.posix.relative(path.posix.dirname(from), to) || path.posix.basename(to);
}

function renderLanguageSelector(routeId, locale) {
  const current = localeFor(locale);
  const entries = publishedLocales('legal').map((candidate) => {
    if (candidate.code === locale) {
      return `          <span aria-current="page" lang="${candidate.lang}">${candidate.label}</span>`;
    }
    return `          <a href="${relativeRoute(routeId, locale, candidate.code)}" hreflang="${candidate.lang}" lang="${candidate.lang}">${candidate.label}</a>`;
  });
  return [
    `        <nav class="language-selector" aria-label="${current.ui.languageSelector}">`,
    entries.join('\n          <span aria-hidden="true">/</span>\n'),
    '        </nav>',
  ].join('\n');
}

function attributeTag(tag, attribute, value, flags = 'i') {
  const escaped = value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp(`<${tag}\\b(?=[^>]*\\b${attribute}="${escaped}")[^>]*>`, flags);
}

function replaceLanguageSelector(html, routeId, locale) {
  const filename = LEGAL_ROUTES[routeId];
  const escapedFilename = filename.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const nav = /<nav\b(?=[^>]*\bclass="language-selector")[^>]*>[\s\S]*?<\/nav>/i;
  const legacyLink = new RegExp(
    `<a\\b(?=[^>]*\\bhref="[^"]*${escapedFilename}")(?=[^>]*\\bclass="back-link")[^>]*>[\\s\\S]*?<\\/a>`,
    'i',
  );
  const marker = nav.test(html) ? nav : legacyLink;
  if (!marker.test(html)) throw new Error(`${locale}/${filename} is missing its language selector`);
  const withoutHeaderSelector = html.replace(marker, '');
  const footerInner = /<div\b(?=[^>]*\bclass="footer-inner")[^>]*>/i;
  if (!footerInner.test(withoutHeaderSelector)) {
    throw new Error(`${locale}/${filename} is missing its footer`);
  }
  return withoutHeaderSelector.replace(
    footerInner,
    (tag) => `${tag}\n${renderLanguageSelector(routeId, locale)}`,
  );
}

function replaceHeadMetadata(html, routeId, locale) {
  const current = localeFor(locale);
  const canonical = absoluteRoute(routeId, locale);
  const alternateLinks = publishedLocales('legal').map((candidate) =>
    `  <link rel="alternate" hreflang="${candidate.lang}" href="${absoluteRoute(routeId, candidate.code)}">`,
  );
  alternateLinks.push(`  <link rel="alternate" hreflang="x-default" href="${absoluteRoute(routeId, defaultLocale)}">`);
  html = html.replace(/\n?\s*<link\b(?=[^>]*\brel="alternate")(?=[^>]*\bhreflang="[^"]+")[^>]*>/gi, '');
  html = html.replace(
    attributeTag('link', 'rel', 'canonical'),
    `  <link rel="canonical" href="${canonical}">\n${alternateLinks.join('\n')}`,
  );

  const ogAlternates = publishedLocales('legal')
    .filter(({ code }) => code !== locale)
    .map(({ ogLocale }) => `  <meta property="og:locale:alternate" content="${ogLocale}">`);
  html = html.replace(/\n?\s*<meta\b(?=[^>]*\bproperty="og:locale:alternate")[^>]*>/gi, '');
  html = html
    .replace(/<html\b[^>]*>/i, `<html lang="${current.lang}" dir="${current.dir}">`)
    .replace(
      attributeTag('meta', 'name', 'robots'),
      `  <meta name="robots" content="${current.surfaces.legal ? 'index,follow' : 'noindex,follow'}">`,
    )
    .replace(attributeTag('meta', 'property', 'og:url'), `  <meta property="og:url" content="${canonical}">`)
    .replace(
      attributeTag('meta', 'property', 'og:locale'),
      `  <meta property="og:locale" content="${current.ogLocale}">${ogAlternates.length ? `\n${ogAlternates.join('\n')}` : ''}`,
    );
  return html;
}

export function renderLegalPage(source, routeId, locale) {
  localeFor(locale);
  if (!LEGAL_ROUTES[routeId]) throw new Error(`Unknown legal route: ${routeId}`);
  return replaceLanguageSelector(replaceHeadMetadata(source, routeId, locale), routeId, locale);
}

export async function buildLocalizedLegalPages(outputRoot) {
  const destinations = [];
  for (const locale of publishedLocales('legal')) {
    for (const [routeId, filename] of Object.entries(LEGAL_ROUTES)) {
      const source = locale.code === defaultLocale
        ? path.join(ROOT, filename)
        : path.join(ROOT, locale.path, filename);
      const destination = path.join(outputRoot, routePath(routeId, locale.code).replace(/^\//, ''));
      const html = renderLegalPage(await fs.readFile(source, 'utf8'), routeId, locale.code);
      await fs.mkdir(path.dirname(destination), { recursive: true });
      await fs.writeFile(destination, html);
      destinations.push(destination);
    }
  }
  return destinations;
}

const isDirectRun = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isDirectRun) {
  const outputFlag = process.argv.indexOf('--output');
  const outputRoot = outputFlag >= 0 && process.argv[outputFlag + 1]
    ? path.resolve(ROOT, process.argv[outputFlag + 1])
    : path.join(ROOT, 'dist');
  const destinations = await buildLocalizedLegalPages(outputRoot);
  console.log(`Built ${destinations.length} localized legal pages in ${path.relative(ROOT, outputRoot)}`);
}
