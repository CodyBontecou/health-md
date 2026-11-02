package com.healthmd.widget.glance

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import androidx.glance.background
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.semantics.contentDescription
import androidx.glance.semantics.semantics
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.healthmd.R
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.repository.ExportHistoryRepository
import com.healthmd.presentation.MainActivity
import com.healthmd.presentation.archive.ArchiveCoverage
import com.healthmd.presentation.archive.CoverageStatus
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.android.EntryPointAccessors
import dagger.hilt.components.SingletonComponent
import java.time.LocalDate
import kotlinx.coroutines.flow.first

/** What the Archive widget shows. Coverage only: no health values, so nothing sensitive. */
data class ArchiveWidgetSummary(
    val streak: Int,
    val gapCount: Int,
    /** The last [RECENT_DAYS] dates, oldest first, ending today. */
    val recent: List<CoverageStatus>,
    val hasHistory: Boolean,
) {
    companion object {
        const val RECENT_DAYS = 14

        /** Stats look back [LOOKBACK_DAYS] so a streak does not reset at a month boundary. */
        private const val LOOKBACK_DAYS = 60L

        fun from(entries: List<ExportHistoryEntry>, today: LocalDate): ArchiveWidgetSummary {
            val days = (LOOKBACK_DAYS - 1 downTo 0).map { back ->
                val date = today.minusDays(back)
                date to ArchiveCoverage.aggregateDay(entries, date, today)
            }
            val stats = ArchiveCoverage.stats(days, today)
            return ArchiveWidgetSummary(
                streak = stats.streak,
                gapCount = days.takeLast(30).count { it.second == CoverageStatus.MISSING },
                recent = days.takeLast(RECENT_DAYS).map { it.second },
                hasHistory = entries.isNotEmpty(),
            )
        }
    }
}

@EntryPoint
@InstallIn(SingletonComponent::class)
interface ArchiveWidgetEntryPoint {
    fun exportHistoryRepository(): ExportHistoryRepository
}

/** Home-screen Archive: streak, recent gaps and the last two weeks of coverage. */
class ArchiveGlanceWidget : GlanceAppWidget() {
    override val sizeMode: SizeMode = SizeMode.Responsive(setOf(Compact, Wide))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val repository = EntryPointAccessors.fromApplication(
            context.applicationContext,
            ArchiveWidgetEntryPoint::class.java,
        ).exportHistoryRepository()
        val entries = runCatching { repository.getAllEntries().first() }.getOrDefault(emptyList())
        val summary = ArchiveWidgetSummary.from(entries, LocalDate.now())
        provideContent { ArchiveWidgetContent(summary) }
    }

    companion object {
        private val Compact = DpSize(110.dp, 110.dp)
        private val Wide = DpSize(250.dp, 110.dp)

        /** Re-renders placed Archive widgets; a no-op when none are placed. */
        suspend fun refresh(context: Context) {
            ArchiveGlanceWidget().updateAll(context.applicationContext)
        }
    }
}

class ArchiveWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = ArchiveGlanceWidget()
}

@Composable
private fun ArchiveWidgetContent(summary: ArchiveWidgetSummary) {
    val context = LocalContext.current
    val wide = LocalSize.current.width >= 220.dp
    val streakLabel = context.getString(R.string.archive_stat_streak)
    val gapsLabel = context.getString(R.string.archive_stat_gaps)
    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .appWidgetBackground()
            .cornerRadius(28.dp)
            .background(HealthWidgetColors.Surface)
            .padding(16.dp)
            .clickable(actionStartActivity<MainActivity>())
            .semantics {
                contentDescription = context.getString(R.string.widget_archive_name)
            },
    ) {
        Text(
            text = context.getString(R.string.widget_archive_name),
            style = TextStyle(color = HealthWidgetColors.Brand, fontSize = 12.sp, fontWeight = FontWeight.Medium),
        )
        if (!summary.hasHistory) {
            Spacer(GlanceModifier.height(8.dp))
            Text(
                text = context.getString(R.string.archive_empty_title),
                style = TextStyle(color = HealthWidgetColors.Primary, fontSize = 14.sp, fontWeight = FontWeight.Medium),
                maxLines = 3,
            )
            return@Column
        }
        Spacer(GlanceModifier.height(4.dp))
        Row {
            Text(
                text = summary.streak.toString(),
                style = TextStyle(color = HealthWidgetColors.Primary, fontSize = 32.sp, fontWeight = FontWeight.Medium),
            )
        }
        Text(text = streakLabel, style = TextStyle(color = HealthWidgetColors.Muted, fontSize = 12.sp), maxLines = 1)
        Text(
            text = "$gapsLabel · ${summary.gapCount}",
            style = TextStyle(
                color = if (summary.gapCount > 0) HealthWidgetColors.CoverageMissing else HealthWidgetColors.Muted,
                fontSize = 12.sp,
            ),
            maxLines = 1,
        )
        Spacer(GlanceModifier.height(8.dp))
        val cells = if (wide) summary.recent else summary.recent.takeLast(7)
        Row {
            cells.forEachIndexed { index, status ->
                if (index > 0) Spacer(GlanceModifier.width(4.dp))
                Box(
                    modifier = GlanceModifier
                        .size(if (wide) 12.dp else 10.dp)
                        .cornerRadius(4.dp)
                        .background(status.widgetColor()),
                ) {}
            }
        }
    }
}

private fun CoverageStatus.widgetColor(): ColorProvider = when (this) {
    CoverageStatus.COMPLETE -> HealthWidgetColors.CoverageComplete
    CoverageStatus.PARTIAL -> HealthWidgetColors.CoveragePartial
    CoverageStatus.MISSING -> HealthWidgetColors.CoverageMissing
    CoverageStatus.IN_PROGRESS -> HealthWidgetColors.Brand
    CoverageStatus.NOT_DUE -> HealthWidgetColors.CoverageNone
}
