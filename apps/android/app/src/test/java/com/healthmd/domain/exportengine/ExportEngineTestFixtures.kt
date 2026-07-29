package com.healthmd.domain.exportengine

import com.healthmd.core.CoreBuildInfo
import com.healthmd.core.CoreMetricRegistrySnapshot
import com.healthmd.core.CoreSelfTestReport
import com.healthmd.core.FixtureValidation
import com.healthmd.core.HealthMdCoreReadiness
import com.healthmd.core.HealthMdCoreService

internal const val TEST_REQUEST_ID = "m6-request"
internal const val TEST_SESSION_ID = "m6-session"

internal fun testReadiness(
    registrySha256: String = "a".repeat(64),
    isReady: Boolean = true,
): HealthMdCoreReadiness {
    val info = CoreBuildInfo(
        crateVersion = "0.1.0-test",
        coreSourceRevision = "core-source-test",
        registrySha256 = registrySha256,
        coreApiVersion = HealthMdCoreService.EXPECTED_CORE_API_VERSION,
        semanticInputVersion = HealthMdCoreService.EXPECTED_SEMANTIC_INPUT_VERSION,
        canonicalModelVersion = HealthMdCoreService.EXPECTED_CANONICAL_MODEL_VERSION,
        registryVersion = HealthMdCoreService.EXPECTED_REGISTRY_VERSION,
        renderInputVersion = HealthMdCoreService.EXPECTED_RENDER_INPUT_VERSION,
        artifactPlanVersion = HealthMdCoreService.EXPECTED_ARTIFACT_PLAN_VERSION,
        renderProfileRevision = HealthMdCoreService.EXPECTED_RENDER_PROFILE_REVISION,
        persistedStateVersion = HealthMdCoreService.EXPECTED_PERSISTED_STATE_VERSION,
    )
    return HealthMdCoreReadiness(
        isReady = isReady,
        buildInfo = info,
        selfTest = CoreSelfTestReport(
            passed = isReady,
            buildInfo = info,
            fixture = FixtureValidation(1u, 0u, "b".repeat(64)),
        ),
    )
}

internal fun testRegistry(
    profile: AndroidExportProfile = AndroidExportProfile.android_frozen_v4,
    registrySha256: String = "a".repeat(64),
): CoreMetricRegistrySnapshot = CoreMetricRegistrySnapshot(
    registryVersion = HealthMdCoreService.EXPECTED_REGISTRY_VERSION,
    registrySha256 = registrySha256,
    profileId = profile.name,
    publicProfileId = when (profile) {
        AndroidExportProfile.android_frozen_v4 -> "android-frozen-v4"
        AndroidExportProfile.android_analytical_v5 -> "android-analytical-v5"
    },
    publicSchema = ExportEnginePin.PUBLIC_SCHEMA,
    publicSchemaVersion = when (profile) {
        AndroidExportProfile.android_frozen_v4 -> 4u
        AndroidExportProfile.android_analytical_v5 -> 5u
    },
    profileRevision = 1u,
    categories = emptyList(),
    metrics = emptyList(),
    unavailableMetrics = emptyList(),
    outputs = emptyList(),
)

internal fun testPin(
    mode: ExportEngineMode = ExportEngineMode.shadow,
    profile: AndroidExportProfile = AndroidExportProfile.android_frozen_v4,
): ExportEnginePin = ExportEnginePin.create(
    engine = mode,
    profile = profile,
    ianaTimeZone = "America/Los_Angeles",
    readiness = testReadiness(),
    registry = testRegistry(profile),
)

internal fun testArtifact(
    path: String = "health/output.json",
    mediaType: String = "application/json",
    writeMode: ExportArtifactWriteMode = ExportArtifactWriteMode.overwrite,
    content: ByteArray = "{}".encodeToByteArray(),
    requestId: String = TEST_REQUEST_ID,
    sessionId: String = TEST_SESSION_ID,
    profile: AndroidExportProfile = AndroidExportProfile.android_frozen_v4,
): ExportArtifactPlanItem {
    val contentSha256 = sha256Hex(content)
    return ExportArtifactPlanItem(
        artifactId = artifactIdHex(
            requestId = requestId,
            sessionId = sessionId,
            profile = profile,
            relativePath = path,
            mediaType = mediaType,
            writeMode = writeMode,
            contentSha256 = contentSha256,
        ),
        relativePath = path,
        mediaType = mediaType,
        writeMode = writeMode,
        content = content,
        sha256 = contentSha256,
    )
}

internal fun testPlan(
    items: List<ExportArtifactPlanItem> = listOf(testArtifact()),
    profile: AndroidExportProfile = AndroidExportProfile.android_frozen_v4,
    requestId: String = TEST_REQUEST_ID,
    sessionId: String = TEST_SESSION_ID,
): ExportArtifactPlan = ExportArtifactPlan(
    schema = ExportArtifactPlan.SCHEMA,
    artifactPlanVersion = ExportArtifactPlan.VERSION,
    requestId = requestId,
    sessionId = sessionId,
    profile = profile,
    items = items,
)

internal fun testRenderInput(
    pin: ExportEnginePin = testPin(),
    configuration: ByteArray = "config".encodeToByteArray(),
    semanticResult: ByteArray = "semantic".encodeToByteArray(),
    batches: List<ByteArray> = listOf("batch".encodeToByteArray()),
): ExportRenderInput = ExportRenderInput(
    pin = pin,
    requestId = TEST_REQUEST_ID,
    sessionId = TEST_SESSION_ID,
    configurationBytes = configuration,
    semanticResultBytes = semanticResult,
    renderBatches = batches,
)
