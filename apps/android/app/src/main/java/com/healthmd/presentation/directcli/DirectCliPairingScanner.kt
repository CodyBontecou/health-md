package com.healthmd.presentation.directcli

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.healthmd.R
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.Spacing
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.MultiFormatReader
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.ReaderException
import com.google.zxing.common.HybridBinarizer
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicReference

@Composable
fun DirectCliPairingScanner(
    onPairingLink: (DirectCliPairingLink) -> Unit,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val latestOnPairingLink by rememberUpdatedState(onPairingLink)
    var cameraPermissionGranted by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
                PackageManager.PERMISSION_GRANTED,
        )
    }
    var permissionRequested by rememberSaveable { mutableStateOf(false) }
    var permissionPermanentlyDenied by rememberSaveable { mutableStateOf(false) }
    var cameraError by remember { mutableStateOf<String?>(null) }
    var scanMessage by remember { mutableStateOf<String?>(null) }
    var accepted by remember { mutableStateOf(false) }
    val hasCamera = remember {
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)
    }
    val cameraUnavailableMessage = stringResource(R.string.direct_cli_camera_unavailable)
    val invalidQrMessage = stringResource(R.string.direct_cli_invalid_qr)
    val scanHint = stringResource(R.string.direct_cli_scan_qr_hint)
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        cameraPermissionGranted = granted
        permissionPermanentlyDenied = !granted && permissionRequested &&
            context.findActivity()?.let { activity ->
                !ActivityCompat.shouldShowRequestPermissionRationale(
                    activity,
                    Manifest.permission.CAMERA,
                )
            } == true
    }
    LaunchedEffect(hasCamera) {
        if (hasCamera && !cameraPermissionGranted && !permissionRequested) {
            permissionRequested = true
            permissionLauncher.launch(Manifest.permission.CAMERA)
        }
    }
    DisposableEffect(lifecycleOwner, hasCamera, permissionRequested) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME && hasCamera) {
                val granted = ContextCompat.checkSelfPermission(
                    context,
                    Manifest.permission.CAMERA,
                ) == PackageManager.PERMISSION_GRANTED
                cameraPermissionGranted = granted
                if (granted) {
                    permissionPermanentlyDenied = false
                } else if (permissionRequested) {
                    permissionPermanentlyDenied = context.findActivity()?.let { activity ->
                        !ActivityCompat.shouldShowRequestPermissionRationale(
                            activity,
                            Manifest.permission.CAMERA,
                        )
                    } == true
                }
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(
            dismissOnBackPress = true,
            dismissOnClickOutside = false,
            usePlatformDefaultWidth = false,
        ),
    ) {
        Surface(modifier = Modifier.fillMaxSize(), color = AppColors.bgPrimary) {
            when {
                !hasCamera -> ScannerUnavailable(
                    message = cameraUnavailableMessage,
                    onDismiss = onDismiss,
                )
                !cameraPermissionGranted -> ScannerUnavailable(
                    message = cameraUnavailableMessage,
                    primaryActionLabel = stringResource(
                        if (permissionPermanentlyDenied) {
                            R.string.notifications_open_settings_button
                        } else {
                            R.string.direct_cli_scan_qr
                        },
                    ),
                    onPrimaryAction = {
                        if (permissionPermanentlyDenied) {
                            context.startActivity(Intent(
                                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.parse("package:${context.packageName}"),
                            ))
                        } else {
                            permissionRequested = true
                            permissionLauncher.launch(Manifest.permission.CAMERA)
                        }
                    },
                    onDismiss = onDismiss,
                )
                else -> {
                    Box(modifier = Modifier.fillMaxSize()) {
                        CameraPreview(
                            modifier = Modifier.fillMaxSize(),
                            onPayload = { payload ->
                                if (!accepted) {
                                    val link = DirectCliPairingLink.parse(payload)
                                    if (link == null) {
                                        scanMessage = invalidQrMessage
                                    } else {
                                        accepted = true
                                        latestOnPairingLink(link)
                                    }
                                }
                            },
                            onError = {
                                cameraError = cameraUnavailableMessage
                            },
                        )

                        Box(
                            modifier = Modifier
                                .align(Alignment.Center)
                                .size(GeistSizes.scannerFrame)
                                .border(
                                    BorderStroke(Spacing.xxs, AppColors.scannerContent),
                                    MaterialTheme.shapes.large,
                                ),
                        )
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .background(AppColors.scannerScrim)
                                .padding(horizontal = Spacing.sm, vertical = Spacing.xs)
                                .align(Alignment.TopCenter),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                text = stringResource(R.string.direct_cli_scan_qr),
                                color = AppColors.scannerContent,
                                style = MaterialTheme.typography.titleLarge,
                            )
                            IconButton(onClick = onDismiss) {
                                Icon(
                                    imageVector = Icons.Default.Close,
                                    contentDescription = stringResource(R.string.close),
                                    tint = AppColors.scannerContent,
                                )
                            }
                        }
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .background(AppColors.scannerScrim)
                                .padding(Spacing.lg)
                                .align(Alignment.BottomCenter),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            Text(
                                text = cameraError ?: scanMessage ?: scanHint,
                                color = AppColors.scannerContent,
                                style = MaterialTheme.typography.bodyLarge,
                            )
                            if (cameraError != null) {
                                Spacer(Modifier.height(Spacing.sm))
                                OutlinedButton(onClick = onDismiss) {
                                    Text(
                                        stringResource(R.string.back),
                                        color = AppColors.scannerContent,
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun CameraPreview(
    modifier: Modifier,
    onPayload: (String) -> Unit,
    onError: () -> Unit,
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val currentOnPayload by rememberUpdatedState(onPayload)
    val currentOnError by rememberUpdatedState(onError)
    val previewView = remember {
        PreviewView(context).apply {
            implementationMode = PreviewView.ImplementationMode.COMPATIBLE
            scaleType = PreviewView.ScaleType.FILL_CENTER
        }
    }
    val analysisExecutor = remember { Executors.newSingleThreadExecutor() }

    DisposableEffect(lifecycleOwner, previewView) {
        val preview = Preview.Builder().build().also {
            it.surfaceProvider = previewView.surfaceProvider
        }
        val analysis = ImageAnalysis.Builder()
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .build()
            .also { useCase ->
                useCase.setAnalyzer(analysisExecutor, QrCodeAnalyzer { payload ->
                    ContextCompat.getMainExecutor(context).execute {
                        currentOnPayload(payload)
                    }
                })
            }
        var active = true
        var provider: ProcessCameraProvider? = null
        val providerFuture = ProcessCameraProvider.getInstance(context)
        providerFuture.addListener({
            if (active) {
                runCatching {
                    providerFuture.get().also { resolved ->
                        provider = resolved
                        resolved.bindToLifecycle(
                            lifecycleOwner,
                            CameraSelector.DEFAULT_BACK_CAMERA,
                            preview,
                            analysis,
                        )
                    }
                }.onFailure { currentOnError() }
            }
        }, ContextCompat.getMainExecutor(context))

        onDispose {
            active = false
            analysis.clearAnalyzer()
            provider?.unbind(preview, analysis)
            analysisExecutor.shutdownNow()
        }
    }

    AndroidView(modifier = modifier, factory = { previewView })
}

@Composable
private fun ScannerUnavailable(
    message: String,
    onDismiss: () -> Unit,
    primaryActionLabel: String? = null,
    onPrimaryAction: (() -> Unit)? = null,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(Spacing.xl),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(message, color = AppColors.textPrimary, style = MaterialTheme.typography.bodyLarge)
        Spacer(Modifier.height(Spacing.lg))
        if (primaryActionLabel != null && onPrimaryAction != null) {
            Button(onClick = onPrimaryAction) { Text(primaryActionLabel) }
            Spacer(Modifier.height(Spacing.sm))
        }
        OutlinedButton(onClick = onDismiss) {
            Text(stringResource(R.string.back))
        }
    }
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}

private class QrCodeAnalyzer(
    private val onPayload: (String) -> Unit,
) : ImageAnalysis.Analyzer {
    private val reader = MultiFormatReader().apply {
        setHints(mapOf(
            DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE),
            DecodeHintType.TRY_HARDER to true,
        ))
    }
    private val lastPayload = AtomicReference<String?>(null)

    override fun analyze(image: ImageProxy) {
        try {
            val luminance = rotatedLuminance(image)
            val source = PlanarYUVLuminanceSource(
                luminance.bytes,
                luminance.width,
                luminance.height,
                0,
                0,
                luminance.width,
                luminance.height,
                false,
            )
            val payload = reader.decodeWithState(BinaryBitmap(HybridBinarizer(source))).text
            if (lastPayload.getAndSet(payload) != payload) onPayload(payload)
        } catch (_: ReaderException) {
            // No complete QR in this frame.
        } finally {
            reader.reset()
            image.close()
        }
    }

    private data class Luminance(val bytes: ByteArray, val width: Int, val height: Int)

    private fun rotatedLuminance(image: ImageProxy): Luminance {
        val width = image.width
        val height = image.height
        val plane = image.planes.first()
        val buffer = plane.buffer
        val source = ByteArray(width * height)
        for (y in 0 until height) {
            for (x in 0 until width) {
                source[y * width + x] = buffer.get(y * plane.rowStride + x * plane.pixelStride)
            }
        }
        return when ((image.imageInfo.rotationDegrees % 360 + 360) % 360) {
            90 -> {
                val output = ByteArray(source.size)
                for (y in 0 until height) for (x in 0 until width) {
                    output[x * height + (height - 1 - y)] = source[y * width + x]
                }
                Luminance(output, height, width)
            }
            180 -> {
                val output = ByteArray(source.size)
                for (y in 0 until height) for (x in 0 until width) {
                    output[(height - 1 - y) * width + (width - 1 - x)] =
                        source[y * width + x]
                }
                Luminance(output, width, height)
            }
            270 -> {
                val output = ByteArray(source.size)
                for (y in 0 until height) for (x in 0 until width) {
                    output[(width - 1 - x) * height + y] = source[y * width + x]
                }
                Luminance(output, height, width)
            }
            else -> Luminance(source, width, height)
        }
    }
}
