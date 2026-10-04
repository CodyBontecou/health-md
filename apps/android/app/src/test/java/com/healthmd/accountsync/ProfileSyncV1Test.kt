package com.healthmd.accountsync

import java.io.File
import kotlinx.serialization.json.*
import org.junit.Test

object ProfileSyncV1FixtureConformance {
    fun run(root: File, codec: ProfileSyncV1): String {
        val directory = File(root, "packages/contracts/profile-sync/v1/fixtures")
        fun load(name: String) = Json.parseToJsonElement(File(directory, name).readText()).jsonObject
        fun need(ok: Boolean, id: String) { check(ok) { id } }
        val vectors = load("content-vectors.json").getValue("positive").jsonObject
        vectors.forEach { (id, row) ->
            val v = row.jsonObject; val bytes = File(directory, v.getValue("file").jsonPrimitive.content).readBytes()
            val hash = v.getValue("sha256").jsonPrimitive.content
            val content = codec.parseContent(bytes, hash)
            need(content.contentJson.encodeToByteArray().contentEquals(bytes), id)
            need(content.requiresAction == v.getValue("requires_action").jsonArray.map { it.jsonPrimitive.content }, id)
            need(ProfileSyncV1.contentHash(bytes) == hash, id)
            need(ProfileSyncV1.contentHash(bytes.copyOf(bytes.size - 1)) != hash, "$id exact bytes")
        }
        val cases = load("parser-cases.json").getValue("cases").jsonArray
        cases.forEach { row ->
            val c = row.jsonObject; val id = c.getValue("id").jsonPrimitive.content
            val bytes = when {
                "repeat" in c -> ByteArray(c.getValue("repeat").jsonPrimitive.int) { 32 }
                "hex" in c -> c.getValue("hex").jsonPrimitive.content.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
                else -> c.getValue("raw").jsonPrimitive.content.encodeToByteArray()
            }
            val result = runCatching {
                when (c.getValue("entry").jsonPrimitive.content) {
                    "content" -> codec.parseContent(bytes)
                    "json" -> ProfileSyncV1.parseJson(bytes, ProfileSyncV1.CONTENT_MAX)
                    "record" -> codec.parseRecord(bytes)
                    "mutation" -> {
                        val mutation = codec.parseMutation(bytes)
                        c["request_hash"]?.let {
                            val expected = it.jsonPrimitive.content
                            need(mutation.requestHash == expected && ProfileSyncV1.mutationHash(bytes) == expected, id)
                            need(ProfileSyncV1.mutationHash(bytes + byteArrayOf(32)) != expected, "$id exact mutation bytes")
                        }
                    }
                    "read" -> codec.parseRead(bytes)
                    "page" -> codec.parsePage(bytes)
                    else -> error("Unknown fixture entry")
                }
            }
            if (result.isFailure) need(result.exceptionOrNull() is ProfileSyncV1.Invalid, "$id fixed codec error")
            need(result.isSuccess == c.getValue("valid").jsonPrimitive.boolean, id)
        }
        val scenarios = load("scenarios.json").getValue("scenarios").jsonArray
        scenarios.forEach { row ->
            val s = row.jsonObject; val id = s.getValue("id").jsonPrimitive.content
            val remote = codec.parseRecord(s.getValue("remote").toString().encodeToByteArray())
            s["mutation"]?.let { codec.parseMutation(it.toString().encodeToByteArray()) }
            s["original"]?.let { codec.parseMutation(it.toString().encodeToByteArray()) }
            s["retry"]?.let { codec.parseMutation(it.toString().encodeToByteArray()) }
            need(outcome(s, remote) == s.getValue("expected").jsonPrimitive.content, id)
        }
        val before = Json.parseToJsonElement(File(directory, "foreign-unchanged.json").readText()).jsonObject
        val after = Json.parseToJsonElement(File(directory, "foreign-local-edit.json").readText()).jsonObject
        need(before.getValue("profile").jsonObject.getValue("platform_extensions").jsonObject["android"] ==
            after.getValue("profile").jsonObject.getValue("platform_extensions").jsonObject["android"], "foreign exact local edit")
        return "${vectors.size} content fixtures, ${cases.size} parser cases, ${scenarios.size} test-only source scenarios"
    }
    // Test-only specification predicates; never production reconciliation or account authority.
    private fun outcome(s: JsonObject, r: ProfileSyncV1.Record): String {
        fun text(key: String) = s.getValue(key).jsonPrimitive.content
        fun bool(key: String) = s.getValue(key).jsonPrimitive.boolean
        return when (text("event")) {
            "publish" -> if (text("native_id") != r.profileId && s.getValue("mutation").jsonObject.getValue("base_revision").jsonPrimitive.long == 0L) "mapped_only_after_receipt" else "invalid"
            "replay" -> if (s["original"] == s["retry"]) "same_receipt" else "idempotency_mismatch"
            "observe" -> if (r.objectRevision <= s.getValue("base_revision").jsonPrimitive.long) "unchanged" else
                if (bool("pending")) { if (r.deleted) "edit_delete_conflict" else "edit_edit_conflict" } else
                if (r.deleted) "keep_local_unlink_review" else "pending_local_review"
            "fence" -> if (s["owner"] == s["current"]) "eligible_metadata_only" else "quarantine"
            "adopt" -> if (bool("already_mapped")) "existing_mapping_no_duplicate" else "fresh_blocked_native_id"
            "keep_both" -> if (text("new_profile_id") != r.profileId && text("new_native_id") != text("new_profile_id")) "independent_identity" else "invalid"
            "names" -> if (s.getValue("ids").jsonArray.distinct().size == s.getValue("names").jsonArray.size) "four_identities_no_fold" else "invalid"
            "preserve" -> if (text("provenance") == "verified") "publish_exact_overlay" else "quarantine"
            "protect" -> if (bool("commit")) "blocked_commit" else "eligible_metadata_only"
            "acceptance" -> if (s["accepted_hash"] != s["fetched_hash"]) "accepted_unchanged_candidate_staged" else "invalid"
            "reset" -> if (!bool("complete_snapshot")) "retain_until_complete" else if (bool("pending")) "quarantine_old_base_no_resurrection" else "keep_local_unlink_review"
            "snapshot_fence" -> if (s["first_snapshot_id"] != s["next_snapshot_id"] || s["first_high"] != s["next_high"]) "discard_restart_snapshot" else "continue_snapshot"
            "reorder" -> if (text("previous_hash") == r.content?.hash) "same_immutable_content" else "invalid"
            "cas" -> if (r.deleted) "gone_never_restore_id" else if (r.objectRevision != s.getValue("base_revision").jsonPrimitive.long) "conflict" else "eligible_metadata_only"
            else -> error("Unknown source scenario")
        }
    }
}
class ProfileSyncV1Test {
    @Test fun sharedFixturesAndSourceScenarios() {
        val root = generateSequence(File(".").absoluteFile) { it.parentFile }
            .first { File(it, "packages/contracts/profile-sync/v1/fixtures").isDirectory }
        ProfileSyncV1FixtureConformance.run(root, ProfileSyncV1())
    }
}
