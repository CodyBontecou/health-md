package com.healthmd.domain.model

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MarkdownTemplateConditionalInstrumentationTest {
    @Test
    fun conditionalTags_areSafeWithAndroidRegex() {
        val template = """
            Before
            {{#sleep}}
            Sleep details
            {{/sleep}}
            {{#activity}}Activity details{{/activity}}
            After
        """.trimIndent()

        val withSleep = applyMarkdownConditionalSection(template, "sleep", include = true)
        val withoutActivity = applyMarkdownConditionalSection(withSleep, "activity", include = false)

        assertTrue(withoutActivity.contains("Sleep details"))
        assertFalse(withoutActivity.contains("{{#sleep}}"))
        assertFalse(withoutActivity.contains("Activity details"))
    }
}
