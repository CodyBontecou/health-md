package com.healthmd.testing

import com.healthmd.domain.exportengine.AndroidExportProfile
import com.healthmd.domain.exportengine.ExportEngineMode
import com.healthmd.domain.exportengine.ExportEnginePin

/** Pure migration evidence: no HealthMdCoreService or native library is constructed. */
internal fun syntheticExportEnginePin(
    mode: ExportEngineMode = ExportEngineMode.shadow,
    profile: AndroidExportProfile = AndroidExportProfile.android_frozen_v4,
    zoneId: String = "America/Los_Angeles",
): ExportEnginePin = ExportEnginePin(
    engine = mode,
    profile = profile,
    publicSchema = ExportEnginePin.PUBLIC_SCHEMA,
    publicSchemaVersion = when (profile) {
        AndroidExportProfile.android_frozen_v4 -> 4u
        AndroidExportProfile.android_analytical_v5 -> 5u
    },
    coreApiVersion = 4u,
    semanticInputVersion = 1u,
    canonicalModelVersion = 1u,
    renderInputVersion = 1u,
    artifactPlanVersion = 1u,
    registryVersion = 1u,
    registrySha256 = "a".repeat(64),
    semanticProfileRevision = 1u,
    renderProfileRevision = 1u,
    coreSourceRevision = "synthetic-migration-evidence",
    ianaTimeZone = zoneId,
)
