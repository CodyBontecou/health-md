#!/usr/bin/env node
import { createHash } from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildDocsMetadataMap } from '../docs-src/lib/docs-metadata.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const REPOSITORY_ROOT = path.resolve(ROOT, '../..');
const DIST = path.join(ROOT, 'dist');
const DOCS_CONTENT = path.join(ROOT, 'docs-src/src/content/docs');
const ORIGIN = 'https://healthmd.app';

function fail(message) {
  throw new Error(message);
}

function sha256(buffer) {
  return createHash('sha256').update(buffer).digest('hex');
}

async function read(relative) {
  return fs.readFile(path.join(DIST, ...relative.replace(/^\/+/, '').split('/')));
}

async function exists(relative) {
  return fs.access(path.join(DIST, ...relative.replace(/^\/+/, '').split('/')))
    .then(() => true)
    .catch(() => false);
}

function htmlPathForRoute(route) {
  return `${route.replace(/^\/+/, '')}index.html`;
}

function sitemapEntry(xml, route) {
  const loc = `${ORIGIN}${route}`.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return xml.match(new RegExp(`<url>\\s*<loc>${loc}<\\/loc>([\\s\\S]*?)<\\/url>`))?.[1];
}

async function validateArtifactManifest() {
  const manifest = JSON.parse((await read('/agents/manifest.json')).toString('utf8'));
  if (manifest.schema !== 'healthmd.agent_assets' || manifest.schema_version !== 1) {
    fail('Invalid /agents/manifest.json schema.');
  }
  for (const artifact of manifest.artifacts ?? []) {
    const buffer = await read(artifact.path);
    if (buffer.length !== artifact.bytes || sha256(buffer) !== artifact.sha256) {
      fail(`Agent artifact checksum mismatch: ${artifact.path}`);
    }
  }

  const skillManifest = JSON.parse((await read('/agents/skills/healthmd-cli/manifest.json')).toString('utf8'));
  const skill = await read(skillManifest.latest.path);
  if (skill.length !== skillManifest.latest.bytes || sha256(skill) !== skillManifest.latest.sha256) {
    fail('Versioned Health.md CLI skill checksum mismatch.');
  }

  const macTools = JSON.parse((await read('/agents/mcp/mac-tools-v1.json')).toString('utf8'));
  const portableTools = JSON.parse((await read('/agents/mcp/portable-tools-v1.json')).toString('utf8'));
  if (macTools.length !== 21 || portableTools.length !== 19) {
    fail('Published MCP tool catalog count mismatch.');
  }
}

async function validateLlmsLinks() {
  const llms = (await read('/llms.txt')).toString('utf8');
  if (!llms.includes('emerging convention, not a web standard')) {
    fail('/llms.txt must describe its non-standard discovery role.');
  }
  const links = [...llms.matchAll(/\]\((https:\/\/healthmd\.app\/[^)]+)\)/g)]
    .map((match) => new URL(match[1]));
  for (const link of links) {
    const pathname = link.pathname;
    const candidates = pathname.endsWith('/')
      ? [`${pathname}index.html`]
      : [pathname, `${pathname}/index.html`];
    if (!await Promise.any(candidates.map(async (candidate) => {
      if (await exists(candidate)) return true;
      throw new Error('missing');
    })).catch(() => false)) {
      fail(`/llms.txt points to a missing local target: ${pathname}`);
    }
  }
  return links.length;
}

async function validateDocsAlternatesAndFreshness() {
  const metadata = await buildDocsMetadataMap({
    contentRoot: DOCS_CONTENT,
    repositoryRoot: REPOSITORY_ROOT,
  });
  const sitemap = (await read('/sitemap-0.xml')).toString('utf8');
  let dated = 0;

  for (const [route, item] of metadata) {
    if (!await exists(item.markdownPath)) fail(`Missing Markdown alternate: ${item.markdownPath}`);
    const [sourceMarkdown, publishedMarkdown] = await Promise.all([
      fs.readFile(item.sourcePath),
      read(item.markdownPath),
    ]);
    if (!publishedMarkdown.equals(sourceMarkdown)) {
      fail(`Markdown alternate changed source bytes: ${path.relative(DOCS_CONTENT, item.sourcePath)}`);
    }
    const html = (await read(`/${htmlPathForRoute(route)}`)).toString('utf8');
    const alternate = html.match(/<link\s+rel="alternate"\s+type="text\/markdown"\s+href="([^"]+)"/i)?.[1];
    if (!alternate || new URL(alternate, ORIGIN).pathname !== item.markdownPath) {
      fail(`Incorrect Markdown alternate on ${route}`);
    }

    if (!item.lastModified) continue;
    const iso = item.lastModified.toISOString();
    if (!html.includes(`property="article:modified_time" content="${iso}"`)) {
      fail(`Missing truthful article:modified_time on ${route}`);
    }
    if (!html.includes(`\"dateModified\":\"${iso}\"`)) {
      fail(`Missing truthful JSON-LD dateModified on ${route}`);
    }
    const entry = sitemapEntry(sitemap, route);
    if (!entry || !entry.includes(`<lastmod>${iso}</lastmod>`)) {
      fail(`Missing matching sitemap lastmod for ${route}`);
    }
    dated += 1;
  }

  return { pages: metadata.size, dated };
}

await validateArtifactManifest();
const llmsLinks = await validateLlmsLinks();
const docs = await validateDocsAlternatesAndFreshness();
console.log(`Agent surfaces valid: ${docs.pages} Markdown alternatives, ${docs.dated} dated pages, ${llmsLinks} llms.txt links, and checksummed public artifacts.`);
