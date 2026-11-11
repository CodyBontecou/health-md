// Inactive AS07 SOURCE only: synthetic admission is not account or execution authority.
import { parseProfileSyncV1Read, parseProfileSyncV1Page, parseProfileSyncV1Error,
  type ProfileSyncV1Read, type ValidatedProfileSyncV1Record } from "./profile-sync-v1-contract";

export type ReadViewContext = Readonly<{
  issuer: string; environment: string; account: string; generation: number;
}>;
type PageRead = Extract<ProfileSyncV1Read, { mode: "snapshot" | "changes" }>;
export type ReadViewResult = Readonly<{
  result: "unavailable" | "invalid" | "quarantined" | "pending" | "complete" | "unchanged" | "resync_required" | "quota_exceeded";
}>;
export type ReadViewPage = Readonly<{
  context: ReadViewContext; read: PageRead;
  requestBytes: readonly number[]; replyBytes: readonly number[];
}>;
export type SelectedRead = Readonly<{
  context: ReadViewContext; read: PageRead; requestBytes: readonly number[]; epoch: number;
}>;
export type CompletedReadView = Readonly<{
  context: ReadViewContext; mode: "snapshot" | "changes"; snapshotId: string; highWatermark: number;
  baseHighWatermark: number | null; items: readonly ValidatedProfileSyncV1Record[];
  pages: readonly ReadViewPage[]; epoch: number;
}>;
export type TentativeReadView = CompletedReadView & Readonly<{ nextCursor: string }>;
export type ParsingRead = SelectedRead & Readonly<{ replyBytes: readonly number[] }>;
export type ReadViewDiagnostic = Readonly<{
  context: ReadViewContext | null; committed: CompletedReadView | null; tentative: TentativeReadView | null;
  selected: SelectedRead | null; parsing: ParsingRead | null; requiresSnapshot: boolean;
  epoch: number; retainedBytes: number; retainedPairs: number;
}>;
export interface ProfileSyncV1ReadView {
  select(context: ReadViewContext, originalReadBytes: Uint8Array): ReadViewResult;
  receive(context: ReadViewContext, originalReadBytes: Uint8Array, originalReplyBytes: Uint8Array): Promise<ReadViewResult>;
  reset(context: ReadViewContext): ReadViewResult;
  switch(nextContext: ReadViewContext): ReadViewResult;
  view(): ReadViewDiagnostic;
}
const MAX_BYTES = 4_194_304;
const result = (value: ReadViewResult["result"]): ReadViewResult => Object.freeze({ result: value });
function ownContext(value: ReadViewContext): ReadViewContext | null {
  try {
    if (!value || typeof value !== "object" || Object.keys(value).sort().join(" ") !== "account environment generation issuer") return null;
    const { issuer, environment, account, generation } = value;
    if (!["https://issuer-a.account-sync.example", "https://issuer-b.account-sync.example"].includes(issuer) ||
        !["synthetic-a", "synthetic-b"].includes(environment) || !["sentinel-A", "sentinel-B"].includes(account) ||
        !Number.isSafeInteger(generation) || generation < 0) return null;
    return Object.freeze({ issuer, environment, account, generation });
  } catch { return null; }
}
function sameContext(a: ReadViewContext, b: ReadViewContext): boolean {
  return a.issuer === b.issuer && a.environment === b.environment && a.account === b.account && a.generation === b.generation;
}
function equalBytes(a: ArrayLike<number>, b: ArrayLike<number>): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}
function capture(input: Uint8Array, maximum: number): Uint8Array | ReadViewResult {
  // Shared backing cannot provide an atomic byte snapshot. Reject it rather than guess.
  try {
    if (!(input instanceof Uint8Array) || !(input.buffer instanceof ArrayBuffer)) return result("invalid");
    if (input.byteLength > maximum) return result("quota_exceeded");
    return new Uint8Array(input.buffer, input.byteOffset, input.byteLength).slice();
  } catch { return result("invalid"); }
}
function advances(prior: ValidatedProfileSyncV1Record, next: ValidatedProfileSyncV1Record): boolean {
  if (prior.deleted || next.objectRevision <= prior.objectRevision || next.eventSequence <= prior.eventSequence) return false;
  if (next.deleted) return true;
  const sameContent = prior.content!.hash === next.content!.hash && prior.content!.contentJson === next.content!.contentJson;
  if (prior.contentRevision === next.contentRevision) return sameContent && prior.orderKey !== next.orderKey;
  return next.contentRevision! > prior.contentRevision! && !sameContent;
}
function frozenBytes(input: Uint8Array): readonly number[] {
  // Allocate once at the known wire length; iterable growth otherwise retains
  // several large backing arrays while admitting a boundary-sized reply.
  const bytes = new Array<number>(input.length);
  for (let i = 0; i < input.length; i++) bytes[i] = input[i]!;
  return Object.freeze(bytes);
}
const cloneContext = (c: ReadViewContext): ReadViewContext => Object.freeze({ ...c });
const cloneRead = (r: PageRead): PageRead => Object.freeze({ ...r });
function clonePage(p: ReadViewPage): ReadViewPage {
  return Object.freeze({ context: cloneContext(p.context), read: cloneRead(p.read),
    requestBytes: Object.freeze(p.requestBytes.slice()), replyBytes: Object.freeze(p.replyBytes.slice()) });
}
function cloneCompleted(v: CompletedReadView): CompletedReadView {
  return Object.freeze({ ...v, context: cloneContext(v.context), items: Object.freeze([...v.items]), pages: Object.freeze(v.pages.map(clonePage)) });
}
function cloneSelected(s: SelectedRead): SelectedRead {
  return Object.freeze({ ...s, context: cloneContext(s.context), read: cloneRead(s.read), requestBytes: Object.freeze(s.requestBytes.slice()) });
}

export function createProfileSyncV1ReadView(injection?: {
  sentinel: "healthmd.profile-sync.v1.read-view.synthetic-only";
  context: ReadViewContext;
  waitForParse?: (completion: Promise<void>) => Promise<void>;
}): ProfileSyncV1ReadView {
  const initial = injection?.sentinel === "healthmd.profile-sync.v1.read-view.synthetic-only" ? ownContext(injection.context) : null;
  const wait = injection?.waitForParse;
  if (!initial || (wait !== undefined && typeof wait !== "function")) {
    const unavailable = () => result("unavailable");
    return Object.freeze({ select: unavailable, receive: async () => unavailable(), reset: unavailable, switch: unavailable,
      view: () => Object.freeze({ context: null, committed: null, tentative: null, selected: null, parsing: null,
        requiresSnapshot: true, epoch: 0, retainedBytes: 0, retainedPairs: 0 }) });
  }
  let context = initial, committed: CompletedReadView | null = null, tentative: TentativeReadView | null = null;
  let selected: SelectedRead | null = null, parsing: ParsingRead | null = null, requiresSnapshot = true, epoch = 0;
  const current = (c: ReadViewContext) => { const owned = ownContext(c); return owned !== null && sameContext(owned, context); };
  function usage(): { retainedBytes: number; retainedPairs: number } {
    const arrays = new Set<readonly number[]>();
    const pages = [...(committed?.pages ?? []), ...(tentative?.pages ?? [])];
    for (const p of pages) { arrays.add(p.requestBytes); arrays.add(p.replyBytes); }
    if (selected) arrays.add(selected.requestBytes);
    if (parsing) { arrays.add(parsing.requestBytes); arrays.add(parsing.replyBytes); }
    let retainedBytes = 0;
    for (const a of arrays) retainedBytes += a.length;
    return { retainedBytes, retainedPairs: pages.length + (parsing ? 1 : 0) };
  }
  function stored(request: Uint8Array): ReadViewPage | undefined {
    return [...(tentative?.pages ?? []), ...(!requiresSnapshot && committed && sameContext(committed.context, context) ? committed.pages : [])]
      .find(p => equalBytes(p.requestBytes, request));
  }
  function discard(value: ReadViewResult["result"]): ReadViewResult {
    epoch++; selected = null; parsing = null; tentative = null; requiresSnapshot = true;
    return result(value);
  }
  function select(c: ReadViewContext, original: Uint8Array): ReadViewResult {
    if (!current(c)) return result("quarantined");
    const owned = capture(original, 8192); if (!(owned instanceof Uint8Array)) return owned;
    let read: ProfileSyncV1Read;
    try { read = parseProfileSyncV1Read(owned); } catch { return result("invalid"); }
    if (read.mode === "revision") return result("invalid");
    if (selected) return result(equalBytes(selected.requestBytes, owned) ? "unchanged" : "quarantined");
    if (stored(owned)) return result("unchanged");
    if (tentative ? read.mode !== tentative.mode || read.cursor !== tentative.nextCursor : read.cursor !== null) return result("quarantined");
    if (read.mode === "changes" && (requiresSnapshot || !committed || !sameContext(committed.context, context))) return result("resync_required");
    if (usage().retainedBytes + owned.length > MAX_BYTES || epoch >= Number.MAX_SAFE_INTEGER - 1) return result("quota_exceeded");
    epoch++;
    selected = Object.freeze({ context, read, requestBytes: frozenBytes(owned), epoch });
    return result("pending");
  }
  async function receive(c: ReadViewContext, originalRead: Uint8Array, originalReply: Uint8Array): Promise<ReadViewResult> {
    if (!current(c)) return result("quarantined");
    const request = capture(originalRead, 8192); if (!(request instanceof Uint8Array)) return request;
    const reply = capture(originalReply, MAX_BYTES); if (!(reply instanceof Uint8Array)) return reply;
    if (!selected || !equalBytes(selected.requestBytes, request)) {
      const prior = stored(request);
      return result(prior && equalBytes(prior.replyBytes, reply) ? "unchanged" : "quarantined");
    }
    if (parsing) return equalBytes(parsing.replyBytes, reply) ? result("pending") : discard("quarantined");
    const before = usage();
    if (before.retainedBytes + reply.length > MAX_BYTES || before.retainedPairs + 1 > 256) return result("quota_exceeded");
    const selection = selected, capturedEpoch = epoch;
    const flight: ParsingRead = Object.freeze({ ...selection, replyBytes: frozenBytes(reply) });
    parsing = flight;
    // Catch the real parser independently of the hook; an early-resolving hook cannot certify a page.
    const real = parseProfileSyncV1Page(reply).then(page => ({ kind: "page" as const, page }), () => {
      try { return { kind: "error" as const, error: parseProfileSyncV1Error(reply) }; }
      catch { return { kind: "invalid" as const }; }
    });
    const completion = real.then(() => {});
    const timing = Promise.resolve().then(() => wait?.(completion)).then(() => true, () => false);
    const [parsed, timingOk] = await Promise.all([real, timing]);
    if (epoch !== capturedEpoch || parsing !== flight || selected !== selection || !sameContext(context, selection.context)) return result("quarantined");
    parsing = null;
    if (!timingOk || parsed.kind === "invalid") return discard("invalid");
    if (parsed.kind === "error") {
      if (parsed.error.result === "resync_required") return discard("resync_required");
      if (parsed.error.result === "requires_upgrade") return discard("invalid");
      return result(parsed.error.result === "unavailable" || parsed.error.result === "invalid" || parsed.error.result === "quota_exceeded"
        ? parsed.error.result : "quarantined");
    }
    const page = parsed.page;
    if (page.mode !== selection.read.mode || page.items.length > selection.read.limit ||
        (tentative && (page.snapshotId !== tentative.snapshotId || page.highWatermark !== tentative.highWatermark))) return discard("quarantined");
    const baseline = committed && sameContext(committed.context, context) ? committed : null;
    if (baseline && page.highWatermark < baseline.highWatermark) return discard("quarantined");
    const items = [...(tentative?.items ?? []), ...page.items];
    if (items.length > (selection.read.mode === "snapshot" ? 100 : 256)) return result("quota_exceeded");
    if (selection.read.mode === "snapshot") {
      const ids = new Set<string>(), events = new Set<number>();
      for (let i = 0; i < items.length; i++) {
        const row = items[i]!, previous = items[i - 1];
        if (ids.has(row.profileId) || events.has(row.eventSequence) || (previous &&
            (previous.orderKey! > row.orderKey! || (previous.orderKey === row.orderKey && previous.profileId >= row.profileId)))) return discard("quarantined");
        ids.add(row.profileId); events.add(row.eventSequence);
      }
    } else {
      // These are coherence constraints on observed records, NOT a reconstructed/accepted native head.
      if (!baseline) return discard("resync_required");
      let sequence = baseline.highWatermark;
      const last = new Map<string, ValidatedProfileSyncV1Record>();
      for (const row of baseline.items) last.set(row.profileId, row);
      for (const row of items) {
        const prior = last.get(row.profileId);
        if (row.eventSequence <= sequence || (prior && !advances(prior, row))) return discard("quarantined");
        sequence = row.eventSequence; last.set(row.profileId, row);
      }
    }
    const pages = [...(tentative?.pages ?? []), Object.freeze({ context, read: selection.read,
      requestBytes: selection.requestBytes, replyBytes: flight.replyBytes })];
    if (page.nextCursor !== null && pages.some(p => p.read.cursor === page.nextCursor)) return discard("quarantined");
    const view: CompletedReadView = Object.freeze({ context, mode: selection.read.mode, snapshotId: page.snapshotId,
      highWatermark: page.highWatermark, baseHighWatermark: selection.read.mode === "changes" ? baseline!.highWatermark : null,
      items: Object.freeze(items), pages: Object.freeze(pages),
      epoch: tentative?.epoch ?? selection.epoch });
    epoch++; selected = null;
    if (page.nextCursor !== null) { tentative = Object.freeze({ ...view, nextCursor: page.nextCursor }); return result("pending"); }
    committed = view; tentative = null; requiresSnapshot = false;
    return result("complete");
  }
  function reset(c: ReadViewContext): ReadViewResult {
    return current(c) ? discard("resync_required") : result("quarantined");
  }
  function switchContext(next: ReadViewContext): ReadViewResult {
    const owned = ownContext(next);
    if (!owned || owned.generation <= context.generation) return result("invalid");
    // Committed bytes keep the original context even across a same-partition generation change.
    context = owned;
    return discard("resync_required");
  }
  return Object.freeze({ select, receive, reset, switch: switchContext,
    view: (): ReadViewDiagnostic => Object.freeze({ context: cloneContext(context), committed: committed ? cloneCompleted(committed) : null,
      tentative: tentative ? Object.freeze({ ...cloneCompleted(tentative), nextCursor: tentative.nextCursor }) : null,
      selected: selected ? cloneSelected(selected) : null,
      parsing: parsing ? Object.freeze({ ...cloneSelected(parsing), replyBytes: Object.freeze(parsing.replyBytes.slice()) }) : null,
      requiresSnapshot, epoch, ...usage() }) });
}
