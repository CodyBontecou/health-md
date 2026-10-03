package com.healthmd.domain.exportengine

import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pure rules for multi-profile output-path overlap detection (mirror of the iOS
 * `ExportProfileOverlapDetectorTests`).
 */
class ExportProfileOverlapDetectorTest {

    private fun settings(
        filenameFormat: String = ExportSettings.DEFAULT_FILENAME_FORMAT,
        folderStructure: String = "",
        formats: Set<ExportFormat> = setOf(ExportFormat.MARKDOWN),
    ) = ExportSettings(
        filenameFormat = filenameFormat,
        folderStructure = folderStructure,
        exportFormats = formats,
    )

    private fun identity(
        id: String,
        name: String,
        target: ExportTarget = ExportTarget.DEVICE_FOLDER,
        root: String?,
        settings: ExportSettings,
    ) = ExportProfileOverlapDetector.ProfilePathIdentity(
        profileId = id,
        name = name,
        target = target,
        settings = settings,
        destinationRootKey = root,
    )

    private fun profile(
        id: String,
        name: String = id,
        target: ExportTarget = ExportTarget.DEVICE_FOLDER,
        apiEndpointUrl: String? = null,
        folderUri: String? = null,
        settingsJson: String = AndroidExportSettingsSnapshotCodec.encodeCanonical(
            AndroidExportSettingsSnapshot.capture(
                settings = settings(),
                pin = null,
                zone = java.time.ZoneId.of("UTC"),
            ),
        ),
    ) = ExportProfile(
        id = id,
        name = name,
        settingsSnapshotJson = settingsJson,
        target = target,
        apiEndpointUrl = apiEndpointUrl,
        folderUri = folderUri,
        createdAtEpochMillis = 0,
        updatedAtEpochMillis = 0,
    )

    @Test
    fun `identical settings and root overlap`() {
        val first = identity("a", "Alpha", root = "content://tree/health", settings = settings())
        val second = identity("b", "Beta", root = "content://tree/health", settings = settings())

        assertEquals(
            listOf("Alpha"),
            ExportProfileOverlapDetector.overlappingProfileNames("b", listOf(first, second)),
        )
        assertEquals(
            listOf("Beta"),
            ExportProfileOverlapDetector.overlappingProfileNames("a", listOf(first, second)),
        )
    }

    @Test
    fun `different destination roots do not overlap`() {
        val first = identity("a", "Alpha", root = "content://tree/health", settings = settings())
        val second = identity("b", "Beta", root = "content://tree/archive", settings = settings())

        assertTrue(
            ExportProfileOverlapDetector
                .overlappingProfileNames("b", listOf(first, second)).isEmpty(),
        )
    }

    @Test
    fun `root comparison is case-insensitive`() {
        val first = identity("a", "Alpha", root = "content://tree/Health", settings = settings())
        val second = identity("b", "Beta", root = "content://tree/health", settings = settings())

        assertEquals(
            listOf("Alpha"),
            ExportProfileOverlapDetector.overlappingProfileNames("b", listOf(first, second)),
        )
    }

    @Test
    fun `different filename templates do not overlap`() {
        val first = identity(
            "a", "Alpha", root = "content://tree/health",
            settings = settings(filenameFormat = "{date}"),
        )
        val second = identity(
            "b", "Beta", root = "content://tree/health",
            settings = settings(filenameFormat = "health-{date}"),
        )

        assertTrue(
            ExportProfileOverlapDetector
                .overlappingProfileNames("b", listOf(first, second)).isEmpty(),
        )
    }

    @Test
    fun `date equivalent templates overlap`() {
        // "{year}-{month}-{day}" renders identically to "{date}"; rendered sample
        // dates catch what a raw template comparison misses.
        val first = identity(
            "a", "Alpha", root = "content://tree/health",
            settings = settings(filenameFormat = "{date}"),
        )
        val second = identity(
            "b", "Beta", root = "content://tree/health",
            settings = settings(filenameFormat = "{year}-{month}-{day}"),
        )

        assertEquals(
            listOf("Alpha"),
            ExportProfileOverlapDetector.overlappingProfileNames("b", listOf(first, second)),
        )
    }

    @Test
    fun `disjoint format sets do not overlap`() {
        val first = identity(
            "a", "Alpha", root = "content://tree/health",
            settings = settings(formats = setOf(ExportFormat.MARKDOWN)),
        )
        val second = identity(
            "b", "Beta", root = "content://tree/health",
            settings = settings(formats = setOf(ExportFormat.JSON)),
        )

        assertTrue(
            ExportProfileOverlapDetector
                .overlappingProfileNames("b", listOf(first, second)).isEmpty(),
        )
    }

    @Test
    fun `api endpoint profiles never participate`() {
        val first = identity("a", "Alpha", target = ExportTarget.API_ENDPOINT, root = null, settings = settings())
        val second = identity("b", "Beta", target = ExportTarget.API_ENDPOINT, root = null, settings = settings())

        assertTrue(
            ExportProfileOverlapDetector
                .overlappingProfileNames("b", listOf(first, second)).isEmpty(),
        )
    }

    @Test
    fun `mixed targets never overlap`() {
        val folder = identity("a", "Alpha", root = "content://tree/health", settings = settings())
        val endpoint = identity(
            "b", "Beta", target = ExportTarget.API_ENDPOINT, root = null, settings = settings(),
        )

        assertTrue(
            ExportProfileOverlapDetector
                .overlappingProfileNames("b", listOf(folder, endpoint)).isEmpty(),
        )
    }

    @Test
    fun `nil root never reports overlap`() {
        val first = identity("a", "Alpha", root = null, settings = settings())
        val second = identity("b", "Beta", root = null, settings = settings())

        assertTrue(
            ExportProfileOverlapDetector
                .overlappingProfileNames("b", listOf(first, second)).isEmpty(),
        )
    }

    @Test
    fun `sorted presentation order`() {
        val subject = identity("s", "Subject", root = "content://tree/health", settings = settings())
        val zulu = identity("z", "Zulu", root = "content://tree/health", settings = settings())
        val alpha = identity("a2", "alpha", root = "content://tree/health", settings = settings())
        val mid = identity("m", "Middle", root = "content://tree/health", settings = settings())

        assertEquals(
            listOf("alpha", "Middle", "Zulu"),
            ExportProfileOverlapDetector.overlappingProfileNames(
                "s", listOf(subject, zulu, alpha, mid),
            ),
        )
    }

    @Test
    fun `identities decode frozen snapshots and fall back to unbound current folder`() {
        val current = settings()
        val bound = profile("bound", folderUri = "content://tree/bound")
        val unbound = profile("unbound")
        val endpoint = profile(
            "endpoint", target = ExportTarget.API_ENDPOINT,
        )

        val identities = ExportProfileOverlapDetector.identities(
            profiles = listOf(bound, unbound, endpoint),
            currentFolderUri = "content://tree/live",
            currentSettings = current,
        )

        assertEquals(
            "content://tree/bound",
            identities.first { it.profileId == "bound" }.destinationRootKey,
        )
        assertEquals(
            "an unbound device-folder profile uses the live folder",
            "content://tree/live",
            identities.first { it.profileId == "unbound" }.destinationRootKey,
        )
        assertEquals(null, identities.first { it.profileId == "endpoint" }.destinationRootKey)
    }

    @Test
    fun `identities inspect saved api profiles against their own endpoint`() {
        fun apiSnapshot(endpoint: String): String = AndroidExportSettingsSnapshotCodec.encodeCanonical(
            AndroidExportSettingsSnapshot.capture(
                settings = settings().copy(
                    exportTarget = ExportTarget.API_ENDPOINT,
                    scheduledExportTarget = ExportTarget.API_ENDPOINT,
                    apiEndpointUrl = endpoint,
                ),
                pin = null,
                zone = java.time.ZoneId.of("UTC"),
            ),
        )
        val firstEndpoint = "https://first.invalid/health"
        val secondEndpoint = "https://second.invalid/health"
        val profiles = listOf(
            profile(
                id = "folder",
                folderUri = "content://tree/live",
            ),
            profile(
                id = "api-a",
                target = ExportTarget.API_ENDPOINT,
                apiEndpointUrl = firstEndpoint,
                settingsJson = apiSnapshot(firstEndpoint),
            ),
            profile(
                id = "api-b",
                target = ExportTarget.API_ENDPOINT,
                apiEndpointUrl = secondEndpoint,
                settingsJson = apiSnapshot(secondEndpoint),
            ),
        )

        val identities = ExportProfileOverlapDetector.identities(
            profiles = profiles,
            currentFolderUri = "content://tree/live",
            currentSettings = settings().copy(apiEndpointUrl = "https://active.invalid/health"),
        )

        assertEquals(3, identities.size)
        assertEquals(null, identities.first { it.profileId == "api-a" }.destinationRootKey)
        assertEquals(null, identities.first { it.profileId == "api-b" }.destinationRootKey)
        assertTrue(
            ExportProfileOverlapDetector
                .overlappingProfileNames("api-a", identities)
                .isEmpty(),
        )
    }

    @Test
    fun `corrupt snapshot has unknown root and cannot fabricate overlap`() {
        val identities = ExportProfileOverlapDetector.identities(
            profiles = listOf(
                profile(
                    id = "valid",
                    folderUri = "content://tree/live",
                ),
                profile(
                    id = "corrupt",
                    folderUri = "content://tree/live",
                    settingsJson = "not-json",
                ),
            ),
            currentFolderUri = "content://tree/live",
            currentSettings = settings(),
        )

        assertEquals(null, identities.first { it.profileId == "corrupt" }.destinationRootKey)
        assertTrue(
            ExportProfileOverlapDetector
                .overlappingProfileNames("valid", identities)
                .isEmpty(),
        )
    }

    @Test
    fun `draft preview names profiles the candidate draft would collide with`() {
        val current = settings()
        val daily = identity("a", "Daily", root = "content://tree/live", settings = settings())
        val weekly = identity("b", "Weekly", root = "content://tree/weekly", settings = settings())

        // Unbound candidate falls back to the live folder, matching unbound saved profiles.
        assertEquals(
            listOf("Daily"),
            ExportProfileOverlapDetector.overlapPreviewNames(
                identities = listOf(daily, weekly),
                currentFolderUri = "content://tree/live",
                candidateTarget = ExportTarget.DEVICE_FOLDER,
                candidateFolderUri = null,
                candidateSettings = current,
            ),
        )

        // Bound candidate collides only with the profile sharing that folder.
        assertEquals(
            listOf("Weekly"),
            ExportProfileOverlapDetector.overlapPreviewNames(
                identities = listOf(daily, weekly),
                currentFolderUri = "content://tree/live",
                candidateTarget = ExportTarget.DEVICE_FOLDER,
                candidateFolderUri = "content://tree/weekly",
                candidateSettings = current,
            ),
        )
    }

    @Test
    fun `draft preview stays silent for api candidates and distinct templates`() {
        val daily = identity("a", "Daily", root = "content://tree/live", settings = settings())

        assertTrue(
            ExportProfileOverlapDetector.overlapPreviewNames(
                identities = listOf(daily),
                currentFolderUri = "content://tree/live",
                candidateTarget = ExportTarget.API_ENDPOINT,
                candidateFolderUri = null,
                candidateSettings = settings(),
            ).isEmpty(),
        )

        assertTrue(
            ExportProfileOverlapDetector.overlapPreviewNames(
                identities = listOf(daily),
                currentFolderUri = "content://tree/live",
                candidateTarget = ExportTarget.DEVICE_FOLDER,
                candidateFolderUri = null,
                candidateSettings = settings(filenameFormat = "unique-{date}"),
            ).isEmpty(),
        )
    }
}
