import HealthKit
import XCTest
@testable import HealthMd

final class HealthKitRecordCatalogTests: XCTestCase {
    func testEveryCurrentHealthMetricDefinitionIsRepresented() {
        let currentMetricIDs = Set(HealthMetrics.all.map(\.id))

        XCTAssertEqual(HealthMetrics.all.count, 171, "Review the catalog whenever HealthMetrics changes")
        XCTAssertEqual(HealthKitRecordCatalog.expectedMetricIDs.count, 171)
        XCTAssertEqual(HealthKitRecordCatalog.cataloguedMetricIDs, currentMetricIDs)
        XCTAssertEqual(HealthKitRecordCatalog.expectedMetricIDs, currentMetricIDs)
        XCTAssertEqual(HealthKitRecordCatalog.uncataloguedMetricIDs, [])
        XCTAssertEqual(HealthKitRecordCatalog.staleExpectedMetricIDs, [])

        for definition in HealthMetrics.all {
            guard let identifier = HealthKitRecordCatalog.primaryObjectTypeIdentifierByMetricID[definition.id],
                  let descriptor = HealthKitRecordCatalog.descriptorByObjectTypeIdentifier[identifier] else {
                XCTFail("Missing catalog descriptor for \(definition.id)")
                continue
            }
            XCTAssertTrue(descriptor.metricIDs.contains(definition.id))
        }
    }

    func testEveryQuantityDescriptorMatchesSystemAdapterCanonicalUnitMap() throws {
        let adapter = SystemHealthStoreAdapter()
        let quantityDescriptors = HealthKitRecordCatalog.descriptors.filter { $0.recordKind == .quantity }

        XCTAssertEqual(quantityDescriptors.count, adapter.unitMap.count)
        for descriptor in quantityDescriptors {
            let identifier = HKQuantityTypeIdentifier(rawValue: descriptor.objectTypeIdentifier)
            let adapterUnit = try XCTUnwrap(
                adapter.unitMap[identifier],
                "Missing adapter unit for \(descriptor.objectTypeIdentifier)"
            )
            XCTAssertEqual(
                descriptor.canonicalUnit,
                adapterUnit.unitString,
                "Canonical unit drift for \(descriptor.objectTypeIdentifier)"
            )
        }
        XCTAssertTrue(
            HealthKitRecordCatalog.descriptors
                .filter { $0.recordKind != .quantity }
                .allSatisfy { $0.canonicalUnit == nil }
        )
    }

    func testSelectingOneNormalMetricDoesNotPullUnrelatedTypes() {
        let quantityPlan = HealthKitRecordCatalog.selectionPlan(enabledMetricIDs: ["steps"])
        let categoryPlan = HealthKitRecordCatalog.selectionPlan(
            enabledMetricIDs: ["symptom_headache"]
        )

        XCTAssertEqual(
            quantityPlan.map(\.objectTypeIdentifier),
            ["HKQuantityTypeIdentifierStepCount"]
        )
        XCTAssertEqual(quantityPlan.first?.metricIDs, ["steps"])
        XCTAssertFalse(quantityPlan.contains { $0.recordKind == .category })
        XCTAssertEqual(
            categoryPlan.map(\.objectTypeIdentifier),
            ["HKCategoryTypeIdentifierHeadache"]
        )
        XCTAssertEqual(categoryPlan.first?.metricIDs, ["symptom_headache"])
    }

    func testSelectingEitherBloodPressureMetricIncludesCorrelationAndBothComponents() {
        let expectedIdentifiers: Set<String> = [
            HealthKitRecordCatalog.bloodPressureCorrelationIdentifier,
            "HKQuantityTypeIdentifierBloodPressureDiastolic",
            "HKQuantityTypeIdentifierBloodPressureSystolic",
        ]

        for metricID in ["blood_pressure_systolic", "blood_pressure_diastolic"] {
            let plan = HealthKitRecordCatalog.selectionPlan(enabledMetricIDs: [metricID])
            XCTAssertEqual(Set(plan.map(\.objectTypeIdentifier)), expectedIdentifiers)
        }

        let correlation = HealthKitRecordCatalog.descriptorByObjectTypeIdentifier[
            HealthKitRecordCatalog.bloodPressureCorrelationIdentifier
        ]
        XCTAssertEqual(correlation?.recordKind, .correlation)
        XCTAssertEqual(
            correlation?.metricIDs,
            ["blood_pressure_diastolic", "blood_pressure_systolic"]
        )
        XCTAssertEqual(
            Set(correlation?.dependencies.map(\.reason) ?? []),
            [.bloodPressureComponent]
        )
    }

    func testStandTimeUsesActualStandTimeAndKeepsStandHourAsCompatibilityDependency() throws {
        let plan = HealthKitRecordCatalog.selectionPlan(enabledMetricIDs: ["stand_time"])
        let standTime = try XCTUnwrap(
            plan.first { $0.objectTypeIdentifier == "HKQuantityTypeIdentifierAppleStandTime" }
        )
        let standHour = try XCTUnwrap(
            plan.first { $0.objectTypeIdentifier == HealthKitRecordCatalog.appleStandHourIdentifier }
        )

        XCTAssertEqual(Set(plan.map(\.objectTypeIdentifier)), [
            "HKQuantityTypeIdentifierAppleStandTime",
            HealthKitRecordCatalog.appleStandHourIdentifier,
        ])
        XCTAssertEqual(standTime.recordKind, .quantity)
        XCTAssertEqual(standTime.canonicalUnit, HKUnit.minute().unitString)
        XCTAssertEqual(standTime.metricIDs, ["stand_time"])
        XCTAssertEqual(standHour.recordKind, .category)
        XCTAssertNil(standHour.canonicalUnit)
        XCTAssertEqual(standHour.metricIDs, ["stand_time"])
        XCTAssertEqual(
            standTime.dependencyReasons[HealthKitRecordCatalog.appleStandHourIdentifier],
            .appleStandHourCompatibility
        )
    }

    func testWorkoutSelectionIncludesRouteAndChildSamples() throws {
        let plan = HealthKitRecordCatalog.selectionPlan(enabledMetricIDs: ["workouts"])
        let identifiers = Set(plan.map(\.objectTypeIdentifier))
        let workout = try XCTUnwrap(
            plan.first { $0.objectTypeIdentifier == HealthKitRecordCatalog.workoutTypeIdentifier }
        )

        XCTAssertTrue(identifiers.contains(HealthKitRecordCatalog.workoutRouteTypeIdentifier))
        XCTAssertTrue(identifiers.contains("HKQuantityTypeIdentifierHeartRate"))
        XCTAssertTrue(identifiers.contains("HKQuantityTypeIdentifierDistanceWalkingRunning"))
        XCTAssertTrue(identifiers.contains("HKQuantityTypeIdentifierRunningPower"))
        XCTAssertTrue(identifiers.contains("HKQuantityTypeIdentifierCyclingCadence"))
        XCTAssertFalse(identifiers.contains(HealthKitRecordCatalog.foodCorrelationIdentifier))
        XCTAssertEqual(workout.recordKind, .workout)
        XCTAssertEqual(workout.metricIDs, ["workouts"])
        XCTAssertEqual(
            workout.dependencyReasons[HealthKitRecordCatalog.workoutRouteTypeIdentifier],
            .workoutRoute
        )
        XCTAssertEqual(
            workout.dependencyReasons["HKQuantityTypeIdentifierHeartRate"],
            .workoutChildSample
        )

        let route = try XCTUnwrap(
            HealthKitRecordCatalog.descriptorByObjectTypeIdentifier[
                HealthKitRecordCatalog.workoutRouteTypeIdentifier
            ]
        )
        XCTAssertEqual(route.recordKind, .workoutRoute)
        XCTAssertEqual(route.metricIDs, ["workouts"])
    }

    func testFoodCorrelationClosesOverNutritionComponentsOnly() throws {
        let dietaryMetricIDs = Set(
            HealthMetrics.all
                .filter { $0.category == .nutrition || $0.category == .vitamins || $0.category == .minerals }
                .map(\.id)
        )
        let plan = HealthKitRecordCatalog.selectionPlan(enabledMetricIDs: ["dietary_protein"])
        let identifiers = Set(plan.map(\.objectTypeIdentifier))
        let food = try XCTUnwrap(
            plan.first { $0.objectTypeIdentifier == HealthKitRecordCatalog.foodCorrelationIdentifier }
        )

        XCTAssertEqual(food.recordKind, .correlation)
        XCTAssertEqual(Set(food.metricIDs), dietaryMetricIDs)
        XCTAssertEqual(plan.count, dietaryMetricIDs.count + 1)
        XCTAssertTrue(identifiers.contains("HKQuantityTypeIdentifierDietaryProtein"))
        XCTAssertTrue(identifiers.contains("HKQuantityTypeIdentifierDietaryVitaminC"))
        XCTAssertTrue(identifiers.contains("HKQuantityTypeIdentifierDietaryIron"))
        XCTAssertFalse(identifiers.contains("HKCategoryTypeIdentifierHeadache"))
        XCTAssertTrue(food.dependencies.allSatisfy { $0.reason == .nutritionComponent })
    }

    func testDuplicateIdentifiersAreGroupedWithoutLosingMetricIDs() {
        let expectedGroups: [String: [String]] = [
            "HKCategoryTypeIdentifierSleepAnalysis": [
                "sleep_awake", "sleep_bedtime", "sleep_core", "sleep_deep",
                "sleep_in_bed", "sleep_rem", "sleep_total", "sleep_wake",
            ],
            "HKQuantityTypeIdentifierHeartRate": [
                "heart_rate_avg", "heart_rate_max", "heart_rate_min",
            ],
            "HKCategoryTypeIdentifierMindfulSession": [
                "mindful_minutes", "mindful_sessions",
            ],
            HealthKitRecordCatalog.stateOfMindIdentifier: [
                "average_valence", "daily_mood", "momentary_emotions", "state_of_mind_entries",
            ],
        ]

        for (identifier, expectedMetricIDs) in expectedGroups {
            let matching = HealthKitRecordCatalog.descriptors.filter {
                $0.objectTypeIdentifier == identifier
            }
            XCTAssertEqual(matching.count, 1)
            XCTAssertEqual(matching.first?.metricIDs, expectedMetricIDs)
        }
        XCTAssertEqual(
            HealthKitRecordCatalog.descriptorByObjectTypeIdentifier[
                HealthKitRecordCatalog.stateOfMindIdentifier
            ]?.recordKind,
            .stateOfMind
        )
    }

    func testSpecialDefinitionsAreExplicitlyCatalogued() throws {
        let workout = try XCTUnwrap(
            HealthKitRecordCatalog.descriptorByObjectTypeIdentifier[
                HealthKitRecordCatalog.workoutTypeIdentifier
            ]
        )
        let medication = try XCTUnwrap(
            HealthKitRecordCatalog.descriptorByObjectTypeIdentifier[
                HealthKitRecordCatalog.medicationDoseEventIdentifier
            ]
        )

        XCTAssertEqual(workout.recordKind, .workout)
        XCTAssertEqual(workout.metricIDs, ["workouts"])
        XCTAssertEqual(
            HealthKitRecordCatalog.workoutTypeIdentifier,
            HKObjectType.workoutType().identifier
        )
        if #available(macOS 15.0, *) {
            XCTAssertEqual(
                HealthKitRecordCatalog.stateOfMindIdentifier,
                HKSampleType.stateOfMindType().identifier
            )
        }
        XCTAssertEqual(medication.recordKind, .medicationDoseEvent)
        XCTAssertEqual(medication.metricIDs, ["medications"])
        if #available(macOS 26.0, *) {
            XCTAssertEqual(
                HealthKitRecordCatalog.medicationDoseEventIdentifier,
                HKMedicationDoseEventType.medicationDoseEventType().identifier
            )
        }
        XCTAssertTrue(HealthKitRecordCatalog.specialAuthorizationDescriptors.contains(medication))
        XCTAssertFalse(HealthKitRecordCatalog.authorizationDescriptors.contains(medication))
    }

    func testSelectionPlanAndDescriptorCollectionsAreDeterministicallyOrdered() {
        let forward = HealthKitRecordCatalog.selectionPlan(
            enabledMetricIDs: ["stand_time", "steps", "blood_pressure_systolic"]
        )
        let reverse = HealthKitRecordCatalog.selectionPlan(
            enabledMetricIDs: ["blood_pressure_systolic", "steps", "stand_time"]
        )
        let identifiers = forward.map(\.objectTypeIdentifier)

        XCTAssertEqual(forward, reverse)
        XCTAssertEqual(identifiers, identifiers.sorted())
        XCTAssertEqual(
            HealthKitRecordCatalog.descriptors.map(\.objectTypeIdentifier),
            HealthKitRecordCatalog.descriptors.map(\.objectTypeIdentifier).sorted()
        )
        for descriptor in HealthKitRecordCatalog.descriptors {
            XCTAssertEqual(descriptor.metricIDs, descriptor.metricIDs.sorted())
            XCTAssertEqual(descriptor.dependencyIdentifiers, descriptor.dependencyIdentifiers.sorted())
        }
    }

    func testNoDescriptorOrDependencyIsOrphaned() {
        let descriptorIdentifiers = Set(
            HealthKitRecordCatalog.descriptors.map(\.objectTypeIdentifier)
        )
        let primaryIdentifiers = Set(
            HealthKitRecordCatalog.primaryObjectTypeIdentifierByMetricID.values
        )
        let dependencyIdentifiers = Set(
            HealthKitRecordCatalog.descriptors.flatMap(\.dependencyIdentifiers)
        )

        XCTAssertEqual(HealthKitRecordCatalog.unresolvedDependencyIdentifiers, [])
        XCTAssertEqual(descriptorIdentifiers, primaryIdentifiers.union(dependencyIdentifiers))
        XCTAssertTrue(HealthKitRecordCatalog.descriptors.allSatisfy { !$0.metricIDs.isEmpty })
        XCTAssertTrue(
            HealthKitRecordCatalog.descriptors
                .flatMap(\.metricIDs)
                .allSatisfy { HealthKitRecordCatalog.expectedMetricIDs.contains($0) }
        )
    }

    func testReverseLookupAndAuthorizationAreDerivedFromCatalog() {
        XCTAssertEqual(
            HealthKitRecordCatalog.metricIDs(
                forObjectTypeIdentifier: "HKQuantityTypeIdentifierHeartRate"
            ),
            ["heart_rate_avg", "heart_rate_max", "heart_rate_min"]
        )
        XCTAssertEqual(
            HealthKitRecordCatalog.metricIDs(
                forObjectTypeIdentifier: HealthKitRecordCatalog.workoutRouteTypeIdentifier
            ),
            ["workouts"]
        )
        XCTAssertEqual(
            HealthKitRecordCatalog.metricIDs(forObjectTypeIdentifier: "HKFutureType"),
            []
        )

        let expectedStandardAuthorization = Set(
            HealthKitRecordCatalog.descriptors.filter { $0.recordKind != .medicationDoseEvent }
        )
        XCTAssertEqual(
            HealthKitRecordCatalog.authorizationDescriptors,
            expectedStandardAuthorization
        )
        XCTAssertEqual(
            HealthKitRecordCatalog.authorizationDescriptors(enabledMetricIDs: ["stand_time"]),
            Set(HealthKitRecordCatalog.selectionPlan(enabledMetricIDs: ["stand_time"]))
        )
    }
}
