import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { submissionOptions, runSubmission, ENDPOINT, KEY_LOCATION } from '../scripts/submit-indexnow.mjs';

const url = 'https://healthmd.app/apple-health-to-csv/';
const key = '1234567890abcdef1234567890abcdef';
function fixture(overrides = {}) {
  const calls = [];
  const fetchImpl = async (target, options) => {
    calls.push({ target, options });
    assert.equal(options.redirect, 'error');
    assert.ok(options.signal instanceof AbortSignal);
    if (overrides[target]) return overrides[target]();
    if (target === KEY_LOCATION) return new Response(key + '\n', { headers: { 'content-type': 'text/plain' } });
    if (target.endsWith('/robots.txt')) return new Response('User-agent: *\nAllow: /', { headers: { 'content-type': 'text/plain' } });
    if (target === ENDPOINT) return new Response(null, { status: 202 });
    return new Response(`<html><head><link rel="canonical" href="${target}"></head><body>Public page</body></html>`, { headers: { 'content-type': 'text/html; charset=utf-8' } });
  };
  return { calls, fetchImpl };
}

test('only explicit, exact production URLs; deduplicate without losing order', () => {
  assert.deepEqual(submissionOptions([url, url]), { submit: false, urls: [url] });
  for (const value of ['http://healthmd.app/', 'https://www.healthmd.app/', 'https://evil.test/', url + '?source=x', url + '#demo', 'https://user@healthmd.app/', '--unknown', 'https://healthmd.app:443/']) {
    assert.throws(() => submissionOptions([value]));
  }
  assert.throws(() => submissionOptions([]));
  assert.throws(() => submissionOptions(['--submit', '--submit', url]));
  assert.throws(() => submissionOptions(Array.from({ length: 101 }, (_, i) => `https://healthmd.app/${i}/`)));
});

test('dry run verifies live key, robots and pages without submitting', async () => {
  const f = fixture();
  const result = await runSubmission([url, url], { ...f, key });
  assert.equal(result.mode, 'dry-run');
  assert.equal(f.calls.length, 3);
  assert.ok(f.calls.every(call => call.options.method !== 'POST'));
});

test('explicit submission sends exactly one scoped payload after preflight', async () => {
  const f = fixture();
  const result = await runSubmission(['--submit', url], { ...f, key });
  assert.equal(result.status, 202);
  assert.match(result.message, /validation pending/);
  const post = f.calls.at(-1);
  assert.equal(post.target, ENDPOINT);
  assert.equal(post.options.method, 'POST');
  assert.deepEqual(JSON.parse(post.options.body), { host: 'healthmd.app', key, keyLocation: KEY_LOCATION, urlList: [url] });
});

const page = (html, headers = {}, status = 200) => () => new Response(html, { status, headers: { 'content-type': 'text/html', ...headers } });
for (const [name, target, response] of [
  ['key mismatch', KEY_LOCATION, () => new Response('wrong', { headers: { 'content-type': 'text/plain' } })],
  ['robots restriction', 'https://healthmd.app/robots.txt', () => new Response('User-agent: *\nDisallow: /private/', { headers: { 'content-type': 'text/plain' } })],
  ['missing canonical', url, page('<head></head>')],
  ['different canonical', url, page('<head><link rel="canonical" href="https://healthmd.app/"></head>')],
  ['duplicate canonical', url, page(`<head><link rel="canonical" href="${url}"><link rel="canonical" href="${url}"></head>`) ],
  ['noindex meta', url, page(`<head><link rel="canonical" href="${url}"><meta name="robots" content="noindex, follow"></head>`) ],
  ['engine noindex', url, page(`<head><link rel="canonical" href="${url}"><meta name="bingbot" content="none"></head>`) ],
  ['header noindex', url, page(`<head><link rel="canonical" href="${url}"></head>`, { 'x-robots-tag': 'noindex' })],
  ['redirect', url, page('', { location: 'https://healthmd.app/' }, 301)],
  ['missing page', url, page('', {}, 404)],
  ['wrong type', url, page('{}', { 'content-type': 'application/json' })],
  ['oversized page', url, page('a'.repeat(2 * 1024 * 1024 + 1))],
]) {
  test(`preflight blocks ${name} without a POST`, async () => {
    const f = fixture({ [target]: response });
    await assert.rejects(runSubmission(['--submit', url], { ...f, key }));
    assert.ok(f.calls.every(call => call.options.method !== 'POST'));
  });
}

test('bad local key fails before network access', async () => {
  const f = fixture();
  await assert.rejects(runSubmission([url], { ...f, key: 'invalid' }));
  assert.equal(f.calls.length, 0);
});

test('HTTP errors are reported once, without retries or success claims', async () => {
  for (const status of [400, 403, 422, 429, 500]) {
    const f = fixture({ [ENDPOINT]: () => new Response(null, { status }) });
    await assert.rejects(runSubmission(['--submit', url], { ...f, key }), new RegExp(`HTTP ${status}`));
    assert.equal(f.calls.filter(call => call.target === ENDPOINT).length, 1);
  }
  const f = fixture({ [ENDPOINT]: () => new Response(null, { status: 200 }) });
  assert.match((await runSubmission(['--submit', url], { ...f, key })).message, /^Received\./);
});

test('network failures never trigger a retry', async () => {
  const f = fixture({ [url]: () => { throw new Error('network unavailable'); } });
  await assert.rejects(runSubmission(['--submit', url], { ...f, key }), /network unavailable/);
  assert.ok(f.calls.every(call => call.options.method !== 'POST'));
});

test('verification artifact is valid and included by the static build', async () => {
  const value = await readFile(new URL('../indexnow-key.txt', import.meta.url), 'utf8');
  assert.match(value, /^[a-f0-9]{32}\n$/);
  const build = await readFile(new URL('../scripts/build-site.mjs', import.meta.url), 'utf8');
  assert.match(build, /'indexnow-key\.txt'/);
});
