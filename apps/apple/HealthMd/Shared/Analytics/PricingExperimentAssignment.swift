//
//  PricingExperimentAssignment.swift
//  HealthMd
//
//  Sticky install-local pricing experiment assignment.
//

import Foundation

nonisolated struct PricingExperimentAssignment: Codable, Equatable, Sendable {
    let experimentId: String
    let variantId: String
    let assignedAt: Date
    let productIdOverride: String?
}

nonisolated final class PricingExperimentAssignmentStore: @unchecked Sendable {
    private static let defaultKey = "pricing.experiment.assignment.v1"

    private let defaults: UserDefaultsStoring
    private let key: String
    private let now: @Sendable () -> Date
    private let queue = DispatchQueue(label: "com.codybontecou.healthmd.pricing-experiment-assignment")

    init(
        defaults: UserDefaultsStoring = SystemUserDefaults(),
        key: String = PricingExperimentAssignmentStore.defaultKey,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.key = key
        self.now = now
    }

    func assignment(for config: PricingExperimentConfig = .baseline) -> PricingExperimentAssignment {
        queue.sync {
            if let persistedAssignment = loadAssignment(),
               isValid(persistedAssignment, for: config) {
                return persistedAssignment
            }

            let assignment = PricingExperimentAssignment(
                experimentId: config.experimentId,
                variantId: config.variantId,
                assignedAt: now(),
                productIdOverride: config.productIdOverride
            )
            save(assignment)
            return assignment
        }
    }

    private func loadAssignment() -> PricingExperimentAssignment? {
        guard let data = defaults.data(forKey: key) else { return nil }

        return try? JSONDecoder().decode(PricingExperimentAssignment.self, from: data)
    }

    private func save(_ assignment: PricingExperimentAssignment) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        guard let data = try? encoder.encode(assignment) else { return }
        defaults.set(data, forKey: key)
    }

    private func isValid(
        _ assignment: PricingExperimentAssignment,
        for config: PricingExperimentConfig
    ) -> Bool {
        guard assignment.experimentId == config.experimentId else { return false }

        return PricingExperimentConfig(
            experimentId: assignment.experimentId,
            variantId: assignment.variantId,
            productIdOverride: assignment.productIdOverride,
            isProductIDOverrideEnabled: config.isProductIDOverrideEnabled
        ) != nil
    }
}
