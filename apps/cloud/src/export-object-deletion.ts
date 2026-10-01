import type { Env } from "./types";

function equalBytes(first: ArrayBuffer, second: ArrayBuffer): boolean {
  const left = new Uint8Array(first);
  const right = new Uint8Array(second);
  return left.byteLength === right.byteLength && left.every((value, index) => value === right[index]);
}

export async function stageExportObjectExactly(
  env: Env,
  objectKey: string,
  ciphertext: Uint8Array,
): Promise<void> {
  if (!(ciphertext.buffer instanceof ArrayBuffer)) {
    throw new Error("Encrypted export object staging is inconsistent");
  }
  const digestSource = ciphertext.byteOffset === 0 && ciphertext.byteLength === ciphertext.buffer.byteLength ?
    ciphertext.buffer : ciphertext.buffer.slice(ciphertext.byteOffset, ciphertext.byteOffset + ciphertext.byteLength);
  const expectedSha256 = await crypto.subtle.digest("SHA-256", digestSource);
  try {
    await env.EXPORTS.put(objectKey, ciphertext, {
      httpMetadata: { contentType: "application/octet-stream", cacheControl: "no-store" },
      sha256: expectedSha256,
    });
  } catch {
    // R2 may have committed the exact bytes before its response was lost.
  }
  let durable: R2Object | null;
  try {
    durable = await env.EXPORTS.head(objectKey);
  } catch {
    throw new Error("Encrypted export object staging verification is unavailable");
  }
  const durableSha256 = durable?.checksums?.sha256;
  if (!durable || durable.size !== ciphertext.byteLength || !durableSha256 ||
      !equalBytes(expectedSha256, durableSha256)) {
    throw new Error("Encrypted export object staging is inconsistent");
  }
}

// R2 delete responses can be lost after commit. Always verify the exact key
// through metadata only: never materialize ciphertext merely to prove erasure,
// and never surface provider errors that could contain an object identifier.
export async function deleteExportObjectExactly(env: Env, objectKey: string): Promise<void> {
  try {
    await env.EXPORTS.delete(objectKey);
  } catch {
    // Verify a possibly committed delete below.
  }
  let durable: R2Object | null;
  try {
    durable = await env.EXPORTS.head(objectKey);
  } catch {
    throw new Error("Encrypted export object deletion verification is unavailable");
  }
  if (durable) throw new Error("Encrypted export object was not removed");
}
