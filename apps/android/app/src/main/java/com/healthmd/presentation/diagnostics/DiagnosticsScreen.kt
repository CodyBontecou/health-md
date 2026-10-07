package com.healthmd.presentation.diagnostics

import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import com.healthmd.BuildConfig
import com.healthmd.R
import com.healthmd.diagnostics.*
import com.healthmd.presentation.common.*
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.Spacing
import java.time.Instant
import java.util.UUID
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
        snapshot = withContext(Dispatchers.IO) { store.snapshot(includePrivate, System.currentTimeMillis() - hours * 3_600_000L, subsystem.takeUnless { it == "all" }, operationId.lowercase().takeUnless(String::isBlank)) }
    }

    fun prepare() {
        if (operationId.isNotBlank() && runCatching { UUID.fromString(operationId) }.isFailure) { error = context.getString(R.string.diagnostics_invalid_operation); return }
        invalidate(); busy = true
        val selected = attachments.toList()
        scope.launch {
            runCatching { withContext(Dispatchers.IO) {
                DiagnosticBundleBuilder.prepare(
                    store, includePrivate, System.currentTimeMillis() - hours * 3_600_000L,
                    subsystem.takeUnless { it == "all" }, operationId.lowercase().takeUnless(String::isBlank),
                    selected.map { (uri, name) -> DiagnosticAttachment(name) { context.contentResolver.openInputStream(uri) ?: throw DiagnosticBundleException("Attachment unavailable") } },
                    BuildConfig.VERSION_NAME, BuildConfig.VERSION_CODE.toString(), "Android ${Build.VERSION.RELEASE} / API ${Build.VERSION.SDK_INT}",
                )
            } }.onSuccess { prepared = it }.onFailure { error = (it as? DiagnosticBundleException)?.message ?: failureText }
            busy = false
        }
    }

    if (preview != null) {
        Column(Modifier.fillMaxSize().padding(Spacing.md)) {
            SecondaryButton(stringResource(R.string.diagnostics_back), onClick = { preview = null }, icon = Icons.AutoMirrored.Outlined.ArrowBack)
            SelectionContainer {
                LazyColumn(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    item { Text(preview!!.first, style = GeistType.heading20, color = AppColors.textPrimary) }
                    item { Text(preview!!.second, style = GeistType.copy13Mono, color = AppColors.textPrimary) }
                }
            }
        }
        androidx.activity.compose.BackHandler { preview = null }
        return
    }

    LazyColumn(Modifier.fillMaxSize().padding(horizontal = Spacing.md), state = listState, verticalArrangement = Arrangement.spacedBy(Spacing.md), contentPadding = PaddingValues(vertical = Spacing.md)) {
        item {
            SecondaryButton(stringResource(R.string.diagnostics_back), onBack, icon = Icons.AutoMirrored.Outlined.ArrowBack, enabled = !busy)
            Text(stringResource(R.string.diagnostics_title), style = GeistType.heading24, color = AppColors.textPrimary)
        }
        item {
            GeistCard(padding = Spacing.md) {
                SectionLabel(stringResource(R.string.diagnostics_recording))
                Text(stringResource(R.string.diagnostics_privacy), style = GeistType.copy14, color = AppColors.textSecondary)
                DiagnosticToggle(stringResource(R.string.diagnostics_enabled), settings.enabled, !busy, "diagnostics.enabled") { changeSettings(settings.copy(enabled = it)) }
                DiagnosticMenu("Verbosity: ${settings.verbosity.name}", DiagnosticVerbosity.entries.map { it.name }, !busy) { changeSettings(settings.copy(verbosity = DiagnosticVerbosity.valueOf(it))) }
                Text(stringResource(R.string.diagnostics_retention), style = GeistType.copy13, color = AppColors.textSecondary)
                if (settings.privateContextUntil > System.currentTimeMillis()) {
                    Text(stringResource(R.string.diagnostics_private_until, Instant.ofEpochMilli(settings.privateContextUntil).toString()), style = GeistType.copy13, color = AppColors.textSecondary)
                    SecondaryButton(stringResource(R.string.diagnostics_stop_private), onClick = { scope.launch { withContext(Dispatchers.IO) { store.stopPrivateContextRecording() }; settings = store.settings } }, enabled = !busy)
                } else {
                    SecondaryButton(stringResource(R.string.diagnostics_start_private), onClick = { scope.launch { withContext(Dispatchers.IO) { store.startPrivateContextRecording() }; settings = store.settings } }, enabled = !busy && settings.enabled)
                }
                Text(stringResource(R.string.diagnostics_private_description), style = GeistType.copy13, color = AppColors.textSecondary)
                SecondaryButton(stringResource(R.string.diagnostics_clear), { confirmClear = true }, Modifier.testTag("diagnostics.clear"), enabled = !busy)
            }
        }
        item {
            GeistCard(padding = Spacing.md) {
                SectionLabel(stringResource(R.string.diagnostics_select))
                val rangeNames = listOf(stringResource(R.string.diagnostics_hour), stringResource(R.string.diagnostics_day), stringResource(R.string.diagnostics_week))
                DiagnosticMenu(rangeNames[listOf(1, 24, 168).indexOf(hours)], rangeNames, !busy) { hours = listOf(1, 24, 168)[rangeNames.indexOf(it)] }
                DiagnosticMenu("Subsystem: $subsystem", listOf("all", "connection", "schedule", "notification", "export", "lifecycle", "diagnostics"), !busy) { subsystem = it }
                OutlinedTextField(operationId, { operationId = it }, label = { Text(stringResource(R.string.diagnostics_operation)) }, modifier = Modifier.fillMaxWidth(), enabled = !busy, singleLine = true, textStyle = GeistType.label14Mono)
                DiagnosticToggle(stringResource(R.string.diagnostics_include_private), includePrivate, !busy) { includePrivate = it }
                OutlinedTextField(search, { search = it }, label = { Text(stringResource(R.string.diagnostics_search)) }, modifier = Modifier.fillMaxWidth(), enabled = !busy)
                SecondaryButton(stringResource(R.string.diagnostics_refresh), { refreshTick++ }, enabled = !busy)
                Text(stringResource(R.string.diagnostics_summary, snapshot.events.size, snapshot.droppedEventCount, snapshot.invalidEventCount, snapshot.truncated.toString()), style = GeistType.copy13, color = AppColors.textSecondary)
            }
        }
        items(snapshot.events.filter { search.isBlank() || it.document.toString().contains(search, ignoreCase = true) }.takeLast(100).reversed(), key = { it.id }) { event ->
            GeistCardClickable(onClick = { preview = event.eventId to event.document.toString() }) {
                Column {
                    Text(event.eventId, style = GeistType.label14Mono, color = AppColors.textPrimary)
                    Text("${event.timestamp} · ${event.severity}", style = GeistType.copy13, color = AppColors.textSecondary)
                }
            }
        }
        item { Text(stringResource(R.string.diagnostics_view_limit), style = GeistType.copy13, color = AppColors.textSecondary) }
        item {
            GeistCard(padding = Spacing.md) {
                SectionLabel(stringResource(R.string.diagnostics_attachments))
                Text(stringResource(R.string.diagnostics_attachment_description), style = GeistType.copy13, color = AppColors.textSecondary)
                SecondaryButton(stringResource(R.string.diagnostics_choose), { filesPicker.launch(arrayOf("*/*")) }, Modifier.testTag("diagnostics.attach"), enabled = !busy)
                attachments.forEachIndexed { index, (_, name) -> SecondaryButton(stringResource(R.string.diagnostics_remove, name), { invalidate(); attachments = attachments.filterIndexed { i, _ -> i != index } }, enabled = !busy) }
            }
        }
        item {
            GeistCard(padding = Spacing.md) {
                SectionLabel(stringResource(R.string.diagnostics_review))
                PrimaryButton(stringResource(R.string.diagnostics_prepare), ::prepare, Modifier.testTag("diagnostics.prepare"), isLoading = busy)
                prepared?.let { bundle ->
                    Text(stringResource(R.string.diagnostics_frozen, bundle.manifest.getValue("event_count").jsonPrimitive.int, bundle.manifest.getValue("health_content").jsonPrimitive.content), style = GeistType.copy13, color = AppColors.textSecondary)
                    (listOf("manifest.json") + bundle.files.map { it.path }).forEach { path -> SecondaryButton(path, { showFile(bundle, path) }, enabled = !busy) }
                    DiagnosticToggle(stringResource(R.string.diagnostics_reviewed), reviewed, !busy, "diagnostics.reviewed") { reviewed = it }
                    SecondaryButton(stringResource(R.string.diagnostics_share), { confirmShare = true }, Modifier.testTag("diagnostics.share"), enabled = reviewed && !busy)
                    SecondaryButton(stringResource(R.string.diagnostics_save), { savePicker.launch("healthmd-diagnostics.zip") }, enabled = reviewed && !busy)
                    Text(stringResource(R.string.diagnostics_bundle_retention), style = GeistType.copy13, color = AppColors.textSecondary)
                }
                error?.let { SelectionContainer { Text(it, style = GeistType.copy13, color = AppColors.error) } }
            }
        }
    }
    if (confirmShare) AlertDialog(
        onDismissRequest = { confirmShare = false }, title = { Text(stringResource(R.string.diagnostics_share_question)) }, text = { Text(stringResource(R.string.diagnostics_share_warning)) },
        confirmButton = { TextButton(onClick = {
            confirmShare = false
            prepared?.let { bundle -> scope.launch { busy = true; runCatching { withContext(Dispatchers.IO) { DiagnosticSharing.share(context, bundle) } }.onFailure { error = failureText }; busy = false } }
        }) { Text(stringResource(R.string.diagnostics_share_confirm)) } },
        dismissButton = { TextButton(onClick = { confirmShare = false }) { Text(stringResource(R.string.diagnostics_cancel)) } },
    )
    if (confirmClear) AlertDialog(
        onDismissRequest = { confirmClear = false }, title = { Text(stringResource(R.string.diagnostics_clear)) }, text = { Text(stringResource(R.string.diagnostics_clear_question)) },
        confirmButton = { TextButton(onClick = { confirmClear = false; scope.launch { busy = true; invalidate(); val cleared = withContext(Dispatchers.IO) { val local = store.clear(); DiagnosticSharing.clearCopies(context) && local }; if (!cleared) error = failureText; settings = store.settings; attachments = emptyList(); snapshot = DiagnosticSnapshot(emptyList(), 0, 0, false); busy = false } }) { Text(stringResource(R.string.diagnostics_clear)) } },
        dismissButton = { TextButton(onClick = { confirmClear = false }) { Text(stringResource(R.string.diagnostics_cancel)) } },
    )
}

@Composable
private fun DiagnosticToggle(label: String, value: Boolean, enabled: Boolean, tag: String = label, onChange: (Boolean) -> Unit) {
    Column(Modifier.fillMaxWidth().padding(vertical = Spacing.sm).testTag(tag)) {
        Text(label, style = GeistType.label14, color = AppColors.textPrimary)
        Switch(checked = value, onCheckedChange = onChange, enabled = enabled, modifier = Modifier.testTag("$tag.switch"))
    }
}

@Composable
private fun DiagnosticMenu(label: String, values: List<String>, enabled: Boolean, onChange: (String) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        SecondaryButton(label, { expanded = true }, enabled = enabled)
        DropdownMenu(expanded, { expanded = false }) { values.forEach { value -> DropdownMenuItem(text = { Text(value) }, onClick = { expanded = false; onChange(value) }) } }
    }
}
