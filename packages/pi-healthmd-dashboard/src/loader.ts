import { createHash } from "node:crypto";
import { constants } from "node:fs";
import { lstat, open, opendir, realpath } from "node:fs/promises";
import { basename, isAbsolute, relative, resolve, sep } from "node:path";
import { classifyContract, extractContext } from "./contracts.js";
import { jsonStringify, parseJsonLossless, parseJsonNumberTokens, utf8ByteLength } from "./json.js";
import type { DocumentOrigin, HealthStore, IndexEntry, JsonValue, LoadLimits, LoadedDocument, ReferenceResolution } from "./model.js";
import { DEFAULT_LIMITS } from "./model.js";

type Obj = { [key: string]: JsonValue };
const object = (value: JsonValue): value is Obj => value !== null && typeof value === "object" && !Array.isArray(value);
type OpenHandle = Awaited<ReturnType<typeof open>>;

async function verifyOpenIdentity(handle: OpenHandle, path: string, expectedCanonical: string) {
  const opened = await handle.stat();
  const currentCanonical = await realpath(path);
  const current = await lstat(path);
  if (current.isSymbolicLink() || currentCanonical !== expectedCanonical || opened.dev !== current.dev || opened.ino !== current.ino) {
    throw new Error(`Path identity changed during read-only open: ${path}`);
  }
  return opened;
}

export async function canonicalRoot(path: string): Promise<string> {
  const input = resolve(path);
  if ((await lstat(input)).isSymbolicLink()) throw new Error(`Symbolic-link inputs are not followed: ${path}`);
  const canonical = await realpath(input);
  const handle = await open(input, constants.O_RDONLY | (constants.O_NOFOLLOW ?? 0));
  try { await verifyOpenIdentity(handle, input, canonical); }
  finally { await handle.close(); }
  return canonical;
}

export function isAtOrBelow(path: string, root: string): boolean {
  const rel = relative(root, path);
  return rel === "" || (!rel.startsWith(`..${sep}`) && rel !== ".." && !isAbsolute(rel));
}

function requireConfinement(path: string, roots: readonly string[], displayPath = path): void {
  if (roots.length > 0 && !roots.some(root => isAtOrBelow(path, root))) throw new Error(`${displayPath} is outside approved Health.md roots`);
}

export async function requireApprovedPath(path: string, approvedRoots: readonly string[]): Promise<string> {
  if (approvedRoots.length === 0) throw new Error("No approved Health.md roots. Approve one with --healthmd-data, HEALTHMD_DATA_PATH, or /healthmd load <path>.");
  const canonical = await canonicalRoot(path);
  if (!approvedRoots.some(root => isAtOrBelow(canonical, root))) throw new Error(`${path} is outside approved Health.md roots; approve it with /healthmd load <path>`);
  return canonical;
}

interface TraversalCounter { entries: number }
async function collectJsonFiles(input: string, limits: LoadLimits, traversal: TraversalCounter, confinementRoots: readonly string[]): Promise<string[]> {
  const root = await canonicalRoot(input);
  requireConfinement(root, confinementRoots, input);
  const rootHandle = await open(root, constants.O_RDONLY | (constants.O_NOFOLLOW ?? 0));
  let rootStat: import("node:fs").Stats;
  try { rootStat = await verifyOpenIdentity(rootHandle, root, root); }
  finally { await rootHandle.close(); }
  if (rootStat.isFile()) {
    if (!root.toLowerCase().endsWith(".json")) throw new Error(`Explicit file is not JSON: ${input}`);
    return [root];
  }
  if (!rootStat.isDirectory()) throw new Error(`Input is neither a file nor directory: ${input}`);
  const output: string[] = [];
  const pending = [root];
  while (pending.length) {
    const directory = pending.pop()!;
    const directoryStat = await lstat(directory);
    if (directoryStat.isSymbolicLink()) throw new Error(`Symbolic-link directories are not followed: ${directory}`);
    const canonicalDirectory = await realpath(directory);
    if (!isAtOrBelow(canonicalDirectory, root)) throw new Error(`Directory identity escaped the selected root: ${directory}`);
    requireConfinement(canonicalDirectory, confinementRoots, directory);
    const handle = await opendir(canonicalDirectory);
    try {
      for await (const child of handle) {
        traversal.entries++;
        if (traversal.entries > limits.maxDirectoryEntries) throw new Error(`Directory entry count exceeds limit ${limits.maxDirectoryEntries}`);
        if (child.isSymbolicLink()) continue;
        const candidate = resolve(canonicalDirectory, child.name);
        if (child.isDirectory()) pending.push(candidate);
        else if (child.isFile() && child.name.toLowerCase().endsWith(".json")) {
          const canonical = await realpath(candidate);
          if (!isAtOrBelow(canonical, root)) throw new Error(`File identity escaped the selected root: ${candidate}`);
          requireConfinement(canonical, confinementRoots, candidate);
          output.push(canonical);
          if (output.length > limits.maxFiles) throw new Error(`JSON file count exceeds limit ${limits.maxFiles}`);
        }
      }
    } finally { await handle.close().catch(() => {}); }
  }
  return output.sort();
}

async function readBoundedFile(file: string, maxBytes: number, confinementRoots: readonly string[]): Promise<Buffer> {
  requireConfinement(file, confinementRoots);
  const handle = await open(file, constants.O_RDONLY | (constants.O_NOFOLLOW ?? 0));
  try {
    const stat = await verifyOpenIdentity(handle, file, file);
    if (!stat.isFile()) throw new Error(`${file} is not a regular file`);
    if (stat.size > maxBytes) throw new Error(`${file} exceeds per-file byte limit ${maxBytes}`);
    const chunks: Buffer[] = [];
    let total = 0;
    while (true) {
      const chunk = Buffer.allocUnsafe(Math.min(64 * 1024, maxBytes + 1 - total));
      const { bytesRead } = await handle.read(chunk, 0, chunk.length, null);
      if (bytesRead === 0) break;
      total += bytesRead;
      if (total > maxBytes) throw new Error(`${file} exceeds per-file byte limit ${maxBytes}`);
      chunks.push(chunk.subarray(0, bytesRead));
    }
    return Buffer.concat(chunks, total);
  } finally { await handle.close(); }
}

function assertJsonDepth(text: string, maxDepth: number): void {
  let depth = 0, inString = false, escaped = false;
  for (const character of text) {
    if (inString) {
      if (escaped) escaped = false;
      else if (character === "\\") escaped = true;
      else if (character === "\"") inString = false;
      continue;
    }
    if (character === "\"") inString = true;
    else if (character === "{" || character === "[") {
      depth++;
      if (depth > maxDepth + 1) throw new Error(`JSON depth exceeds limit ${maxDepth}`);
    } else if (character === "}" || character === "]") depth--;
  }
}

function childPath(parent: string, key: string | number, maxBytes: number): string {
  const parentBytes = utf8ByteLength(parent);
  let path: string;
  if (typeof key === "number") path = `${parent}[${key}]`;
  else {
    if (parentBytes + utf8ByteLength(key) + 4 > maxBytes) throw new Error(`JSON path exceeds per-path byte limit ${maxBytes}`);
    path = /^[A-Za-z_$][A-Za-z0-9_$-]*$/.test(key) ? `${parent}.${key}` : `${parent}[${jsonStringify(key)}]`;
  }
  if (utf8ByteLength(path) > maxBytes) throw new Error(`JSON path exceeds per-path byte limit ${maxBytes}`);
  return path;
}

interface IndexCounters { leaves: number; nodes: number; pathBytes: number }
function reservePath(path: string, counters: IndexCounters, limits: LoadLimits): string {
  counters.pathBytes += utf8ByteLength(path);
  if (counters.pathBytes > limits.maxIndexedPathBytes) throw new Error(`Indexed JSON paths exceed total byte limit ${limits.maxIndexedPathBytes}`);
  return path;
}

type Context = Partial<Pick<IndexEntry, "ownerDate" | "recordTimestamp" | "unit" | "statistic" | "semanticId" | "provenance" | "platform" | "provider" | "source" | "captureStatus">>;
function mergeContext(parent: Context, value: JsonValue, path: string, document: LoadedDocument): Context {
  const local = object(value) ? extractContext(value) : {};
  const provider = path.match(/(?:^|\.)providers\.([^.[]+)/)?.[1] ?? (path.match(/^\$\.whoop(?:\.|$)/) ? "whoop" : undefined);
  const platform = path.match(/(?:^|\.)platform\.([^.[]+)/)?.[1];
  const ownerDate = local.ownerDate ?? parent.ownerDate ?? document.ownerDate;
  const recordTimestamp = local.recordTimestamp ?? parent.recordTimestamp;
  const unit = local.unit ?? parent.unit, statistic = local.statistic ?? parent.statistic, semanticId = local.semanticId ?? parent.semanticId;
  const provenance = local.provenance ?? parent.provenance, resolvedPlatform = platform ?? local.platform ?? parent.platform ?? document.platform;
  const resolvedProvider = provider ?? local.provider ?? parent.provider, source = local.source ?? parent.source;
  const captureStatus = local.captureStatus ?? parent.captureStatus ?? document.captureStatus;
  return {
    ...(ownerDate ? { ownerDate } : {}), ...(recordTimestamp ? { recordTimestamp } : {}), ...(unit ? { unit } : {}),
    ...(statistic ? { statistic } : {}), ...(semanticId ? { semanticId } : {}), ...(provenance ? { provenance } : {}),
    ...(resolvedPlatform ? { platform: resolvedPlatform } : {}), ...(resolvedProvider ? { provider: resolvedProvider } : {}),
    ...(source ? { source } : {}), ...(captureStatus ? { captureStatus } : {}),
  };
}

function indexDocument(document: LoadedDocument, counters: IndexCounters, limits: LoadLimits): IndexEntry[] {
  const entries: IndexEntry[] = [];
  const stack: Array<{ value: JsonValue; path: string; depth: number; context: Context }> = [{ value: document.value, path: reservePath("$", counters, limits), depth: 0, context: {} }];
  while (stack.length) {
    const item = stack.pop()!;
    if (item.depth > limits.maxDepth) throw new Error(`JSON depth exceeds limit ${limits.maxDepth}`);
    counters.nodes++;
    if (counters.nodes > limits.maxNodes) throw new Error(`JSON node count exceeds limit ${limits.maxNodes}`);
    const kind: IndexEntry["kind"] = Array.isArray(item.value) ? "array" : object(item.value) ? "object" : "scalar";
    const context = mergeContext(item.context, item.value, item.path, document);
    const date = context.recordTimestamp ?? context.ownerDate;
    entries.push({ documentId: document.id, file: document.path, path: item.path, value: item.value, kind, contractKind: document.contractKind, ...(document.schema ? { schema: document.schema } : {}), ...(document.schemaVersion !== undefined ? { schemaVersion: document.schemaVersion } : {}), contractValid: document.contractValid, contractErrors: document.contractErrors, origin: document.origin, ...(document.operation ? { operation: document.operation } : {}), ...context, ...(date ? { date } : {}) });
    if (kind === "scalar") {
      counters.leaves++;
      if (counters.leaves > limits.maxLeaves) throw new Error(`JSON leaf count exceeds limit ${limits.maxLeaves}`);
    } else if (Array.isArray(item.value)) {
      for (let index = item.value.length - 1; index >= 0; index--) {
        const path = reservePath(childPath(item.path, index, limits.maxPathBytes), counters, limits);
        stack.push({ value: item.value[index]!, path, depth: item.depth + 1, context });
      }
    } else if (object(item.value)) {
      const children = Object.entries(item.value);
      for (let index = children.length - 1; index >= 0; index--) {
        const [key, value] = children[index]!;
        const path = reservePath(childPath(item.path, key, limits.maxPathBytes), counters, limits);
        stack.push({ value, path, depth: item.depth + 1, context });
      }
    }
  }
  return entries;
}

function findReferences(document: LoadedDocument, limits: LoadLimits, referenceCount: { value: number }): Omit<ReferenceResolution, "status" | "detail">[] {
  const found: Omit<ReferenceResolution, "status" | "detail">[] = [];
  const stack: Array<{ value: JsonValue; path: string }> = [{ value: document.value, path: "$" }];
  while (stack.length) {
    const { value, path } = stack.pop()!;
    if (Array.isArray(value)) {
      for (let index = value.length - 1; index >= 0; index--) stack.push({ value: value[index]!, path: childPath(path, index, limits.maxPathBytes) });
      continue;
    }
    if (!object(value)) continue;
    const schemaVersion = typeof value.schema_version === "number" || typeof value.schema_version === "string" || typeof value.schema_version === "bigint" ? value.schema_version : undefined;
    if (typeof value.schema === "string" && schemaVersion !== undefined && typeof value.sha256 === "string" && /^[0-9a-f]{64}$/.test(value.sha256)) {
      referenceCount.value++;
      if (referenceCount.value > limits.maxReferences) throw new Error(`Contract reference count exceeds limit ${limits.maxReferences}`);
      found.push({ documentId: document.id, path, schema: value.schema, schemaVersion, sha256: value.sha256, ...(typeof value.byte_count === "number" ? { expectedBytes: value.byte_count } : {}) });
    }
    for (const [key, child] of Object.entries(value)) stack.push({ value: child, path: childPath(path, key, limits.maxPathBytes) });
  }
  return found;
}

function resolveReferences(documents: LoadedDocument[], limits: LoadLimits): ReferenceResolution[] {
  const referenceCount = { value: 0 };
  const references = documents.flatMap(document => findReferences(document, limits, referenceCount));
  return references.map(reference => {
    const digest = documents.find(candidate => candidate.sha256 === reference.sha256);
    if (digest) {
      if (reference.expectedBytes !== undefined && digest.bytes !== reference.expectedBytes) return { ...reference, status: "byte_count_mismatch", resolvedDocumentId: digest.id, detail: `Digest matched ${basename(digest.path)}, but bytes ${digest.bytes} != expected ${reference.expectedBytes}` };
      if (digest.schema !== reference.schema || String(digest.schemaVersion) !== String(reference.schemaVersion)) return { ...reference, status: "digest_mismatch", resolvedDocumentId: digest.id, detail: "Digest matched loaded bytes, but contract identity did not" };
      return { ...reference, status: "resolved", resolvedDocumentId: digest.id, detail: `Matched exact loaded bytes in ${basename(digest.path)}` };
    }
    const identity = documents.find(candidate => candidate.schema === reference.schema && String(candidate.schemaVersion) === String(reference.schemaVersion));
    if (identity) return { ...reference, status: "digest_mismatch", resolvedDocumentId: identity.id, detail: "Loaded contract identity has a different SHA-256" };
    return { ...reference, status: "unresolved", detail: "No matching companion bytes were explicitly loaded" };
  });
}

interface BufferedJsonInput {
  path: string;
  bytes: Buffer;
  origin: DocumentOrigin;
  operation?: string;
}

export interface InMemoryJsonInput {
  path: string;
  text: string;
  origin: Exclude<DocumentOrigin, "file">;
  operation: string;
}

function buildStore(inputs: BufferedJsonInput[], limits: LoadLimits): HealthStore {
  if (inputs.length > limits.maxFiles) throw new Error(`JSON document count exceeds limit ${limits.maxFiles}`);
  const documents: LoadedDocument[] = [];
  const warnings: string[] = [];
  let totalBytes = 0;
  for (const input of inputs) {
    if (input.bytes.byteLength > limits.maxFileBytes) throw new Error(`${input.path} exceeds per-document byte limit ${limits.maxFileBytes}`);
    totalBytes += input.bytes.byteLength;
    if (totalBytes > limits.maxTotalBytes) throw new Error(`Loaded JSON exceeds total byte limit ${limits.maxTotalBytes}`);
    let value: JsonValue;
    const text = input.bytes.toString("utf8");
    try {
      assertJsonDepth(text, limits.maxDepth);
      value = parseJsonLossless(text);
    } catch (error) {
      if (error instanceof Error && /JSON depth exceeds/.test(error.message)) throw error;
      warnings.push(`${basename(input.path)}: invalid JSON (${error instanceof Error ? error.message : String(error)})`);
      continue;
    }
    const queryIdentity = object(value) && (value.schema === "healthmd.query_response" || value.schema === "healthmd.mcp_query_pages");
    const classification = classifyContract(value, queryIdentity ? parseJsonNumberTokens(text) : undefined);
    const contractErrors = classification.errors.map(error => error.slice(0, 512));
    if (contractErrors.length) warnings.push(...contractErrors.slice(0, 20).map(error => `${basename(input.path)}: ${error}`));
    documents.push({
      id: `doc-${documents.length + 1}`, path: input.path, origin: input.origin,
      ...(input.operation ? { operation: input.operation } : {}), bytes: input.bytes.byteLength,
      sha256: createHash("sha256").update(input.bytes).digest("hex"), value,
      contractKind: classification.kind, contractValid: classification.valid, contractErrors,
      experimentalV9: classification.experimentalV9,
      ...(classification.schema ? { schema: classification.schema } : {}),
      ...(classification.schemaVersion !== undefined ? { schemaVersion: classification.schemaVersion } : {}),
      ...(classification.profile ? { profile: classification.profile } : {}),
      ...(classification.ownerDate ? { ownerDate: classification.ownerDate } : {}),
      ...(classification.platform ? { platform: classification.platform } : {}),
      ...(classification.captureStatus ? { captureStatus: classification.captureStatus } : {}),
    });
  }
  const counters: IndexCounters = { leaves: 0, nodes: 0, pathBytes: 0 };
  const entries = documents.flatMap(document => indexDocument(document, counters, limits));
  return { documents, entries, references: resolveReferences(documents, limits), warnings: warnings.slice(0, 100), limits };
}

export function loadHealthDataText(inputs: InMemoryJsonInput[], overrides: Partial<LoadLimits> = {}): HealthStore {
  if (inputs.length === 0) throw new Error("At least one fetched Health.md JSON document is required");
  const limits = { ...DEFAULT_LIMITS, ...overrides };
  return buildStore(inputs.map(input => ({ ...input, bytes: Buffer.from(input.text, "utf8") })), limits);
}

export async function loadHealthData(inputs: string[], overrides: Partial<LoadLimits> = {}, confinementRoots: readonly string[] = []): Promise<HealthStore> {
  if (inputs.length === 0) throw new Error("At least one explicit local file or directory is required");
  const limits = { ...DEFAULT_LIMITS, ...overrides };
  const allFiles = new Set<string>();
  const traversal = { entries: 0 };
  for (const input of inputs) {
    for (const file of await collectJsonFiles(input, limits, traversal, confinementRoots)) {
      allFiles.add(file);
      if (allFiles.size > limits.maxFiles) throw new Error(`JSON file count exceeds limit ${limits.maxFiles}`);
    }
  }
  const buffered: BufferedJsonInput[] = [];
  let totalBytes = 0;
  for (const file of [...allFiles].sort()) {
    const bytes = await readBoundedFile(file, limits.maxFileBytes, confinementRoots);
    totalBytes += bytes.byteLength;
    if (totalBytes > limits.maxTotalBytes) throw new Error(`Loaded JSON exceeds total byte limit ${limits.maxTotalBytes}`);
    buffered.push({ path: file, bytes, origin: "file" });
  }
  return buildStore(buffered, limits);
}

export function storeSummary(store: HealthStore): string {
  const proposed = store.documents.filter(document => document.experimentalV9).length;
  const contracts = new Set(store.documents.map(document => `${document.contractKind}:${document.schema ?? "unknown"}@${document.schemaVersion ?? "?"}`));
  const origins = new Set(store.documents.map(document => document.origin));
  const refs = store.references.reduce<Record<string, number>>((counts, reference) => ({ ...counts, [reference.status]: (counts[reference.status] ?? 0) + 1 }), {});
  return `${store.documents.length} documents; ${store.entries.length} indexed paths; origins ${[...origins].join(", ") || "none"}; contracts ${[...contracts].join(", ") || "none"}; valid proposed v9 readers ${proposed}; references ${jsonStringify(refs)}`;
}
