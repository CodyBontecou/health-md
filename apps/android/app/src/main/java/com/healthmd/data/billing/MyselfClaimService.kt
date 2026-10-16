package com.healthmd.data.billing

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URI

/** Explicit purchase-claim traffic only; health data never crosses this boundary. */
object MyselfClaimService {
    suspend fun createClaim(purchaseToken: String): String = withContext(Dispatchers.IO) {
        val server = "https://myself.md"
        val connection = URI("$server/api/migration/proof").toURL().openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 15_000
            connection.readTimeout = 30_000
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            val body = JSONObject().put("app", "health.md").put("store", "android")
                .put("kind", "iap").put("proof", purchaseToken).toString()
            connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            val status = connection.responseCode
            val stream = if (status == 200) connection.inputStream else connection.errorStream
            val response = stream?.bufferedReader()?.use { it.readText() }
                ?: error("The claim service did not respond.")
            val result = JSONObject(response)
            check(status == 200) { result.optString("error", "Your purchase could not be verified.") }
            val claimUrl = result.getString("claimUrl")
            val url = URI(claimUrl)
            check(url.scheme == "https" && url.host == "myself.md" && url.port == -1 &&
                url.userInfo == null && url.path == "/claim" && url.query == null &&
                url.fragment?.matches(Regex("^[A-Za-z0-9_-]{43}$")) == true) {
                "The claim service returned an invalid link."
            }
            claimUrl
        } finally {
            connection.disconnect()
        }
    }
}
