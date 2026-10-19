import fs from 'node:fs/promises';
import path from 'node:path';

// A build is immutable during validation. Keep caches scoped to one validation
// so repeated navigation links share I/O and fragment parsing, including misses.
export function createBuildLinkCache(dist, escapeMessage) {
  const existence = new Map();
  const targets = new Map();
  const html = new Map();
  const ids = new Map();

  function exists(file) {
    if (!existence.has(file)) {
      existence.set(file, fs.access(file).then(() => true, () => false));
    }
    return existence.get(file);
  }

  function targetFile(url) {
    if (!targets.has(url.pathname)) {
      targets.set(url.pathname, resolveTarget(url.pathname));
    }
    return targets.get(url.pathname);
  }

  async function resolveTarget(pathname) {
    const decoded = decodeURIComponent(pathname).replace(/^\/+/, '');
    const base = path.resolve(dist, decoded);
    if (base !== dist && !base.startsWith(`${dist}${path.sep}`)) {
      throw new Error(`${escapeMessage}: ${pathname}`);
    }
    const candidates = pathname.endsWith('/')
      ? [path.join(base, 'index.html'), `${base}.html`]
      : [base, path.join(base, 'index.html'), `${base}.html`];
    for (const candidate of candidates) {
      if (await exists(candidate)) return candidate;
    }
    return candidates[0];
  }

  function htmlFor(file) {
    if (!html.has(file)) html.set(file, fs.readFile(file, 'utf8'));
    return html.get(file);
  }

  function idsFor(file) {
    if (!ids.has(file)) {
      ids.set(file, htmlFor(file).then((source) => new Set(
        [...source.matchAll(/\bid=(['"])(.*?)\1/gi)].map((match) => match[2]),
      )));
    }
    return ids.get(file);
  }

  return { exists, targetFile, htmlFor, idsFor };
}
