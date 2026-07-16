#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const DIST = path.join(ROOT, 'dist');
const CANONICAL_ORIGIN = 'https://healthmd.app';
const SITE_ORIGINS = new Set([CANONICAL_ORIGIN, 'https://healthmd.isolated.tech']);
const DOCS_PREFIX = '/docs';

async function walk(directory) {
  const entries = await fs.readdir(directory, { withFileTypes: true });
  const files = [];
  for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...await walk(absolute));
    else if (entry.isFile()) files.push(absolute);
  }
  return files;
}

function pageUrl(file) {
  const relative = path.relative(DIST, file).split(path.sep).join('/');
  if (relative === 'index.html') return `${CANONICAL_ORIGIN}${DOCS_PREFIX}/`;
  if (relative.endsWith('/index.html')) {
    return `${CANONICAL_ORIGIN}${DOCS_PREFIX}/${relative.slice(0, -'index.html'.length)}`;
  }
  return `${CANONICAL_ORIGIN}${DOCS_PREFIX}/${relative}`;
}

function targetFile(url) {
  let relative = decodeURIComponent(url.pathname.slice(DOCS_PREFIX.length));
  relative = relative.replace(/^\/+/, '');
  if (relative === '404/') relative = '404.html';
  else if (!relative || relative.endsWith('/')) relative += 'index.html';
  const candidate = path.resolve(DIST, relative);
  if (candidate !== DIST && !candidate.startsWith(`${DIST}${path.sep}`)) {
    throw new Error(`path escapes docs build: ${url.pathname}`);
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
  const sourceUrl = pageUrl(sourceFile);
  const attributes = [...html.matchAll(/\b(?:href|src)=(['"])(.*?)\1/gi)].map((match) => match[2]);

  for (const destination of attributes) {
    if (!destination || /^(?:mailto:|tel:|data:|javascript:)/i.test(destination)) continue;

    let resolved;
    try {
      resolved = new URL(destination, sourceUrl);
    } catch {
      failures.push(`${path.relative(DIST, sourceFile)}: invalid URL ${JSON.stringify(destination)}`);
      continue;
    }

    if (!SITE_ORIGINS.has(resolved.origin) || !resolved.pathname.startsWith(`${DOCS_PREFIX}/`)) continue;

    let target;
    try {
      target = targetFile(resolved);
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
      const targetHtml = await htmlFor(target);
      const ids = new Set([...targetHtml.matchAll(/\bid=(['"])(.*?)\1/gi)].map((match) => match[2]));
      if (!ids.has(fragment)) {
        failures.push(`${path.relative(DIST, sourceFile)}: ${destination} -> missing fragment #${fragment}`);
      }
    }
  }
}

if (failures.length > 0) {
  console.error(`Built documentation link check failed with ${failures.length} issue(s):`);
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log(`Built documentation links valid: ${checked} internal targets checked across ${htmlFiles.length} HTML pages.`);
