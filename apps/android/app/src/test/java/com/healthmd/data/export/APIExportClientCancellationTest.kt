package com.healthmd.data.export

import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.async
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.SocketPolicy
import org.junit.After
import org.junit.Before
import org.junit.Test

/**
 * The scheduled-export notification cancel action cancels the exporter child job; the real OkHttp
 * transport must honour that cancellation while an upload is in flight instead of blocking until
 * the read timeout and degrading the user's cancellation into a retryable network failure.
 */
class APIExportClientCancellationTest {

    private lateinit var server: MockWebServer
    private lateinit var client: APIExportClient

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        client = APIExportClient(OkHttpClient())
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun uploadReturnsResponseForSuccessfulPost() = runBlocking {
        server.enqueue(
            MockResponse().setResponseCode(200).setBody("""{"ok":true}"""),
        )

        val result = client.upload(
            endpointUrl = server.url("/healthmd-qa").toString(),
            payload = """{"dates":1}""",
            authorizationHeader = null,
            requestHeaders = emptyList(),
        )

        assertThat(result.statusCode).isEqualTo(200)
        assertThat(result.responseBodyPreview).contains("ok")
    }

    @Test
    fun uploadThrowsCancellationPromptlyWhenInFlightUploadIsCancelled() = runBlocking {
        // The stalled server never responds; only cancellation can end this upload early.
        server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE))

        val startedAt = System.currentTimeMillis()
        val upload = async {
            client.upload(
                endpointUrl = server.url("/healthmd-qa").toString(),
                payload = """{"dates":1}""",
                authorizationHeader = null,
                requestHeaders = emptyList(),
            )
        }
        delay(300)
        upload.cancel()

        val error = runCatching { upload.await() }.exceptionOrNull()
        val elapsed = System.currentTimeMillis() - startedAt
        assertThat(error).isInstanceOf(CancellationException::class.java)
        assertThat(elapsed).isLessThan(5_000)
    }
}
