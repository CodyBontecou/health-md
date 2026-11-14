package com.healthmd.presentation.onboarding

import android.text.format.DateFormat
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowForward
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.healthmd.R
import com.healthmd.data.drive.GoogleDriveDestination
import com.healthmd.data.drive.GoogleDriveErrorId
import com.healthmd.domain.onboarding.HealthPack
import com.healthmd.presentation.drive.userText
import com.healthmd.domain.model.SavedAPIEndpoint
import com.healthmd.domain.model.SavedAPIEndpointRules
import com.healthmd.presentation.endpoints.BoundEndpointRow
import com.healthmd.domain.repository.PurchaseOffer
import com.healthmd.presentation.common.HealthConnectActionError
import com.healthmd.presentation.common.HealthConnectErrorNotice
import com.healthmd.presentation.theme.*
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

// region Welcome (A0)

@Composable
internal fun WelcomeStep(onStart: () -> Unit, onUseSharedSetup: () -> Unit) {
    val reading = LocalOnboardingReadingLayout.current
    val colors = LocalGeistColors.current
    OnboardingStepScaffold(
        step = OnboardingStep.WELCOME,
        onBack = null,
        footer = {
            OnboardingPrimaryButton(
                text = stringResource(R.string.onboarding_get_started),
                onClick = onStart,
                trailingIcon = Icons.AutoMirrored.Outlined.ArrowForward,
            )
            OnboardingFootnote(stringResource(R.string.onboarding_welcome_privacy), Icons.Outlined.Lock)
            OnboardingSecondaryButton(stringResource(R.string.shared_setup_use), onUseSharedSetup)
        },
    ) {
        if (!reading) WelcomeHero()
        OnboardingTitle(
            stringResource(R.string.onboarding_welcome_title_lead),
            stringResource(R.string.onboarding_welcome_title_accent),
            large = !reading,
        )
        OnboardingBodyText(stringResource(R.string.onboarding_welcome_body))
        val steps = listOf(
            R.string.onboarding_welcome_step_1,
            R.string.onboarding_welcome_step_2,
            R.string.onboarding_welcome_step_3,
        )
        val stepCard: @Composable (Int, Int, Modifier) -> Unit = { index, label, modifier ->
            Column(
                modifier.background(colors.background200, RoundedCornerShape(GeistRadii.medium)).padding(GeistSpacing.space3),
                verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
            ) {
                Text(stringResource(R.string.onboarding_welcome_step_label, index + 1), style = GeistType.label12, color = colors.brandPrimary)
                Text(stringResource(label), style = GeistType.label14, color = colors.primary)
            }
        }
        if (reading) {
            Column(verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
                steps.forEachIndexed { i, label -> stepCard(i, label, Modifier.fillMaxWidth()) }
            }
        } else {
            Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
                steps.forEachIndexed { i, label -> stepCard(i, label, Modifier.weight(1f).fillMaxHeight()) }
            }
        }
    }
}

/** Decorative stack of daily notes; hidden from accessibility and in reading layouts. */
@Composable
private fun WelcomeHero() {
    val colors = LocalGeistColors.current
    val today = remember { LocalDate.now() }
    val shape = RoundedCornerShape(GeistRadii.large - 4.dp)
    Box(
        Modifier.fillMaxWidth().height(250.dp).testTag(OnboardingTestTags.HERO).clearAndSetSemantics { },
        contentAlignment = Alignment.Center,
    ) {
        listOf(-9f to (-64).dp, 8f to 64.dp).forEachIndexed { index, (angle, offset) ->
            Column(
                Modifier.offset(x = offset).size(180.dp).rotate(angle).background(colors.background200, shape)
                    .padding(GeistSpacing.space4),
                verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
                horizontalAlignment = if (index == 0) Alignment.Start else Alignment.End,
            ) {
                Text("${today.minusDays(2L - index)}.md", style = GeistType.label12Mono, color = colors.gray.c700)
                Box(Modifier.fillMaxWidth(0.7f).height(8.dp).background(colors.gray.c200, CircleShape))
                Box(Modifier.fillMaxWidth(0.5f).height(8.dp).background(colors.gray.c200, CircleShape))
            }
        }
        Column(
            Modifier.width(210.dp).background(colors.gray.c100, shape)
                .padding(GeistSpacing.space4),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(formatDate(today, "MMMd"), style = GeistType.heading16, color = colors.primary, modifier = Modifier.weight(1f))
                Text(".md", style = GeistType.label12Mono, color = colors.secondary,
                    modifier = Modifier.background(colors.gray.c200, RoundedCornerShape(6.dp)).padding(horizontal = 6.dp, vertical = 2.dp))
            }
            HeroRow(HealthPack.SLEEP, stringResource(R.string.onboarding_note_chart_sleep), "7h 42m")
            HeroRow(HealthPack.ACTIVITY, stringResource(R.string.onboarding_note_chart_steps), "8,432")
            HeroRow(HealthPack.HEART, "HRV", "48 ms")
            Canvas(Modifier.fillMaxWidth().height(28.dp)) {
                val points = listOf(20f, 16f, 22f, 10f, 14f, 6f, 12f, 4f)
                val path = Path()
                points.forEachIndexed { i, y ->
                    val x = size.width * i / (points.size - 1)
                    val py = size.height * y / 28f
                    if (i == 0) path.moveTo(x, py) else path.lineTo(x, py)
                }
                drawPath(path, colors.brandPrimary, style = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round))
            }
        }
        Row(
            Modifier.align(Alignment.BottomEnd).padding(end = GeistSpacing.space6)
                .background(colors.primary, RoundedCornerShape(GeistRadii.small))
                .padding(horizontal = GeistSpacing.space3, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Icon(Icons.Outlined.Check, contentDescription = null, tint = colors.background100, modifier = Modifier.size(14.dp))
            Text(stringResource(R.string.onboarding_welcome_saved_badge), style = GeistType.label12, color = colors.background100)
        }
    }
}

@Composable
private fun HeroRow(pack: HealthPack, label: String, value: String) {
    val colors = LocalGeistColors.current
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        PackIconTile(pack, size = 30.dp)
        Text(label, style = GeistType.copy13, color = colors.secondary, modifier = Modifier.weight(1f))
        Text(value, style = GeistType.label14Mono, color = colors.primary)
    }
}

// endregion

// region Packs (A1)

@Composable
internal fun PacksStep(
    selected: Set<HealthPack>,
    unavailable: Set<HealthPack>,
    onToggle: (HealthPack) -> Unit,
    onToggleAll: () -> Unit,
    onContinue: () -> Unit,
    onBack: () -> Unit,
) {
    val colors = LocalGeistColors.current
    val reading = LocalOnboardingReadingLayout.current
    val available = HealthPack.entries.filterNot { it in unavailable }
    val allOn = selected.containsAll(available) && available.isNotEmpty()
    val count = HealthPack.metricCount(selected)
    OnboardingStepScaffold(
        step = OnboardingStep.PACKS,
        onBack = onBack,
        footer = {
            Row(Modifier.fillMaxWidth().padding(horizontal = GeistSpacing.space1)) {
                Text(
                    if (selected.isEmpty()) stringResource(R.string.onboarding_packs_none)
                    else pluralStringResource(R.plurals.onboarding_packs_metrics_selected, count, count),
                    style = GeistType.label14,
                    color = colors.primary,
                    modifier = Modifier.weight(1f),
                )
                Text(stringResource(R.string.onboarding_packs_next_hint), style = GeistType.copy14, color = colors.secondary)
            }
            OnboardingPrimaryButton(
                text = stringResource(R.string.onboarding_continue),
                onClick = onContinue,
                enabled = OnboardingFlow.canContinueFromPacks(selected.size),
            )
        },
    ) {
        OnboardingTitle(stringResource(R.string.onboarding_packs_title_lead), stringResource(R.string.onboarding_packs_title_accent))
        OnboardingBodyText(stringResource(R.string.onboarding_packs_body))
        Row(
            Modifier.fillMaxWidth()
                .heightIn(min = GeistSizes.minimumTouchTarget)
                .clip(RoundedCornerShape(GeistRadii.small))
                .toggleable(value = allOn, role = Role.Checkbox, onValueChange = { onToggleAll() })
                .testTag(OnboardingTestTags.SELECT_ALL)
                .padding(horizontal = GeistSpacing.space1),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
        ) {
            TriStateCheckbox(
                state = when {
                    allOn -> ToggleableState.On
                    selected.isEmpty() -> ToggleableState.Off
                    else -> ToggleableState.Indeterminate
                },
                onClick = null,
                colors = brandCheckboxColors(),
            )
            Text(
                stringResource(if (allOn) R.string.onboarding_packs_deselect_all else R.string.onboarding_packs_select_all),
                style = GeistType.label16,
                color = colors.primary,
                modifier = Modifier.weight(1f),
            )
            Text(
                stringResource(R.string.onboarding_packs_selected, selected.size, HealthPack.entries.size),
                style = GeistType.copy14,
                color = colors.secondary,
            )
        }
        val rows = if (reading) HealthPack.entries.map { listOf(it) } else HealthPack.entries.chunked(2)
        Column(verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
            rows.forEach { row ->
                Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
                    row.forEach { pack ->
                        PackCard(
                            pack = pack,
                            selected = pack in selected,
                            unavailable = pack in unavailable,
                            onToggle = { onToggle(pack) },
                            modifier = Modifier.weight(1f).fillMaxHeight(),
                        )
                    }
                    if (row.size == 1 && !reading) Spacer(Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
private fun PackCard(pack: HealthPack, selected: Boolean, unavailable: Boolean, onToggle: () -> Unit, modifier: Modifier) {
    val colors = LocalGeistColors.current
    val shape = RoundedCornerShape(GeistRadii.listGroup)
    Column(
        modifier
            .clip(shape)
            .background(if (selected) colors.brandSubtle else colors.background200)
            .toggleable(value = selected, enabled = !unavailable, role = Role.Checkbox, onValueChange = { onToggle() })
            .testTag(OnboardingTestTags.PACK)
            .heightIn(min = 132.dp)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
            PackIconTile(pack)
            Spacer(Modifier.weight(1f))
            Checkbox(checked = selected, onCheckedChange = null, enabled = !unavailable, colors = brandCheckboxColors())
        }
        Text(stringResource(pack.nameRes), style = GeistType.label16, color = if (unavailable) colors.disabled else colors.primary)
        Text(
            stringResource(if (unavailable) R.string.onboarding_packs_unavailable else pack.detailRes),
            style = GeistType.copy13,
            color = colors.secondary,
        )
        Spacer(Modifier.weight(1f))
        Text(
            pluralStringResource(R.plurals.onboarding_packs_types, pack.metricCount, pack.metricCount),
            style = GeistType.label12,
            color = if (selected) colors.brandOnPrimary else colors.secondary,
            modifier = Modifier
                .background(if (selected) colors.brandPrimary else colors.gray.c300, RoundedCornerShape(GeistRadii.small))
                .padding(horizontal = GeistSpacing.space2, vertical = GeistSpacing.space1),
        )
    }
}

@Composable
private fun brandCheckboxColors() = CheckboxDefaults.colors(
    checkedColor = LocalGeistColors.current.brandPrimary,
    checkmarkColor = LocalGeistColors.current.brandOnPrimary,
    uncheckedColor = LocalGeistColors.current.secondary,
)

// endregion

// region Health Connect (A2)

@Composable
internal fun HealthStep(
    selected: Set<HealthPack>,
    healthConnectAvailable: Boolean,
    needsSetup: Boolean,
    actionError: HealthConnectActionError?,
    onDismissError: () -> Unit,
    onConnect: () -> Unit,
    onSkip: () -> Unit,
    onBack: () -> Unit,
) {
    val colors = LocalGeistColors.current
    val reading = LocalOnboardingReadingLayout.current
    OnboardingStepScaffold(
        step = OnboardingStep.HEALTH,
        onBack = onBack,
        onSkip = onSkip,
        footer = {
            OnboardingPrimaryButton(
                text = stringResource(
                    when {
                        !healthConnectAvailable -> R.string.onboarding_health_install
                        needsSetup -> R.string.onboarding_health_open_settings
                        else -> R.string.onboarding_health_continue
                    },
                ),
                onClick = onConnect,
                leadingIcon = Icons.Outlined.Favorite,
            )
            OnboardingSecondaryButton(stringResource(R.string.onboarding_skip_for_now), onSkip)
        },
    ) {
        if (!reading) {
            Row(
                Modifier.fillMaxWidth().height(150.dp).testTag(OnboardingTestTags.HERO).clearAndSetSemantics { },
                horizontalArrangement = Arrangement.spacedBy(14.dp, Alignment.CenterHorizontally),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(Modifier.size(76.dp).background(colors.background200, RoundedCornerShape(22.dp)), contentAlignment = Alignment.Center) {
                    Icon(Icons.Outlined.Favorite, contentDescription = null, tint = colors.red.c900, modifier = Modifier.size(36.dp))
                }
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    listOf(colors.brandBorder, colors.brandPrimary.copy(alpha = 0.6f), colors.brandPrimary).forEach {
                        Box(Modifier.size(6.dp).background(it, CircleShape))
                    }
                    Icon(Icons.AutoMirrored.Outlined.ArrowForward, contentDescription = null, tint = colors.brandPrimary, modifier = Modifier.size(18.dp))
                }
                Box(Modifier.size(76.dp).background(colors.primary, RoundedCornerShape(22.dp)), contentAlignment = Alignment.Center) {
                    Icon(Icons.Outlined.Description, contentDescription = null, tint = colors.background100, modifier = Modifier.size(36.dp))
                }
            }
        }
        OnboardingTitle(stringResource(R.string.onboarding_health_title_lead), stringResource(R.string.onboarding_health_title_accent))
        val allowAll = stringResource(R.string.onboarding_health_allow_all)
        val body = stringResource(R.string.onboarding_health_body, allowAll)
        Text(
            buildAnnotatedString {
                val start = body.indexOf(allowAll)
                append(body)
                if (start >= 0) addStyle(SpanStyle(color = colors.primary, fontWeight = FontWeight.SemiBold), start, start + allowAll.length)
            },
            style = GeistType.copy16,
            color = colors.secondary,
        )
        actionError?.let { HealthConnectErrorNotice(error = it, onDismiss = onDismissError) }
        @OptIn(ExperimentalLayoutApi::class)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2), verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
            HealthPack.entries.filter { it in selected }.forEach { pack ->
                val tone = pack.tone()
                Row(
                    Modifier.heightIn(min = GeistSizes.controlSmall)
                        .background(tone.container, RoundedCornerShape(GeistRadii.small))
                        .padding(start = GeistSpacing.space2, end = GeistSpacing.space3),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Icon(pack.icon, contentDescription = null, tint = tone.content, modifier = Modifier.size(16.dp))
                    Text(
                        stringResource(R.string.onboarding_health_pack_chip, stringResource(pack.nameRes), pack.metricCount),
                        style = GeistType.label14,
                        color = tone.content,
                    )
                }
            }
        }
        Row(Modifier.fillMaxWidth().padding(top = GeistSpacing.space2), horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
            listOf(
                Icons.Outlined.VisibilityOff to R.string.onboarding_health_read_only,
                Icons.Outlined.PhoneAndroid to R.string.onboarding_health_on_phone,
                Icons.Outlined.Tune to R.string.onboarding_health_change_anytime,
            ).forEach { (icon, label) ->
                Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Icon(icon, contentDescription = null, tint = colors.brandPrimary)
                    Text(stringResource(label), style = GeistType.label12, color = colors.secondary)
                }
            }
        }
    }
}

// endregion

// region Folder (A3)

@Composable
internal fun FolderStep(
    destination: OnboardingDestination,
    folderName: String?,
    subfolder: String,
    apiEndpoint: SavedAPIEndpoint?,
    metricCount: Int,
    driveAvailable: Boolean,
    driveDestination: GoogleDriveDestination?,
    driveConnecting: Boolean,
    driveError: GoogleDriveErrorId?,
    onSelectDestination: (OnboardingDestination) -> Unit,
    onConnectDrive: () -> Unit,
    onPickFolder: () -> Unit,
    onAddEndpoint: () -> Unit,
    onEditEndpoint: () -> Unit,
    onContinue: () -> Unit,
    onSkip: () -> Unit,
    onBack: () -> Unit,
) {
    val colors = LocalGeistColors.current
    val reading = LocalOnboardingReadingLayout.current
    val usesDrive = destination == OnboardingDestination.GOOGLE_DRIVE && driveAvailable
    val usesFolder = destination != OnboardingDestination.API_ENDPOINT && !usesDrive
    OnboardingStepScaffold(
        step = OnboardingStep.FOLDER,
        onBack = onBack,
        onSkip = onSkip,
        footer = {
            if (usesDrive && driveDestination == null) {
                OnboardingPrimaryButton(
                    text = stringResource(R.string.google_drive_connect),
                    onClick = onConnectDrive,
                    enabled = !driveConnecting,
                    isLoading = driveConnecting,
                    leadingIcon = Icons.Outlined.CloudQueue,
                )
            } else OnboardingPrimaryButton(
                text = stringResource(if (usesFolder && folderName == null) R.string.onboarding_folder_choose else R.string.onboarding_folder_show_notes),
                onClick = if (usesFolder && folderName == null) onPickFolder else onContinue,
                leadingIcon = if (usesFolder && folderName == null) Icons.Outlined.FolderOpen else null,
                trailingIcon = if (usesFolder && folderName == null) null else Icons.AutoMirrored.Outlined.ArrowForward,
            )
        },
    ) {
        OnboardingTitle(stringResource(R.string.onboarding_folder_title_lead), stringResource(R.string.onboarding_folder_title_accent))
        OnboardingBodyText(
            when {
                usesDrive -> stringResource(R.string.onboarding_folder_drive_body)
                usesFolder -> stringResource(R.string.onboarding_folder_body, subfolder.ifBlank { "health" })
                else -> stringResource(R.string.onboarding_folder_api_body)
            },
        )
        if (!reading && usesFolder) FolderPreview(folderName, subfolder)
        if (!reading && !usesFolder && apiEndpoint != null) PayloadPreview(apiEndpoint, metricCount)
        Column(verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
            DestinationRow(
                selected = destination == OnboardingDestination.LOCAL_FOLDER,
                icon = Icons.Outlined.Folder,
                iconTint = colors.brandPrimary,
                iconContainer = colors.background100,
                title = stringResource(R.string.onboarding_folder_local),
                detail = if (destination == OnboardingDestination.LOCAL_FOLDER && folderName != null) {
                    stringResource(R.string.onboarding_folder_selected, folderName)
                } else {
                    stringResource(R.string.onboarding_folder_local_detail)
                },
                badge = stringResource(R.string.onboarding_folder_recommended),
                onClick = {
                    if (destination == OnboardingDestination.LOCAL_FOLDER) onPickFolder()
                    else onSelectDestination(OnboardingDestination.LOCAL_FOLDER)
                },
            )
            DestinationRow(
                selected = destination == OnboardingDestination.API_ENDPOINT,
                icon = Icons.Outlined.Api,
                iconTint = colors.amber.c900,
                iconContainer = colors.amber.c200,
                title = stringResource(R.string.onboarding_folder_api),
                detail = stringResource(R.string.onboarding_folder_api_detail),
                onClick = { onSelectDestination(OnboardingDestination.API_ENDPOINT) },
            )
            if (destination == OnboardingDestination.API_ENDPOINT) {
                if (apiEndpoint != null) {
                    BoundEndpointRow(apiEndpoint, onEdit = onEditEndpoint, modifier = Modifier.padding(start = GeistSpacing.space4))
                } else {
                    TextButton(onClick = onAddEndpoint, modifier = Modifier.padding(start = GeistSpacing.space2)) {
                        Icon(Icons.Outlined.Add, contentDescription = null, tint = colors.brandPrimary, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(GeistSpacing.space2))
                        Text(stringResource(R.string.onboarding_folder_api_add), style = GeistType.button14, color = colors.brandPrimary)
                    }
                }
            }
            DestinationRow(
                selected = destination == OnboardingDestination.GOOGLE_DRIVE,
                icon = Icons.Outlined.CloudQueue,
                iconTint = colors.green.c900,
                iconContainer = colors.green.c200,
                title = stringResource(R.string.onboarding_folder_drive),
                detail = when {
                    driveAvailable -> stringResource(R.string.onboarding_folder_drive_connect_detail)
                    destination == OnboardingDestination.GOOGLE_DRIVE && folderName != null ->
                        stringResource(R.string.onboarding_folder_selected, folderName)
                    else -> stringResource(R.string.onboarding_folder_drive_detail)
                },
                onClick = {
                    when {
                        destination != OnboardingDestination.GOOGLE_DRIVE -> onSelectDestination(OnboardingDestination.GOOGLE_DRIVE)
                        driveAvailable -> if (driveDestination == null) onConnectDrive()
                        else -> onPickFolder()
                    }
                },
            )
            if (usesDrive) {
                if (driveDestination != null) {
                    BoundDriveRow(driveDestination, changeEnabled = !driveConnecting, onChange = onConnectDrive,
                        modifier = Modifier.padding(start = GeistSpacing.space4))
                }
                driveError?.let { error ->
                    Text(
                        error.userText(),
                        style = GeistType.copy13,
                        color = colors.error,
                        modifier = Modifier.padding(start = GeistSpacing.space4).testTag(OnboardingTestTags.DRIVE_ERROR),
                    )
                }
            }
            if (usesFolder && folderName != null) {
                TextButton(onClick = onPickFolder) {
                    Text(stringResource(R.string.onboarding_folder_change), style = GeistType.button14, color = colors.brandPrimary)
                }
            }
        }
    }
}

/** AE2-style connected row for Google Drive: green dot, "Google Drive" / folder, and Change. */
@Composable
private fun BoundDriveRow(destination: GoogleDriveDestination, changeEnabled: Boolean, onChange: () -> Unit, modifier: Modifier = Modifier) {
    val colors = LocalGeistColors.current
    Row(
        modifier.fillMaxWidth().background(colors.background100, RoundedCornerShape(GeistRadii.medium))
            .padding(start = GeistSpacing.space3, top = GeistSpacing.space2, bottom = GeistSpacing.space2, end = GeistSpacing.space1),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
    ) {
        Box(Modifier.size(8.dp).background(colors.success, CircleShape))
        Column(Modifier.weight(1f)) {
            Text(stringResource(R.string.google_drive_destination_label), style = GeistType.label14, color = colors.primary)
            Text(destination.folderLabel, style = GeistType.copy13Mono, color = colors.secondary)
        }
        TextButton(onClick = onChange, enabled = changeEnabled, modifier = Modifier.testTag(OnboardingTestTags.DRIVE_CHANGE)) {
            Text(stringResource(R.string.onboarding_folder_drive_change), style = GeistType.button14, color = colors.brandPrimary)
        }
    }
}

/** AE2: the inverse-surface preview of what is POSTed: host/path and the envelope keys. */
@Composable
private fun PayloadPreview(endpoint: SavedAPIEndpoint, metricCount: Int) {
    val colors = LocalGeistColors.current
    val today = remember { LocalDate.now() }
    val target = SavedAPIEndpointRules.displayUrl(endpoint.url)
    val label = stringResource(R.string.onboarding_folder_payload_label, target)
    val ink = colors.background100
    val key = colors.brandBorder
    val dim = colors.gray.c500
    Column(
        Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = label }
            .background(colors.primary, RoundedCornerShape(GeistRadii.large - 4.dp)).padding(GeistSpacing.space4),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
            Text("POST", style = GeistType.label12Mono, color = colors.primary,
                modifier = Modifier.background(colors.green.c500, RoundedCornerShape(4.dp)).padding(horizontal = 6.dp, vertical = 1.dp))
            Text(target, style = GeistType.copy13Mono, color = ink, maxLines = 1)
        }
        val line: @Composable (String, String?, Int) -> Unit = { k, v, indent ->
            Text(
                buildAnnotatedString {
                    withStyle(SpanStyle(color = key)) { append("\"$k\"") }
                    if (v != null) append(": $v")
                },
                style = GeistType.copy13Mono,
                color = ink,
                modifier = Modifier.padding(start = (indent * 14).dp),
            )
        }
        Text("{", style = GeistType.copy13Mono, color = ink)
        line("schema", "\"healthmd.api_export\",", 1)
        line("records", "[{", 1)
        line("date", "\"$today\",", 2)
        Text(pluralStringResource(R.plurals.onboarding_folder_payload_more, metricCount, metricCount),
            style = GeistType.copy13Mono, color = dim, modifier = Modifier.padding(start = 28.dp))
        Text("  }]", style = GeistType.copy13Mono, color = ink)
        Text("}", style = GeistType.copy13Mono, color = ink)
    }
}

/** The inverse-surface tree of what will be written: folder, subfolder, one file per day. */
@Composable
private fun FolderPreview(folderName: String?, subfolder: String) {
    val colors = LocalGeistColors.current
    val today = remember { LocalDate.now() }
    val label = stringResource(R.string.onboarding_folder_preview_label)
    val ink = colors.background100
    val dim = colors.gray.c500
    Column(
        Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = label }
            .background(colors.primary, RoundedCornerShape(GeistRadii.large - 4.dp)).padding(GeistSpacing.space4),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
            Icon(Icons.Outlined.Folder, contentDescription = null, tint = ink, modifier = Modifier.size(14.dp))
            Text(folderName ?: stringResource(R.string.onboarding_storage_selected_folder_fallback), style = GeistType.copy13Mono, color = ink)
        }
        if (subfolder.isNotBlank()) {
            Row(Modifier.padding(start = 20.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
                Icon(Icons.Outlined.Folder, contentDescription = null, tint = ink, modifier = Modifier.size(14.dp))
                Text(subfolder, style = GeistType.copy13Mono, color = ink)
            }
        }
        (0..2).forEach { back ->
            Row(
                Modifier.fillMaxWidth().padding(start = 40.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
            ) {
                Box(Modifier.size(6.dp).background(colors.green.c500, CircleShape))
                Text("${today.minusDays(back.toLong())}.md", style = GeistType.copy13Mono,
                    color = if (back == 2) dim else ink, modifier = Modifier.weight(1f))
                if (back == 0) Text(stringResource(R.string.onboarding_folder_preview_new), style = GeistType.label12, color = colors.green.c500)
            }
        }
        Text(stringResource(R.string.onboarding_folder_preview_more, 4), style = GeistType.copy13Mono, color = dim,
            modifier = Modifier.padding(start = 54.dp))
    }
}

@Composable
private fun DestinationRow(
    selected: Boolean,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    iconTint: androidx.compose.ui.graphics.Color,
    iconContainer: androidx.compose.ui.graphics.Color,
    title: String,
    detail: String,
    onClick: () -> Unit,
    badge: String? = null,
) {
    val colors = LocalGeistColors.current
    Row(
        Modifier.fillMaxWidth()
            .clip(RoundedCornerShape(GeistRadii.listGroup))
            .background(if (selected) colors.brandSubtle else colors.background200)
            .selectable(selected = selected, role = Role.RadioButton, onClick = onClick)
            .testTag(OnboardingTestTags.DESTINATION)
            .heightIn(min = 72.dp)
            .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space3),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(Modifier.size(GeistSizes.control).background(iconContainer, RoundedCornerShape(GeistSpacing.space3)), contentAlignment = Alignment.Center) {
            Icon(icon, contentDescription = null, tint = iconTint)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = GeistType.label16, color = colors.primary)
            Text(detail, style = GeistType.copy13, color = colors.secondary)
        }
        if (badge != null && !LocalOnboardingReadingLayout.current) {
            Text(
                badge.uppercase(LocalConfiguration.current.locales[0] ?: Locale.getDefault()),
                style = GeistType.label12,
                color = colors.brandOnPrimary,
                modifier = Modifier.background(colors.brandPrimary, RoundedCornerShape(6.dp)).padding(horizontal = 6.dp, vertical = 3.dp),
            )
        }
        RadioButton(selected = selected, onClick = null, colors = RadioButtonDefaults.colors(selectedColor = colors.brandPrimary, unselectedColor = colors.secondary))
    }
}

// endregion

// region First note (A4 / no-data)

/** What the First note step's primary action does. */
internal sealed interface FirstNoteAction {
    /** The single free export (or a paid export) of the seven days. */
    data class Save(val count: Int, val destination: String, val sends: Boolean) : FirstNoteAction
    /** A folder destination was skipped: pick one before saving. */
    data object ChooseFolder : FirstNoteAction
    /** Sample note: finish without consuming the free export. */
    data object Finish : FirstNoteAction
    /** No access and no free export left: continue to Make it daily. */
    data object FreeUsed : FirstNoteAction
}

@Composable
internal fun FirstNoteStep(
    note: NotePreviewState,
    selectedDay: Int,
    showRaw: Boolean,
    action: FirstNoteAction,
    isSaving: Boolean,
    saveFailed: Boolean,
    onSelectDay: (Int) -> Unit,
    onToggleRaw: () -> Unit,
    onPrimary: () -> Unit,
    onContinueWithoutSaving: () -> Unit,
    onBack: () -> Unit,
) {
    val colors = LocalGeistColors.current
    val days = when (note) {
        is NotePreviewState.Ready -> note.days
        is NotePreviewState.Sample -> note.days
        else -> emptyList()
    }
    val sample = note as? NotePreviewState.Sample
    OnboardingStepScaffold(
        step = OnboardingStep.FIRST_NOTE,
        onBack = onBack,
        footer = {
            if (saveFailed) {
                Text(stringResource(R.string.onboarding_note_save_failed), style = GeistType.copy13, color = colors.error)
            }
            OnboardingPrimaryButton(
                text = when (action) {
                    is FirstNoteAction.Save -> pluralStringResource(
                        if (action.sends) R.plurals.onboarding_note_send else R.plurals.onboarding_note_save,
                        action.count, action.count, action.destination,
                    )
                    FirstNoteAction.ChooseFolder -> stringResource(R.string.onboarding_note_choose_folder)
                    FirstNoteAction.Finish -> stringResource(R.string.onboarding_note_finish)
                    FirstNoteAction.FreeUsed -> stringResource(R.string.onboarding_continue)
                },
                onClick = onPrimary,
                enabled = note !is NotePreviewState.Loading,
                isLoading = isSaving,
                leadingIcon = when (action) {
                    is FirstNoteAction.Save -> Icons.Outlined.Download
                    FirstNoteAction.ChooseFolder -> Icons.Outlined.FolderOpen
                    else -> null
                },
            )
            val fine = when (action) {
                is FirstNoteAction.Save -> days.firstOrNull()?.let { first ->
                    stringResource(R.string.onboarding_note_range, formatDate(first.date, "MMMd"), formatDate(days.last().date, "MMMd")) +
                        " " + stringResource(R.string.onboarding_note_free)
                }
                FirstNoteAction.Finish -> stringResource(R.string.onboarding_note_finish_fine)
                FirstNoteAction.FreeUsed -> stringResource(R.string.onboarding_note_free_used)
                FirstNoteAction.ChooseFolder -> null
            }
            fine?.let { Text(it, style = GeistType.copy13, color = colors.secondary) }
            if (action is FirstNoteAction.ChooseFolder || saveFailed) {
                OnboardingSecondaryButton(stringResource(R.string.onboarding_note_continue_without_saving), onContinueWithoutSaving, enabled = !isSaving)
            }
        },
    ) {
        if (sample != null) {
            OnboardingTitle(stringResource(R.string.onboarding_note_sample_title_lead), stringResource(R.string.onboarding_note_sample_title_accent))
            Row(
                Modifier.fillMaxWidth().testTag(OnboardingTestTags.SAMPLE_NOTICE)
                    .background(colors.tertiaryContainer, RoundedCornerShape(GeistRadii.medium))
                    .padding(horizontal = 14.dp, vertical = GeistSpacing.space3),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Icon(Icons.Outlined.Info, contentDescription = null, tint = colors.onTertiaryContainer)
                Text(
                    stringResource(
                        if (sample.reason == SampleReason.NO_HEALTH_ACCESS) R.string.onboarding_note_sample_no_access
                        else R.string.onboarding_note_sample_no_data,
                    ),
                    style = GeistType.copy14,
                    color = colors.onTertiaryContainer,
                )
            }
        } else {
            OnboardingTitle(stringResource(R.string.onboarding_note_title_lead), stringResource(R.string.onboarding_note_title_accent))
            if (note is NotePreviewState.Ready) {
                val ready = note.days.count { it.hasNote }
                OnboardingBodyText(pluralStringResource(R.plurals.onboarding_note_ready, ready, ready))
            }
        }
        if (note is NotePreviewState.Loading || note is NotePreviewState.Idle) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3)) {
                CircularProgressIndicator(Modifier.size(20.dp), color = colors.brandPrimary, strokeWidth = 2.dp)
                Text(stringResource(R.string.onboarding_note_loading), style = GeistType.copy14, color = colors.secondary)
            }
            return@OnboardingStepScaffold
        }
        WeekChart(days, selectedDay, onSelectDay)
        days.getOrNull(selectedDay)?.let { day -> NoteCard(day, showRaw, isSample = sample != null, onToggleRaw = onToggleRaw) }
    }
}

/** Seven bars, one per day; tapping a bar previews that day's note. */
@Composable
private fun WeekChart(days: List<OnboardingNoteDay>, selectedDay: Int, onSelectDay: (Int) -> Unit) {
    val colors = LocalGeistColors.current
    val values = days.map(OnboardingNoteParser::chartValue)
    val max = values.filterNotNull().maxOrNull()?.takeIf { it > 0 }
    val isSleep = OnboardingNoteParser.chartIsSleep(days)
    val title = when {
        max == null -> stringResource(R.string.onboarding_note_chart_days)
        isSleep -> stringResource(R.string.onboarding_note_chart_sleep)
        else -> stringResource(R.string.onboarding_note_chart_steps)
    }
    val average = values.filterNotNull().takeIf { it.isNotEmpty() }?.average()
    Column(
        Modifier.fillMaxWidth().background(colors.background200, RoundedCornerShape(GeistRadii.large - 4.dp))
            .padding(start = GeistSpacing.space4, end = GeistSpacing.space4, top = 14.dp, bottom = 10.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(title, style = GeistType.label14, color = if (isSleep) HealthPack.SLEEP.tone().content else colors.primary, modifier = Modifier.weight(1f))
            if (average != null && max != null) {
                val avgText = if (isSleep) "${average.toInt() / 60}h ${average.toInt() % 60}m" else String.format(Locale.getDefault(), "%,d", average.toInt())
                Text(stringResource(R.string.onboarding_note_average, avgText), style = GeistType.label12Mono, color = colors.secondary)
            }
        }
        Row(Modifier.fillMaxWidth().height(96.dp), horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2), verticalAlignment = Alignment.Bottom) {
            days.forEachIndexed { index, day ->
                val selected = index == selectedDay
                val fraction = when {
                    !day.hasNote -> 0.12f
                    max == null -> 0.7f
                    else -> ((values[index] ?: 0.0) / max).toFloat().coerceIn(0.12f, 1f)
                }
                val dayName = formatDate(day.date, "EEEMMMd")
                val a11y = if (day.hasNote) dayName else stringResource(R.string.onboarding_note_day_a11y, dayName, stringResource(R.string.onboarding_note_day_no_note))
                Column(
                    Modifier.weight(1f).fillMaxHeight()
                        .clip(RoundedCornerShape(GeistRadii.small))
                        .selectable(selected = selected, role = Role.Tab, onClick = { onSelectDay(index) })
                        .semantics { contentDescription = a11y }
                        .testTag(OnboardingTestTags.DAY),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(6.dp, Alignment.Bottom),
                ) {
                    Box(
                        Modifier.fillMaxWidth().fillMaxHeight(fraction * 0.78f)
                            .background(
                                when {
                                    selected -> colors.brandPrimary
                                    day.hasNote -> colors.brandSubtle
                                    else -> colors.gray.c300
                                },
                                RoundedCornerShape(GeistRadii.small),
                            ),
                    )
                    Text(
                        formatDate(day.date, "EEEEE"),
                        style = if (selected) GeistType.label12.copy(fontWeight = FontWeight.Bold) else GeistType.label12,
                        color = if (selected) colors.primary else colors.secondary,
                    )
                }
            }
        }
    }
}

@Composable
private fun NoteCard(day: OnboardingNoteDay, showRaw: Boolean, isSample: Boolean, onToggleRaw: () -> Unit) {
    val colors = LocalGeistColors.current
    Column(
        Modifier.fillMaxWidth().background(colors.background200, RoundedCornerShape(GeistRadii.large - 4.dp)).padding(GeistSpacing.space4),
        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
            Text(formatDate(day.date, "EEEMMMd"), style = GeistType.heading20, color = colors.primary, modifier = Modifier.weight(1f))
            if (isSample) {
                Text(stringResource(R.string.onboarding_note_sample_badge), style = GeistType.label12, color = colors.onTertiaryContainer,
                    modifier = Modifier.background(colors.tertiaryContainer, RoundedCornerShape(6.dp)).padding(horizontal = 7.dp, vertical = 3.dp))
            }
            day.fileName?.let {
                Text(it, style = GeistType.label12Mono, color = colors.secondary,
                    modifier = Modifier.background(colors.background100, RoundedCornerShape(6.dp)).padding(horizontal = 7.dp, vertical = 3.dp))
            }
        }
        if (!day.hasNote) {
            Text(stringResource(R.string.onboarding_note_empty_day), style = GeistType.copy14, color = colors.secondary)
            return@Column
        }
        if (showRaw) {
            Text(
                day.raw.orEmpty(),
                style = GeistType.copy13Mono,
                color = colors.primary,
                modifier = Modifier.fillMaxWidth().testTag(OnboardingTestTags.RAW_FILE)
                    .background(colors.background100, RoundedCornerShape(GeistRadii.medium))
                    .horizontalScroll(rememberScrollState()).padding(GeistSpacing.space3),
            )
        } else {
            @OptIn(ExperimentalLayoutApi::class)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                OnboardingNoteParser.highlights(day.sections).forEach { (section, row) ->
                    val tone = section.pack?.tone() ?: PackTone(colors.gray.c300, colors.secondary)
                    Text(
                        buildAnnotatedString {
                            append(row.label.lowercase(LocalConfiguration.current.locales[0] ?: Locale.getDefault()))
                            append(' ')
                            withStyle(GeistType.label12Mono.toSpanStyle()) { append(row.value) }
                        },
                        style = GeistType.label12,
                        color = tone.content,
                        modifier = Modifier.background(tone.container, RoundedCornerShape(GeistRadii.small))
                            .padding(horizontal = GeistSpacing.space2, vertical = GeistSpacing.space1),
                    )
                }
            }
            HorizontalDivider(color = colors.gray.c300)
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                day.sections.forEach { section ->
                    Text(section.title, style = GeistType.label16, color = colors.primary, modifier = Modifier.padding(top = GeistSpacing.space1))
                    section.rows.forEach { row ->
                        Row(horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
                            Text(row.label, style = GeistType.copy14, color = colors.secondary, modifier = Modifier.weight(1f))
                            Text(row.value, style = GeistType.label14Mono, color = colors.primary)
                        }
                    }
                }
            }
        }
        TextButton(onClick = onToggleRaw, modifier = Modifier.testTag(OnboardingTestTags.RAW_TOGGLE)) {
            Text(
                stringResource(if (showRaw) R.string.onboarding_note_view_rendered else R.string.onboarding_note_view_raw),
                style = GeistType.button14,
                color = colors.brandPrimary,
            )
        }
    }
}

// endregion

// region Make it daily (A5)

@Composable
internal fun DailyStep(
    savedNoteCount: Int?,
    destinationLabel: String?,
    offer: DailyOffer,
    trialOffer: PurchaseOffer?,
    purchasesAvailable: Boolean,
    isBusy: Boolean,
    purchaseFailed: Boolean,
    onStartTrial: () -> Unit,
    onEnable: () -> Unit,
    onNotNow: () -> Unit,
) {
    val colors = LocalGeistColors.current
    val destination = destinationLabel ?: stringResource(R.string.onboarding_daily_destination_fallback)
    val time = formatTime(OnboardingFlow.DAILY_HOUR, OnboardingFlow.DAILY_MINUTE)
    OnboardingStepScaffold(
        step = OnboardingStep.DAILY,
        onBack = null,
        footer = {
            if (purchaseFailed) Text(stringResource(R.string.onboarding_daily_purchase_error), style = GeistType.copy13, color = colors.error)
            when (offer) {
                DailyOffer.TRIAL -> OnboardingPrimaryButton(
                    text = stringResource(R.string.onboarding_daily_start_trial),
                    onClick = onStartTrial,
                    enabled = purchasesAvailable && trialOffer != null,
                    isLoading = isBusy,
                )
                DailyOffer.ENABLE -> OnboardingPrimaryButton(
                    text = stringResource(R.string.onboarding_daily_enable),
                    onClick = onEnable,
                    isLoading = isBusy,
                    leadingIcon = Icons.Outlined.Schedule,
                )
            }
            OnboardingSecondaryButton(stringResource(R.string.onboarding_daily_not_now), onNotNow, enabled = !isBusy)
            if (offer == DailyOffer.TRIAL) {
                Text(stringResource(R.string.onboarding_daily_cancel_anytime), style = GeistType.copy13, color = colors.secondary)
            }
        },
    ) {
        Row(
            Modifier.fillMaxWidth().padding(top = GeistSpacing.space4)
                .background(if (savedNoteCount != null) colors.green.c100 else colors.gray.c200, RoundedCornerShape(GeistRadii.medium))
                .padding(horizontal = 14.dp, vertical = GeistSpacing.space3),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Icon(
                if (savedNoteCount != null) Icons.Outlined.CheckCircle else Icons.Outlined.Info,
                contentDescription = null,
                tint = if (savedNoteCount != null) colors.success else colors.secondary,
            )
            Text(
                if (savedNoteCount != null) pluralStringResource(R.plurals.onboarding_daily_saved, savedNoteCount, savedNoteCount, destination)
                else stringResource(R.string.onboarding_daily_nothing_saved),
                style = GeistType.label14,
                color = if (savedNoteCount != null) colors.green.c1000 else colors.primary,
            )
        }
        Text(
            stringResource(R.string.onboarding_daily_title),
            style = GeistType.heading32,
            color = colors.primary,
            modifier = Modifier.padding(top = GeistSpacing.space2).semantics { heading() },
        )
        OnboardingBodyText(stringResource(R.string.onboarding_daily_body))
        Column(
            Modifier.fillMaxWidth().background(colors.background200, RoundedCornerShape(GeistRadii.large - 4.dp)).padding(GeistSpacing.space4),
            verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
        ) {
            val sentence = stringResource(R.string.onboarding_daily_sentence, time, destination)
            Text(
                buildAnnotatedString {
                    append(sentence)
                    sentence.indexOf(time).takeIf { it >= 0 }?.let { addStyle(SpanStyle(fontWeight = FontWeight.SemiBold), it, it + time.length) }
                    sentence.lastIndexOf(destination).takeIf { it >= 0 }?.let {
                        addStyle(GeistType.copy14Mono.toSpanStyle(), it, it + destination.length)
                    }
                },
                style = GeistType.copy16,
                color = colors.primary,
            )
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                when {
                    offer == DailyOffer.ENABLE -> Text(stringResource(R.string.onboarding_daily_background_note), style = GeistType.copy14, color = colors.secondary)
                    !purchasesAvailable -> Text(stringResource(R.string.onboarding_daily_billing_unavailable), style = GeistType.copy14, color = colors.secondary)
                    trialOffer == null -> Text(stringResource(R.string.onboarding_daily_loading_price), style = GeistType.copy14, color = colors.secondary)
                    else -> {
                        Text(stringResource(R.string.onboarding_daily_timeline_today), style = GeistType.copy14, color = colors.secondary)
                        Text(stringResource(R.string.onboarding_daily_timeline_reminder), style = GeistType.copy14, color = colors.secondary)
                        Text(stringResource(R.string.onboarding_daily_timeline_billing, trialOffer.localizedPriceText), style = GeistType.copy14, color = colors.secondary)
                    }
                }
            }
        }
    }
}

// endregion

@Composable
internal fun formatDate(date: LocalDate, skeleton: String): String {
    val locale = LocalConfiguration.current.locales[0] ?: Locale.getDefault()
    return date.format(DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(locale, skeleton), locale))
}

@Composable
internal fun formatTime(hour: Int, minute: Int): String {
    val context = androidx.compose.ui.platform.LocalContext.current
    val locale = LocalConfiguration.current.locales[0] ?: Locale.getDefault()
    val skeleton = if (DateFormat.is24HourFormat(context)) "Hm" else "hm"
    return java.time.LocalTime.of(hour, minute)
        .format(DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(locale, skeleton), locale))
}
