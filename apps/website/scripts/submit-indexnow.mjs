#!/usr/bin/env node
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { Parser } from 'htmlparser2';

const ORIGIN = 'https://healthmd.app';
export const KEY_LOCATION = `${ORIGIN}/indexnow-key.txt`;
export const ENDPOINT = 'https://api.indexnow.org/indexnow';

export function submissionOptions(args) {
  const submit = args.includes('--submit');
  if (args.filter(arg => arg === '--submit').length > 1) throw new Error('Duplicate --submit');
  const urls = [...new Set(args.filter(arg => arg !== '--submit').map(value => {
    const url = new URL(value);
    if (url.origin !== ORIGIN || url.username || url.password || url.search || url.hash || url.href !== value) {
      throw new Error('Use exact https://healthmd.app canonical URLs without queries or fragments');
    }
    return url.href;
  }))];
  if (!urls.length || urls.length > 100) throw new Error('Supply 1–100 recently changed canonical page URLs; add --submit to notify IndexNow');
  return { submit, urls };
}

async function boundedText(response, limit) {
  const reader = response.body.getReader();
  const chunks = [];
  let length = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > limit) throw new Error('Response exceeds preflight size limit');
      chunks.push(value);
    }
  } finally { await reader.cancel(); }
  return Buffer.concat(chunks).toString('utf8');
}

async function getText(fetchImpl, url, type, limit) {
  const response = await fetchImpl(url, { redirect: 'error', signal: AbortSignal.timeout(20000) });
  if (response.status !== 200 || !response.headers.get('content-type')?.toLowerCase().startsWith(type)) {
    throw new Error(`Preflight requires HTTP 200 ${type}: ${url}`);
  }
  return { response, text: await boundedText(response, limit) };
}

export function assertIndexable(html, response, url) {
  const canonicals = [];
  const directives = [response.headers.get('x-robots-tag') || ''];
  let inHead = false;
  const parser = new Parser({
    onopentag(name, attrs) {
      if (name === 'head') inHead = true;
      if (!inHead) return;
      if (name === 'link' && attrs.rel?.toLowerCase().split(/\s+/).includes('canonical')) canonicals.push(attrs.href);
      if (name === 'meta' && /^(robots|bingbot|yandex|yandexbot|naverbot|yeti|seznambot|amazonbot|yepbot)$/i.test(attrs.name || '')) directives.push(attrs.content || '');
    },
    onclosetag(name) { if (name === 'head') inHead = false; },
  });
  parser.end(html);
  if (directives.some(value => /\b(noindex|none)\b/i.test(value))) throw new Error(`Page is noindex: ${url}`);
  if (canonicals.length !== 1 || canonicals[0] !== url) throw new Error(`Page must have one matching canonical: ${url}`);
}

export async function runSubmission(args, { fetchImpl = fetch, key } = {}) {
  const { submit, urls } = submissionOptions(args);
  if (!/^[a-f0-9]{32}$/.test(key || '')) throw new Error('Expected the committed 32-character IndexNow verification key');
  const publishedKey = await getText(fetchImpl, KEY_LOCATION, 'text/plain', 256);
  if (publishedKey.text.trim() !== key) throw new Error('Published verification key does not match; deploy before submitting');
  const robots = await getText(fetchImpl, `${ORIGIN}/robots.txt`, 'text/plain', 65536);
  // Conservative guard for this site's allow-all policy. Revisit with a full
  // robots parser if selective crawl restrictions are introduced.
  if (/^\s*Disallow:\s*[^\s#]+/im.test(robots.text)) throw new Error('robots.txt has crawl restrictions; review before submitting');
  for (const url of urls) {
    const page = await getText(fetchImpl, url, 'text/html', 2 * 1024 * 1024);
    assertIndexable(page.text, page.response, url);
  }
  const payload = { host: 'healthmd.app', key, keyLocation: KEY_LOCATION, urlList: urls };
  if (!submit) return { mode: 'dry-run', urls, message: 'Live preflight passed. No IndexNow notification sent.' };
  const response = await fetchImpl(ENDPOINT, {
    method: 'POST', redirect: 'error', signal: AbortSignal.timeout(20000),
    headers: { 'content-type': 'application/json; charset=utf-8' }, body: JSON.stringify(payload),
  });
  await response.body?.cancel();
  if (![200, 202].includes(response.status)) throw new Error(`IndexNow returned HTTP ${response.status}; inspect before retrying (no automatic retry)`);
  return { mode: 'submitted', status: response.status, urls,
    message: response.status === 202 ? 'Received; key validation pending. Indexing is not guaranteed.' : 'Received. Indexing is not guaranteed.' };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    const key = (await readFile(new URL('../indexnow-key.txt', import.meta.url), 'utf8')).trim();
    console.log(JSON.stringify(await runSubmission(process.argv.slice(2), { key }), null, 2));
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
