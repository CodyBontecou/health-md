package com.healthmd.clinicianreport

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.clinicianreport.AndroidClinicianReportPdfRenderer
import com.healthmd.data.clinicianreport.ReportPageSize
import com.healthmd.domain.clinicianreport.*
import com.tom_roush.pdfbox.contentstream.operator.Operator
import com.tom_roush.pdfbox.cos.COSArray
import com.tom_roush.pdfbox.cos.COSDictionary
import com.tom_roush.pdfbox.cos.COSName
import com.tom_roush.pdfbox.cos.COSNumber
import com.tom_roush.pdfbox.pdfparser.PDFStreamParser
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.pdmodel.documentinterchange.logicalstructure.PDMarkedContentReference
import com.tom_roush.pdfbox.pdmodel.documentinterchange.logicalstructure.PDParentTreeValue
import com.tom_roush.pdfbox.pdmodel.documentinterchange.logicalstructure.PDStructureElement
import com.tom_roush.pdfbox.pdmodel.documentinterchange.logicalstructure.PDStructureNode
import com.tom_roush.pdfbox.pdmodel.font.PDType0Font
import com.tom_roush.pdfbox.pdmodel.graphics.image.PDImageXObject
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.ByteArrayOutputStream
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.IdentityHashMap
import java.util.Locale

@RunWith(RobolectricTestRunner::class)
class AndroidClinicianReportPdfRendererTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()

    @Test fun pageSizeSelectionUsesPinnedRegion() {
        assertThat(ReportPageSize.forRegion("US")).isEqualTo(ReportPageSize.LETTER)
        assertThat(ReportPageSize.forRegion("CA")).isEqualTo(ReportPageSize.LETTER)
        assertThat(ReportPageSize.forRegion("MX")).isEqualTo(ReportPageSize.LETTER)
        assertThat(ReportPageSize.forRegion("DE")).isEqualTo(ReportPageSize.A4)
        assertThat(ReportPageSize.forRegion(null)).isEqualTo(ReportPageSize.A4)
        assertThat(ReportPageSize.LETTER.width).isEqualTo(612)
        assertThat(ReportPageSize.A4.height).isEqualTo(842)
    }

    @Test fun taggedMultipagePdfHasExactParentTreeHierarchyArtifactsFooterAndMetadata() {
        val report = denseEnglishReport()
        listOf(ReportPageSize.LETTER, ReportPageSize.A4).forEach { size ->
            val bytes = ByteArrayOutputStream().use { output ->
                val pages = AndroidClinicianReportPdfRenderer(context).render(report, output, size)
                assertThat(pages).isGreaterThan(1)
                output.toByteArray()
            }
            assertThat(bytes.copyOfRange(0, 5).decodeToString()).isEqualTo("%PDF-")
            PDDocument.load(bytes).use { document ->
                val catalog = document.documentCatalog
                val root = catalog.structureTreeRoot
                assertThat(root).isNotNull()
                assertThat(catalog.markInfo.isMarked).isTrue()
                assertThat(catalog.language).isEqualTo("en")
                assertThat(catalog.viewerPreferences.displayDocTitle()).isTrue()
                assertThat(document.documentInformation.title).isEqualTo(report.title)
                assertThat(document.documentInformation.subject).isEqualTo(report.pdfSubject)
                assertThat(document.documentInformation.keywords).contains("Health.md")
                assertThat(root.parentTreeNextKey).isEqualTo(document.numberOfPages)

                val allElements = mutableListOf<PDStructureElement>()
                collectElements(root, allElements)
                validateHierarchy(root, report)
                assertThat(allElements.map { it.structureType }).doesNotContain("Artifact")

                var totalBdc = 0
                var totalEmc = 0
                var totalArtifacts = 0
                var embeddedFonts = 0
                val semanticReferenceCounts = IdentityHashMap<COSDictionary, Int>()
                document.pages.forEach { page ->
                    assertThat(page.structParents).isAtLeast(0)
                    val parentValue = root.parentTree.getValue(page.structParents) as PDParentTreeValue
                    val parentArray = parentValue.cosObject as COSArray
                    assertThat(parentArray.size()).isGreaterThan(0)

                    page.resources.fontNames.forEach { name ->
                        val font = page.resources.getFont(name)
                        if (font is PDType0Font && font.isEmbedded) embeddedFonts += 1
                    }
                    val parsed = parsedPage(page)
                    totalBdc += parsed.semanticMarks.size
                    totalEmc += parsed.emc
                    totalArtifacts += parsed.artifacts
                    assertThat(parsed.semanticMarks.map { it.mcid }).containsExactlyElementsIn(0 until parentArray.size())
                    assertThat(parsed.semanticMarks.map { it.mcid }.distinct()).hasSize(parentArray.size())
                    assertThat(parsed.emc).isEqualTo(parsed.semanticMarks.size + parsed.artifacts)
                    assertThat(parsed.footerDividerYs).contains(38f)
                    assertThat(parsed.footerDividerYs).doesNotContain(size.height - 38f)
                    assertThat(
                        parsed.textOffsets.any { (x, y) -> x == 44f && y in 15f..35f } ||
                            parsed.imageOffsets.any { (x, y) -> x == 44f && y in 15f..35f },
                    ).isTrue()

                    parsed.semanticMarks.forEach { mark ->
                        val parentDictionary = parentArray.getObject(mark.mcid) as COSDictionary
                        val structureElement = PDStructureElement(parentDictionary)
                        assertThat(structureElement.cosObject).isSameInstanceAs(parentDictionary)
                        assertThat(structureElement.structureType).isEqualTo(mark.role)
                        val references = structureElement.kids.filterIsInstance<PDMarkedContentReference>()
                        assertThat(references).hasSize(1)
                        val reference = references.single()
                        assertThat(reference.mcid).isEqualTo(mark.mcid)
                        assertThat(reference.page.cosObject).isSameInstanceAs(page.cosObject)
                        semanticReferenceCounts[parentDictionary] = (semanticReferenceCounts[parentDictionary] ?: 0) + 1
                    }
                }

                val markedElements = allElements.filter { element ->
                    element.kids.any { it is PDMarkedContentReference }
                }
                assertThat(semanticReferenceCounts.size).isEqualTo(markedElements.size)
                markedElements.forEach { element ->
                    assertThat(semanticReferenceCounts[element.cosObject]).isEqualTo(1)
                }
                assertThat(totalBdc).isGreaterThan(0)
                assertThat(totalEmc).isEqualTo(totalBdc + totalArtifacts)
                assertThat(totalArtifacts).isAtLeast(document.numberOfPages * 2)
                assertThat(embeddedFonts).isGreaterThan(0)

                val xmp = catalog.metadata.toByteArray().decodeToString()
                assertThat(xmp).contains("dc:language")
                assertThat(xmp).contains("en")
                assertThat(xmp.lowercase()).doesNotContain("pdfuaid")
            }
        }
    }

    @Test fun complexScriptsUseShapedImageAppearanceWithLocalizedActualText() {
        val locales = listOf("ar-SA", "bn-BD", "hi-IN", "pa-Guru-IN", "zh-Hans-CN", "ja-JP")
        locales.forEach { tag ->
            val vocabulary = reportVocabulary(Locale.forLanguageTag(tag))
            val range = ReportDateRange(LocalDate.of(2026, 1, 1), LocalDate.of(2026, 1, 1))
            val report = ClinicianReportGenerator(vocabulary).generate(
                ClinicianReportInput(
                    configuration = ReportConfiguration(range, setOf(ReportMetric.STEPS), ReportDetailLevel.SUMMARY_AND_READINGS),
                    zoneId = ZoneId.of("Asia/Kathmandu"),
                    generatedAt = Instant.parse("2026-01-02T00:00:00Z"),
                    dailyValues = listOf(DailyReportValue(ReportMetric.STEPS, range.startDate, 1234.0)),
                ),
            )
            val bytes = ByteArrayOutputStream().use { output ->
                AndroidClinicianReportPdfRenderer(context).render(report, output)
                output.toByteArray()
            }
            PDDocument.load(bytes).use { document ->
                assertThat(document.documentCatalog.language).isEqualTo(vocabulary.languageTag)
                val allElements = mutableListOf<PDStructureElement>()
                collectElements(document.documentCatalog.structureTreeRoot, allElements)
                assertThat(allElements.mapNotNull { it.actualText }).contains(report.title)
                assertThat(allElements.mapNotNull { it.actualText }).contains(report.sections.single().localizedTitle)
                val imageCount = document.pages.sumOf { page ->
                    page.resources.xObjectNames.count { page.resources.getXObject(it) is PDImageXObject }
                }
                assertThat(imageCount).isGreaterThan(0)
            }
        }
    }

    private fun validateHierarchy(root: PDStructureNode, report: ClinicianReportData) {
        val rootChildren = structureChildren(root)
        assertThat(rootChildren).hasSize(1)
        val document = rootChildren.single()
        assertThat(document.structureType).isEqualTo("Document")
        val documentChildren = structureChildren(document)
        assertThat(documentChildren.first().structureType).isEqualTo("H1")
        assertThat(documentChildren.count { it.structureType == "H1" }).isEqualTo(1)
        assertThat(documentChildren.drop(1).map { it.structureType }.distinct()).containsExactly("Sect")

        val sections = documentChildren.filter { it.structureType == "Sect" }
        assertThat(sections).isNotEmpty()
        sections.forEach { section ->
            val children = structureChildren(section)
            children.filter { it.structureType == "H2" }.forEach { heading ->
                assertThat(heading.actualText).isNotEmpty()
            }
            children.forEachIndexed { index, child ->
                if (child.structureType == "Table") {
                    assertThat(index).isGreaterThan(0)
                    assertThat(children[index - 1].structureType).isEqualTo("H3")
                    validateTable(child, report)
                }
            }
        }
        assertThat(sections.flatMap(::structureChildren).map { it.structureType }).contains("H2")
    }

    private fun validateTable(table: PDStructureElement, report: ClinicianReportData) {
        val rows = structureChildren(table)
        assertThat(rows).isNotEmpty()
        assertThat(rows.map { it.structureType }.distinct()).containsExactly("TR")
        val headerRows = mutableListOf<List<String>>()
        rows.forEach { row ->
            val cells = structureChildren(row)
            assertThat(cells).isNotEmpty()
            val roles = cells.map { it.structureType }.distinct()
            assertThat(roles.size).isEqualTo(1)
            assertThat(roles.single()).isAnyOf("TH", "TD")
            cells.forEach { cell ->
                assertThat(structureChildren(cell)).isEmpty()
                val references = cell.kids.filterIsInstance<PDMarkedContentReference>()
                assertThat(references).hasSize(1)
            }
            if (roles.single() == "TH") headerRows += cells.map { it.actualText }
        }
        assertThat(headerRows.size).isGreaterThan(1)
        val expectedHeaders = report.sections.single().table!!.columns
        headerRows.forEach { assertThat(it).containsExactlyElementsIn(expectedHeaders).inOrder() }
    }

    private fun parsedPage(page: PDPage): ParsedPage {
        val parser = PDFStreamParser(page).apply { parse() }
        val tokens = parser.tokens
        val marks = mutableListOf<SemanticMark>()
        val dividerYs = mutableListOf<Float>()
        val textOffsets = mutableListOf<Pair<Float, Float>>()
        val imageOffsets = mutableListOf<Pair<Float, Float>>()
        var artifacts = 0
        var emc = 0
        tokens.forEachIndexed { index, token ->
            if (token !is Operator) return@forEachIndexed
            when (token.name) {
                "BDC" -> {
                    val role = (tokens[index - 2] as COSName).name
                    val propertyName = tokens[index - 1] as COSName
                    val properties = page.resources.getProperties(propertyName).cosObject
                    val mcid = properties.getInt(COSName.MCID, -1)
                    assertThat(mcid).isAtLeast(0)
                    marks += SemanticMark(role, mcid)
                }
                "BMC" -> if (index > 0 && tokens[index - 1] == COSName.ARTIFACT) artifacts += 1
                "EMC" -> emc += 1
                "m" -> if (index >= 2) {
                    val x = (tokens[index - 2] as COSNumber).floatValue()
                    val y = (tokens[index - 1] as COSNumber).floatValue()
                    if (x == 44f) dividerYs += y
                }
                "Td" -> if (index >= 2) {
                    textOffsets += (tokens[index - 2] as COSNumber).floatValue() to
                        (tokens[index - 1] as COSNumber).floatValue()
                }
                "cm" -> if (index >= 6) {
                    imageOffsets += (tokens[index - 2] as COSNumber).floatValue() to
                        (tokens[index - 1] as COSNumber).floatValue()
                }
            }
        }
        return ParsedPage(marks, artifacts, emc, dividerYs, textOffsets, imageOffsets)
    }

    private fun structureChildren(node: PDStructureNode): List<PDStructureElement> =
        node.kids.filterIsInstance<PDStructureElement>()

    private fun collectElements(node: PDStructureNode, output: MutableList<PDStructureElement>) {
        structureChildren(node).forEach { element ->
            output += element
            collectElements(element, output)
        }
    }

    private fun denseEnglishReport(): ClinicianReportData {
        val vocabulary = reportVocabulary(Locale.US)
        val range = ReportDateRange(LocalDate.of(2026, 1, 1), LocalDate.of(2026, 1, 30))
        val start = range.startDate.atStartOfDay(ZoneId.of("UTC")).toInstant()
        return ClinicianReportGenerator(vocabulary).generate(
            ClinicianReportInput(
                configuration = ReportConfiguration(range, setOf(ReportMetric.HEART_RATE), ReportDetailLevel.SUMMARY_AND_READINGS),
                zoneId = ZoneId.of("UTC"),
                generatedAt = Instant.parse("2026-02-01T00:00:00Z"),
                scalarObservations = (0 until 320).map {
                    ScalarReportObservation(ReportMetric.HEART_RATE, start.plusSeconds(it * 60L), 60.0 + it % 20, "heart-$it", ReportSource("Synthetic Source"))
                },
                warnings = listOf(ClinicianReportWarning.SourceFailure(range.startDate)),
            ),
        )
    }

    private data class SemanticMark(val role: String, val mcid: Int)
    private data class ParsedPage(
        val semanticMarks: List<SemanticMark>,
        val artifacts: Int,
        val emc: Int,
        val footerDividerYs: List<Float>,
        val textOffsets: List<Pair<Float, Float>>,
        val imageOffsets: List<Pair<Float, Float>>,
    )
}
