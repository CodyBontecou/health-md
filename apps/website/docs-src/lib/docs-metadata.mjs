import { execFileSync } from 'node:child_process';
import fs from 'node:fs/promises';
import path from 'node:path';
import {
  defaultLocale,
  enabledLocales,
  localeFor,
} from '../../i18n/locales.mjs';
import { docsPathForSlug } from '../../i18n/routes.mjs';

export function markdownPathForDocsPath(pathname) {
  const clean = String(pathname).split(/[?#]/, 1)[0];
  if (!/(?:^|\/)docs(?:\/|$)/.test(clean)) {
    throw new Error(`Not a documentation path: ${pathname}`);
  }
  const withLeadingSlash = clean.startsWith('/') ? clean : `/${clean}`;
  const normalized = withLeadingSlash.endsWith('/') ? withLeadingSlash : `${withLeadingSlash}/`;
  return `${normalized}index.md`;
}

export function docsRouteForSource(relativePath) {
  const normalized = String(relativePath).replaceAll('\\', '/').replace(/^\/+/, '');
  const segments = normalized.split('/');
  const locale = enabledLocales.find((code) => localeFor(code).path === segments[0]) ?? defaultLocale;
  if (locale !== defaultLocale) segments.shift();
  const filename = segments.pop();
  if (!filename?.endsWith('.md')) throw new Error(`Not a Markdown source: ${relativePath}`);
  const basename = filename.slice(0, -3);
  if (basename !== 'index') segments.push(basename);
  return docsPathForSlug(segments.join('/'), locale);
}

export async function walkMarkdownSources(contentRoot) {
  const files = [];
  async function visit(directory) {
    const entries = await fs.readdir(directory, { withFileTypes: true });
    entries.sort((left, right) => left.name.localeCompare(right.name));
    for (const entry of entries) {
      const absolute = path.join(directory, entry.name);
      if (entry.isDirectory()) await visit(absolute);
      else if (entry.isFile() && entry.name.endsWith('.md')) files.push(absolute);
    }
  }
  await visit(contentRoot);
  return files;
}

function gitLastModified(repositoryRoot, sourcePath) {
  const relative = path.relative(repositoryRoot, sourcePath);
  try {
    const value = execFileSync(
      'git',
      ['-C', repositoryRoot, 'log', '-1', '--format=%cI', '--', relative],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] },
    ).trim();
    if (!value) return undefined;
    const date = new Date(value);
    return Number.isNaN(date.valueOf()) ? undefined : date;
  } catch {
    return undefined;
  }
}

export async function buildDocsMetadataMap({ contentRoot, repositoryRoot }) {
  const metadata = new Map();
  for (const sourcePath of await walkMarkdownSources(contentRoot)) {
    const relative = path.relative(contentRoot, sourcePath).split(path.sep).join('/');
    const pathname = docsRouteForSource(relative);
    metadata.set(pathname, {
      sourcePath,
      markdownPath: markdownPathForDocsPath(pathname),
      lastModified: gitLastModified(repositoryRoot, sourcePath),
    });
  }
  return metadata;
}
