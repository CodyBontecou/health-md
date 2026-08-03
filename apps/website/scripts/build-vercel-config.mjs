#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { publishedLocales } from '../i18n/locales.mjs';
import { routePath } from '../i18n/routes.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const VERCEL_TEMPLATE = path.join(ROOT, 'vercel.template.json');
export const VERCEL_CONFIG = path.join(ROOT, 'vercel.json');
const MARKER = '    "__HEALTHMD_LOCALE_REDIRECTS__",';

function redirectLine(source) {
  return `    { "source": ${JSON.stringify(source)}, "destination": ${JSON.stringify(`${source}/`)}, "permanent": true },`;
}

export function renderVercelConfig(template) {
  const markerCount = template.split(MARKER).length - 1;
  if (markerCount !== 1) {
    throw new Error(`Vercel template must contain exactly one locale redirect marker; found ${markerCount}`);
  }

  const sources = publishedLocales('redirect').flatMap(({ code, path: localePath }) => {
    if (!localePath) throw new Error(`${code} enables redirects without a localized path`);
    return [
      routePath('home', code).replace(/\/$/, ''),
      routePath('docsHome', code).replace(/\/$/, ''),
    ];
  });
  if (new Set(sources).size !== sources.length) {
    throw new Error('Generated Vercel locale redirects must have unique source paths');
  }

  const rendered = template.replace(MARKER, sources.map(redirectLine).join('\n'));
  JSON.parse(rendered);
  return rendered;
}

export async function expectedVercelConfig() {
  return renderVercelConfig(await fs.readFile(VERCEL_TEMPLATE, 'utf8'));
}

export async function writeVercelConfig() {
  const rendered = await expectedVercelConfig();
  await fs.writeFile(VERCEL_CONFIG, rendered);
  return rendered;
}

const isDirectRun = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isDirectRun) {
  const expected = await expectedVercelConfig();
  if (process.argv.includes('--check')) {
    const actual = await fs.readFile(VERCEL_CONFIG, 'utf8');
    if (actual !== expected) {
      throw new Error('vercel.json is stale; run npm run i18n:vercel');
    }
    console.log('Vercel locale redirects match i18n/locales.mjs.');
  } else {
    await fs.writeFile(VERCEL_CONFIG, expected);
    console.log(`Built ${path.relative(ROOT, VERCEL_CONFIG)} from ${path.relative(ROOT, VERCEL_TEMPLATE)}.`);
  }
}
