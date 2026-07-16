#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import {
  lstat,
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  rename,
  rm,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const DOCS_SRC_ROOT = path.resolve(SCRIPT_DIR, '..');
const WEBSITE_ROOT = path.resolve(DOCS_SRC_ROOT, '..');
const CONTENT_TARGET = path.join(DOCS_SRC_ROOT, 'src/content/docs/reference');
const RAW_TARGET = path.join(DOCS_SRC_ROOT, 'public/reference/generated');
const LOCK_TARGET = path.join(DOCS_SRC_ROOT, 'reference-source.json');
const PUBLIC_ROUTE_PREFIX = '/docs/reference';
const GROUPS = ['core', 'individual', 'rollups', 'automation', 'cli'];
const GROUP_TITLES = {
  core: 'Core generated artifacts',
  individual: 'Individual Entry generated artifacts',
  rollups: 'Roll-up generated artifacts',
  automation: 'Automation generated artifacts',
  cli: 'CLI generated artifacts',
};

function fail(message) {
  throw new Error(message);
}

function usage() {
  return `Usage:
  node scripts/sync-export-reference.mjs --write [--source /absolute/app/path]
  node scripts/sync-export-reference.mjs --check [--source /absolute/app/path]
  node scripts/sync-export-reference.mjs --verify

Source resolution: --source, HEALTHMD_APP_ROOT, then the sibling app checkout.`;
}

function parseArgs(argv) {
  let mode = null;
  let source = null;
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--write' || argument === '--check' || argument === '--verify') {
      if (mode) fail(`Choose exactly one mode; received ${mode} and ${argument}.`);
      mode = argument.slice(2);
    } else if (argument === '--source') {
      if (source !== null) fail('--source may be supplied only once.');
      index += 1;
      if (index >= argv.length || argv[index].startsWith('--')) fail('--source requires a path.');
      source = argv[index];
    } else if (argument === '--help' || argument === '-h') {
      console.log(usage());
      process.exit(0);
    } else {
      fail(`Unknown argument: ${argument}\n\n${usage()}`);
    }
  }
  if (!mode) fail(`A mode is required.\n\n${usage()}`);
  if (mode === 'verify' && source !== null) fail('--verify does not use an app checkout; remove --source.');
  return { mode, source };
}

function resolveSourceRoot(sourceArgument) {
  if (sourceArgument) return path.resolve(sourceArgument);
  if (process.env.HEALTHMD_APP_ROOT) return path.resolve(process.env.HEALTHMD_APP_ROOT);
  // docs-src is nested one level below the website checkout; ../../app is its sibling app checkout.
  return path.resolve(DOCS_SRC_ROOT, '../../app');
}

function compareUTF8(left, right) {
  return Buffer.from(left, 'utf8').compare(Buffer.from(right, 'utf8'));
}

function sha256(buffer) {
  return createHash('sha256').update(buffer).digest('hex');
}

function byteCompare(left, right) {
  return left.length === right.length && left.equals(right);
}

function canonicalJSON(value) {
  return `${JSON.stringify(value, null, 2)}\n`;
}

function routePathForContent(relativeContentPath) {
  const withoutExtension = relativeContentPath.replace(/\.md$/i, '');
  const segments = withoutExtension.split('/');
  if (segments.at(-1) === 'index') segments.pop();
  const suffix = segments.length > 0 ? `${segments.map(encodeURIComponent).join('/')}/` : '';
  return `${PUBLIC_ROUTE_PREFIX}/${suffix}`;
}

function rawRouteForGenerated(relativeGeneratedPath) {
  return `${PUBLIC_ROUTE_PREFIX}/generated/${relativeGeneratedPath.split('/').map(encodeURIComponent).join('/')}`;
}

function contentPathForSource(sourcePath) {
  if (!sourcePath.startsWith('generated/')) {
    return sourcePath;
  }
  const relative = sourcePath.slice('generated/'.length).replace(/\.md$/i, '.md');
  if (relative === 'README.md') return 'generated/readme.md';
  return `generated/${relative}`;
}

async function walkFiles(root) {
  const output = [];
  async function visit(absoluteDirectory, relativeDirectory) {
    const entries = await readdir(absoluteDirectory, { withFileTypes: true });
    entries.sort((left, right) => Buffer.from(left.name).compare(Buffer.from(right.name)));
    for (const entry of entries) {
      const relative = relativeDirectory ? `${relativeDirectory}/${entry.name}` : entry.name;
      const absolute = path.join(absoluteDirectory, entry.name);
      if (entry.isSymbolicLink()) fail(`Symlinks are not allowed in the reference source: ${relative}`);
      if (entry.isDirectory()) {
        await visit(absolute, relative);
      } else if (entry.isFile()) {
        output.push(relative);
      } else {
        fail(`Unsupported filesystem entry in the reference source: ${relative}`);
      }
    }
  }
  await visit(root, '');
  return output;
}

function assertPortableInventory(paths, label) {
  const exact = new Set();
  const folded = new Map();
  for (const relative of paths) {
    if (relative.includes('\\') || relative.startsWith('/') || relative.split('/').some((part) => part === '' || part === '.' || part === '..')) {
      fail(`Non-portable ${label} path: ${relative}`);
    }
    if (/\p{Cc}/u.test(relative)) fail(`Control character in ${label} path: ${JSON.stringify(relative)}`);
    if (relative !== relative.normalize('NFC')) fail(`Non-NFC ${label} path: ${relative}`);
    if (exact.has(relative)) fail(`Duplicate ${label} path: ${relative}`);
    exact.add(relative);
    const key = relative.toLocaleLowerCase('en-US');
    if (folded.has(key)) fail(`Case-colliding ${label} paths: ${folded.get(key)} and ${relative}`);
    folded.set(key, relative);
  }
}

function decodeMarkdown(buffer, sourcePath) {
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(buffer).replace(/\r\n?/g, '\n');
  } catch {
    fail(`Markdown is not valid UTF-8: ${sourcePath}`);
  }
}

function firstNonEmptyLine(markdown) {
  const lines = markdown.split('\n');
  const index = lines.findIndex((line) => line.trim() !== '');
  return index === -1 ? { index: -1, line: '' } : { index, line: lines[index] };
}

function extractTitle(markdown, sourcePath) {
  const first = firstNonEmptyLine(markdown);
  const match = first.line.match(/^#\s+(.+?)\s*$/);
  if (!match) fail(`Rendered Markdown must begin with an H1: ${sourcePath}`);
  const lines = markdown.split('\n');
  lines.splice(first.index, 1);
  while (lines.length > 0 && lines[0] === '') lines.shift();
  return { title: match[1], body: lines.join('\n').replace(/^\n+/, '') };
}

function yamlString(value) {
  return JSON.stringify(value);
}

function addFrontmatter(title, body) {
  const normalizedBody = body.endsWith('\n') ? body : `${body}\n`;
  return `---\ntitle: ${yamlString(title)}\neditUrl: false\n---\n\n${normalizedBody}`;
}

function splitDestination(destination) {
  const match = destination.match(/^([^?#]*)(\?[^#]*)?(#.*)?$/s);
  return {
    path: match?.[1] ?? destination,
    query: match?.[2] ?? '',
    fragment: match?.[3] ?? '',
  };
}

function buildLinkResolver(sourceEntries, renderedRoutes) {
  const sourcePaths = new Set(sourceEntries.map((entry) => entry.path));
  const directories = new Set(['', 'generated', ...GROUPS.map((group) => `generated/${group}`)]);
  const allTargets = [...sourcePaths, ...directories];
  const folded = new Map(allTargets.map((target) => [target.toLocaleLowerCase('en-US'), target]));
  const directoryRoutes = new Map([
    ['', `${PUBLIC_ROUTE_PREFIX}/`],
    ['generated', `${PUBLIC_ROUTE_PREFIX}/generated/`],
    ...GROUPS.map((group) => [`generated/${group}`, `${PUBLIC_ROUTE_PREFIX}/generated/${group}/`]),
  ]);
  const publishedURLs = new Set([
    ...renderedRoutes.values(),
    ...sourceEntries.filter((entry) => entry.routes.raw).map((entry) => entry.routes.raw),
    ...directoryRoutes.values(),
  ]);
  const foldedPublishedURLs = new Map([...publishedURLs].map((url) => [url.toLowerCase(), url]));

  return function resolveLocalLink(destination, sourcePath) {
    if (destination === '' || destination.startsWith('#') || destination.startsWith('?')) return destination;
    if (/^[A-Za-z][A-Za-z0-9+.-]*:/.test(destination) || destination.startsWith('//')) return destination;

    const parts = splitDestination(destination);
    if (parts.path.startsWith('/')) {
      const routeCandidate = publishedURLs.has(parts.path) ? parts.path : (parts.path.endsWith('/') ? parts.path : `${parts.path}/`);
      if (!publishedURLs.has(routeCandidate)) {
        const caseMatch = foldedPublishedURLs.get(routeCandidate.toLowerCase());
        if (caseMatch) fail(`Case mismatch in root-relative link from ${sourcePath}: ${destination} (actual: ${caseMatch})`);
        fail(`Unresolved root-relative link in ${sourcePath}: ${destination}`);
      }
      return destination;
    }

    let decoded;
    try {
      decoded = decodeURIComponent(parts.path);
    } catch {
      fail(`Invalid percent-encoding in link from ${sourcePath}: ${destination}`);
    }
    if (decoded.includes('\\') || decoded.includes('\0')) fail(`Unsafe local link in ${sourcePath}: ${destination}`);

    const sourceDirectory = path.posix.dirname(sourcePath);
    const normalizedTarget = path.posix.normalize(path.posix.join(sourceDirectory === '.' ? '' : sourceDirectory, decoded));
    const target = normalizedTarget.length > 1 && normalizedTarget.endsWith('/') ? normalizedTarget.slice(0, -1) : normalizedTarget;
    if (target === '..' || target.startsWith('../') || path.posix.isAbsolute(target)) {
      fail(`Local link escapes docs/reference in ${sourcePath}: ${destination}`);
    }

    let exactTarget = target;
    if (!sourcePaths.has(exactTarget) && !directories.has(exactTarget)) {
      const alternate = exactTarget.endsWith('/') ? exactTarget.slice(0, -1) : `${exactTarget}/index.md`;
      if (sourcePaths.has(alternate)) exactTarget = alternate;
    }
    if (!sourcePaths.has(exactTarget) && !directories.has(exactTarget)) {
      const caseMatch = folded.get(exactTarget.toLocaleLowerCase('en-US'));
      if (caseMatch) fail(`Case mismatch in link from ${sourcePath}: ${destination} (actual: ${caseMatch})`);
      fail(`Unresolved local link in ${sourcePath}: ${destination}`);
    }

    let route = directoryRoutes.get(exactTarget);
    if (!route) route = renderedRoutes.get(exactTarget) ?? rawRouteForGenerated(exactTarget.slice('generated/'.length));
    return `${route}${parts.query}${parts.fragment}`;
  };
}

function transformMarkdownDestination(inner, resolver, sourcePath) {
  const leadingMatch = inner.match(/^\s*/);
  const leading = leadingMatch?.[0] ?? '';
  const rest = inner.slice(leading.length);
  if (rest.startsWith('<')) {
    const close = rest.indexOf('>');
    if (close === -1) return inner;
    const destination = rest.slice(1, close);
    const rewritten = resolver(destination, sourcePath);
    return `${leading}<${rewritten}>${rest.slice(close + 1)}`;
  }

  let end = 0;
  let escaped = false;
  while (end < rest.length) {
    const character = rest[end];
    if (escaped) {
      escaped = false;
      end += 1;
      continue;
    }
    if (character === '\\') {
      escaped = true;
      end += 1;
      continue;
    }
    if (/\s/.test(character)) break;
    end += 1;
  }
  if (end === 0) return inner;
  const destination = rest.slice(0, end);
  const rewritten = resolver(destination, sourcePath);
  return `${leading}${rewritten}${rest.slice(end)}`;
}

function rewriteMarkdownLinksInText(text, resolver, sourcePath) {
  let output = '';
  let cursor = 0;
  while (cursor < text.length) {
    const marker = text.indexOf('](', cursor);
    if (marker === -1) {
      output += text.slice(cursor);
      break;
    }
    output += text.slice(cursor, marker + 2);
    let index = marker + 2;
    let depth = 1;
    let escaped = false;
    let angle = false;
    for (; index < text.length; index += 1) {
      const character = text[index];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (character === '\\') {
        escaped = true;
        continue;
      }
      if (character === '<' && depth === 1) angle = true;
      if (character === '>' && angle) angle = false;
      if (angle) continue;
      if (character === '(') depth += 1;
      if (character === ')') {
        depth -= 1;
        if (depth === 0) break;
      }
    }
    if (depth !== 0) {
      output += text.slice(marker + 2);
      break;
    }
    const inner = text.slice(marker + 2, index);
    output += transformMarkdownDestination(inner, resolver, sourcePath);
    output += ')';
    cursor = index + 1;
  }
  return output;
}

function rewriteHTMLHrefs(text, resolver, sourcePath) {
  return text.replace(/(<[A-Za-z][^>]*?\bhref\s*=\s*)(["'])([^"']*)(\2)/gi, (match, prefix, quote, destination) => {
    return `${prefix}${quote}${resolver(destination, sourcePath)}${quote}`;
  });
}

function rewriteReferenceDefinition(text, resolver, sourcePath) {
  return text.replace(/^(\s{0,3}\[[^\]]+\]:\s*)(<[^>]+>|\S+)(.*)$/u, (match, prefix, token, suffix) => {
    if (token.startsWith('<') && token.endsWith('>')) {
      return `${prefix}<${resolver(token.slice(1, -1), sourcePath)}>${suffix}`;
    }
    return `${prefix}${resolver(token, sourcePath)}${suffix}`;
  });
}

function transformOutsideInlineCode(line, transform) {
  let output = '';
  let cursor = 0;
  while (cursor < line.length) {
    if (line[cursor] !== '`') {
      const next = line.indexOf('`', cursor);
      const end = next === -1 ? line.length : next;
      output += transform(line.slice(cursor, end));
      cursor = end;
      continue;
    }
    let runLength = 1;
    while (line[cursor + runLength] === '`') runLength += 1;
    const marker = '`'.repeat(runLength);
    const close = line.indexOf(marker, cursor + runLength);
    if (close === -1) {
      output += transform(line.slice(cursor));
      break;
    }
    output += line.slice(cursor, close + runLength);
    cursor = close + runLength;
  }
  return output;
}

function rewriteMarkdown(markdown, sourcePath, resolver) {
  const lines = markdown.split('\n');
  let fence = null;
  return lines.map((line) => {
    const fenceMatch = line.match(/^ {0,3}(`{3,}|~{3,})/);
    if (fenceMatch) {
      const marker = fenceMatch[1];
      if (!fence) {
        fence = { character: marker[0], length: marker.length };
      } else if (marker[0] === fence.character && marker.length >= fence.length) {
        fence = null;
      }
      return line;
    }
    if (fence) return line;
    return transformOutsideInlineCode(line, (segment) => {
      let result = rewriteMarkdownLinksInText(segment, resolver, sourcePath);
      result = rewriteHTMLHrefs(result, resolver, sourcePath);
      result = rewriteReferenceDefinition(result, resolver, sourcePath);
      return result;
    });
  }).join('\n');
}

function classifySource(relative, buffer) {
  const extension = path.posix.extname(relative).toLowerCase();
  if (!relative.startsWith('generated/')) {
    if (extension !== '.md') fail(`Only Markdown is allowed at docs/reference root: ${relative}`);
    return 'handwritten-markdown';
  }
  if (extension === '.json') return 'generated-json';
  if (extension === '.csv') return 'generated-csv';
  if (extension === '.md') {
    const markdown = decodeMarkdown(buffer, relative);
    const first = firstNonEmptyLine(markdown).line;
    if (/^#\s+/.test(first)) return 'generated-rendered-markdown';
    if (first.trim() === '---') return 'generated-raw-markdown-fixture';
    return 'generated-raw-markdown';
  }
  return 'generated-raw';
}

function collectSchemaIdentifiers(parsedJSON) {
  const pairs = new Map();
  function visit(value) {
    if (Array.isArray(value)) {
      value.forEach(visit);
      return;
    }
    if (!value || typeof value !== 'object') return;
    if (typeof value.schema === 'string' && (typeof value.schema_version === 'number' || typeof value.schema_version === 'string')) {
      const version = value.schema_version;
      if (!pairs.has(value.schema)) pairs.set(value.schema, new Set());
      pairs.get(value.schema).add(version);
    }
    Object.values(value).forEach(visit);
  }
  parsedJSON.forEach(({ value }) => visit(value));
  return [...pairs.entries()]
    .sort(([left], [right]) => compareUTF8(left, right))
    .map(([identifier, versions]) => ({
      identifier,
      versions: [...versions].sort((left, right) => {
        if (typeof left === 'number' && typeof right === 'number') return left - right;
        return compareUTF8(String(left), String(right));
      }),
    }));
}

function assertCurrentSchemaContracts(parsedJSON) {
  const schemas = collectSchemaIdentifiers(parsedJSON);
  const versionsByIdentifier = new Map(schemas.map((entry) => [entry.identifier, entry.versions]));
  const required = new Map([
    ['healthmd.api_export', [1, 2]],
    ['healthmd.external_provider_daily', [1]],
    ['healthmd.health_data', [7]],
    ['healthmd.healthkit_records', [1]],
    ['healthmd.raw_result', [1]],
    ['healthmd.rollup_summary', [7]],
  ]);
  for (const [identifier, expectedVersions] of required) {
    const actualVersions = versionsByIdentifier.get(identifier);
    if (canonicalJSON(actualVersions) !== canonicalJSON(expectedVersions)) {
      fail(`Unexpected ${identifier} versions: expected ${expectedVersions.join(', ')}, found ${actualVersions?.join(', ') ?? 'none'}.`);
    }
  }

  const dictionary = parsedJSON.find((entry) => entry.path === 'generated/core/data-dictionary.json')?.value;
  if (!Array.isArray(dictionary) || dictionary.length === 0) {
    fail('generated/core/data-dictionary.json must be a non-empty array.');
  }
  const dictionaryVersions = [...new Set(dictionary.map((entry) => entry?.schemaVersion))];
  if (canonicalJSON(dictionaryVersions) !== canonicalJSON([7])) {
    fail(`The generated data dictionary must contain schemaVersion 7 only; found ${dictionaryVersions.join(', ')}.`);
  }
}

function safeManifestPath(group, manifestPath, sourceByPath) {
  if (typeof manifestPath !== 'string' || manifestPath === '' || manifestPath.includes('\\')) {
    fail(`Invalid ${group} manifest path: ${JSON.stringify(manifestPath)}`);
  }
  const normalized = path.posix.normalize(manifestPath);
  if (normalized === '..' || normalized.startsWith('../') || path.posix.isAbsolute(normalized)) {
    fail(`Manifest path escapes generated/${group}: ${manifestPath}`);
  }
  const sourcePath = `generated/${group}/${normalized}`;
  if (!sourceByPath.has(sourcePath)) {
    const folded = [...sourceByPath.keys()].find((candidate) => candidate.toLocaleLowerCase('en-US') === sourcePath.toLocaleLowerCase('en-US'));
    if (folded) fail(`Case mismatch in ${group} manifest: ${manifestPath} (actual: ${folded})`);
    fail(`Missing file listed by ${group} manifest: ${manifestPath}`);
  }
  return sourcePath;
}

function verifyManifestEntries(group, manifest, sourceByPath) {
  const entries = group === 'core' ? manifest.files : manifest.artifacts;
  if (!Array.isArray(entries)) fail(`generated/${group}/manifest.json has no artifact array.`);
  const seen = new Set();
  for (const entry of entries) {
    const sourcePath = safeManifestPath(group, entry.path, sourceByPath);
    if (seen.has(sourcePath)) fail(`Duplicate path in ${group} manifest: ${entry.path}`);
    seen.add(sourcePath);
    const source = sourceByPath.get(sourcePath);
    if (entry.bytes !== source.bytes) {
      fail(`${group} manifest byte count mismatch for ${entry.path}: expected ${entry.bytes}, found ${source.bytes}`);
    }
    if (typeof entry.sha256 !== 'string' || entry.sha256.toLowerCase() !== source.sha256) {
      fail(`${group} manifest SHA-256 mismatch for ${entry.path}.`);
    }
  }
  const manifestPath = `generated/${group}/manifest.json`;
  const groupPrefix = `generated/${group}/`;
  const groupInventory = [...sourceByPath.keys()]
    .filter((sourcePath) => sourcePath.startsWith(groupPrefix) && sourcePath !== manifestPath)
    .sort(compareUTF8);
  const listedInventory = [...seen].sort(compareUTF8);
  if (groupInventory.join('\0') !== listedInventory.join('\0')) {
    const listed = new Set(listedInventory);
    const actual = new Set(groupInventory);
    const details = [
      ...groupInventory.filter((sourcePath) => !listed.has(sourcePath)).map((sourcePath) => `unlisted ${sourcePath}`),
      ...listedInventory.filter((sourcePath) => !actual.has(sourcePath)).map((sourcePath) => `missing ${sourcePath}`),
    ];
    fail(`${group} manifest does not cover its complete artifact inventory: ${details.join(', ')}`);
  }
  if (group === 'automation') {
    if (manifest.hashed_artifact_count !== entries.length) {
      fail('automation manifest hashed_artifact_count does not match its artifacts array.');
    }
    if (manifest.artifact_count !== entries.length + 1) {
      fail('automation manifest artifact_count must include every hashed artifact plus manifest.json.');
    }
  }
}

function verifyRequiredManifests(parsedJSON, sourceByPath) {
  const parsedByPath = new Map(parsedJSON.map((entry) => [entry.path, entry.value]));
  for (const group of ['core', 'automation', 'rollups']) {
    const manifestPath = `generated/${group}/manifest.json`;
    const manifest = parsedByPath.get(manifestPath);
    if (!manifest) fail(`Required manifest is missing or invalid: ${manifestPath}`);
    verifyManifestEntries(group, manifest, sourceByPath);
  }
}

function runGit(sourceRoot, args) {
  try {
    return execFileSync('git', ['-C', sourceRoot, ...args], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
  } catch {
    return null;
  }
}

function sourceProvenance(sourceRoot) {
  let repository = runGit(sourceRoot, ['remote', 'get-url', 'origin']);
  if (repository?.startsWith('git@github.com:')) repository = `https://github.com/${repository.slice('git@github.com:'.length).replace(/\.git$/, '')}.git`;
  const status = runGit(sourceRoot, ['status', '--porcelain=v1', '--untracked-files=all', '--', 'docs/reference']);
  const sourceCommit = status === '' ? runGit(sourceRoot, ['log', '-1', '--format=%H', '--', 'docs/reference']) : null;
  const tree = status === '' ? runGit(sourceRoot, ['rev-parse', 'HEAD:docs/reference']) : null;
  return {
    app_repository_url: repository,
    source_app_commit: sourceCommit,
    docs_reference_git_tree: tree,
  };
}

function aggregateSourceDigest(sourceEntries) {
  const hash = createHash('sha256');
  for (const entry of sourceEntries) {
    hash.update(entry.path, 'utf8');
    hash.update('\0');
    hash.update(String(entry.bytes), 'ascii');
    hash.update('\0');
    hash.update(entry.sha256, 'ascii');
    hash.update('\n');
  }
  return hash.digest('hex');
}

function artifactTable(entries, sourcePrefix = 'generated/') {
  const lines = [
    '| Artifact | Bytes | SHA-256 | Rendered | Raw |',
    '|---|---:|---|---|---|',
  ];
  for (const entry of entries) {
    const artifact = entry.path.startsWith(sourcePrefix) ? entry.path.slice(sourcePrefix.length) : entry.path;
    const rendered = entry.routes.rendered ? `[Open page](${entry.routes.rendered})` : '—';
    const raw = `[Download](${entry.routes.raw})`;
    lines.push(`| \`${artifact.replace(/\|/g, '\\|')}\` | ${entry.bytes} | \`${entry.sha256}\` | ${rendered} | ${raw} |`);
  }
  return lines.join('\n');
}

function landingPage(title, body) {
  return addFrontmatter(title, `${body.trim()}\n`);
}

function createLandingPages(generatedEntries) {
  const files = new Map();
  const groupLinks = GROUPS.map((group) => `- [${GROUP_TITLES[group]}](${PUBLIC_ROUTE_PREFIX}/generated/${group}/)`).join('\n');
  const sections = [];
  const rootEntries = generatedEntries.filter((entry) => !entry.path.slice('generated/'.length).includes('/'));
  if (rootEntries.length > 0) sections.push(`## Root artifacts\n\n${artifactTable(rootEntries)}`);
  for (const group of GROUPS) {
    const entries = generatedEntries.filter((entry) => entry.path.startsWith(`generated/${group}/`));
    sections.push(`## ${GROUP_TITLES[group]}\n\n${artifactTable(entries)}`);
  }
  files.set('generated/index.md', landingPage('Generated export artifacts', `These deterministic synthetic artifacts are copied byte-for-byte from the authoritative Health.md app reference. Use rendered pages for readable generated prose and raw links for exact fixtures.\n\n## Artifact groups\n\n${groupLinks}\n\n${sections.join('\n\n')}`));

  for (const group of GROUPS) {
    const entries = generatedEntries.filter((entry) => entry.path.startsWith(`generated/${group}/`));
    files.set(`generated/${group}/index.md`, landingPage(GROUP_TITLES[group], `This group contains ${entries.length} deterministic artifact${entries.length === 1 ? '' : 's'}. Checksums are SHA-256 hashes of the exact raw bytes.\n\n[View all generated artifacts](${PUBLIC_ROUTE_PREFIX}/generated/)\n\n${artifactTable(entries, `generated/${group}/`)}`));
  }
  return files;
}

async function buildExpected(sourceRoot, stagingRoot) {
  const referenceRoot = path.join(sourceRoot, 'docs/reference');
  const referenceStat = await lstat(referenceRoot).catch(() => null);
  if (!referenceStat?.isDirectory()) fail(`Reference source directory not found: ${referenceRoot}`);

  const sourcePaths = await walkFiles(referenceRoot);
  assertPortableInventory(sourcePaths, 'source');
  const sourceData = [];
  for (const relative of sourcePaths) {
    const buffer = await readFile(path.join(referenceRoot, ...relative.split('/')));
    sourceData.push({ path: relative, buffer, bytes: buffer.length, sha256: sha256(buffer) });
  }

  const handwritten = sourceData.filter((entry) => !entry.path.startsWith('generated/'));
  const generated = sourceData.filter((entry) => entry.path.startsWith('generated/'));
  if (handwritten.length !== 12) fail(`Expected 12 handwritten reference pages, found ${handwritten.length}.`);
  for (const entry of handwritten) {
    if (path.posix.extname(entry.path).toLowerCase() !== '.md') fail(`Unexpected handwritten reference file: ${entry.path}`);
  }

  const renderedRoutes = new Map();
  const routeOwners = new Map();
  for (const entry of sourceData) {
    entry.classification = classifySource(entry.path, entry.buffer);
    const rendered = entry.classification === 'handwritten-markdown' || entry.classification === 'generated-rendered-markdown';
    const contentPath = rendered ? contentPathForSource(entry.path) : null;
    const renderedRoute = contentPath ? routePathForContent(contentPath) : null;
    const rawRoute = entry.path.startsWith('generated/') ? rawRouteForGenerated(entry.path.slice('generated/'.length)) : null;
    entry.routes = { rendered: renderedRoute, raw: rawRoute };
    if (renderedRoute) {
      const key = renderedRoute.toLocaleLowerCase('en-US');
      if (routeOwners.has(key)) fail(`Duplicate rendered route ${renderedRoute}: ${routeOwners.get(key)} and ${entry.path}`);
      routeOwners.set(key, entry.path);
      renderedRoutes.set(entry.path, renderedRoute);
    }
  }
  for (const relative of ['generated/index.md', ...GROUPS.map((group) => `generated/${group}/index.md`)]) {
    const route = routePathForContent(relative);
    const key = route.toLocaleLowerCase('en-US');
    if (routeOwners.has(key)) fail(`Generated landing route collides with ${routeOwners.get(key)}: ${route}`);
    routeOwners.set(key, `<landing:${relative}>`);
  }

  const parsedJSON = [];
  for (const entry of generated.filter((item) => item.classification === 'generated-json')) {
    try {
      parsedJSON.push({ path: entry.path, value: JSON.parse(decodeMarkdown(entry.buffer, entry.path)) });
    } catch (error) {
      fail(`Generated JSON does not parse (${entry.path}): ${error.message}`);
    }
  }
  const sourceByPath = new Map(sourceData.map((entry) => [entry.path, entry]));
  verifyRequiredManifests(parsedJSON, sourceByPath);
  assertCurrentSchemaContracts(parsedJSON);

  const resolver = buildLinkResolver(sourceData, renderedRoutes);
  // Validate link safety in every source Markdown file. Only rendered pages use the rewritten result.
  for (const entry of sourceData.filter((item) => path.posix.extname(item.path).toLowerCase() === '.md')) {
    rewriteMarkdown(decodeMarkdown(entry.buffer, entry.path), entry.path, resolver);
  }

  const contentFiles = new Map();
  for (const entry of sourceData.filter((item) => item.routes.rendered)) {
    const markdown = decodeMarkdown(entry.buffer, entry.path);
    const { title, body } = extractTitle(markdown, entry.path);
    const rewritten = rewriteMarkdown(body, entry.path, resolver);
    const relativeContentPath = contentPathForSource(entry.path);
    if (contentFiles.has(relativeContentPath)) fail(`Duplicate content output path: ${relativeContentPath}`);
    contentFiles.set(relativeContentPath, addFrontmatter(title, rewritten));
  }
  for (const [relative, content] of createLandingPages(generated)) {
    if (contentFiles.has(relative)) fail(`Landing page output collision: ${relative}`);
    contentFiles.set(relative, content);
  }
  assertPortableInventory([...contentFiles.keys()], 'content output');

  const contentRoot = path.join(stagingRoot, 'content');
  const rawRoot = path.join(stagingRoot, 'raw');
  await mkdir(contentRoot, { recursive: true });
  await mkdir(rawRoot, { recursive: true });
  for (const [relative, content] of contentFiles) {
    const destination = path.join(contentRoot, ...relative.split('/'));
    await mkdir(path.dirname(destination), { recursive: true });
    await writeFile(destination, content, 'utf8');
  }
  for (const entry of generated) {
    const relative = entry.path.slice('generated/'.length);
    const destination = path.join(rawRoot, ...relative.split('/'));
    await mkdir(path.dirname(destination), { recursive: true });
    await writeFile(destination, entry.buffer);
  }

  const sourceEntries = sourceData.map(({ path: sourcePath, bytes, sha256: hash, classification, routes }) => ({
    path: sourcePath,
    bytes,
    sha256: hash,
    classification,
    routes,
  }));
  const publishedOutputs = [];
  for (const relative of [...contentFiles.keys()].sort()) {
    const buffer = await readFile(path.join(contentRoot, ...relative.split('/')));
    publishedOutputs.push({
      path: `src/content/docs/reference/${relative}`,
      bytes: buffer.length,
      sha256: sha256(buffer),
      classification: 'rendered-page',
      route: routePathForContent(relative),
    });
  }
  for (const entry of generated) {
    const relative = entry.path.slice('generated/'.length);
    publishedOutputs.push({
      path: `public/reference/generated/${relative}`,
      bytes: entry.bytes,
      sha256: entry.sha256,
      classification: 'raw-artifact',
      route: entry.routes.raw,
    });
  }
  publishedOutputs.sort((left, right) => compareUTF8(left.path, right.path));

  const renderedSourceCount = sourceEntries.filter((entry) => entry.routes.rendered).length;
  const lock = {
    format: 'healthmd.reference-source',
    format_version: 1,
    ...sourceProvenance(sourceRoot),
    aggregate: {
      algorithm: 'SHA-256',
      digest: aggregateSourceDigest(sourceEntries),
      canonicalization: 'For each source file sorted by path: UTF-8 path, NUL, decimal byte count, NUL, lowercase SHA-256, LF.',
    },
    schemas: collectSchemaIdentifiers(parsedJSON),
    counts: {
      source_files: sourceEntries.length,
      handwritten_markdown_pages: handwritten.length,
      generated_artifacts: generated.length,
      generated_json_artifacts: generated.filter((entry) => entry.classification === 'generated-json').length,
      generated_markdown_artifacts: generated.filter((entry) => entry.path.endsWith('.md')).length,
      generated_csv_artifacts: generated.filter((entry) => entry.classification === 'generated-csv').length,
      rendered_source_pages: renderedSourceCount,
      generated_landing_pages: 1 + GROUPS.length,
      rendered_pages: contentFiles.size,
      raw_artifacts: generated.length,
    },
    files: sourceEntries,
    published_outputs: publishedOutputs,
  };
  const lockBuffer = Buffer.from(canonicalJSON(lock));
  await writeFile(path.join(stagingRoot, 'reference-source.json'), lockBuffer);

  return {
    contentRoot,
    rawRoot,
    lockPath: path.join(stagingRoot, 'reference-source.json'),
    lock,
  };
}

async function inventoryFiles(root) {
  const stat = await lstat(root).catch(() => null);
  if (!stat) return [];
  if (!stat.isDirectory()) fail(`Expected a directory: ${root}`);
  return walkFiles(root);
}

async function compareTrees(expectedRoot, actualRoot, label) {
  const expectedPaths = await inventoryFiles(expectedRoot);
  const actualPaths = await inventoryFiles(actualRoot);
  const expectedSet = new Set(expectedPaths);
  const actualSet = new Set(actualPaths);
  const differences = [];
  for (const relative of expectedPaths) {
    if (!actualSet.has(relative)) {
      differences.push(`missing ${label}: ${relative}`);
      continue;
    }
    const [expected, actual] = await Promise.all([
      readFile(path.join(expectedRoot, ...relative.split('/'))),
      readFile(path.join(actualRoot, ...relative.split('/'))),
    ]);
    if (!byteCompare(expected, actual)) differences.push(`changed ${label}: ${relative}`);
  }
  for (const relative of actualPaths) {
    if (!expectedSet.has(relative)) differences.push(`unexpected ${label}: ${relative}`);
  }
  return differences;
}

async function compareFile(expectedPath, actualPath, label) {
  const [expected, actual] = await Promise.all([
    readFile(expectedPath),
    readFile(actualPath).catch(() => null),
  ]);
  if (!actual) return [`missing ${label}`];
  return byteCompare(expected, actual) ? [] : [`changed ${label}`];
}

async function replaceOutputsAtomically(expected) {
  const nonce = `${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  const operations = [
    { staged: expected.contentRoot, target: CONTENT_TARGET },
    { staged: expected.rawRoot, target: RAW_TARGET },
    { staged: expected.lockPath, target: LOCK_TARGET },
  ];
  const backups = [];
  const installed = [];
  try {
    for (const operation of operations) {
      await mkdir(path.dirname(operation.target), { recursive: true });
      const backup = `${operation.target}.sync-backup-${nonce}`;
      const exists = await lstat(operation.target).catch(() => null);
      if (exists) {
        await rename(operation.target, backup);
        backups.push({ target: operation.target, backup });
      }
      await rename(operation.staged, operation.target);
      installed.push(operation.target);
    }
    for (const { backup } of backups) await rm(backup, { recursive: true, force: true });
  } catch (error) {
    for (const target of installed.reverse()) await rm(target, { recursive: true, force: true }).catch(() => {});
    for (const { target, backup } of backups.reverse()) await rename(backup, target).catch(() => {});
    throw error;
  }
}

function validateLockShape(lock, lockBuffer) {
  if (!lock || lock.format !== 'healthmd.reference-source' || lock.format_version !== 1) fail('Unsupported reference-source.json format.');
  if (canonicalJSON(lock) !== lockBuffer.toString('utf8')) fail('reference-source.json is not in canonical deterministic JSON form.');
  if (!Array.isArray(lock.files) || !Array.isArray(lock.published_outputs)) fail('reference-source.json is missing inventories.');
  const paths = lock.files.map((entry) => entry.path);
  assertPortableInventory(paths, 'lock source');
  if ([...paths].sort(compareUTF8).join('\0') !== paths.join('\0')) {
    fail('reference-source.json source files are not sorted by path.');
  }
  for (const entry of lock.files) {
    if (!Number.isSafeInteger(entry.bytes) || entry.bytes < 0 || !/^[0-9a-f]{64}$/.test(entry.sha256)) {
      fail(`Invalid file metadata in reference-source.json: ${entry.path}`);
    }
    if (!entry.routes || !Object.hasOwn(entry.routes, 'rendered') || !Object.hasOwn(entry.routes, 'raw')) {
      fail(`Missing routes in reference-source.json: ${entry.path}`);
    }
  }
  if (lock.aggregate?.algorithm !== 'SHA-256' || lock.aggregate.digest !== aggregateSourceDigest(lock.files)) {
    fail('reference-source.json aggregate digest does not match its file inventory.');
  }
  if (lock.counts?.source_files !== lock.files.length) fail('reference-source.json source file count is inconsistent.');
  const generated = lock.files.filter((entry) => entry.path.startsWith('generated/'));
  if (lock.counts?.generated_artifacts !== generated.length || lock.counts?.raw_artifacts !== generated.length) {
    fail('reference-source.json generated artifact counts are inconsistent.');
  }
  const outputPaths = lock.published_outputs.map((entry) => entry.path);
  assertPortableInventory(outputPaths, 'published output');
  if ([...outputPaths].sort(compareUTF8).join('\0') !== outputPaths.join('\0')) {
    fail('reference-source.json published outputs are not sorted by path.');
  }
  for (const entry of lock.published_outputs) {
    if (!Number.isSafeInteger(entry.bytes) || entry.bytes < 0 || !/^[0-9a-f]{64}$/.test(entry.sha256)) {
      fail(`Invalid published output metadata: ${entry.path}`);
    }
    if (!entry.path.startsWith('src/content/docs/reference/') && !entry.path.startsWith('public/reference/generated/')) {
      fail(`Published output escapes script-owned trees: ${entry.path}`);
    }
  }
}

async function verifyCommitted() {
  const lockBuffer = await readFile(LOCK_TARGET).catch(() => null);
  if (!lockBuffer) fail(`Committed lock is missing: ${LOCK_TARGET}`);
  let lock;
  try {
    lock = JSON.parse(lockBuffer.toString('utf8'));
  } catch (error) {
    fail(`reference-source.json does not parse: ${error.message}`);
  }
  validateLockShape(lock, lockBuffer);

  const actualOutputPaths = [
    ...(await inventoryFiles(CONTENT_TARGET)).map((relative) => `src/content/docs/reference/${relative}`),
    ...(await inventoryFiles(RAW_TARGET)).map((relative) => `public/reference/generated/${relative}`),
  ].sort(compareUTF8);
  const lockedOutputPaths = lock.published_outputs.map((entry) => entry.path);
  if (actualOutputPaths.join('\0') !== lockedOutputPaths.join('\0')) {
    const actual = new Set(actualOutputPaths);
    const locked = new Set(lockedOutputPaths);
    const details = [
      ...lockedOutputPaths.filter((item) => !actual.has(item)).map((item) => `missing output: ${item}`),
      ...actualOutputPaths.filter((item) => !locked.has(item)).map((item) => `unexpected output: ${item}`),
    ];
    fail(`Committed output inventory differs from reference-source.json:\n${details.join('\n')}`);
  }
  for (const entry of lock.published_outputs) {
    const buffer = await readFile(path.join(DOCS_SRC_ROOT, ...entry.path.split('/')));
    if (buffer.length !== entry.bytes || sha256(buffer) !== entry.sha256) fail(`Committed output hash mismatch: ${entry.path}`);
  }

  const generatedEntries = lock.files.filter((entry) => entry.path.startsWith('generated/'));
  const sourceByPath = new Map();
  const parsedJSON = [];
  for (const entry of generatedEntries) {
    const relative = entry.path.slice('generated/'.length);
    const buffer = await readFile(path.join(RAW_TARGET, ...relative.split('/')));
    if (buffer.length !== entry.bytes || sha256(buffer) !== entry.sha256) fail(`Raw snapshot hash mismatch: ${entry.path}`);
    sourceByPath.set(entry.path, { ...entry, buffer });
    if (entry.classification === 'generated-json' || entry.path.toLowerCase().endsWith('.json')) {
      try {
        parsedJSON.push({ path: entry.path, value: JSON.parse(decodeMarkdown(buffer, entry.path)) });
      } catch (error) {
        fail(`Generated JSON does not parse (${entry.path}): ${error.message}`);
      }
    }
  }
  verifyRequiredManifests(parsedJSON, sourceByPath);
  assertCurrentSchemaContracts(parsedJSON);
  const schemas = collectSchemaIdentifiers(parsedJSON);
  if (canonicalJSON(schemas) !== canonicalJSON(lock.schemas)) fail('Schema identifiers in reference-source.json do not match the raw snapshot.');

  const renderedOutputs = lock.published_outputs.filter((entry) => entry.classification === 'rendered-page');
  const rawOutputs = lock.published_outputs.filter((entry) => entry.classification === 'raw-artifact');
  if (lock.counts.rendered_pages !== renderedOutputs.length || lock.counts.raw_artifacts !== rawOutputs.length) {
    fail('Published output counts in reference-source.json are inconsistent.');
  }
  return lock;
}

async function main() {
  const { mode, source } = parseArgs(process.argv.slice(2));
  if (mode === 'verify') {
    const lock = await verifyCommitted();
    console.log(`VERIFY OK: ${lock.counts.source_files} source records, ${lock.counts.rendered_pages} rendered pages, and ${lock.counts.raw_artifacts} exact raw artifacts are coherent.`);
    console.log(`Aggregate SHA-256: ${lock.aggregate.digest}`);
    return;
  }

  const sourceRoot = resolveSourceRoot(source);
  const temporaryParent = mode === 'write' ? DOCS_SRC_ROOT : tmpdir();
  const stagingRoot = await mkdtemp(path.join(temporaryParent, '.healthmd-reference-sync-'));
  try {
    const expected = await buildExpected(sourceRoot, stagingRoot);
    if (mode === 'write') {
      await replaceOutputsAtomically(expected);
      console.log(`WRITE OK: ${expected.lock.counts.source_files} source files produced ${expected.lock.counts.rendered_pages} rendered pages and ${expected.lock.counts.raw_artifacts} exact raw artifacts.`);
      console.log(`Source commit: ${expected.lock.source_app_commit ?? 'unavailable'}`);
      console.log(`docs/reference tree: ${expected.lock.docs_reference_git_tree ?? 'unavailable (source tree is dirty or not in Git)'}`);
      console.log(`Aggregate SHA-256: ${expected.lock.aggregate.digest}`);
    } else {
      const differences = [
        ...(await compareTrees(expected.contentRoot, CONTENT_TARGET, 'rendered page')),
        ...(await compareTrees(expected.rawRoot, RAW_TARGET, 'raw artifact')),
        ...(await compareFile(expected.lockPath, LOCK_TARGET, 'reference-source.json')),
      ];
      if (differences.length > 0) fail(`CHECK FAILED: script-owned outputs are stale:\n${differences.join('\n')}`);
      console.log(`CHECK OK: ${expected.lock.counts.rendered_pages} rendered pages, ${expected.lock.counts.raw_artifacts} exact raw artifacts, and reference-source.json match the app source.`);
      console.log(`Aggregate SHA-256: ${expected.lock.aggregate.digest}`);
    }
  } finally {
    await rm(stagingRoot, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(`sync-export-reference: ${error.message}`);
  process.exitCode = 1;
});
