import Foundation

/// Native source facts extend already-validated successor API records before exact envelope sizing.
nonisolated enum AppleWakeDateAPIRecordComposer {
    struct Source: Sendable {
        let ownerDate: String
        let aggregate: Data
        let archive: HealthKitRecordArchive?
        let partialFailures: [ExportPartialFailure]
        let captureStatus: String
        let providers: HealthProviderSections?
        let quantities: AppleWakeDateQuantityProjection
        let sleepStages: AppleWakeDateSleepStageProjection
        let correlations: AppleWakeDateCorrelationProjection
        let workouts: AppleWakeDateWorkoutProjection
        let mindfulness: AppleWakeDateMindfulnessProjection
    }

    @MainActor
    static func compose(sources: [Source], calendarTimeZoneIdentifier: String,
        directory: URL) async throws -> [String: ExportArtifactFile] {
        let worker = Task.detached(priority: .utility) {
            var files: [String: ExportArtifactFile] = [:]
            let expectedContext = ["calendar_timezone": calendarTimeZoneIdentifier,
                "timestamp_timezone": "UTC", "sleep_day_attribution": "morning_ends",
                "sleep_owner_day_rule": "session_end_date", "sleep_interval_clipping": "none"]
            for source in sources {
                try Task.checkCancellation()
                guard files[source.ownerDate] == nil,
                      var root = try JSONSerialization.jsonObject(with: source.aggregate) as? [String: Any],
                      root["date"] as? String == source.ownerDate,
                      root["schema"] as? String == "healthmd.health_data",
                      root["schema_version"] as? Int == 11,
                      root["schema_profile"] as? String == "apple-v11",
                      root["unit_system"] as? String == "metric",
                      root["time_context"] as? [String: String] == expectedContext,
                      root["healthkit_record_archive"] == nil, root["diagnostics"] == nil,
                      root["providers"] == nil else {
                    throw APIEndpointExportRunner.EngineError.invalidPreparedPlan
                }
                if let archive = source.archive {
                    guard archive.dailyOwnership.ownerDate == source.ownerDate,
                          archive.dailyOwnership.calendarTimeZoneIdentifier == calendarTimeZoneIdentifier else {
                        throw APIEndpointExportRunner.EngineError.invalidPreparedPlan
                    }
                }
                root["raw_capture_status"] = source.captureStatus
                try source.quantities.addJSON(to: &root)
                try source.sleepStages.addJSON(to: &root)
                try source.correlations.addJSON(to: &root)
                try source.workouts.addJSON(to: &root)
                try source.mindfulness.addJSON(to: &root)
                if let providers = source.providers, !providers.isEmpty {
                    root["providers"] = try AppleWakeDateProviderProjection.lazyJSONObject(providers)
                }
                if !source.partialFailures.isEmpty {
                    root["diagnostics"] = ExportDiagnosticSerializer.lazyDiagnostics(source.partialFailures)
                }
                files[source.ownerDate] = try ExportArtifactIO.renderTemporary(in: directory,
                    prefix: "api-wake-source-record", mediaType: "application/json") { sink in
                    try HealthKitRecordArchiveSerializer.writeDailyJSONObject(root, archive: source.archive,
                        to: sink, outputFormatting: [.sortedKeys])
                }
            }
            return files
        }
        do {
            return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        } catch is AppleWakeDateMindfulnessProjection.ProjectionError {
            throw APIEndpointExportRunner.EngineError.invalidPreparedPlan
        } catch is AppleWakeDateWorkoutProjection.ProjectionError {
            throw APIEndpointExportRunner.EngineError.invalidPreparedPlan
        } catch is AppleWakeDateCorrelationProjection.ProjectionError {
            throw APIEndpointExportRunner.EngineError.invalidPreparedPlan
        }
    }
}
