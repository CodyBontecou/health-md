package com.healthmd.direct.protocol

import com.google.common.truth.Truth.assertThat
import java.util.Base64
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Test

/**
 * Export-profiles decision 10 (v2 mirror): byte-exact vectors for the additive
 * `settings_policy = profile` request shape, frozen in
 * `packages/contracts/direct-protocol/v2/fixtures/profile-policy-reference.json`
 * and verified from both sides (this suite and the Rust `v2_profile_vectors`).
 */
class ProfilePolicyInteropTest {
    private val fixture = DirectJson.json.parseToJsonElement(
        requireNotNull(javaClass.getResource("/profile-policy-reference.json")).readText(),
    ).jsonObject

    private fun b64(key: String): ByteArray =
        Base64.getDecoder().decode(fixture.getValue(key).jsonPrimitive.content)

    private fun text(key: String): String =
        fixture.getValue(key).jsonPrimitive.content

    private fun requestJson(): JsonObject =
        DirectJson.json.parseToJsonElement(b64("request_json_base64").decodeToString()).jsonObject

    @Test
    fun canonicalRequestBytesMatchTheFrozenVector() {
        val canonical = DirectJson.canonicalBytes(requestJson())
        assertThat(canonical).isEqualTo(b64("request_json_base64"))
    }

    @Test
    fun requestFingerprintMatchesTheFrozenVector() {
        val fingerprint = DirectJson.sha256Hex(DirectJson.canonicalBytes(requestJson()))
        assertThat(fingerprint).isEqualTo(text("request_fingerprint"))
    }

    @Test
    fun profileRequestDecodesThroughTheTypedModel() {
        val request = DirectJson.json.decodeFromString(ExportRequest.serializer(), requestJson().toString())
        val product = DirectJson.json.parseToJsonElement(request.product.toString()).jsonObject

        assertThat(product.getValue("product_id").jsonPrimitive.content).isEqualTo("generated_files_v1")
        assertThat(product.getValue("settings_policy").jsonPrimitive.content).isEqualTo("profile")
        assertThat(product.getValue("profile_reference").jsonObject.getValue("profile_id").jsonPrimitive.content)
            .isEqualTo("99999999-8888-4777-8666-555555555555")
        assertThat(product.getValue("profile_reference").jsonObject.getValue("name").jsonPrimitive.content)
            .isEqualTo("Weekly Sleep")
    }

    @Test
    fun generatedFilesProductBuilderMatchesTheFrozenProduct() {
        val reference = ProfileReference(
            profileId = "99999999-8888-4777-8666-555555555555",
            name = "Weekly Sleep",
        )
        val built = V2Codec.generatedFilesProduct(SettingsPolicy.PROFILE, reference)
        val frozen = requestJson().getValue("product").jsonObject
        assertThat(DirectJson.canonicalBytes(built)).isEqualTo(DirectJson.canonicalBytes(frozen))
    }

    @Test
    fun unnamedReferenceOmitsTheNameField() {
        val built = V2Codec.generatedFilesProduct(
            SettingsPolicy.PROFILE,
            ProfileReference(profileId = "99999999-8888-4777-8666-555555555555"),
        )
        val frozenUnnamed = DirectJson.json
            .parseToJsonElement(b64("request_unnamed_reference_json_base64").decodeToString())
            .jsonObject
            .getValue("product")
            .jsonObject

        assertThat(DirectJson.canonicalBytes(built)).isEqualTo(DirectJson.canonicalBytes(frozenUnnamed))
        assertThat(built.getValue("profile_reference").jsonObject.keys).doesNotContain("name")
    }

    @Test
    fun oldPeerFailsClosedOnTheProfilePolicyAndReference() {
        // An older v2 peer knows neither the policy variant nor the field: both must
        // fail the decode instead of silently defaulting.
        @Serializable
        data class LegacyProduct(
            @SerialName("settings_policy") val settingsPolicy: String,
        )
        val legacyJson = Json { ignoreUnknownKeys = false }
        val product = requestJson().getValue("product").jsonObject

        val policyRejected = runCatching {
            val policy = product.getValue("settings_policy").jsonPrimitive.content
            check(policy == "requested_scope" || policy == "saved_device_settings") {
                "unknown policy"
            }
        }
        assertThat(policyRejected.isFailure).isTrue()

        val fieldRejected = runCatching {
            legacyJson.decodeFromString(LegacyProduct.serializer(), product.toString())
        }
        assertThat(fieldRejected.isFailure).isTrue()
    }
}
