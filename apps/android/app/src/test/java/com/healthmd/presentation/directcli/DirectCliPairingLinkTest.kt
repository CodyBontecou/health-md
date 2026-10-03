package com.healthmd.presentation.directcli

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class DirectCliPairingLinkTest {
    private val code = "12345678901234567890"

    @Test
    fun parsesCanonicalLanAndTailscalePayloads() {
        val link = DirectCliPairingLink.parse(
            "healthmd://direct-cli/pair?host=192.168.1.42&port=17647&code=$code",
        )

        assertThat(link).isEqualTo(DirectCliPairingLink("192.168.1.42", 17_647, code))
        listOf(
            "10.0.0.1",
            "172.16.0.1",
            "172.31.255.254",
            "192.168.255.254",
            "100.64.0.1",
            "100.127.255.254",
        ).forEach { host ->
            assertThat(DirectCliPairingLink.parse(
                "healthmd://direct-cli/pair?code=$code&port=65535&host=$host",
            )).isNotNull()
        }
    }

    @Test
    fun rejectsWrongOriginPublicAndAmbiguousHosts() {
        listOf(
            "https://direct-cli/pair?host=192.168.1.42&port=17647&code=$code",
            "HEALTHMD://DIRECT-CLI/pair?host=192.168.1.42&port=17647&code=$code",
            "healthmd://other/pair?host=192.168.1.42&port=17647&code=$code",
            "healthmd://direct-cli/other?host=192.168.1.42&port=17647&code=$code",
            "healthmd://user@direct-cli/pair?host=192.168.1.42&port=17647&code=$code",
            "healthmd://direct-cli/pair?host=example.com&port=17647&code=$code",
            "healthmd://direct-cli/pair?host=8.8.8.8&port=17647&code=$code",
            "healthmd://direct-cli/pair?host=127.0.0.1&port=17647&code=$code",
            "healthmd://direct-cli/pair?host=172.15.255.255&port=17647&code=$code",
            "healthmd://direct-cli/pair?host=172.32.0.1&port=17647&code=$code",
            "healthmd://direct-cli/pair?host=100.63.255.255&port=17647&code=$code",
            "healthmd://direct-cli/pair?host=100.128.0.1&port=17647&code=$code",
            "healthmd://direct-cli/pair?host=192.168.001.042&port=17647&code=$code",
            "healthmd://direct-cli/pair?host=3232235818&port=17647&code=$code",
        ).forEach { assertThat(DirectCliPairingLink.parse(it)).isNull() }
    }

    @Test
    fun rejectsMalformedOrExpandedPayloads() {
        listOf(
            " healthmd://direct-cli/pair?host=192.168.1.42&port=17647&code=$code",
            "healthmd://direct-cli/pair?host=192.168.1.42&port=17647&code=$code ",
            "healthmd://direct-cli/pair?host=192.168.1.42&port=17647&code=${code}\n",
            "healthmd://direct-cli/pair?host=192.168.1.42&port=17647&code=%31%32%33",
            "healthmd://direct-cli/pair?host=192.168.1.42&port=17647&code=123456",
            "healthmd://direct-cli/pair?host=192.168.1.42&port=17647&code=1234567890123456789a",
            "healthmd://direct-cli/pair?host=192.168.1.42&port=0&code=$code",
            "healthmd://direct-cli/pair?host=192.168.1.42&port=+17647&code=$code",
            "healthmd://direct-cli/pair?host=192.168.1.42&port=65536&code=$code",
            "healthmd://direct-cli/pair?host=192.168.1.42&port=17647&code=$code&extra=1",
            "healthmd://direct-cli/pair?host=192.168.1.42&port=17647&code=$code&code=$code",
            "healthmd://direct-cli/pair?host=192.168.1.42&port=17647&code=$code#fragment",
            String(CharArray(513) { 'a' }),
        ).forEach { assertThat(DirectCliPairingLink.parse(it)).isNull() }
    }
}
