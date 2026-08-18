import Foundation
import HealthMdCoreRust

/// Native presentation/SDK adapter for the shared Rust registry.
///
/// HealthKit type resolution, `#available` evaluation, permissions, persistence, and localized
/// strings remain in Swift. The adapter consumes one coarse immutable profile snapshot.
enum HealthMdCoreRegistryAdapter {
    enum AdapterError: Error, Equatable {
        case invalidMetadata
    }

    static func appleSnapshot(
        service: HealthMdCoreService = HealthMdCoreService()
    ) throws -> CoreMetricRegistrySnapshot {
        try service.metricRegistry(profile: .appleHealthDataV8)
    }

    static func definitions(
        from snapshot: CoreMetricRegistrySnapshot
    ) throws -> [HealthMetricDefinition] {
        guard snapshot.profileId == "apple_health_data_v8",
              snapshot.publicProfileId == "apple-v8",
              snapshot.publicSchema == HealthMdExportSchema.identifier,
              snapshot.publicSchemaVersion == UInt32(HealthMdExportSchema.version),
              snapshot.registryVersion == 1,
              snapshot.profileRevision == 1,
              snapshot.registrySha256 == HealthMetrics.registrySHA256,
              snapshot.metrics.count == 230 else {
            throw AdapterError.invalidMetadata
        }

        return try snapshot.metrics.enumerated().map { index, metric in
            guard metric.ordinal == UInt32(index),
                  let category = HealthMetricCategory(rawValue: metric.categoryId),
                  let availability = HealthMetricAvailability(rawValue: metric.availabilityKey),
                  let metricType = metricType(metric.kind),
                  let aggregation = aggregation(metric.sourceAggregation) else {
                throw AdapterError.invalidMetadata
            }
            return HealthMetricDefinition(
                id: metric.selectionId,
                name: metric.referenceName,
                category: category,
                unit: metric.unit,
                healthKitIdentifier: metric.sourceSelector == "None" ? nil : metric.sourceSelector,
                metricType: metricType,
                aggregation: aggregation,
                isArchiveOnly: metric.archiveOnly,
                isEnabledByDefault: metric.defaultEnabled,
                availability: availability
            )
        }
    }

    /// Health-free JSON-pointer-style differences for shadow rollout diagnostics.
    static func shadowDifferences(
        snapshot: CoreMetricRegistrySnapshot,
        nativeDefinitions: [HealthMetricDefinition] = HealthMetrics.all
    ) -> [String] {
        var differences: [String] = []
        guard let rustDefinitions = try? definitions(from: snapshot) else {
            return ["/registry/invalid_metadata"]
        }
        if rustDefinitions.count != nativeDefinitions.count {
            differences.append("/metrics/count")
        }
        for index in 0..<min(rustDefinitions.count, nativeDefinitions.count) {
            let rust = rustDefinitions[index]
            let native = nativeDefinitions[index]
            let prefix = "/metrics/\(index)"
            if rust.id != native.id { differences.append("\(prefix)/selection_id") }
            if rust.name != native.name { differences.append("\(prefix)/reference_name") }
            if rust.category != native.category { differences.append("\(prefix)/category_id") }
            if rust.unit != native.unit { differences.append("\(prefix)/unit") }
            if rust.healthKitIdentifier != native.healthKitIdentifier { differences.append("\(prefix)/source_selector") }
            if metricTypeKey(rust.metricType) != metricTypeKey(native.metricType) {
                differences.append("\(prefix)/kind")
            }
            if aggregationKey(rust.aggregation) != aggregationKey(native.aggregation) {
                differences.append("\(prefix)/source_aggregation")
            }
            if rust.isArchiveOnly != native.isArchiveOnly { differences.append("\(prefix)/archive_only") }
            if rust.isEnabledByDefault != native.isEnabledByDefault { differences.append("\(prefix)/default_enabled") }
            if rust.availability != native.availability { differences.append("\(prefix)/availability_key") }
        }

        let rustArchive = Set(snapshot.metrics.filter(\.archiveOnly).map(\.selectionId))
        if rustArchive != HealthMetricExportMapping.reviewedArchiveOnlyMetricIDs {
            differences.append("/outputs/archive_only")
        }
        let rustMapping = Dictionary(
            grouping: snapshot.outputs,
            by: { $0.selectionIds.first ?? "" }
        ).mapValues { outputs in
            outputs.sorted { $0.ordinal < $1.ordinal }.map(\.key)
        }
        if rustMapping != HealthMetricExportMapping.metricIdToFrontmatterKeys {
            differences.append("/outputs/flat")
        }
        return differences
    }

    private static func metricTypeKey(_ value: HealthMetricDefinition.MetricType) -> String {
        switch value {
        case .quantity: "quantity"
        case .category: "category"
        case .workout: "workout"
        }
    }

    private static func aggregationKey(_ value: HealthMetricDefinition.AggregationType) -> String {
        switch value {
        case .cumulative: "cumulative"
        case .discreteAvg: "discreteAvg"
        case .discreteMin: "discreteMin"
        case .discreteMax: "discreteMax"
        case .mostRecent: "mostRecent"
        case .duration: "duration"
        case .count: "count"
        }
    }

    private static func metricType(
        _ value: String
    ) -> HealthMetricDefinition.MetricType? {
        switch value {
        case "quantity": .quantity
        case "category": .category
        case "workout": .workout
        default: nil
        }
    }

    private static func aggregation(
        _ value: String
    ) -> HealthMetricDefinition.AggregationType? {
        switch value {
        case "cumulative": .cumulative
        case "discreteAvg": .discreteAvg
        case "discreteMin": .discreteMin
        case "discreteMax": .discreteMax
        case "mostRecent": .mostRecent
        case "duration": .duration
        case "count": .count
        default: nil
        }
    }
}
