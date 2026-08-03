#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  authoredDocSlugs,
  defaultLocale,
  localeFor,
  publishedLocales,
} from '../i18n/locales.mjs';
import { docsPathForSlug, routePath } from '../i18n/routes.mjs';
import { loadCatalog } from './build-localized-pages.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const DIST = path.join(ROOT, 'dist');
const SITE_ORIGIN = 'https://healthmd.app';
const landingLocales = publishedLocales('landing');
const docsLocales = publishedLocales('docs');
const legalLocales = publishedLocales('legal');
const defaultLocaleConfig = localeFor(defaultLocale);
const authoredDocSlugSet = new Set(authoredDocSlugs);
const firstExportScreenshotFields = [
  'firstExportOnboardingScreenshot',
  'firstExportMetricScreenshot',
  'firstExportPreviewScreenshot',
];

async function sourceDocSlugs(directory, relative = '') {
  const slugs = [];
  for (const entry of await fs.readdir(directory, { withFileTypes: true })) {
    if (!relative && entry.isDirectory() && docsLocales.some(({ path: localePath }) => localePath === entry.name)) {
      continue;
    }
    const childRelative = path.posix.join(relative, entry.name);
    const childPath = path.join(directory, entry.name);
    if (entry.isDirectory()) slugs.push(...await sourceDocSlugs(childPath, childRelative));
    else if (entry.isFile() && entry.name.endsWith('.md')) {
      const withoutExtension = childRelative.replace(/\.md$/, '');
      const normalized = withoutExtension.replace(/(^|\/)index$/, '').replace(/^\/+|\/+$/g, '');
      slugs.push(['docs', normalized].filter(Boolean).join('/'));
    }
  }
  return slugs;
}

const englishDocSlugs = await sourceDocSlugs(path.join(ROOT, 'docs-src/src/content/docs'));
assert.equal(new Set(englishDocSlugs).size, englishDocSlugs.length, 'English documentation slugs must be unique');
const fallbackDocSlugs = englishDocSlugs.filter((slug) => !authoredDocSlugSet.has(slug));
assert.ok(fallbackDocSlugs.length > 0, 'Generated/reference docs must retain protected English fallbacks');
assert.ok(
  fallbackDocSlugs.every((slug) => slug === 'docs/reference' || slug.startsWith('docs/reference/')),
  'Only generated/reference documentation may use the English fallback contract',
);

async function read(relative) {
  return fs.readFile(path.join(DIST, relative), 'utf8');
}

function distRelative(pathname) {
  const clean = pathname.replace(/^\//, '');
  if (!clean || pathname.endsWith('/')) return path.join(clean, 'index.html');
  return clean;
}

function absolute(pathname) {
  return new URL(pathname, SITE_ORIGIN).href;
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function sitemapEntry(sitemap, canonical) {
  return sitemap.match(new RegExp(`<url><loc>${escapeRegExp(canonical)}</loc>[\\s\\S]*?<\\/url>`))?.[0] ?? '';
}

const [rootSitemap, docsSitemap] = await Promise.all([
  read('sitemap.xml'),
  read('sitemap-0.xml'),
]);

for (const locale of landingLocales) {
  const [landing, catalog] = await Promise.all([
    read(distRelative(routePath('home', locale.code))),
    loadCatalog(locale.code),
  ]);
  const canonical = absolute(routePath('home', locale.code));
  assert.match(landing, new RegExp(`<html lang="${locale.lang}" dir="${locale.dir}">`));
  assert.ok(landing.includes(`<link rel="canonical" href="${canonical}">`));
  assert.ok(landing.includes(`<meta property="og:locale" content="${locale.ogLocale}">`));
  assert.ok(landing.includes(`"inLanguage": "${locale.lang}"`));
  assert.ok(landing.includes(catalog.landing.static.heroTitle));
  assert.ok(landing.includes(locale.assets.appStoreBadge));
  assert.ok(landing.includes(locale.assets.playStoreBadge));
  assert.ok(landing.includes(locale.assets.scheduleScreenshot));
  assert.ok(landing.includes('id="healthmd-landing-messages"'));
  assert.ok(landing.includes('id="healthmd-locale-redirect"'));
  assert.ok(landing.includes(`aria-label="${locale.ui.languageSelector}"`));
  assert.ok(landing.includes(`aria-current="page" lang="${locale.lang}">${locale.label}</span>`));
  const legalLocale = locale.surfaces.legal ? locale.code : defaultLocale;
  assert.ok(landing.includes(`href="${routePath('privacy', legalLocale)}">${catalog.landing.static.privacy}</a>`));
  assert.ok(landing.includes(`href="${routePath('terms', legalLocale)}">${catalog.landing.static.terms}</a>`));
  for (const alternate of landingLocales) {
    assert.ok(
      landing.includes(`hreflang="${alternate.lang}" href="${absolute(routePath('home', alternate.code))}"`),
      `${locale.code} landing is missing ${alternate.lang} hreflang`,
    );
    if (alternate.code !== locale.code) {
      assert.ok(
        landing.includes(`<meta property="og:locale:alternate" content="${alternate.ogLocale}">`),
        `${locale.code} landing is missing ${alternate.ogLocale} Open Graph locale`,
      );
    }
  }
  assert.ok(landing.includes(`hreflang="x-default" href="${absolute(routePath('home', defaultLocale))}"`));
  assert.ok(rootSitemap.includes(`<loc>${canonical}</loc>`), `Root sitemap must include ${canonical}`);
}

for (const locale of legalLocales) {
  for (const routeId of ['privacy', 'terms']) {
    const pathname = routePath(routeId, locale.code);
    const page = await read(distRelative(pathname));
    const canonical = absolute(pathname);
    assert.match(page, new RegExp(`<html lang="${locale.lang}" dir="${locale.dir}">`));
    assert.ok(page.includes(`<link rel="canonical" href="${canonical}">`));
    assert.ok(page.includes(`<meta property="og:url" content="${canonical}">`));
    assert.ok(page.includes(`<meta property="og:locale" content="${locale.ogLocale}">`));
    for (const alternate of legalLocales) {
      assert.ok(page.includes(`hreflang="${alternate.lang}"`));
      if (alternate.code !== locale.code) {
        assert.ok(page.includes(`<meta property="og:locale:alternate" content="${alternate.ogLocale}">`));
      }
    }
    assert.ok(page.includes(`hreflang="x-default" href="${absolute(routePath(routeId, defaultLocale))}"`));
    if (locale.code !== defaultLocale) {
      assert.match(page, /href="\.\.\/(?:privacy-policy|terms-of-service)\.html"[^>]*hreflang="en"/i);
    }
    assert.ok(rootSitemap.includes(`<loc>${canonical}</loc>`), `Root sitemap must include ${canonical}`);
  }
}

for (const locale of landingLocales.filter(({ surfaces }) => !surfaces.legal)) {
  for (const routeId of ['privacy', 'terms']) {
    const unpublishedFile = path.join(DIST, distRelative(routePath(routeId, locale.code)));
    await assert.rejects(
      fs.access(unpublishedFile),
      (error) => error?.code === 'ENOENT',
      `${locale.code} legal review draft must not be emitted`,
    );
  }
}

for (const locale of docsLocales) {
  for (const slug of authoredDocSlugs) {
    const pathname = docsPathForSlug(slug, locale.code);
    const page = await read(distRelative(pathname));
    const canonical = absolute(pathname);
    assert.match(page, new RegExp(`<html lang="${locale.lang}" dir="${locale.dir}"`));
    assert.doesNotMatch(page, /<meta name="robots" content="noindex,follow"/);
    assert.ok(page.includes(`<link rel="canonical" href="${canonical}"/>`));
    assert.ok(page.includes(`<meta property="og:locale" content="${locale.ogLocale}"/>`));
    assert.ok(page.includes(`"inLanguage":"${locale.lang}"`));
    for (const alternate of docsLocales) {
      assert.ok(
        page.includes(`hreflang="${alternate.lang}" href="${absolute(docsPathForSlug(slug, alternate.code))}"`),
        `${pathname} is missing ${alternate.lang} hreflang`,
      );
      if (alternate.code !== locale.code) {
        assert.ok(
          page.includes(`<meta property="og:locale:alternate" content="${alternate.ogLocale}"/>`),
          `${pathname} is missing ${alternate.ogLocale} Open Graph locale`,
        );
      }
    }
    assert.ok(page.includes(`hreflang="x-default" href="${absolute(docsPathForSlug(slug, defaultLocale))}"`));
    assert.ok(page.includes(locale.assets.docsOgImage));
    const sitemapUrl = sitemapEntry(docsSitemap, canonical);
    assert.ok(sitemapUrl, `Docs sitemap must include ${canonical}`);
    for (const alternate of docsLocales) {
      assert.ok(
        sitemapUrl.includes(`hreflang="${alternate.lang}" href="${absolute(docsPathForSlug(slug, alternate.code))}"`),
        `Docs sitemap entry ${canonical} is missing ${alternate.lang}`,
      );
    }
    assert.ok(sitemapUrl.includes(`hreflang="x-default" href="${absolute(docsPathForSlug(slug, defaultLocale))}"`));
  }

  if (locale.code !== defaultLocale) {
    for (const slug of fallbackDocSlugs) {
      const fallbackPath = docsPathForSlug(slug, locale.code);
      const englishPath = docsPathForSlug(slug, defaultLocale);
      const fallback = await read(distRelative(fallbackPath));
      assert.match(fallback, /<meta name="robots" content="noindex,follow"\/>/);
      assert.ok(fallback.includes(`<link rel="canonical" href="${absolute(englishPath)}"/>`));
      assert.ok(fallback.includes(`<meta property="og:url" content="${absolute(englishPath)}"/>`));
      assert.ok(fallback.includes(`<meta property="og:locale" content="${defaultLocaleConfig.ogLocale}"/>`));
      assert.ok(fallback.includes(defaultLocaleConfig.assets.docsOgImage));
      assert.match(fallback, /<main\b[^>]* lang="en"/);
      assert.doesNotMatch(fallback, /"inLanguage":"/);
      assert.doesNotMatch(fallback, /<link rel="alternate" hreflang=/);
      assert.doesNotMatch(fallback, /<meta property="og:locale:alternate"/);
      assert.ok(!docsSitemap.includes(`<loc>${absolute(fallbackPath)}</loc>`));
    }
  }
}

for (const slug of fallbackDocSlugs) {
  const englishCanonical = absolute(docsPathForSlug(slug, defaultLocale));
  const entry = sitemapEntry(docsSitemap, englishCanonical);
  assert.ok(entry, `Docs sitemap must include canonical English fallback source ${englishCanonical}`);
  assert.ok(entry.includes(`hreflang="${defaultLocaleConfig.lang}" href="${englishCanonical}"`));
  assert.ok(entry.includes(`hreflang="x-default" href="${englishCanonical}"`));
  for (const locale of docsLocales.filter(({ code }) => code !== defaultLocale)) {
    assert.ok(
      !entry.includes(absolute(docsPathForSlug(slug, locale.code))),
      `${englishCanonical} must not advertise the ${locale.code} fallback route`,
    );
  }
}

for (const locale of landingLocales.filter(({ code }) => code !== defaultLocale)) {
  assert.ok(!rootSitemap.includes(`https://healthmd.app/${locale.path}/visualizations/`));
  const htmlFiles = [];
  async function walk(directory) {
    for (const entry of await fs.readdir(directory, { withFileTypes: true })) {
      const file = path.join(directory, entry.name);
      if (entry.isDirectory()) await walk(file);
      else if (entry.isFile() && entry.name.endsWith('.html')) htmlFiles.push(file);
    }
  }
  await walk(path.join(DIST, locale.path));
  let indexable = 0;
  for (const file of htmlFiles) {
    const html = await fs.readFile(file, 'utf8');
    assert.match(html, new RegExp(`<html lang="${locale.lang}"`));
    if (!/<meta name="robots" content="noindex,follow"\/?>(?:<\/meta>)?/.test(html)) indexable += 1;
  }
  const expectedIndexable = 1 + authoredDocSlugs.length + (locale.surfaces.legal ? 2 : 0);
  assert.equal(indexable, expectedIndexable, `${locale.code} must expose exactly ${expectedIndexable} indexable pages`);
}

const requiredAssets = landingLocales.flatMap((locale) => [
  locale.assets.appStoreBadge.replace(/^\//, ''),
  locale.assets.playStoreBadge.replace(/^\//, ''),
  locale.assets.scheduleScreenshot.replace(/^\//, ''),
  locale.assets.docsOgImage.replace(/^\/docs\//, 'docs/'),
  ...firstExportScreenshotFields.map((field) => locale.assets[field].replace(/^\/docs\//, 'docs/')),
]);
await Promise.all([...new Set(requiredAssets)].map((relative) => fs.access(path.join(DIST, relative))));

console.log(`Built localization is valid for ${landingLocales.map(({ code }) => code).join(', ')}.`);
