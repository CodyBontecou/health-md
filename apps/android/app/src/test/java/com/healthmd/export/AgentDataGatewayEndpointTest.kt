package com.healthmd.export

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.AgentDataGatewayEndpoint
import org.junit.Test

class AgentDataGatewayEndpointTest {
    @Test
    fun acceptsHttpAndHttpsAndRedactsQueryParameters() {
        val httpsUrl = "https://gateway.example.com:8791/base?key=secret"
        val httpUrl = "http://localhost:8791?key=secret"

        assertThat(AgentDataGatewayEndpoint.isConfigured(httpsUrl)).isTrue()
        assertThat(AgentDataGatewayEndpoint.displayName(httpsUrl)).isEqualTo("gateway.example.com")
        assertThat(AgentDataGatewayEndpoint.redactedDescription(httpsUrl))
            .isEqualTo("https://gateway.example.com:8791/base")
        assertThat(AgentDataGatewayEndpoint.isConfigured(httpUrl)).isTrue()
        assertThat(AgentDataGatewayEndpoint.redactedDescription(httpUrl))
            .isEqualTo("http://localhost:8791")
    }

    @Test
    fun rejectsUnsafeDestinations() {
        assertThat(AgentDataGatewayEndpoint.isConfigured("ftp://gateway.example.com")).isFalse()
        assertThat(AgentDataGatewayEndpoint.isConfigured("https://user:pass@gateway.example.com")).isFalse()
        assertThat(AgentDataGatewayEndpoint.isConfigured("https://gateway.example.com#fragment")).isFalse()
        assertThat(AgentDataGatewayEndpoint.isConfigured("https://gateway.example.com\r\nInjected: yes")).isFalse()
        assertThat(AgentDataGatewayEndpoint.isConfigured("   ")).isFalse()
    }

    @Test
    fun fingerprintIsStableAndNeverPersistsTheEndpoint() {
        val first = AgentDataGatewayEndpoint.fingerprint("https://gateway.example.com:8791")
        val second = AgentDataGatewayEndpoint.fingerprint(" https://gateway.example.com:8791 ")
        val changed = AgentDataGatewayEndpoint.fingerprint("https://other.example.com:8791")

        assertThat(first).isEqualTo(second)
        assertThat(first).isNotEqualTo(changed)
        assertThat(first).matches("^[0-9a-f]{64}$")
        assertThat(AgentDataGatewayEndpoint.fingerprint("not a url")).isNull()
    }

    @Test
    fun displayNameFallsBackToConfigurationPrompt() {
        assertThat(AgentDataGatewayEndpoint.displayName("")).isEqualTo("Configure endpoint")
        assertThat(AgentDataGatewayEndpoint.redactedDescription(""))
            .isEqualTo("No endpoint configured")
    }
}
