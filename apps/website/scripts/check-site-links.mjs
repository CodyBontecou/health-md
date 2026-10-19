#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createBuildLinkCache } from './lib/build-link-cache.mjs';

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

export async function checkBuiltSiteLinks(dist = DIST) {
  function pageURL(file) {
    const relative = path.relative(dist, file).split(path.sep).join('/');
    if (relative === 'index.html') return new URL('/', CANONICAL_ORIGIN);
    if (relative.endsWith('/index.html')) return new URL(`/${relative.slice(0, -'index.html'.length)}`, CANONICAL_ORIGIN);
    return new URL(`/${relative}`, CANONICAL_ORIGIN);
  }

  const { exists, targetFile, htmlFor, idsFor } = createBuildLinkCache(dist, 'path escapes dist');

  const allFiles = await walk(dist);
  const htmlFiles = allFiles.filter((file) => file.endsWith('.html'));
  if (htmlFiles.length === 0) throw new Error(`No HTML files found in ${dist}`);

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
        failures.push(`${path.relative(dist, sourceFile)}: invalid URL ${JSON.stringify(destination)}`);
        continue;
      }

      if (!SITE_ORIGINS.has(resolved.origin)) continue;
      if (IGNORED_PATH_PREFIXES.some((prefix) => resolved.pathname.startsWith(prefix))) continue;

      let target;
      try {
        target = await targetFile(resolved);
      } catch (error) {
        failures.push(`${path.relative(dist, sourceFile)}: ${error.message}`);
        continue;
      }

      checked += 1;
      if (!await exists(target)) {
        failures.push(`${path.relative(dist, sourceFile)}: ${destination} -> missing ${path.relative(dist, target)}`);
        continue;
      }

      if (resolved.hash && target.endsWith('.html')) {
        const fragment = decodeURIComponent(resolved.hash.slice(1));
        const ids = await idsFor(target);
        if (!ids.has(fragment)) {
          failures.push(`${path.relative(dist, sourceFile)}: ${destination} -> missing fragment #${fragment}`);
        }
      }
    }
  }

  return { failures, checked, pages: htmlFiles.length };
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const { failures, checked, pages } = await checkBuiltSiteLinks();
  if (failures.length > 0) {
    console.error(`Built site link check failed with ${failures.length} issue(s):`);
    for (const failure of failures) console.error(`- ${failure}`);
    process.exitCode = 1;
  } else console.log(`Built site links valid: ${checked} local targets checked across ${pages} HTML pages.`);
}
