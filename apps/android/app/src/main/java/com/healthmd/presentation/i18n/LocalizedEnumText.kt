package com.healthmd.presentation.i18n

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.healthmd.R
import com.healthmd.domain.model.BulletStyle
import com.healthmd.domain.model.DateFormatPreference
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.MarkdownTemplateStyle
import com.healthmd.domain.model.TimeFormatPreference
import com.healthmd.domain.model.UnitPreference
import com.healthmd.domain.model.WriteMode

@Composable
fun ExportFormat.localizedDisplayName(): String = when (this) {
    ExportFormat.MARKDOWN -> stringResource(R.string.format_display_markdown)
    ExportFormat.OBSIDIAN_BASES -> stringResource(R.string.format_display_obsidian_bases)
    ExportFormat.JSON -> stringResource(R.string.format_display_json)
    ExportFormat.CSV -> stringResource(R.string.format_display_csv)
}

@Composable
fun WriteMode.localizedDisplayName(): String = when (this) {
    WriteMode.OVERWRITE -> stringResource(R.string.write_mode_display_overwrite)
    WriteMode.APPEND -> stringResource(R.string.write_mode_display_append)
    WriteMode.UPDATE -> stringResource(R.string.write_mode_display_update)
}

@Composable
fun WriteMode.localizedDescription(): String = when (this) {
    WriteMode.OVERWRITE -> stringResource(R.string.write_mode_desc_overwrite)
    WriteMode.APPEND -> stringResource(R.string.write_mode_desc_append)
    WriteMode.UPDATE -> stringResource(R.string.write_mode_desc_update)
}

@Composable
fun DateFormatPreference.localizedDisplayName(): String = when (this) {
    DateFormatPreference.ISO8601 -> stringResource(R.string.date_format_display_iso8601)
    DateFormatPreference.US_SHORT -> stringResource(R.string.date_format_display_us_short)
    DateFormatPreference.US_LONG -> stringResource(R.string.date_format_display_us_long)
    DateFormatPreference.EU_SHORT -> stringResource(R.string.date_format_display_eu_short)
    DateFormatPreference.EU_LONG -> stringResource(R.string.date_format_display_eu_long)
    DateFormatPreference.COMPACT -> stringResource(R.string.date_format_display_compact)
    DateFormatPreference.FRIENDLY -> stringResource(R.string.date_format_display_friendly)
}

@Composable
fun TimeFormatPreference.localizedDisplayName(): String = when (this) {
    TimeFormatPreference.HOUR_24 -> stringResource(R.string.time_format_display_24h)
    TimeFormatPreference.HOUR_24_SECONDS -> stringResource(R.string.time_format_display_24h_seconds)
    TimeFormatPreference.HOUR_12 -> stringResource(R.string.time_format_display_12h)
    TimeFormatPreference.HOUR_12_SECONDS -> stringResource(R.string.time_format_display_12h_seconds)
}

@Composable
fun UnitPreference.localizedDisplayName(): String = when (this) {
    UnitPreference.METRIC -> stringResource(R.string.unit_display_metric)
    UnitPreference.IMPERIAL -> stringResource(R.string.unit_display_imperial)
}

@Composable
fun UnitPreference.localizedDescription(): String = when (this) {
    UnitPreference.METRIC -> stringResource(R.string.unit_desc_metric)
    UnitPreference.IMPERIAL -> stringResource(R.string.unit_desc_imperial)
}

@Composable
fun MarkdownTemplateStyle.localizedDisplayName(): String = when (this) {
    MarkdownTemplateStyle.STANDARD -> stringResource(R.string.template_display_standard)
    MarkdownTemplateStyle.COMPACT -> stringResource(R.string.template_display_compact)
    MarkdownTemplateStyle.DETAILED -> stringResource(R.string.template_display_detailed)
    MarkdownTemplateStyle.CUSTOM -> stringResource(R.string.template_display_custom)
}

@Composable
fun MarkdownTemplateStyle.localizedDescription(): String = when (this) {
    MarkdownTemplateStyle.STANDARD -> stringResource(R.string.template_desc_standard)
    MarkdownTemplateStyle.COMPACT -> stringResource(R.string.template_desc_compact)
    MarkdownTemplateStyle.DETAILED -> stringResource(R.string.template_desc_detailed)
    MarkdownTemplateStyle.CUSTOM -> stringResource(R.string.template_desc_custom)
}

@Composable
fun BulletStyle.localizedDisplayName(): String = when (this) {
    BulletStyle.DASH -> stringResource(R.string.bullet_display_dash)
    BulletStyle.ASTERISK -> stringResource(R.string.bullet_display_asterisk)
    BulletStyle.PLUS -> stringResource(R.string.bullet_display_plus)
}
