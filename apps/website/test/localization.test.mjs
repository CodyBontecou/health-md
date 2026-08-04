import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  authoredDocSlugs,
  defaultLocale,
  publishedLocales,
} from '../i18n/locales.mjs';
import {
  docsEntryId,
  docsPathForSlug,
  hasDocTranslation,
  routePath,
  translatedLocalesForDoc,
} from '../i18n/routes.mjs';
import { assertCatalogParity, loadCatalog, renderLanding } from '../scripts/build-localized-pages.mjs';
import { renderLegalPage } from '../scripts/build-localized-legal-pages.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const landingLocales = publishedLocales('landing');
const translatedLocales = landingLocales.filter(({ code }) => code !== defaultLocale);
const [source, english, ...translations] = await Promise.all([
  readFile(path.join(ROOT, 'index.html'), 'utf8'),
  loadCatalog(defaultLocale),
  ...translatedLocales.map(({ code }) => loadCatalog(code)),
]);

for (const [index, locale] of translatedLocales.entries()) {
  const translation = translations[index];
  test(`${locale.label} catalog renders a localized landing route`, () => {
    assert.doesNotThrow(() => assertCatalogParity(english, translation));
    const html = renderLanding(source, locale.code, english, translation);
    const expectedUrl = `https://healthmd.app/${locale.path}/`;
    const legalLocale = locale.surfaces.legal ? locale.code : defaultLocale;
    assert.match(html, new RegExp(`<html lang="${locale.lang}" dir="${locale.dir}">`));
    assert.ok(html.includes(`<link rel="canonical" href="${expectedUrl}">`));
    assert.ok(html.includes(`href="${docsPathForSlug('', locale.code)}"`));
    assert.equal(html.split(locale.assets.appStoreBadge).length - 1, 2);
    assert.equal(html.split(locale.assets.playStoreBadge).length - 1, 2);
    assert.equal(html.split(`aria-label="${locale.ui.languageSelector}"`).length - 1, 2);
    assert.equal(html.split(`aria-current="page" lang="${locale.lang}">${locale.label}</span>`).length - 1, 1);
    assert.equal((html.match(/class="language-menu/g) ?? []).length, 1);
    assert.ok(html.includes(translation.landing.static.downloadTitle));
    assert.ok(html.includes(translation.landing.static.downloadOffer));
    assert.ok(html.includes(`href="${routePath('privacy', legalLocale)}">${translation.landing.static.privacy}</a>`));
    assert.ok(html.includes(`href="${routePath('terms', legalLocale)}">${translation.landing.static.terms}</a>`));
    assert.ok(html.includes('class="language-menu footer-language-menu"'));
    for (const alternate of landingLocales) {
      const alternatePath = alternate.path ? `/${alternate.path}/` : '/';
      assert.ok(html.includes(`hreflang="${alternate.lang}" href="https://healthmd.app${alternatePath}"`));
    }
    const schema = JSON.parse(html.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/)[1]);
    const runtime = JSON.parse(html.match(/<script id="healthmd-landing-messages" type="application\/json">([\s\S]*?)<\/script>/)[1]);
    assert.equal(schema.inLanguage, locale.lang);
    assert.equal(schema.url, expectedUrl);
    assert.equal(runtime.intlLocale, locale.intlLocale);
    assert.ok(html.includes(`href="${runtime.sampleMarkdownHref}" download data-sample-download`));
    assert.doesNotMatch(html, /Move your<br>health forward\.|Your data\. Your rules\./);
  });
}

test('unpublished legal translations remain noindex review drafts', async () => {
  for (const locale of publishedLocales('landing').filter(({ surfaces }) => !surfaces.legal)) {
    for (const filename of ['privacy-policy.html', 'terms-of-service.html']) {
      const html = await readFile(path.join(ROOT, locale.path, filename), 'utf8');
      assert.match(html, /<meta\b(?=[^>]*name="robots")(?=[^>]*content="noindex,follow")[^>]*>/);
      assert.match(
        html,
        new RegExp(`<nav\\b(?=[^>]*class="language-selector")(?=[^>]*aria-label="${locale.ui.languageSelector}")[^>]*>`),
      );
      const rendered = renderLegalPage(html, filename.startsWith('privacy') ? 'privacy' : 'terms', locale.code);
      const renderedHeader = rendered.slice(rendered.indexOf('<header'), rendered.indexOf('</header>'));
      const renderedFooter = rendered.slice(rendered.indexOf('<footer'), rendered.indexOf('</footer>'));
      assert.ok(rendered.includes('<meta name="robots" content="noindex,follow">'));
      assert.doesNotMatch(renderedHeader, /class="language-selector"/);
      assert.match(renderedFooter, /class="language-selector"/);
    }
  }
});

test('published legal pages derive reciprocal metadata and language navigation from the manifest', async () => {
  for (const locale of publishedLocales('legal')) {
    const sourcePath = locale.code === defaultLocale
      ? path.join(ROOT, 'privacy-policy.html')
      : path.join(ROOT, locale.path, 'privacy-policy.html');
    const html = renderLegalPage(await readFile(sourcePath, 'utf8'), 'privacy', locale.code);
    assert.match(html, new RegExp(`<html lang="${locale.lang}" dir="${locale.dir}">`));
    assert.ok(html.includes('<meta name="robots" content="index,follow">'));
    assert.ok(html.includes(`aria-label="${locale.ui.languageSelector}"`));
    assert.ok(html.includes(`aria-current="page" lang="${locale.lang}">${locale.label}</span>`));
    const renderedHeader = html.slice(html.indexOf('<header'), html.indexOf('</header>'));
    const renderedFooter = html.slice(html.indexOf('<footer'), html.indexOf('</footer>'));
    assert.doesNotMatch(renderedHeader, /class="language-selector"/);
    assert.match(renderedFooter, /class="language-selector"/);
    for (const alternate of publishedLocales('legal')) {
      assert.ok(html.includes(`hreflang="${alternate.lang}" href="https://healthmd.app${alternate.code === defaultLocale ? '/privacy-policy.html' : `/${alternate.path}/privacy-policy.html`}"`));
    }
  }
});

test('docs IDs place every configured locale before the docs segment', () => {
  assert.equal(docsEntryId('index.md'), 'docs');
  assert.equal(docsEntryId('configuration.md'), 'docs/configuration');
  assert.equal(docsEntryId('reference/generated/index.md'), 'docs/reference/generated');
  for (const locale of translatedLocales) {
    assert.equal(docsEntryId(`${locale.path}/index.md`), `${locale.path}/docs`);
    assert.equal(
      docsEntryId(`${locale.path}/configuration.md`),
      `${locale.path}/docs/configuration`,
    );
  }
});

test('all authored docs are translated and generated references remain protected fallbacks', () => {
  const allDocsLocales = publishedLocales('docs').map(({ code }) => code);
  for (const locale of translatedLocales) {
    for (const slug of authoredDocSlugs) {
      const pathname = docsPathForSlug(slug, locale.code);
      assert.equal(hasDocTranslation(pathname, locale.code), true, pathname);
      assert.deepEqual(translatedLocalesForDoc(pathname), allDocsLocales, pathname);
    }
    const fallback = docsPathForSlug('reference', locale.code);
    assert.equal(hasDocTranslation(fallback, locale.code), false, fallback);
    assert.deepEqual(translatedLocalesForDoc(fallback), [defaultLocale]);
  }
});

test('all authored translations preserve fenced and inline technical literals', async () => {
  const filenames = authoredDocSlugs.map((slug) => (
    slug === 'docs' ? 'index.md' : `${slug.replace(/^docs\//, '')}.md`
  ));
  const fencedBlocks = (markdown) => [...markdown.matchAll(/```[^\n]*\n[\s\S]*?```/g)].map((match) => match[0]);
  const inlineCode = (markdown) => [...markdown.matchAll(/(?<!`)`([^`\n]+)`(?!`)/g)].map((match) => match[1]);

  for (const locale of translatedLocales) {
    for (const filename of filenames) {
      const [englishDoc, translation] = await Promise.all([
        readFile(path.join(ROOT, 'docs-src/src/content/docs', filename), 'utf8'),
        readFile(path.join(ROOT, 'docs-src/src/content/docs', locale.path, filename), 'utf8'),
      ]);
      assert.deepEqual(
        fencedBlocks(translation),
        fencedBlocks(englishDoc),
        `${locale.code}/${filename} must preserve fenced technical examples`,
      );
      assert.deepEqual(
        inlineCode(translation),
        inlineCode(englishDoc),
        `${locale.code}/${filename} must preserve inline technical literals`,
      );
    }
  }
});
