#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { defaultLocale, localeFor, publishedLocales } from '../i18n/locales.mjs';
import { routePath } from '../i18n/routes.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const SOURCE = path.join(ROOT, 'sitemap.xml');
const SITE_ORIGIN = 'https://healthmd.app';
const HOME_LASTMOD = '2026-08-03';
const LEGAL_LASTMOD = '2026-08-06';

function absoluteRoute(routeId, locale) {
  return new URL(routePath(routeId, locale), SITE_ORIGIN).href;
}

function alternateLinks(routeId, surface) {
  const links = publishedLocales(surface).map((locale) =>
    `    <xhtml:link rel="alternate" hreflang="${locale.lang}" href="${absoluteRoute(routeId, locale.code)}" />`,
  );
  links.push(`    <xhtml:link rel="alternate" hreflang="x-default" href="${absoluteRoute(routeId, defaultLocale)}" />`);
  return links.join('\n');
}

function routeEntry(routeId, locale, surface, { changefreq, lastmod, priority }) {
  return [
    '  <url>',
    `    <loc>${absoluteRoute(routeId, locale)}</loc>`,
    alternateLinks(routeId, surface),
    `    <lastmod>${lastmod}</lastmod>`,
    `    <changefreq>${changefreq}</changefreq>`,
    `    <priority>${priority}</priority>`,
    '  </url>',
  ].join('\n');
}

function routeCluster(routeId, surface, metadata) {
  return publishedLocales(surface)
    .map(({ code }) => routeEntry(routeId, code, surface, metadata))
    .join('\n');
}

function replaceBlock(source, name, content) {
  const begin = `  <!-- BEGIN GENERATED ${name} -->`;
  const end = `  <!-- END GENERATED ${name} -->`;
  const pattern = new RegExp(`${begin.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}[\\s\\S]*?${end.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}`);
  if (!pattern.test(source)) throw new Error(`Sitemap is missing ${name} markers`);
  return source.replace(pattern, `${begin}\n${content}\n${end}`);
}

export function renderLocalizedSitemap(source) {
  const home = routeCluster('home', 'landing', {
    changefreq: 'weekly',
    lastmod: HOME_LASTMOD,
    priority: '1.0',
  });
  const legal = [
    routeCluster('privacy', 'legal', {
      changefreq: 'yearly',
      lastmod: LEGAL_LASTMOD,
      priority: '0.4',
    }),
    routeCluster('terms', 'legal', {
      changefreq: 'yearly',
      lastmod: LEGAL_LASTMOD,
      priority: '0.4',
    }),
  ].join('\n');
  return replaceBlock(replaceBlock(source, 'LOCALIZED HOME URLS', home), 'LOCALIZED LEGAL URLS', legal);
}

export async function localizeSitemapFile(file) {
  const source = await fs.readFile(file, 'utf8');
  await fs.writeFile(file, renderLocalizedSitemap(source));
  return file;
}

export async function buildLocalizedSitemap(outputFile) {
  const source = await fs.readFile(SOURCE, 'utf8');
  const rendered = renderLocalizedSitemap(source);
  await fs.mkdir(path.dirname(outputFile), { recursive: true });
  await fs.writeFile(outputFile, rendered);
  return outputFile;
}

const isDirectRun = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isDirectRun) {
  const writeSource = process.argv.includes('--write-source');
  const outputFlag = process.argv.indexOf('--output');
  const outputFile = writeSource
    ? SOURCE
    : outputFlag >= 0 && process.argv[outputFlag + 1]
      ? path.resolve(ROOT, process.argv[outputFlag + 1])
      : path.join(ROOT, 'dist', 'sitemap.xml');
  await buildLocalizedSitemap(outputFile);
  console.log(`Built localized sitemap at ${path.relative(ROOT, outputFile)}`);
}
