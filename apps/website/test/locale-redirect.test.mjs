import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import vm from 'node:vm';

const index = await readFile(new URL('../index.html', import.meta.url), 'utf8');
const redirectSource = index.match(
  /<script id="healthmd-locale-redirect">([\s\S]*?)<\/script>/,
)?.[1];

assert.ok(redirectSource, 'landing page must include the locale redirect bootstrap');

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

test('Spanish browser preferences redirect the canonical landing entry', () => {
  assert.deepEqual(
    runRedirect({
      languages: ['es-MX', 'en-US'],
      search: '?utm_source=test',
      hash: '#scheduling',
    }),
    ['/es/?utm_source=test#scheduling'],
  );
  assert.deepEqual(runRedirect({ pathname: '/index.html', languages: ['es-ES'] }), ['/es/']);
});

test('locale negotiation uses the first supported browser language', () => {
  assert.deepEqual(runRedirect({ languages: ['fr-FR', 'es-ES', 'en-US'] }), ['/es/']);
  assert.deepEqual(runRedirect({ languages: ['fr-FR', 'en-US', 'es-ES'] }), []);
  assert.deepEqual(runRedirect({ languages: ['en-US', 'es-ES'] }), []);
  assert.deepEqual(runRedirect({ languages: ['fr-FR'] }), []);
});

test('navigator.language is used when navigator.languages is unavailable', () => {
  assert.deepEqual(runRedirect({ language: 'es-419' }), ['/es/']);
});

test('deleting /es keeps the canonical root in English for the browsing session', () => {
  const sessionStorage = createSessionStorage();

  assert.deepEqual(runRedirect({
    pathname: '/es/',
    languages: ['es-ES'],
    sessionStorage,
  }), []);
  assert.equal(sessionStorage.getItem('healthmd-locale-detected'), '1');
  assert.deepEqual(runRedirect({ languages: ['es-ES'], sessionStorage }), []);
});

test('automatic locale detection only runs once per browsing session', () => {
  const sessionStorage = createSessionStorage();

  assert.deepEqual(runRedirect({ languages: ['es-ES'], sessionStorage }), ['/es/']);
  assert.deepEqual(runRedirect({ languages: ['es-ES'], sessionStorage }), []);
});

test('explicit locale routes and non-web previews are never overridden', () => {
  assert.deepEqual(runRedirect({ pathname: '/es/', languages: ['en-US'] }), []);
  assert.deepEqual(runRedirect({ pathname: '/docs/', languages: ['es-ES'] }), []);
  assert.deepEqual(runRedirect({ protocol: 'file:', languages: ['es-ES'] }), []);
});
