export type SourceDomain = "health" | "location" | "usage";
export type SourceAvailability = "available" | "planned" | "unavailable" | "unknown";
export interface SourceReadiness {
  readonly id: string;
  readonly domain: SourceDomain;
  readonly capture: SourceAvailability;
  readonly display: SourceAvailability;
  readonly query: SourceAvailability;
  readonly export: SourceAvailability;
}
export interface OperationScope {
  readonly isCancelled: () => boolean;
  /** Register owned resource cleanup before suspending; called once on every exit. */
  readonly addFinalizer: (finalizer: () => void | Promise<void>) => void;
}
export interface ReadinessOperation {
  readonly read: (scope: OperationScope) => Promise<readonly SourceReadiness[]>;
}
export type ReadinessError = "operation_failed" | "invalid_source_state" | "cleanup_failed";
export interface ReadinessState {
  /** ready means the projection loaded, not that any native capability is available. */
  readonly phase: "idle" | "loading" | "ready" | "error" | "disposed";
  readonly selectedDomain: SourceDomain | "all";
  readonly sources: readonly SourceReadiness[];
  readonly errorCode: ReadinessError | null;
}
export interface ReadinessModel {
  readonly getSnapshot: () => ReadinessState;
  readonly subscribe: (listener: () => void) => () => void;
  readonly selectDomain: (domain: SourceDomain | "all") => void;
  readonly refresh: () => Promise<void>;
  readonly cancel: () => Promise<void>;
  readonly dispose: () => Promise<void>;
}
const domains: readonly string[] = ["health", "location", "usage"];
const availability: readonly string[] = ["available", "planned", "unavailable", "unknown"];
const invalid = () => new Error("invalid_source_state");
function copySources(sources: readonly SourceReadiness[]): readonly SourceReadiness[] {
  if (!Array.isArray(sources) || sources.length > 64) throw invalid();
  const ids = new Set<string>();
  return Object.freeze(sources.map((source) => {
    if (!source || typeof source.id !== "string" || !/^[a-z][a-z0-9._:-]{0,127}$/.test(source.id)
      || ids.has(source.id) || !domains.includes(source.domain)
      || ![source.capture, source.display, source.query, source.export].every((value) => availability.includes(value))) throw invalid();
    ids.add(source.id);
    return Object.freeze({ id: source.id, domain: source.domain, capture: source.capture,
      display: source.display, query: source.query, export: source.export });
  }));
}
function makeScope() {
  let cancelled = false;
  let closed = false;
  let closing: Promise<boolean> | undefined;
  const finalizers: (() => void | Promise<void>)[] = [];
  return {
    context: Object.freeze({
      isCancelled: () => cancelled,
      addFinalizer: (finalizer: () => void | Promise<void>) => {
        if (closed) throw new Error("operation_scope_closed");
        finalizers.push(finalizer);
      },
    }),
    close: (cancel: boolean): Promise<boolean> => {
      cancelled ||= cancel;
      if (!closing) {
        closed = true;
        const owned = finalizers.splice(0).reverse();
        closing = (async () => {
          let failed = false;
          for (const finalize of owned) {
            try { await finalize(); } catch { failed = true; }
          }
          return failed;
        })();
      }
      return closing;
    },
  };
}
/** Presentation-only seam. The injected operation owns source/grant authority. */
export function createReadinessModel(operation: ReadinessOperation): ReadinessModel {
  let state: ReadinessState = Object.freeze({ phase: "idle", selectedDomain: "all", sources: Object.freeze([]), errorCode: null });
  let generation = 0;
  let disposed = false;
  let disposeCleanup: Promise<boolean> | undefined;
  let active: ReturnType<typeof makeScope> | undefined;
  const listeners = new Set<() => void>();
  const publish = (update: Partial<ReadinessState>) => {
    state = Object.freeze({ ...state, ...update });
    for (const listener of [...listeners]) {
      try { listener(); } catch { /* A view subscriber cannot break operation cleanup. */ }
    }
  };
  const ensureLive = () => { if (disposed) throw new Error("model_disposed"); };
  return Object.freeze({
    getSnapshot: () => state,
    subscribe: (listener: () => void) => {
      ensureLive(); listeners.add(listener);
      return () => { listeners.delete(listener); };
    },
    selectDomain: (domain: SourceDomain | "all") => {
      ensureLive();
      if (domain !== "all" && !domains.includes(domain)) throw new Error("invalid_domain");
      if (state.selectedDomain !== domain) publish({ selectedDomain: domain });
    },
    refresh: async () => {
      ensureLive();
      const mine = ++generation;
      const prior = active;
      const cleanupFailed = prior ? await prior.close(true) : false;
      if (active === prior) active = undefined;
      if (disposed || mine !== generation) return;
      if (cleanupFailed) {
        publish({ phase: "error", errorCode: "cleanup_failed" });
        return;
      }
      const scope = makeScope(); active = scope;
      publish({ phase: "loading", errorCode: null });
      // Loading subscribers can synchronously cancel, dispose or supersede us.
      if (disposed || mine !== generation || scope.context.isCancelled()) {
        await scope.close(true);
        if (active === scope) active = undefined;
        return;
      }
      let next: readonly SourceReadiness[] | undefined;
      let errorCode: ReadinessError | null = null;
      try {
        const result = await operation.read(scope.context);
        if (!scope.context.isCancelled()) {
          try { next = copySources(result); } catch { errorCode = "invalid_source_state"; }
        }
      } catch { errorCode = "operation_failed"; }
      const finalizationFailed = await scope.close(false);
      if (active === scope) active = undefined;
      if (disposed || mine !== generation || scope.context.isCancelled()) return;
      if (finalizationFailed) errorCode = "cleanup_failed";
      if (errorCode) publish({ phase: "error", errorCode });
      else if (next) publish({ phase: "ready", sources: next, errorCode: null });
    },
    cancel: async () => {
      ensureLive(); const mine = ++generation;
      const previous = active;
      const failed = previous ? await previous.close(true) : false;
      if (active === previous) active = undefined;
      if (!disposed && mine === generation) publish({ phase: failed ? "error" : "idle", errorCode: failed ? "cleanup_failed" : null });
    },
    dispose: async () => {
      if (disposed) { if (disposeCleanup) await disposeCleanup; return; }
      disposed = true; ++generation;
      const previous = active;
      disposeCleanup = previous?.close(true);
      publish({ phase: "disposed", sources: Object.freeze([]), errorCode: null });
      listeners.clear();
      if (disposeCleanup) await disposeCleanup;
      if (active === previous) active = undefined;
    },
  });
}
/** Immutable component-facing props; selection never mutates capture/query/export state. */
export function projectReadiness(state: ReadinessState) {
  return Object.freeze({ phase: state.phase, selectedDomain: state.selectedDomain, errorCode: state.errorCode,
    sources: Object.freeze(state.sources.filter((source) => state.selectedDomain === "all" || source.domain === state.selectedDomain)) });
}
