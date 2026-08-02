#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const DIST = path.join(ROOT, 'dist');
const CANONICAL_ORIGIN = 'https://healthmd.app';
const SITE_ORIGINS = new Set([CANONICAL_ORIGIN, 'https://www.healthmd.app', 'https://healthmd.isolated.tech']);
const IGNORED_PATH_PREFIXES = ['/cdn-cgi/', '/_vercel/'];

async function walk(directory) {
  const entries = await fs.readdir(directory, { withFileTypes: true });
  const files = [];
  for (const entry of entries.sort((left, right) => left.name.localeCompare(right.name))) {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...await walk(absolute));
    else if (entry.isFile()) files.push(absolute);
  }
  return files;
}

function pageURL(file) {
  const relative = path.relative(DIST, file).split(path.sep).join('/');
  if (relative === 'index.html') return new URL('/', CANONICAL_ORIGIN);
  if (relative.endsWith('/index.html')) return new URL(`/${relative.slice(0, -'index.html'.length)}`, CANONICAL_ORIGIN);
  return new URL(`/${relative}`, CANONICAL_ORIGIN);
}

function safeDistPath(pathname) {
  const decoded = decodeURIComponent(pathname).replace(/^\/+/, '');
  const candidate = path.resolve(DIST, decoded);
  if (candidate !== DIST && !candidate.startsWith(`${DIST}${path.sep}`)) {
    throw new Error(`path escapes dist: ${pathname}`);
  }
  return candidate;
}

async function exists(file) {
  try {
    await fs.access(file);
    return true;
  } catch {
    return false;
  }
}

async function targetFile(url) {
  const base = safeDistPath(url.pathname);
  const candidates = url.pathname.endsWith('/')
    ? [path.join(base, 'index.html')]
    : [base, path.join(base, 'index.html'), `${base}.html`];
  for (const candidate of candidates) {
    if (await exists(candidate)) return candidate;
  }
  return candidates[0];
}

const allFiles = await walk(DIST);
const htmlFiles = allFiles.filter((file) => file.endsWith('.html'));
if (htmlFiles.length === 0) throw new Error(`No HTML files found in ${DIST}`);

const htmlCache = new Map();
async function htmlFor(file) {
  if (!htmlCache.has(file)) htmlCache.set(file, await fs.readFile(file, 'utf8'));
  return htmlCache.get(file);
}

const failures = [];
let checked = 0;
for (const sourceFile of htmlFiles) {
  const html = await htmlFor(sourceFile);
  const sourceURL = pageURL(sourceFile);
  const attributes = [...html.matchAll(/\b(?:href|src)=(['"])(.*?)\1/gi)].map((match) => match[2]);

  for (const destination of attributes) {
    if (!destination || /^(?:mailto:|tel:|data:|javascript:|blob:)/i.test(destination)) continue;

    let resolved;
    try {
      resolved = new URL(destination, sourceURL);
    } catch {
      failures.push(`${path.relative(DIST, sourceFile)}: invalid URL ${JSON.stringify(destination)}`);
      continue;
    }

    if (!SITE_ORIGINS.has(resolved.origin)) continue;
    if (IGNORED_PATH_PREFIXES.some((prefix) => resolved.pathname.startsWith(prefix))) continue;

    let target;
    try {
      target = await targetFile(resolved);
    } catch (error) {
      failures.push(`${path.relative(DIST, sourceFile)}: ${error.message}`);
      continue;
    }

    checked += 1;
    if (!await exists(target)) {
      failures.push(`${path.relative(DIST, sourceFile)}: ${destination} -> missing ${path.relative(DIST, target)}`);
      continue;
    }

    if (resolved.hash && target.endsWith('.html')) {
      const fragment = decodeURIComponent(resolved.hash.slice(1));
      const targetHTML = await htmlFor(target);
      const ids = new Set([...targetHTML.matchAll(/\bid=(['"])(.*?)\1/gi)].map((match) => match[2]));
      if (!ids.has(fragment)) {
        failures.push(`${path.relative(DIST, sourceFile)}: ${destination} -> missing fragment #${fragment}`);
      }
    }
  }
}

if (failures.length > 0) {
  console.error(`Built site link check failed with ${failures.length} issue(s):`);
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log(`Built site links valid: ${checked} local targets checked across ${htmlFiles.length} HTML pages.`);
