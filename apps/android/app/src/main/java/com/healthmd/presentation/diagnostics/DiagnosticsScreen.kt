package com.healthmd.presentation.diagnostics

import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.AttachFile
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Save
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.healthmd.BuildConfig
import com.healthmd.R
import com.healthmd.diagnostics.*
import com.healthmd.presentation.common.AdaptiveActionPair
import com.healthmd.presentation.common.AppSwitch
import com.healthmd.presentation.common.PrimaryButton
import com.healthmd.presentation.common.SecondaryButton
import com.healthmd.presentation.common.SubScreen
import com.healthmd.presentation.settings.groupRowShape
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors
import java.time.Instant
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.int

@Composable
fun DiagnosticsScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    // Keep the reviewed file list in place when returning from a full-screen preview.
    val listState = rememberLazyListState()
    val store = remember { Diagnostics.initialize(context) }
    var settings by remember { mutableStateOf(store.settings) }
    var includePrivate by remember { mutableStateOf(false) }
    var hours by remember { mutableIntStateOf(24) }
    var subsystem by remember { mutableStateOf("all") }
    var operationId by remember { mutableStateOf("") }
    var search by remember { mutableStateOf("") }
    var snapshot by remember { mutableStateOf(DiagnosticSnapshot(emptyList(), 0, 0, false)) }
    var attachments by remember { mutableStateOf<List<Pair<Uri, String>>>(emptyList()) }
    var prepared by remember { mutableStateOf<PreparedDiagnosticBundle?>(null) }
    var reviewed by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var preview by remember { mutableStateOf<Pair<String, String>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var confirmShare by remember { mutableStateOf(false) }
    var confirmClear by remember { mutableStateOf(false) }
    var refreshTick by remember { mutableIntStateOf(0) }
    val failureText = stringResource(R.string.diagnostics_failure)
    val previewTruncatedText = stringResource(R.string.diagnostics_preview_truncated)

    fun invalidate() { prepared?.delete(); prepared = null; reviewed = false; error = null }
    fun changeSettings(value: DiagnosticSettings) {
        if (busy) return
        invalidate(); busy = true
        scope.launch {
            withContext(Dispatchers.IO) { store.configure(value.enabled, value.verbosity) }
            settings = store.settings; refreshTick++; busy = false
        }
    }
    fun showFile(bundle: PreparedDiagnosticBundle, path: String) {
        scope.launch {
            runCatching { withContext(Dispatchers.IO) { bundle.preview(path) } }
                .onSuccess { (text, truncated) -> preview = path to (text + if (truncated) previewTruncatedText else "") }
                .onFailure { error = failureText }
        }
    }
    val filesPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        scope.launch {
            val picked = withContext(Dispatchers.IO) { uris.map { uri ->
                val name = runCatching { context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null } }.getOrNull() ?: "attachment.bin"
                uri to name
            } }
            invalidate(); attachments = attachments + picked
        }
    }
    val savePicker = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/zip")) { uri ->
        val bundle = prepared
        if (uri != null && bundle != null && reviewed) scope.launch {
            busy = true
            runCatching { withContext(Dispatchers.IO) {
                bundle.verifiedFile().inputStream().use { input ->
                    val output = context.contentResolver.openOutputStream(uri, "wt") ?: throw DiagnosticBundleException("Destination unavailable")
                    output.use { input.copyTo(it, 64 * 1024) }
                }
            } }.onFailure { error = failureText }
            busy = false
        }
    }

    LaunchedEffect(hours, subsystem, operationId, includePrivate, refreshTick) {
        // Cancellation prevents an old private snapshot replacing a new public one.
        invalidate(); snapshot = DiagnosticSnapshot(emptyList(), 0, 0, false)
        snapshot = withContext(Dispatchers.IO) { store.snapshot(includePrivate, System.currentTimeMillis() - hours * 3_600_000L, subsystem.takeUnless { it == "all" }, operationId.lowercase(Locale.ROOT).takeUnless(String::isBlank)) }
    }

    fun prepare() {
        if (operationId.isNotBlank() && !DiagnosticBundleBuilder.isCanonicalOperationId(operationId.lowercase(Locale.ROOT))) { error = context.getString(R.string.diagnostics_invalid_operation); return }
        invalidate(); busy = true
        val selected = attachments.toList()
        scope.launch {
            runCatching { withContext(Dispatchers.IO) {
                DiagnosticBundleBuilder.prepare(
                    store, includePrivate, System.currentTimeMillis() - hours * 3_600_000L,
                    subsystem.takeUnless { it == "all" }, operationId.lowercase(Locale.ROOT).takeUnless(String::isBlank),
                    selected.map { (uri, name) -> DiagnosticAttachment(name) { context.contentResolver.openInputStream(uri) ?: throw DiagnosticBundleException("Attachment unavailable") } },
                    BuildConfig.VERSION_NAME, BuildConfig.VERSION_CODE.toString(), "Android ${Build.VERSION.RELEASE} / API ${Build.VERSION.SDK_INT}",
                )
            } }.onSuccess { prepared = it }.onFailure { error = (it as? DiagnosticBundleException)?.message ?: failureText }
            busy = false
        }
    }

    val colors = LocalGeistColors.current

    preview?.let { (path, text) ->
        androidx.activity.compose.BackHandler { preview = null }
        SubScreen(title = path.substringAfterLast('/'), onBack = { preview = null }) {
            DiagnosticFilePreview(path, text)
        }
        return
    }

    SubScreen(title = stringResource(R.string.diagnostics_title), onBack = { if (!busy) onBack() }) {
        LazyColumn(
            Modifier.fillMaxSize(),
            state = listState,
            contentPadding = PaddingValues(start = GeistSpacing.space4, end = GeistSpacing.space4, bottom = GeistSpacing.space8),
        ) {
            item(key = "recording") {
                val privateActive = settings.privateContextUntil > System.currentTimeMillis()
                ToolGroupHeading(stringResource(R.string.diagnostics_recording))
                Text(
                    stringResource(R.string.diagnostics_privacy),
                    style = GeistType.copy14,
                    color = colors.secondary,
                    modifier = Modifier.padding(start = GeistSpacing.space4, end = GeistSpacing.space4, bottom = GeistSpacing.space3),
                )
                ToolRows(
                    listOf(
                        { shape -> ToolSwitchRow(shape, stringResource(R.string.diagnostics_enabled), settings.enabled, !busy, tag = "diagnostics.enabled") { changeSettings(settings.copy(enabled = it)) } },
                        { shape ->
                            ToolMenuRow(
                                shape = shape,
                                title = stringResource(R.string.m3_tools_diagnostics_verbosity),
                                selected = settings.verbosity.name,
                                values = DiagnosticVerbosity.entries.map { it.name },
                                enabled = !busy,
                            ) { changeSettings(settings.copy(verbosity = DiagnosticVerbosity.valueOf(it))) }
                        },
                        { shape ->
                            if (privateActive) {
                                ToolRow(
                                    shape = shape,
                                    title = stringResource(R.string.diagnostics_stop_private),
                                    subtitle = stringResource(R.string.diagnostics_private_until, Instant.ofEpochMilli(settings.privateContextUntil).toString()),
                                    onClick = { scope.launch { withContext(Dispatchers.IO) { store.stopPrivateContextRecording() }; settings = store.settings } },
                                    enabled = !busy,
                                    titleColor = colors.brandPrimary,
                                )
                            } else {
                                ToolRow(
                                    shape = shape,
                                    title = stringResource(R.string.diagnostics_start_private),
                                    onClick = { scope.launch { withContext(Dispatchers.IO) { store.startPrivateContextRecording() }; settings = store.settings } },
                                    enabled = !busy && settings.enabled,
                                    titleColor = colors.brandPrimary,
                                )
                            }
                        },
                        { shape ->
                            ToolRow(
                                shape = shape,
                                title = stringResource(R.string.diagnostics_clear),
                                onClick = { confirmClear = true },
                                enabled = !busy,
                                titleColor = colors.error,
                                showChevron = false,
                                modifier = Modifier.testTag("diagnostics.clear"),
                            )
                        },
                    ),
                )
                ToolGroupFooter(stringResource(R.string.diagnostics_retention))
                ToolGroupFooter(stringResource(R.string.diagnostics_private_description))
            }
            item(key = "select") {
                val rangeHours = listOf(1, 24, 168)
                val rangeNames = listOf(stringResource(R.string.diagnostics_hour), stringResource(R.string.diagnostics_day), stringResource(R.string.diagnostics_week))
                ToolGroupHeading(stringResource(R.string.diagnostics_select))
                ToolRows(
                    listOf(
                        { shape ->
                            ToolMenuRow(shape, stringResource(R.string.m3_tools_diagnostics_time_range), rangeNames[rangeHours.indexOf(hours)], rangeNames, !busy) {
                                hours = rangeHours[rangeNames.indexOf(it)]
                            }
                        },
                        { shape ->
                            ToolMenuRow(shape, stringResource(R.string.m3_tools_diagnostics_subsystem), subsystem, DiagnosticSubsystems, !busy) { subsystem = it }
                        },
                        { shape -> ToolSwitchRow(shape, stringResource(R.string.diagnostics_include_private), includePrivate, !busy) { includePrivate = it } },
                        { shape ->
                            ToolFieldRow(shape) {
                                OutlinedTextField(operationId, { operationId = it }, label = { Text(stringResource(R.string.diagnostics_operation)) }, modifier = Modifier.fillMaxWidth(), enabled = !busy, singleLine = true, textStyle = GeistType.label14Mono, shape = RoundedCornerShape(GeistRadii.small))
                            }
                        },
                        { shape ->
                            ToolFieldRow(shape) {
                                OutlinedTextField(search, { search = it }, label = { Text(stringResource(R.string.diagnostics_search)) }, modifier = Modifier.fillMaxWidth(), enabled = !busy, shape = RoundedCornerShape(GeistRadii.small))
                            }
                        },
                        { shape ->
                            ToolRow(
                                shape = shape,
                                title = stringResource(R.string.diagnostics_refresh),
                                subtitle = stringResource(R.string.diagnostics_summary, snapshot.events.size, snapshot.droppedEventCount, snapshot.invalidEventCount, snapshot.truncated.toString()),
                                onClick = { refreshTick++ },
                                enabled = !busy,
                                titleColor = colors.brandPrimary,
                                showChevron = false,
                                trailing = { Icon(Icons.Outlined.Refresh, contentDescription = null, tint = colors.brandPrimary) },
                            )
                        },
                    ),
                )
            }
            val visibleEvents = snapshot.events.filter { search.isBlank() || it.document.toString().contains(search, ignoreCase = true) }.takeLast(100).reversed()
            item(key = "events-heading") { ToolGroupHeading(stringResource(R.string.m3_tools_diagnostics_events)) }
            itemsIndexed(visibleEvents, key = { _, event -> event.id }) { index, event ->
                ToolRow(
                    shape = groupRowShape(index, visibleEvents.size),
                    title = event.eventId,
                    titleMono = true,
                    subtitle = "${event.timestamp} · ${event.severity}",
                    onClick = { preview = event.eventId to event.document.toString() },
                    modifier = Modifier.padding(bottom = if (index < visibleEvents.size - 1) 2.dp else 0.dp),
                )
            }
            item(key = "events-footer") { ToolGroupFooter(stringResource(R.string.diagnostics_view_limit)) }
            item(key = "attachments") {
                ToolGroupHeading(stringResource(R.string.diagnostics_attachments))
                ToolRows(
                    buildList<@Composable (Shape) -> Unit> {
                        add { shape ->
                            ToolRow(
                                shape = shape,
                                title = stringResource(R.string.diagnostics_choose),
                                onClick = { filesPicker.launch(arrayOf("*/*")) },
                                enabled = !busy,
                                titleColor = colors.brandPrimary,
                                showChevron = false,
                                trailing = { Icon(Icons.Outlined.AttachFile, contentDescription = null, tint = colors.brandPrimary) },
                                modifier = Modifier.testTag("diagnostics.attach"),
                            )
                        }
                        attachments.forEachIndexed { index, (_, name) ->
                            add { shape ->
                                ToolRow(
                                    shape = shape,
                                    title = name,
                                    showChevron = false,
                                    trailing = {
                                        IconButton(
                                            onClick = { invalidate(); attachments = attachments.filterIndexed { i, _ -> i != index } },
                                            enabled = !busy,
                                            modifier = Modifier.size(GeistSizes.minimumTouchTarget),
                                        ) {
                                            Icon(Icons.Outlined.Close, contentDescription = stringResource(R.string.diagnostics_remove, name), tint = colors.secondary)
                                        }
                                    },
                                )
                            }
                        }
                    },
                )
                ToolGroupFooter(stringResource(R.string.diagnostics_attachment_description))
            }
            item(key = "review") {
                ToolGroupHeading(stringResource(R.string.diagnostics_review))
                Column(verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3)) {
                    PrimaryButton(stringResource(R.string.diagnostics_prepare), ::prepare, Modifier.testTag("diagnostics.prepare"), isLoading = busy)
                    error?.let { message -> ToolNote(message, error = true) }
                }
                prepared?.let { bundle ->
                    val paths = listOf("manifest.json") + bundle.files.map { it.path }
                    ToolGroupHeading(stringResource(R.string.m3_tools_diagnostics_files))
                    Text(
                        stringResource(R.string.diagnostics_frozen, bundle.manifest.getValue("event_count").jsonPrimitive.int, bundle.manifest.getValue("health_content").jsonPrimitive.content),
                        style = GeistType.copy14,
                        color = colors.secondary,
                        modifier = Modifier.padding(start = GeistSpacing.space4, end = GeistSpacing.space4, bottom = GeistSpacing.space3),
                    )
                    ToolRows(
                        paths.map<String, @Composable (Shape) -> Unit> { path ->
                            { shape ->
                                ToolRow(
                                    shape = shape,
                                    title = path.substringAfterLast('/'),
                                    subtitle = path,
                                    subtitleMono = true,
                                    onClick = { showFile(bundle, path) },
                                    enabled = !busy,
                                )
                            }
                        } + listOf<@Composable (Shape) -> Unit>(
                            { shape -> ToolSwitchRow(shape, stringResource(R.string.diagnostics_reviewed), reviewed, !busy, tag = "diagnostics.reviewed") { reviewed = it } },
                        ),
                    )
                    AdaptiveActionPair(
                        primaryAction = { modifier ->
                            SecondaryButton(stringResource(R.string.diagnostics_share), { confirmShare = true }, modifier.testTag("diagnostics.share"), icon = Icons.Outlined.Share, enabled = reviewed && !busy)
                        },
                        secondaryAction = { modifier ->
                            SecondaryButton(stringResource(R.string.diagnostics_save), { savePicker.launch("healthmd-diagnostics.zip") }, modifier, icon = Icons.Outlined.Save, enabled = reviewed && !busy)
                        },
                        modifier = Modifier.padding(top = GeistSpacing.space4),
                    )
                    ToolGroupFooter(stringResource(R.string.diagnostics_bundle_retention))
                }
            }
        }
    }
    if (confirmShare) ToolConfirmDialog(
        icon = Icons.Outlined.Share,
        title = stringResource(R.string.diagnostics_share_question),
        message = stringResource(R.string.diagnostics_share_warning),
        confirm = stringResource(R.string.diagnostics_share_confirm),
        onDismiss = { confirmShare = false },
        onConfirm = {
            confirmShare = false
            prepared?.let { bundle -> scope.launch { busy = true; runCatching { withContext(Dispatchers.IO) { DiagnosticSharing.share(context, bundle) } }.onFailure { error = failureText }; busy = false } }
        },
    )
    if (confirmClear) ToolConfirmDialog(
        icon = Icons.Outlined.DeleteOutline,
        title = stringResource(R.string.diagnostics_clear),
        message = stringResource(R.string.diagnostics_clear_question),
        confirm = stringResource(R.string.diagnostics_clear),
        onDismiss = { confirmClear = false },
        onConfirm = { confirmClear = false; scope.launch { busy = true; invalidate(); val cleared = withContext(Dispatchers.IO) { val local = store.clear(); DiagnosticSharing.clearCopies(context) && local }; if (!cleared) error = failureText; settings = store.settings; attachments = emptyList(); snapshot = DiagnosticSnapshot(emptyList(), 0, 0, false); busy = false } },
    )
}

private val DiagnosticSubsystems = listOf("all", "connection", "schedule", "notification", "export", "lifecycle", "diagnostics")

/** A bundle file or event document, styled like the export file reader: a path card above a mono surface. */
@Composable
private fun DiagnosticFilePreview(path: String, text: String) {
    val colors = LocalGeistColors.current
    Column(
        Modifier
            .fillMaxSize()
            .padding(start = GeistSpacing.space4, end = GeistSpacing.space4, bottom = GeistSpacing.space3),
        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(GeistRadii.listGroup))
                .background(colors.background200)
                .padding(GeistSpacing.space4),
        ) {
            SelectionContainer { Text(path, style = GeistType.label12Mono, color = colors.primary) }
        }
        Box(
            Modifier
                .weight(1f)
                .fillMaxWidth()
                .clip(RoundedCornerShape(GeistRadii.medium))
                .background(colors.gray.c100),
        ) {
            SelectionContainer {
                LazyColumn(contentPadding = PaddingValues(GeistSpacing.space4)) {
                    item { Text(text, style = GeistType.label12Mono, color = colors.primary) }
                }
            }
        }
    }
}

// Tools list-group building blocks, shared by Diagnostics, Direct CLI, and Clinic access. They
// draw the DESIGN.md `list-group` exactly as SettingsGroup does (background-200 rows, 20dp outer
// and 4dp inner corners, 2dp gaps) but without the Settings icon circle.

/** A list-group heading: `heading-14` in the brand color. */
@Composable
internal fun ToolGroupHeading(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text,
        style = GeistType.heading14,
        color = LocalGeistColors.current.brandPrimary,
        modifier = Modifier
            .padding(start = GeistSpacing.space4, top = GeistSpacing.space6, bottom = GeistSpacing.space2)
            .then(modifier)
            .semantics { heading() },
    )
}

/** Supporting text under a list group. */
@Composable
internal fun ToolGroupFooter(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        style = GeistType.copy13,
        color = LocalGeistColors.current.secondary,
        modifier = modifier.padding(start = GeistSpacing.space4, end = GeistSpacing.space4, top = GeistSpacing.space2),
    )
}

/** The rows of one list group, 2dp apart, each given its position's corner shape. */
@Composable
internal fun ToolRows(rows: List<@Composable (Shape) -> Unit>, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        rows.forEachIndexed { index, row -> row(groupRowShape(index, rows.size)) }
    }
}

/** One list-group row: a title, optional subtitle (mono for paths), and trailing content or a chevron. */
@Composable
internal fun ToolRow(
    shape: Shape,
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    subtitleMono: Boolean = false,
    titleMono: Boolean = false,
    titleColor: Color? = null,
    onClick: (() -> Unit)? = null,
    enabled: Boolean = true,
    showChevron: Boolean = onClick != null,
    trailing: (@Composable () -> Unit)? = null,
) {
    val colors = LocalGeistColors.current
    Row(
        modifier
            .fillMaxWidth()
            .clip(shape)
            .background(colors.background200)
            .then(if (onClick != null) Modifier.clickable(enabled = enabled, role = Role.Button, onClick = onClick) else Modifier)
            .heightIn(min = if (subtitle != null) 72.dp else 56.dp)
            .padding(start = GeistSpacing.space4, end = GeistSpacing.space4, top = GeistSpacing.space2, bottom = GeistSpacing.space2),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
    ) {
        Column(Modifier.weight(1f)) {
            Text(
                title,
                style = if (titleMono) GeistType.label14Mono else GeistType.label16,
                color = if (!enabled) colors.disabled else titleColor ?: colors.primary,
            )
            subtitle?.let {
                Text(it, style = if (subtitleMono) GeistType.copy13Mono else GeistType.copy14, color = colors.secondary)
            }
        }
        trailing?.invoke()
        if (showChevron) {
            Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = null, tint = colors.secondary)
        }
    }
}

/** A row that holds a form field on the group surface. */
@Composable
internal fun ToolFieldRow(shape: Shape, modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier
            .fillMaxWidth()
            .clip(shape)
            .background(LocalGeistColors.current.background200)
            .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space3),
        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
        content = content,
    )
}

/** A whole-row toggle: the row owns the action and the [AppSwitch] only shows state. */
@Composable
internal fun ToolSwitchRow(
    shape: Shape,
    title: String,
    checked: Boolean,
    enabled: Boolean,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    tag: String = title,
    onCheckedChange: (Boolean) -> Unit,
) {
    val colors = LocalGeistColors.current
    Row(
        modifier
            .fillMaxWidth()
            .clip(shape)
            .background(colors.background200)
            .toggleable(value = checked, enabled = enabled, role = Role.Switch, onValueChange = onCheckedChange)
            .testTag(tag)
            .heightIn(min = if (subtitle != null) 72.dp else 56.dp)
            .padding(start = GeistSpacing.space4, end = GeistSpacing.space4, top = GeistSpacing.space2, bottom = GeistSpacing.space2),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = GeistType.label16, color = if (enabled) colors.primary else colors.disabled)
            subtitle?.let { Text(it, style = GeistType.copy14, color = colors.secondary) }
        }
        AppSwitch(checked = checked, onCheckedChange = null, enabled = enabled, modifier = Modifier.testTag("$tag.switch"))
    }
}

/** A row showing its current value; tapping it opens the choices in a dropdown menu. */
@Composable
private fun ToolMenuRow(
    shape: Shape,
    title: String,
    selected: String,
    values: List<String>,
    enabled: Boolean,
    onChange: (String) -> Unit,
) {
    val colors = LocalGeistColors.current
    var expanded by remember { mutableStateOf(false) }
    Box {
        ToolRow(
            shape = shape,
            title = title,
            onClick = { expanded = true },
            enabled = enabled,
            showChevron = false,
            trailing = {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(selected, style = GeistType.label14, color = colors.secondary)
                    Icon(Icons.Outlined.ExpandMore, contentDescription = null, tint = colors.secondary)
                }
            },
        )
        DropdownMenu(expanded, { expanded = false }, containerColor = colors.gray.c200) {
            values.forEach { value ->
                DropdownMenuItem(
                    text = { Text(value, style = GeistType.label14, color = colors.primary) },
                    trailingIcon = if (value == selected) {
                        { Icon(Icons.Outlined.Check, contentDescription = null, tint = colors.brandPrimary) }
                    } else null,
                    onClick = { expanded = false; onChange(value) },
                )
            }
        }
    }
}

/** A tonal note; errors read in the error tone and stay selectable for support reports. */
@Composable
internal fun ToolNote(message: String, modifier: Modifier = Modifier, error: Boolean = false) {
    val colors = LocalGeistColors.current
    Row(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(GeistRadii.medium))
            .background(if (error) colors.red.c100 else colors.gray.c200)
            .padding(GeistSpacing.space4),
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
    ) {
        Icon(
            if (error) Icons.Outlined.ErrorOutline else Icons.Outlined.Info,
            contentDescription = null,
            tint = if (error) colors.error else colors.secondary,
            modifier = Modifier.size(20.dp),
        )
        SelectionContainer { Text(message, style = GeistType.copy14, color = colors.primary) }
    }
}

/** The M3 confirmation dialog: 28dp `gray-200` container, icon, filled-pill confirm, text dismiss. */
@Composable
internal fun ToolConfirmDialog(
    icon: ImageVector,
    title: String,
    message: String,
    confirm: String,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit,
    dismiss: String = stringResource(R.string.cancel),
) {
    val colors = LocalGeistColors.current
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = colors.gray.c200,
        shape = RoundedCornerShape(GeistRadii.large),
        icon = { Icon(icon, contentDescription = null, tint = colors.brandPrimary) },
        title = { Text(title, style = GeistType.heading24, color = colors.primary) },
        text = { Text(message, style = GeistType.copy14, color = colors.secondary) },
        confirmButton = {
            Button(
                onClick = onConfirm,
                shape = RoundedCornerShape(GeistRadii.full),
                colors = ButtonDefaults.buttonColors(containerColor = colors.brandPrimary, contentColor = colors.brandOnPrimary),
            ) { Text(confirm, style = GeistType.button14) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(dismiss, style = GeistType.button14, color = colors.brandPrimary) }
        },
    )
}
