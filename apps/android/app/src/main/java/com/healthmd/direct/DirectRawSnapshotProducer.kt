package com.healthmd.direct

import com.healthmd.rawexport.DirectRawExportStorage
import com.healthmd.rawexport.RawExportResult
import com.healthmd.rawexport.RawHealthRepositoryRegistry
import com.healthmd.rawexport.RawSnapshotExportOrchestrator
import com.healthmd.rawexport.RawSnapshotRequest
import com.healthmd.rawexport.RawSnapshotStatus
import com.healthmd.rawexport.RawSnapshotValidator
import com.healthmd.rawexport.RawValidationOptions
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class DirectRawSnapshotProducer @Inject constructor(
    private val repositories: RawHealthRepositoryRegistry,
) {
    suspend fun produce(
        jobDirectory: File,
        providerId: String,
        request: RawSnapshotRequest,
    ): RawExportResult {
        val repository = requireNotNull(repositories.repositoryFor(providerId)) {
            "The selected provider does not support provider-native raw snapshots."
        }
        val raw = RawSnapshotExportOrchestrator(
            repository = repository,
            storage = DirectRawExportStorage(File(jobDirectory, "raw")),
            spoolRoot = File(jobDirectory, "spool"),
        ).export(request)
        require(raw.manifest.status == RawSnapshotStatus.COMPLETE || raw.manifest.status == RawSnapshotStatus.PARTIAL) {
            "The provider did not produce a completed raw snapshot."
        }
        val file = File(raw.finalLocation)
        require(file.isFile) { "The completed raw snapshot is missing." }
        val validation = file.inputStream().buffered().use { input ->
            RawSnapshotValidator().validate(
                input = input,
                format = raw.format,
                options = RawValidationOptions(
                    expectedArtifactChecksumSha256 = raw.artifactChecksumSha256,
                    artifactFileName = file.name,
                ),
            )
        }
        require(validation.valid && validation.artifactChecksumVerified) {
            "The completed raw snapshot did not pass local validation."
        }
        return raw
    }
}
