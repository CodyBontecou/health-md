package com.healthmd.presentation.common

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.data.storage.FileExportManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.withContext

/**
 * Display name of the app's export folder ("Documents"). A device-folder automation without
 * its own folder writes there, so sentences name it instead of "the selected folder".
 */
val LocalAppFolderName = compositionLocalOf<String?> { null }

@Composable
fun ProvideAppFolderName(folderUri: Flow<String?>, content: @Composable () -> Unit) {
    val context = LocalContext.current.applicationContext
    val uri by folderUri.collectAsStateWithLifecycle(initialValue = null)
    val name by produceState<String?>(initialValue = null, uri) {
        value = uri?.let { withContext(Dispatchers.IO) { FileExportManager(context).getFolderDisplayName(it) } }
    }
    CompositionLocalProvider(LocalAppFolderName provides name, content = content)
}
