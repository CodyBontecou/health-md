// Test-only oracle. Actual production codec functions are injected by the runner,
// not replaced with a success stub. This is NOT AS07 native reconciliation/storage.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

export function scenarioOutcome(s) {
  const r = s.remote;
  switch (s.event) {
    case "publish": return s.native_id !== r.profile_id && s.mutation.base_revision === 0 ? "mapped_only_after_receipt" : "invalid";
    case "replay": return JSON.stringify(s.original) === JSON.stringify(s.retry) ? "same_receipt" : "idempotency_mismatch";
    case "observe": return r.object_revision <= s.base_revision ? "unchanged" : s.pending ? (r.deleted ? "edit_delete_conflict" : "edit_edit_conflict") : r.deleted ? "keep_local_unlink_review" : "pending_local_review";
    case "fence": return JSON.stringify(s.owner) === JSON.stringify(s.current) ? "eligible_metadata_only" : "quarantine";
    case "adopt": return s.already_mapped ? "existing_mapping_no_duplicate" : "fresh_blocked_native_id";
    case "keep_both": return s.new_profile_id !== r.profile_id && s.new_native_id !== s.new_profile_id ? "independent_identity" : "invalid";
    case "names": return new Set(s.ids).size === s.names.length ? "four_identities_no_fold" : "invalid";
    case "preserve": return s.provenance === "verified" ? "publish_exact_overlay" : "quarantine";
    case "protect": return s.commit ? "blocked_commit" : "eligible_metadata_only";
    case "acceptance": return s.accepted_hash !== s.fetched_hash ? "accepted_unchanged_candidate_staged" : "invalid";
    case "reset": return !s.complete_snapshot ? "retain_until_complete" : s.pending ? "quarantine_old_base_no_resurrection" : "keep_local_unlink_review";
    case "snapshot_fence": return s.first_snapshot_id !== s.next_snapshot_id || s.first_high !== s.next_high ? "discard_restart_snapshot" : "continue_snapshot";
    case "reorder": return s.previous_hash === r.content_hash ? "same_immutable_content" : "invalid";
    case "cas": return r.deleted ? "gone_never_restore_id" : r.object_revision !== s.base_revision ? "conflict" : "eligible_metadata_only";
    default: throw new Error("unknown source scenario");
  }
}
export async function runConformance(codec, root) {
  const dir = resolve(root, "packages/contracts/profile-sync/v1/fixtures");
  const load = name => JSON.parse(readFileSync(resolve(dir, name), "utf8"));
  const encode = v => new TextEncoder().encode(JSON.stringify(v));
  let fixtures = 0, parserCases = 0, scenarios = 0, readRequests = 0, fixedErrors = 0;
  const vectors = load("content-vectors.json");
  for (const [id, row] of Object.entries(vectors.positive)) {
    const bytes = new Uint8Array(readFileSync(resolve(dir, row.file)));
    const content = await codec.ValidatedProfileSyncV1Content.parse(bytes, row.sha256);
    assert.equal(content.contentJson, new TextDecoder().decode(bytes), id);
    assert.deepEqual(content.requiresAction, row.requires_action, id);
    assert.equal(await codec.profileSyncV1Hash(bytes), row.sha256, id);
    // Bytes, whitespace and Unicode are not silently canonicalized.
    assert.notEqual(await codec.profileSyncV1Hash(bytes.subarray(0, bytes.length - 1)), row.sha256, id);
    fixtures++;
  }
  for (const c of load("parser-cases.json").cases) {
    const bytes = c.repeat !== undefined ? new TextEncoder().encode(" ".repeat(c.repeat)) : c.hex !== undefined ? new Uint8Array(Buffer.from(c.hex, "hex")) : new TextEncoder().encode(c.raw);
    const parse = {
      content: b => codec.ValidatedProfileSyncV1Content.parse(b),
      json: b => codec.parseProfileSyncJson(b, 262_144),
      record: b => codec.ValidatedProfileSyncV1Record.parse(b),
      mutation: codec.parseProfileSyncV1Mutation,
      read: codec.parseProfileSyncV1Read,
      error: codec.parseProfileSyncV1Error,
      page: codec.parseProfileSyncV1Page,
    }[c.entry];
    assert.ok(parse, c.id);
    let accepted = true;
    try {
      const result = await parse(bytes);
      if (c.expected_name) {
        assert.equal(JSON.parse(result.contentJson).profile.name, c.expected_name, c.id);
        assert.equal(result.contentJson, c.raw, c.id);
        assert.equal(result.hash, c.expected_content_hash, c.id);
      }
      if (c.expected_read) {
        const e = c.expected_read;
        assert.deepEqual(result, e.mode === "revision" ? { mode: "revision", profileId: e.profile_id, contentRevision: e.content_revision, contentHash: e.content_hash } : { mode: e.mode, cursor: e.cursor, limit: e.limit }, c.id);
        assert.ok(Object.isFrozen(result), c.id); readRequests++;
      }
      if (c.expected_result) {
        assert.deepEqual(result, { result: c.expected_result }, c.id);
        assert.ok(Object.isFrozen(result), c.id);
        // A known error cannot become a successful read/page/reference/mutation.
        for (const success of [codec.parseProfileSyncV1Read, codec.parseProfileSyncV1Page, codec.parseProfileSyncV1Mutation, b => codec.ValidatedProfileSyncV1Record.parse(b)]) {
          await assert.rejects(async () => success(bytes), codec.ProfileSyncV1Error, c.id);
        }
        fixedErrors++;
      }
      if (c.request_hash) {
        assert.equal(result.requestHash, c.request_hash, c.id);
        assert.equal(await codec.profileSyncV1MutationHash(bytes), c.request_hash, c.id);
        assert.notEqual(await codec.profileSyncV1MutationHash(new Uint8Array([...bytes, 32])), c.request_hash, c.id);
      }
    } catch (e) { assert.ok(e instanceof codec.ProfileSyncV1Error, `${c.id}: fixed codec error`); accepted = false; }
    assert.equal(accepted, c.valid, c.id); parserCases++;
  }
  for (const s of load("scenarios.json").scenarios) {
    // Every shared scenario traverses the real full-content/metadata parser first.
    await codec.ValidatedProfileSyncV1Record.parse(encode(s.remote));
    if (s.mutation) await codec.parseProfileSyncV1Mutation(encode(s.mutation));
    if (s.original) await codec.parseProfileSyncV1Mutation(encode(s.original));
    if (s.retry) await codec.parseProfileSyncV1Mutation(encode(s.retry));
    assert.equal(scenarioOutcome(s), s.expected, s.id); scenarios++;
  }
  const foreign = JSON.parse(readFileSync(resolve(dir, "foreign-unchanged.json"), "utf8"));
  const edited = JSON.parse(readFileSync(resolve(dir, "foreign-local-edit.json"), "utf8"));
  assert.deepEqual(foreign.profile.platform_extensions.android, edited.profile.platform_extensions.android);
  assert.equal(foreign.profile.destination.kind, edited.profile.destination.kind);
  // Parser snapshots mutable input before digest awaits.
  const original = new Uint8Array(readFileSync(resolve(dir, "registry-current.json")));
  const pending = codec.ValidatedProfileSyncV1Content.parse(original); original.fill(32);
  const validated = await pending;
  assert.equal(validated.hash, vectors.positive["registry-current"].sha256);
  assert.ok(Object.isFrozen(validated));
  assert.throws(() => { validated.hash = "0".repeat(64); }, TypeError);
  assert.equal(codec.ValidatedProfileSyncV1Content.isValidated(validated), true);
  assert.equal(codec.ValidatedProfileSyncV1Content.isValidated({ contentJson: "{}", hash: "0".repeat(64) }), false);
  assert.equal(codec.ValidatedProfileSyncV1Content.isValidated(Object.create(codec.ValidatedProfileSyncV1Content.prototype)), false);
  assert.equal(codec.ValidatedProfileSyncV1Record.isValidated(Object.create(codec.ValidatedProfileSyncV1Record.prototype)), false);
  assert.throws(() => Reflect.construct(codec.ValidatedProfileSyncV1Content, [Symbol(), "{}", "0".repeat(64), []]), codec.ProfileSyncV1Error);
  assert.equal(readRequests, 6); assert.equal(fixedErrors, 11);
  return { fixtures, parserCases, scenarios, readRequests, fixedErrors, scope: "real codecs + test-only source scenario predicates; no auth/storage/native apply" };
}
