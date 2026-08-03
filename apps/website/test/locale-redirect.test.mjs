import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import vm from 'node:vm';
import { localeForLanguage, publishedLocales } from '../i18n/locales.mjs';
import { loadCatalog, renderLanding } from '../scripts/build-localized-pages.mjs';

const [source, english] = await Promise.all([
  readFile(new URL('../index.html', import.meta.url), 'utf8'),
  loadCatalog('en'),
]);
const index = renderLanding(source, 'en', english, english);
const redirectSource = index.match(
  /<script id="healthmd-locale-redirect">([\s\S]*?)<\/script>/,
)?.[1];

assert.ok(redirectSource, 'rendered landing page must include the locale redirect bootstrap');

function createSessionStorage() {
  const values = new Map();
  return {
    getItem(key) {
      return values.get(key) ?? null;
    },
    setItem(key, value) {
      values.set(key, String(value));
    },
  };
}

function runRedirect({
  pathname = '/',
  protocol = 'https:',
  search = '',
  hash = '',
  languages,
  language = 'en-US',
  sessionStorage,
} = {}) {
  const destinations = [];
  const location = {
    pathname,
    protocol,
    search,
    hash,
    replace(destination) {
      destinations.push(destination);
    },
  };

  vm.runInNewContext(redirectSource, {
    window: {
      location,
      navigator: { languages, language },
      sessionStorage,
    },
  });

  return destinations;
}

test('supported browser preferences redirect the canonical landing entry', () => {
  for (const [language, destination] of [
    ['es-MX', '/es/'],
    ['de-AT', '/de/'],
    ['fr-CA', '/fr/'],
    ['pt-BR', '/pt-br/'],
    ['it-CH', '/it/'],
    ['nl-BE', '/nl/'],
    ['ja-JP', '/ja/'],
    ['ko-KR', '/ko/'],
    ['zh-CN', '/zh-hans/'],
  ]) {
    assert.deepEqual(runRedirect({ languages: [language] }), [destination], language);
  }
  assert.deepEqual(
    runRedirect({
      languages: ['fr-FR', 'en-US'],
      search: '?utm_source=test',
      hash: '#scheduling',
    }),
    ['/fr/?utm_source=test#scheduling'],
  );
  assert.deepEqual(runRedirect({ pathname: '/index.html', languages: ['de-DE'] }), ['/de/']);
});

test('locale negotiation uses exact regional tags before aliases and keeps browser order', () => {
  assert.deepEqual(runRedirect({ languages: ['zh-Hans', 'es-ES', 'en-US'] }), ['/zh-hans/']);
  assert.deepEqual(runRedirect({ languages: ['fr-FR', 'es-ES', 'en-US'] }), ['/fr/']);
  assert.deepEqual(runRedirect({ languages: ['en-US', 'zh-Hans', 'es-ES'] }), []);
  assert.deepEqual(runRedirect({ languages: ['en-US', 'de-DE'] }), []);
  assert.deepEqual(runRedirect({ languages: ['pt-PT'] }), ['/pt-br/']);
  assert.deepEqual(runRedirect({ languages: ['zh-Hans'] }), ['/zh-hans/']);
  assert.deepEqual(runRedirect({ languages: ['zh-Hans-CN'] }), ['/zh-hans/']);
  assert.deepEqual(runRedirect({ languages: ['zh-Hans-SG'] }), ['/zh-hans/']);
  assert.deepEqual(runRedirect({ languages: ['zh-SG'] }), ['/zh-hans/']);
  assert.deepEqual(runRedirect({ languages: ['zh'] }), []);
  assert.deepEqual(runRedirect({ languages: ['zh-TW'] }), []);
  assert.deepEqual(runRedirect({ languages: ['zh-HK'] }), []);
  assert.deepEqual(runRedirect({ languages: ['zh-MO'] }), []);
  assert.deepEqual(runRedirect({ languages: ['zh-Hant'] }), []);
});

test('manifest language resolution respects exact scripts before safe aliases', () => {
  assert.equal(localeForLanguage('it-CH').code, 'it');
  assert.equal(localeForLanguage('pt-PT').code, 'pt-br');
  assert.equal(localeForLanguage('zh_CN').code, 'zh-hans');
  assert.equal(localeForLanguage('zh-Hans-CN').code, 'zh-hans');
  assert.equal(localeForLanguage('zh-Hans-SG').code, 'zh-hans');
  assert.equal(localeForLanguage('zh-SG').code, 'zh-hans');
  assert.equal(localeForLanguage('zh').code, 'en');
  assert.equal(localeForLanguage('zh-Hant').code, 'en');
  assert.equal(localeForLanguage('zh-TW').code, 'en');
  assert.equal(localeForLanguage('zh-HK').code, 'en');
  assert.equal(localeForLanguage('zh-MO').code, 'en');
});

test('navigator.language is used when navigator.languages is unavailable', () => {
  assert.deepEqual(runRedirect({ language: 'es-419' }), ['/es/']);
  assert.deepEqual(runRedirect({ language: 'pt_BR' }), ['/pt-br/']);
});

test('leaving a localized route keeps the canonical root in English for the browsing session', () => {
  const sessionStorage = createSessionStorage();

  assert.deepEqual(runRedirect({
    pathname: '/de/',
    languages: ['de-DE'],
    sessionStorage,
  }), []);
  assert.equal(sessionStorage.getItem('healthmd-locale-detected'), '1');
  assert.deepEqual(runRedirect({ languages: ['de-DE'], sessionStorage }), []);
});

test('automatic locale detection only runs once per browsing session', () => {
  const sessionStorage = createSessionStorage();

  assert.deepEqual(runRedirect({ languages: ['fr-FR'], sessionStorage }), ['/fr/']);
  assert.deepEqual(runRedirect({ languages: ['fr-FR'], sessionStorage }), []);
});

test('explicit locale routes, docs, and non-web previews are never overridden', () => {
  for (const { path: localePath } of publishedLocales('landing').filter(({ path: value }) => value)) {
    const pathname = `/${localePath}/`;
    assert.deepEqual(runRedirect({ pathname, languages: ['en-US'] }), [], pathname);
  }
  assert.deepEqual(runRedirect({ pathname: '/docs/', languages: ['es-ES'] }), []);
  assert.deepEqual(runRedirect({ protocol: 'file:', languages: ['de-DE'] }), []);
});
