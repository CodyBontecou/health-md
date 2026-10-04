/** Bounded I/O and fixed, health-free JSON responses. No exception text escapes. */
export const REQUEST_MAX_BYTES = 16 * 1024;
export const REQUEST_TIMEOUT_MS = 5_000;
export const PROVIDER_MAX_BYTES = 16 * 1024;
export const PROVIDER_TIMEOUT_MS = 5_000;

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

export function onlyFields(body: Record<string, unknown>, fields: readonly string[]): boolean {
  return Object.keys(body).every((field) => fields.includes(field));
}

export function isObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

async function readText(body: ReadableStream<Uint8Array> | null, maxBytes: number, signal?: AbortSignal): Promise<string> {
  if (!body) throw new Error("body_missing");
  const reader = body.getReader();
  const cancel = () => { void reader.cancel().catch(() => {}); };
  signal?.addEventListener("abort", cancel, { once: true });
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      if (signal?.aborted) throw new Error("body_cancelled");
      const { value, done } = await reader.read();
      if (signal?.aborted) throw new Error("body_cancelled");
      if (done) break;
      size += value.byteLength;
      if (size > maxBytes) throw new Error("body_too_large");
      chunks.push(value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    return new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes);
  } finally {
    signal?.removeEventListener("abort", cancel);
    cancel();
    reader.releaseLock();
  }
}

function declaredOversize(headers: Headers, maxBytes: number): boolean {
  const length = headers.get("content-length");
  return length !== null && (!/^\d+$/.test(length) || Number(length) > maxBytes);
}

/** Caller supplies a deadline covering both headers and body. */
export async function readBoundedJson(response: Response, maxBytes = PROVIDER_MAX_BYTES, signal?: AbortSignal): Promise<unknown> {
  if (declaredOversize(response.headers, maxBytes)) {
    void response.body?.cancel().catch(() => {});
    throw new Error("body_too_large");
  }
  return JSON.parse(await readText(response.body, maxBytes, signal));
}

export async function readJsonBody(request: Request): Promise<Record<string, unknown> | null> {
  if (declaredOversize(request.headers, REQUEST_MAX_BYTES)) {
    void request.body?.cancel().catch(() => {});
    return null;
  }
  const controller = new AbortController();
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    const deadline = new Promise<never>((_, reject) => {
      timer = setTimeout(() => {
        controller.abort();
        reject(new Error("body_timeout"));
      }, REQUEST_TIMEOUT_MS);
    });
    const value: unknown = await Promise.race([
      readText(request.body, REQUEST_MAX_BYTES, controller.signal).then((text) => JSON.parse(text)), deadline,
    ]);
    return isObject(value) ? value : null;
  } catch {
    return null;
  } finally { if (timer !== undefined) clearTimeout(timer); controller.abort(); }
}

/** Deadline/abort includes streaming the response, not just receiving headers. */
export async function providerJson(url: string, options: RequestInit, successBody: "json" | "discard" = "json"): Promise<{ status: number; body: unknown; headers: Headers }> {
  const controller = new AbortController();
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    const deadline = new Promise<never>((_, reject) => {
      timer = setTimeout(() => { controller.abort(); reject(new Error("provider_timeout")); }, PROVIDER_TIMEOUT_MS);
    });
    return await Promise.race([
      (async () => {
        // "error" is rejected by the deployed compatibility profile. Manual mode
        // never follows a redirect; every 3xx below is a fixed provider failure.
        const response = await fetch(url, { ...options, redirect: "manual", signal: controller.signal });
        // Error bodies are never parsed, retained, logged, or reflected.
        if (response.status !== 200 || successBody === "discard") {
          void response.body?.cancel().catch(() => {});
          return { status: response.status, body: null, headers: response.headers };
        }
        return { status: response.status, body: await readBoundedJson(response, PROVIDER_MAX_BYTES, controller.signal), headers: response.headers };
      })(),
      deadline,
    ]);
  } finally { if (timer !== undefined) clearTimeout(timer); controller.abort(); }
}
