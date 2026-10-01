import type { Env } from "./types";

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
