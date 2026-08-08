package com.healthmd.data.clinicianreport

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.text.Layout as AndroidTextLayout
import android.text.StaticLayout
import android.text.TextDirectionHeuristics
import android.text.TextPaint
import androidx.core.content.res.ResourcesCompat
import com.healthmd.R
import com.healthmd.domain.clinicianreport.ClinicianReportData
import com.healthmd.domain.clinicianreport.ReportTable
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.cos.COSArray
import com.tom_roush.pdfbox.cos.COSDictionary
import com.tom_roush.pdfbox.cos.COSName
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.pdmodel.PDPageContentStream
import com.tom_roush.pdfbox.pdmodel.common.PDMetadata
import com.tom_roush.pdfbox.pdmodel.common.PDNumberTreeNode
import com.tom_roush.pdfbox.pdmodel.documentinterchange.logicalstructure.PDMarkInfo
import com.tom_roush.pdfbox.pdmodel.documentinterchange.logicalstructure.PDMarkedContentReference
import com.tom_roush.pdfbox.pdmodel.documentinterchange.logicalstructure.PDParentTreeValue
import com.tom_roush.pdfbox.pdmodel.documentinterchange.logicalstructure.PDStructureElement
import com.tom_roush.pdfbox.pdmodel.documentinterchange.logicalstructure.PDStructureTreeRoot
import com.tom_roush.pdfbox.pdmodel.documentinterchange.markedcontent.PDPropertyList
import com.tom_roush.pdfbox.pdmodel.font.PDType0Font
import com.tom_roush.pdfbox.pdmodel.graphics.image.LosslessFactory
import com.tom_roush.pdfbox.pdmodel.graphics.image.PDImageXObject
import com.tom_roush.pdfbox.pdmodel.interactive.viewerpreferences.PDViewerPreferences
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.OutputStream
import java.util.Locale
import java.util.concurrent.CancellationException
import javax.inject.Inject
import kotlin.math.ceil
import kotlin.math.max

interface ClinicianReportPdfRenderer {
    fun render(
        report: ClinicianReportData,
        output: OutputStream,
        pageSize: ReportPageSize = ReportPageSize.forRegion(report.paperRegionCode),
        shouldContinue: () -> Boolean = { true },
    ): Int
}

data class ReportPageSize(val width: Int, val height: Int) {
    companion object {
        val LETTER = ReportPageSize(612, 792)
        val A4 = ReportPageSize(595, 842)
        fun forRegion(regionCode: String?): ReportPageSize =
            if (regionCode?.uppercase(Locale.ROOT) in setOf("US", "CA", "MX")) LETTER else A4
        fun forLocale(locale: Locale = Locale.getDefault()): ReportPageSize = forRegion(locale.country)
    }
}

/**
 * A local-only tagged PDF writer. PDFBox-Android is required because Android's PdfDocument canvas
 * cannot author marked content, a structure tree, a parent tree, document language, or artifacts.
 * This output is described as tagged PDF; it intentionally makes no PDF/UA conformance claim.
 */
@SuppressLint("ResourceType") // Font resources are valid raw InputStreams for PDFBox embedding.
class AndroidClinicianReportPdfRenderer @Inject constructor(
    @ApplicationContext private val context: Context,
) : ClinicianReportPdfRenderer {
    private val sansTypeface = ResourcesCompat.getFont(context, R.font.geist_regular) ?: Typeface.DEFAULT
    private val mediumTypeface = ResourcesCompat.getFont(context, R.font.geist_semibold) ?: Typeface.DEFAULT_BOLD
    private val monoTypeface = ResourcesCompat.getFont(context, R.font.geist_mono_regular) ?: Typeface.MONOSPACE

    init {
        PDFBoxResourceLoader.init(context.applicationContext)
    }

    override fun render(
        report: ClinicianReportData,
        output: OutputStream,
        pageSize: ReportPageSize,
        shouldContinue: () -> Boolean,
    ): Int {
        val cancellation = RenderCancellation(shouldContinue)
        cancellation.check()
        PDDocument().use { document ->
            cancellation.check()
            val fonts = Fonts(
                regular = PDType0Font.load(document, context.resources.openRawResource(R.font.geist_regular), true),
                medium = PDType0Font.load(document, context.resources.openRawResource(R.font.geist_semibold), true),
                mono = PDType0Font.load(document, context.resources.openRawResource(R.font.geist_mono_regular), true),
            )
            cancellation.check()
            val tagged = TaggedDocument(document, report, cancellation)
            val layout = Layout(
                document = document,
                tagged = tagged,
                size = pageSize,
                fonts = fonts,
                typefaces = Typefaces(sansTypeface, mediumTypeface, monoTypeface),
                isRtl = report.isRtl,
                pageFooterTemplate = report.pageFooterTemplate,
                cancellation = cancellation,
            )
            layout.startPage()
            layout.title(report.title)
            layout.scope("Sect") {
                layout.meta(report.metadataPeriodLabel, report.dateRangeLabel)
                layout.meta(report.metadataGeneratedLabel, report.generatedLabel)
                layout.meta(report.metadataTimeZoneLabel, report.timeZoneLabel)
                report.displayName?.let { layout.meta(report.metadataPatientLabel, it) }
            }
            if (report.warnings.isNotEmpty()) {
                layout.checkpoint()
                layout.scope("Sect") {
                    layout.sectionStart(report.availabilityNoteTitle)
                    report.warnings.forEach {
                        layout.checkpoint()
                        layout.paragraph(it)
                    }
                }
            }
            report.sections.forEach { section ->
                layout.checkpoint()
                layout.scope("Sect") {
                    layout.sectionStart(section.localizedTitle)
                    section.noDataMessage?.let(layout::paragraph)
                    section.facts.forEach {
                        layout.checkpoint()
                        layout.fact(it.label, it.value)
                    }
                    section.coverageDisclosure?.let(layout::paragraph)
                    section.sourcesDisclosure?.let(layout::paragraph)
                    section.table?.let(layout::table)
                }
            }
            layout.checkpoint()
            layout.scope("Sect") {
                layout.sectionStart(report.aboutTitle)
                layout.paragraph(report.disclaimer)
                layout.paragraph(report.attribution)
                report.practiceLine?.let(layout::smallParagraph)
            }
            layout.finish()
            cancellation.check()
            tagged.finish()
            cancellation.check()
            document.save(output)
            cancellation.check()
            return layout.pageCount
        }
    }

    private class RenderCancellation(
        private val shouldContinue: () -> Boolean,
    ) {
        fun check() {
            if (!shouldContinue()) throw CancellationException("Clinician report rendering was cancelled")
        }
    }

    private data class Fonts(val regular: PDType0Font, val medium: PDType0Font, val mono: PDType0Font)
    private data class Typefaces(val regular: Typeface, val medium: Typeface, val mono: Typeface)

    private class TaggedDocument(
        private val document: PDDocument,
        private val report: ClinicianReportData,
        private val cancellation: RenderCancellation,
    ) {
        private val root = PDStructureTreeRoot()
        private val documentElement = PDStructureElement("Document", root).apply {
            language = report.languageTag
            title = report.title
        }
        private val scopes = mutableListOf(documentElement)
        private val parentTreeNumbers = linkedMapOf<Int, PDParentTreeValue>()
        private var page: PDPage? = null
        private var pageParentArray: COSArray? = null

        init {
            val catalog = document.documentCatalog
            catalog.structureTreeRoot = root
            root.appendKid(documentElement)
            catalog.markInfo = PDMarkInfo().apply { isMarked = true }
            catalog.language = report.languageTag
            catalog.viewerPreferences = PDViewerPreferences(COSDictionary()).apply { setDisplayDocTitle(true) }
            document.documentInformation.apply {
                title = report.title
                subject = report.pdfSubject
                keywords = report.pdfKeywords.joinToString(", ")
                author = "Health.md"
                creator = "Health.md"
            }
            catalog.metadata = PDMetadata(document).apply {
                importXMPMetadata(xmp(report).toByteArray(Charsets.UTF_8))
            }
        }

        fun beginPage(newPage: PDPage, pageIndex: Int) {
            cancellation.check()
            page = newPage
            newPage.structParents = pageIndex
            pageParentArray = COSArray()
            parentTreeNumbers[pageIndex] = PDParentTreeValue(pageParentArray!!)
        }

        fun <T> scope(role: String, title: String? = null, body: () -> T): T {
            val element = PDStructureElement(role, scopes.last()).apply {
                if (title != null) this.title = title
            }
            scopes.last().appendKid(element)
            scopes += element
            return try {
                body()
            } finally {
                check(scopes.removeAt(scopes.lastIndex) === element)
            }
        }

        fun markedContent(
            stream: PDPageContentStream,
            role: String,
            actualText: String,
            draw: () -> Unit,
        ) {
            cancellation.check()
            val currentPage = checkNotNull(page)
            val parents = checkNotNull(pageParentArray)
            val element = PDStructureElement(role, scopes.last()).apply {
                page = currentPage
                this.actualText = actualText
            }
            scopes.last().appendKid(element)
            val mcid = parents.size()
            val reference = PDMarkedContentReference().apply {
                page = currentPage
                this.mcid = mcid
            }
            element.appendKid(reference)
            parents.add(element.cosObject)
            val properties = PDPropertyList.create(COSDictionary().apply { setInt(COSName.MCID, mcid) })
            stream.beginMarkedContent(COSName.getPDFName(role), properties)
            try {
                draw()
            } finally {
                stream.endMarkedContent()
            }
        }

        fun artifact(stream: PDPageContentStream, draw: () -> Unit) {
            cancellation.check()
            stream.beginMarkedContent(COSName.ARTIFACT)
            try {
                draw()
            } finally {
                stream.endMarkedContent()
            }
        }

        fun finish() {
            cancellation.check()
            check(scopes.size == 1)
            root.parentTree = PDNumberTreeNode(PDParentTreeValue::class.java).apply {
                numbers = parentTreeNumbers
            }
            root.parentTreeNextKey = parentTreeNumbers.size
        }

        private fun xmp(report: ClinicianReportData): String {
            val title = xml(report.title)
            val subject = xml(report.pdfSubject)
            val language = xml(report.languageTag)
            val keywords = xml(report.pdfKeywords.joinToString(", "))
            return """<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>
<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description rdf:about="" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:pdf="http://ns.adobe.com/pdf/1.3/" xmlns:xmp="http://ns.adobe.com/xap/1.0/"><dc:title><rdf:Alt><rdf:li xml:lang="$language">$title</rdf:li></rdf:Alt></dc:title><dc:description><rdf:Alt><rdf:li xml:lang="$language">$subject</rdf:li></rdf:Alt></dc:description><dc:language><rdf:Bag><rdf:li>$language</rdf:li></rdf:Bag></dc:language><pdf:Keywords>$keywords</pdf:Keywords><xmp:CreatorTool>Health.md</xmp:CreatorTool></rdf:Description></rdf:RDF></x:xmpmeta>
<?xpacket end="w"?>"""
        }

        private fun xml(value: String): String = value
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace("\"", "&quot;")
            .replace("'", "&apos;")
    }

    private class Layout(
        private val document: PDDocument,
        private val tagged: TaggedDocument,
        private val size: ReportPageSize,
        private val fonts: Fonts,
        private val typefaces: Typefaces,
        private val isRtl: Boolean,
        private val pageFooterTemplate: String,
        private val cancellation: RenderCancellation,
    ) {
        private data class Style(
            val font: PDType0Font,
            val typeface: Typeface,
            val size: Float,
            val color: Int,
            val key: String,
        )
        private data class RasterKey(val text: String, val styleKey: String)

        private val margin = 44f
        private val contentWidth = size.width - margin * 2f
        private val contentBottom = size.height - 48f
        private val titleStyle = Style(fonts.medium, typefaces.medium, 22f, Color.rgb(23, 23, 23), "title")
        private val headingStyle = Style(fonts.medium, typefaces.medium, 13f, Color.rgb(102, 72, 143), "heading")
        private val bodyStyle = Style(fonts.regular, typefaces.regular, 9.5f, Color.rgb(23, 23, 23), "body")
        private val bodyMediumStyle = Style(fonts.medium, typefaces.medium, 9.5f, Color.rgb(23, 23, 23), "body-medium")
        private val mutedStyle = Style(fonts.regular, typefaces.regular, 8.5f, Color.rgb(77, 77, 77), "muted")
        private val tableStyle = Style(fonts.mono, typefaces.mono, 7.3f, Color.rgb(23, 23, 23), "table")
        private val tableHeaderStyle = Style(fonts.medium, typefaces.medium, 7.5f, Color.rgb(23, 23, 23), "table-header")
        private val rasterCache = linkedMapOf<RasterKey, PDImageXObject>()
        private var page: PDPage? = null
        private var stream: PDPageContentStream? = null
        private var y = margin
        var pageCount = 0
            private set

        fun <T> scope(role: String, body: () -> T): T = tagged.scope(role, body = body)

        fun checkpoint() = cancellation.check()

        fun startPage() {
            cancellation.check()
            finishCurrentPage()
            cancellation.check()
            pageCount += 1
            val newPage = PDPage().apply { mediaBox = com.tom_roush.pdfbox.pdmodel.common.PDRectangle(size.width.toFloat(), size.height.toFloat()) }
            document.addPage(newPage)
            page = newPage
            stream = PDPageContentStream(document, newPage)
            tagged.beginPage(newPage, pageCount - 1)
            y = margin
        }

        fun finish() {
            cancellation.check()
            finishCurrentPage()
            cancellation.check()
        }

        fun title(text: String) {
            ensure(44f)
            semantic("H1", text) { drawText(text, margin, y, contentWidth, titleStyle) }
            y += 32f
            divider(y)
            y += 12f
        }

        fun meta(label: String, value: String) {
            val actual = "$label: $value"
            val valueLines = wrap(value, bodyStyle, contentWidth - 84f)
            val height = max(14f, valueLines.size * 12f)
            if (height > contentBottom - margin) {
                paragraph(actual)
                return
            }
            ensure(height)
            semantic("P", actual) {
                val labelX = if (isRtl) size.width - margin - 80f else margin
                val valueX = if (isRtl) margin else margin + 84f
                drawText("$label:", labelX, y, 80f, bodyMediumStyle)
                valueLines.forEachIndexed { index, line -> drawText(line, valueX, y + index * 12f, contentWidth - 84f, bodyStyle) }
            }
            y += height
        }

        fun sectionStart(title: String) {
            ensure(43f)
            y += 14f
            semantic("H2", title) { drawText(title, margin, y, contentWidth, headingStyle) }
            y += 21f
            divider(y)
            y += 8f
        }

        fun fact(label: String, value: String) {
            val lines = wrap(value, bodyStyle, contentWidth - 120f)
            val height = lines.size * 13f + 2f
            if (height > contentBottom - margin) {
                paragraph("$label: $value")
                return
            }
            ensure(height)
            semantic("P", "$label: $value") {
                val labelX = if (isRtl) size.width - margin - 116f else margin
                val valueX = if (isRtl) margin else margin + 120f
                drawText(label, labelX, y, 116f, bodyMediumStyle)
                lines.forEachIndexed { index, line -> drawText(line, valueX, y + index * 13f, contentWidth - 120f, bodyStyle) }
            }
            y += height
        }

        fun paragraph(text: String) = paragraph(text, bodyStyle, 13f)
        fun smallParagraph(text: String) = paragraph(text, mutedStyle, 12f)

        private fun paragraph(text: String, style: Style, lineHeight: Float) {
            val lines = wrap(text, style, contentWidth)
            var index = 0
            while (index < lines.size) {
                if (contentBottom - y < lineHeight) startPage()
                val capacity = max(1, ((contentBottom - y) / lineHeight).toInt())
                val chunk = lines.subList(index, minOf(lines.size, index + capacity))
                semantic("P", chunk.joinToString(" ")) {
                    chunk.forEachIndexed { offset, line -> drawText(line, margin, y + offset * lineHeight, contentWidth, style) }
                }
                y += chunk.size * lineHeight + 3f
                index += chunk.size
                if (index < lines.size) startPage()
            }
        }

        fun table(table: ReportTable) {
            ensure(7f + 20f + 19f + if (table.rows.isEmpty()) 0f else 16f)
            y += 7f
            semantic("H3", table.title) { drawText(table.title, margin, y, contentWidth, headingStyle) }
            y += 20f
            scope("Table") {
                tableHeader(table.columns)
                val columns = table.columns.size.coerceAtLeast(1)
                val columnWidth = contentWidth / columns
                table.rows.forEach { row ->
                    cancellation.check()
                    if (y + 16f > contentBottom) {
                        startPage()
                        tableHeader(table.columns)
                    }
                    scope("TR") {
                        repeat(columns) { logicalIndex ->
                            val fullText = row.getOrNull(logicalIndex).orEmpty()
                            val visible = ellipsis(fullText, tableStyle, columnWidth - 6f)
                            semantic("TD", fullText) {
                                val visualIndex = if (isRtl) columns - 1 - logicalIndex else logicalIndex
                                drawText(visible, margin + visualIndex * columnWidth + 3f, y + 2f, columnWidth - 6f, tableStyle)
                            }
                        }
                    }
                    y += 16f
                    divider(y)
                }
            }
        }

        private fun tableHeader(columns: List<String>) {
            ensure(19f)
            val count = columns.size.coerceAtLeast(1)
            val columnWidth = contentWidth / count
            artifact {
                current().setNonStrokingColor(244 / 255f, 239 / 255f, 247 / 255f)
                current().addRect(margin, pdfBottom(y + 17f), contentWidth, 17f)
                current().fill()
            }
            scope("TR") {
                columns.forEachIndexed { logicalIndex, label ->
                    val visible = ellipsis(label, tableHeaderStyle, columnWidth - 6f)
                    semantic("TH", label) {
                        val visualIndex = if (isRtl) count - 1 - logicalIndex else logicalIndex
                        drawText(visible, margin + visualIndex * columnWidth + 3f, y + 2f, columnWidth - 6f, tableHeaderStyle)
                    }
                }
            }
            y += 19f
        }

        private fun ensure(height: Float) {
            if (y + height > contentBottom) startPage()
        }

        private fun finishCurrentPage() {
            val active = stream ?: return
            cancellation.check()
            val footer = pageFooterTemplate.replace("%1\$d", pageCount.toString())
            artifact {
                active.setStrokingColor(220 / 255f, 220 / 255f, 220 / 255f)
                active.setLineWidth(0.7f)
                // PDF coordinates originate at the lower-left: this is exactly 38 pt
                // above the physical bottom, not 38 pt below the top.
                active.moveTo(margin, FOOTER_DIVIDER_BOTTOM)
                active.lineTo(size.width - margin, FOOTER_DIVIDER_BOTTOM)
                active.stroke()
                drawTextRaw(footer, margin, size.height - 32f, contentWidth, mutedStyle)
            }
            cancellation.check()
            active.close()
            stream = null
            page = null
        }

        private fun divider(top: Float) = artifact {
            current().setStrokingColor(220 / 255f, 220 / 255f, 220 / 255f)
            current().setLineWidth(0.7f)
            current().moveTo(margin, pdfBaseline(top))
            current().lineTo(size.width - margin, pdfBaseline(top))
            current().stroke()
        }

        private fun semantic(role: String, actualText: String, draw: () -> Unit) {
            tagged.markedContent(current(), role, actualText, draw)
        }

        private fun artifact(draw: () -> Unit) {
            tagged.artifact(current(), draw)
        }

        private fun drawText(text: String, x: Float, top: Float, width: Float, style: Style) {
            drawTextRaw(text, x, top, width, style)
        }

        private fun drawTextRaw(text: String, x: Float, top: Float, width: Float, style: Style) {
            cancellation.check()
            if (text.isEmpty()) return
            if (canRenderVector(text, style.font)) {
                val textWidth = style.font.getStringWidth(text) / 1000f * style.size
                val alignedX = if (isRtl) x + max(0f, width - textWidth) else x
                val red = Color.red(style.color)
                val green = Color.green(style.color)
                val blue = Color.blue(style.color)
                current().setNonStrokingColor(red / 255f, green / 255f, blue / 255f)
                current().beginText()
                current().setFont(style.font, style.size)
                current().newLineAtOffset(alignedX, pdfBaseline(top + style.size))
                current().showText(text)
                current().endText()
            } else {
                val image = rasterImage(text, style)
                val imageWidth = image.width / RASTER_SCALE
                val imageHeight = image.height / RASTER_SCALE
                val alignedX = if (isRtl) x + max(0f, width - imageWidth) else x
                current().drawImage(image, alignedX, pdfBottom(top + imageHeight), imageWidth, imageHeight)
            }
        }

        private fun canRenderVector(text: String, font: PDType0Font): Boolean {
            val iterator = text.codePoints().iterator()
            while (iterator.hasNext()) {
                val codePoint = iterator.nextInt()
                if (Character.isISOControl(codePoint) || !font.hasGlyph(codePoint)) return false
            }
            return true
        }

        private fun rasterImage(text: String, style: Style): PDImageXObject {
            cancellation.check()
            val key = RasterKey(text, style.key)
            rasterCache[key]?.let { return it }
            val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
                color = style.color
                textSize = style.size * RASTER_SCALE
                typeface = if (style.typeface.isBold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
            }
            val desiredWidth = max(1, ceil(AndroidTextLayout.getDesiredWidth(text, paint).toDouble()).toInt() + 4)
            val layout = StaticLayout.Builder.obtain(text, 0, text.length, paint, desiredWidth)
                .setAlignment(AndroidTextLayout.Alignment.ALIGN_NORMAL)
                .setIncludePad(false)
                .setTextDirection(if (isRtl) TextDirectionHeuristics.FIRSTSTRONG_RTL else TextDirectionHeuristics.FIRSTSTRONG_LTR)
                .build()
            cancellation.check()
            val bitmap = Bitmap.createBitmap(desiredWidth, max(1, layout.height), Bitmap.Config.ARGB_8888)
            val image = try {
                Canvas(bitmap).also(layout::draw)
                cancellation.check()
                LosslessFactory.createFromImage(document, bitmap)
            } finally {
                bitmap.recycle()
            }
            cancellation.check()
            if (rasterCache.size < MAX_RASTER_CACHE_ENTRIES) rasterCache[key] = image
            return image
        }

        private fun wrap(text: String, style: Style, maxWidth: Float): List<String> {
            if (text.isBlank()) return listOf("")
            val result = mutableListOf<String>()
            var current = ""
            text.trim().split(Regex("\\s+")).forEach { word ->
                cancellation.check()
                val pieces = splitLongWord(word, style, maxWidth)
                pieces.forEach { piece ->
                    val candidate = if (current.isEmpty()) piece else "$current $piece"
                    if (measure(candidate, style) <= maxWidth || current.isEmpty()) {
                        current = candidate
                    } else {
                        result += current
                        current = piece
                    }
                }
            }
            if (current.isNotEmpty()) result += current
            return result.ifEmpty { listOf("") }
        }

        private fun splitLongWord(word: String, style: Style, maxWidth: Float): List<String> {
            if (measure(word, style) <= maxWidth) return listOf(word)
            val result = mutableListOf<String>()
            var current = ""
            val iterator = word.codePoints().iterator()
            var codePoints = 0
            while (iterator.hasNext()) {
                if (codePoints++ % 64 == 0) cancellation.check()
                val next = String(Character.toChars(iterator.nextInt()))
                if (current.isNotEmpty() && measure(current + next, style) > maxWidth) {
                    result += current
                    current = next
                } else {
                    current += next
                }
            }
            if (current.isNotEmpty()) result += current
            return result
        }

        private fun measure(text: String, style: Style): Float = if (canRenderVector(text, style.font)) {
            style.font.getStringWidth(text) / 1000f * style.size
        } else {
            Paint(Paint.ANTI_ALIAS_FLAG).apply {
                textSize = style.size
                typeface = Typeface.DEFAULT
            }.measureText(text)
        }

        private fun ellipsis(text: String, style: Style, maxWidth: Float): String {
            if (measure(text, style) <= maxWidth) return text
            var result = text
            var removed = 0
            while (result.isNotEmpty() && measure("$result…", style) > maxWidth) {
                if (removed++ % 32 == 0) cancellation.check()
                val last = result.offsetByCodePoints(result.length, -1)
                result = result.substring(0, last)
            }
            return "$result…"
        }

        private fun current(): PDPageContentStream = checkNotNull(stream)
        private fun pdfBaseline(topBaseline: Float): Float = size.height - topBaseline
        private fun pdfBottom(bottomFromTop: Float): Float = size.height - bottomFromTop

        companion object {
            internal const val FOOTER_DIVIDER_BOTTOM = 38f
            private const val RASTER_SCALE = 3f
            private const val MAX_RASTER_CACHE_ENTRIES = 1024
        }
    }
}
