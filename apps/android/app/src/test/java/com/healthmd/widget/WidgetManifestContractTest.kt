package com.healthmd.widget

import com.google.common.truth.Truth.assertThat
import org.junit.Test
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

class WidgetManifestContractTest {
    @Test
    fun `manifest declares four non-exported providers and exported setup activity`() {
        val manifest = sourceFile("app/src/main/AndroidManifest.xml").readText()

        listOf(
            "HealthSummaryWidgetReceiver",
            "ActivityWidgetReceiver",
            "HeartRangeWidgetReceiver",
            "SleepWidgetReceiver",
        ).forEach { receiver ->
            val declaration = Regex(
                "<receiver[^>]*android:name=\"[^\"]*$receiver\"[\\s\\S]*?</receiver>"
            ).find(manifest)?.value
            assertThat(declaration).isNotNull()
            assertThat(declaration).contains("android:exported=\"false\"")
            assertThat(declaration).contains("android.appwidget.action.APPWIDGET_UPDATE")
        }
        val localeReceiver = Regex(
            "<receiver[^>]*HealthWidgetLocaleChangeReceiver[^>]*>[\\s\\S]*?</receiver>"
        ).find(manifest)?.value
        assertThat(localeReceiver).isNotNull()
        assertThat(localeReceiver).contains("android:exported=\"false\"")
        assertThat(localeReceiver).contains("android.intent.action.LOCALE_CHANGED")
        assertThat(localeReceiver).contains("android.intent.action.APPLICATION_LOCALE_CHANGED")
        assertThat(localeReceiver).contains("android.intent.action.TIME_SET")
        assertThat(localeReceiver).contains("android.intent.action.DATE_CHANGED")
        assertThat(localeReceiver).contains("android.intent.action.TIMEZONE_CHANGED")

        val setup = Regex(
            "<activity[^>]*android:name=\"\\.widget\\.setup\\.WidgetSetupActivity\"[\\s\\S]*?</activity>"
        ).find(manifest)?.value
        assertThat(setup).isNotNull()
        assertThat(setup).contains("android:exported=\"true\"")
        assertThat(setup).contains("android.appwidget.action.APPWIDGET_CONFIGURE")
    }

    @Test
    fun `provider metadata is responsive manually refreshed and keyguard excluded on api 36`() {
        val names = listOf(
            "health_summary_widget_info.xml",
            "activity_widget_info.xml",
            "heart_range_widget_info.xml",
            "sleep_widget_info.xml",
        )
        names.forEach { name ->
            val base = providerAttributes(sourceFile("app/src/main/res/xml/$name"))
            assertThat(base["updatePeriodMillis"]).isEqualTo("0")
            assertThat(base["resizeMode"]).contains("horizontal")
            assertThat(base["resizeMode"]).contains("vertical")
            assertThat(base["widgetCategory"]).isEqualTo("home_screen")
            assertThat(base["configure"]).isEqualTo("com.healthmd.widget.setup.WidgetSetupActivity")
            assertThat(base["previewImage"]).isNotNull()

            val api31 = providerAttributes(sourceFile("app/src/main/res/xml-v31/$name"))
            assertThat(api31["previewLayout"]).isNotNull()
            assertThat(api31["targetCellWidth"]).isNotNull()
            assertThat(api31["targetCellHeight"]).isNotNull()
            assertThat(api31["maxResizeWidth"]).isNotNull()
            assertThat(api31["maxResizeHeight"]).isNotNull()

            val api36 = providerAttributes(sourceFile("app/src/main/res/xml-v36/$name"))
            assertThat(api36["widgetCategory"]).isEqualTo("home_screen|not_keyguard")
        }
    }

    @Test
    fun `picker previews are synthetic local assets`() {
        listOf(
            "widget_health_summary_preview.png",
            "widget_activity_preview.png",
            "widget_heart_range_preview.png",
            "widget_sleep_preview.png",
        ).forEach { name ->
            val file = sourceFile("app/src/main/res/drawable-nodpi/$name")
            assertThat(file.isFile).isTrue()
            assertThat(file.length()).isGreaterThan(0L)
        }
    }

    private fun providerAttributes(file: File): Map<String, String> {
        val root = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file).documentElement
        return (0 until root.attributes.length).associate { index ->
            val attribute = root.attributes.item(index)
            attribute.nodeName.substringAfter(':') to attribute.nodeValue
        }
    }

    private fun sourceFile(relativePath: String): File {
        var directory: File? = File(requireNotNull(System.getProperty("user.dir"))).absoluteFile
        while (directory != null) {
            val candidate = File(directory, relativePath)
            if (candidate.isFile) return candidate
            directory = directory.parentFile
        }
        error("Could not locate $relativePath")
    }
}
