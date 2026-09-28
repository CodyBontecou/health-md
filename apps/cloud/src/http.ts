import type { Env } from "./types";

const JSON_HEADERS = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer",
};

export class HttpError extends Error {
  readonly status: number;
  readonly code: string;
  constructor(status: number, code: string, message: string) {
    super(message);
    this.name = "HttpError";
    this.status = status;
    this.code = code;
  }
}

export function json(value: unknown, init: ResponseInit = {}): Response {
  const headers = new Headers(JSON_HEADERS);
  new Headers(init.headers).forEach((value, key) => headers.set(key, value));
  return new Response(JSON.stringify(value), { ...init, headers });
}

export function redirect(location: string, status = 303): Response {
  return new Response(null, {
    status,
    headers: {
      Location: location,
      "Cache-Control": "no-store",
      "Referrer-Policy": "no-referrer",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

export function errorResponse(error: unknown): Response {
  if (error instanceof HttpError) {
    return json({ error: error.code, message: error.message }, { status: error.status });
  }
  return json({ error: "internal_error", message: "The request could not be completed." }, { status: 500 });
}

export function assertJsonContentType(request: Request): void {
  const type = request.headers.get("Content-Type")?.split(";", 1)[0]?.trim().toLowerCase();
  if (type !== "application/json") {
    throw new HttpError(415, "unsupported_media_type", "Content-Type must be application/json.");
  }
}

export async function readJson<T>(request: Request, maximumBytes = 16_384): Promise<T> {
  assertJsonContentType(request);
  const bytes = await readBoundedBody(request, maximumBytes);
  try {
    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)) as T;
  } catch {
    throw new HttpError(400, "invalid_json", "Request body must be valid UTF-8 JSON.");
  }
}

export async function readBoundedBody(request: Request, maximumBytes: number): Promise<Uint8Array> {
  const declared = request.headers.get("Content-Length");
  if (declared !== null) {
    const length = Number(declared);
    if (!Number.isSafeInteger(length) || length < 0) {
      throw new HttpError(400, "invalid_content_length", "Content-Length is invalid.");
    }
    if (length > maximumBytes) throw new HttpError(413, "payload_too_large", "Export payload is too large.");
  }
  if (request.body === null) throw new HttpError(400, "empty_body", "Request body is required.");
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > maximumBytes) {
        await reader.cancel();
        throw new HttpError(413, "payload_too_large", "Export payload is too large.");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  if (total === 0) throw new HttpError(400, "empty_body", "Request body is required.");
  const result = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return result;
}

export function parsePositiveInteger(value: string, name: string, minimum: number, maximum: number): number {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < minimum || parsed > maximum) {
    throw new Error(`${name} must be an integer from ${minimum} through ${maximum}`);
  }
  return parsed;
}

export function assertSameOrigin(request: Request, env: Env): void {
  const origin = request.headers.get("Origin");
  if (env.ENVIRONMENT === "development" && origin === null && env.SYNTHETIC_PREVIEW_ONLY !== "1") return;
  if (origin === env.PUBLIC_ORIGIN) return;
  // Tailscale Serve rewrites HTTPS Origin to its HTTP loopback upstream.
  // Trust this shape ONLY in the upload-disabled synthetic preview, and
  // require a non-simple dashboard header so a cross-site form cannot mutate it.
  if (env.ENVIRONMENT === "development" && env.SYNTHETIC_PREVIEW_ONLY === "1") {
    const expected = new URL(env.PUBLIC_ORIGIN);
    const incoming = new URL(request.url);
    if (expected.protocol === "https:" && incoming.protocol === "http:" &&
        incoming.host === expected.host && origin === `http://${expected.host}` &&
        request.headers.get("X-Forwarded-Proto") === "https" &&
        request.headers.get("X-Forwarded-Host") === expected.host &&
        request.headers.get("X-HealthMd-Intent") === "dashboard") return;
  }
  throw new HttpError(403, "invalid_origin", "Request origin is not allowed.");
}

export function withSecurityHeaders(response: Response, env: Env): Response {
  const headers = new Headers(response.headers);
  headers.set("X-Content-Type-Options", "nosniff");
  headers.set("Referrer-Policy", "no-referrer");
  headers.set("Permissions-Policy", "camera=(), microphone=(), geolocation=(), payment=(), usb=()");
  headers.set("Cross-Origin-Opener-Policy", "same-origin");
  headers.set("Cross-Origin-Resource-Policy", "same-origin");
  headers.set("X-Frame-Options", "DENY");
  if (env.ENVIRONMENT === "production") {
    headers.set("Strict-Transport-Security", "max-age=63072000; includeSubDomains; preload");
  }
  return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
}
