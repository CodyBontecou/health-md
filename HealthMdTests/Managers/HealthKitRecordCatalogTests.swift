import HealthKit
import XCTest
@testable import HealthMd

final class HealthKitRecordCatalogTests: XCTestCase {
    func testEveryCurrentHealthMetricDefinitionIsRepresented() {
        let currentMetricIDs = Set(HealthMetrics.all.map(\.id))

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
        let quantityDescriptors = HealthKitRecordCatalog.descriptors.filter {
            $0.recordKind == .quantity && HealthKitRecordCatalog.isRuntimeAvailable($0)
        }

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

        let newQuantityPlan = HealthKitRecordCatalog.selectionPlan(enabledMetricIDs: ["rowing_speed"])
        let newCategoryPlan = HealthKitRecordCatalog.selectionPlan(enabledMetricIDs: ["pregnancy_test_result"])
        XCTAssertEqual(newQuantityPlan.map(\.objectTypeIdentifier), ["HKQuantityTypeIdentifierRowingSpeed"])
        XCTAssertEqual(newQuantityPlan.first?.metricIDs, ["rowing_speed"])
        XCTAssertEqual(newCategoryPlan.map(\.objectTypeIdentifier), ["HKCategoryTypeIdentifierPregnancyTestResult"])
        XCTAssertEqual(newCategoryPlan.first?.metricIDs, ["pregnancy_test_result"])
    }

    func testEnvironmentalAudioExposureEventKeepsStableMetricIdentityAndResolvesSDKRawIdentifier() throws {
        let metric = try XCTUnwrap(
            HealthMetrics.all.first { $0.id == "environmental_audio_exposure_event" }
        )
        XCTAssertEqual(metric.name, "Environmental Audio Exposure Event")
        XCTAssertEqual(
            metric.healthKitIdentifier,
            "HKCategoryTypeIdentifierEnvironmentalAudioExposureEvent",
            "The long-lived Health.md definition identity remains stable"
        )

        let plan = HealthKitRecordCatalog.attributedSelectionPlan(
            enabledMetricIDs: [metric.id]
        )
        let entry = try XCTUnwrap(plan.first)
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(
            entry.objectTypeIdentifier,
            HealthKitRecordCatalog.environmentalAudioExposureEventIdentifier
        )
        XCTAssertEqual(entry.objectTypeIdentifier, "HKCategoryTypeIdentifierAudioExposureEvent")
        let resolved = try XCTUnwrap(HealthKitRecordCatalog.resolveObjectType(entry.descriptor))
        XCTAssertEqual(resolved.identifier, entry.objectTypeIdentifier)
        XCTAssertTrue(resolved is HKCategoryType)
    }

    func testNewQuantityUnitsAreHealthKitCompatibleOnSupportedRuntimes() throws {
        let adapter = SystemHealthStoreAdapter()
        let archiveOnlyQuantities = HealthMetrics.all.filter {
            $0.isArchiveOnly && $0.metricType == .quantity && $0.availability.isAvailableOnCurrentPlatform
        }

        for metric in archiveOnlyQuantities {
            let rawIdentifier = try XCTUnwrap(metric.healthKitIdentifier)
            let identifier = HKQuantityTypeIdentifier(rawValue: rawIdentifier)
            let type = try XCTUnwrap(
                HKQuantityType.quantityType(forIdentifier: identifier),
                "Supported HealthKit type did not resolve: \(rawIdentifier)"
            )
            let unit = try XCTUnwrap(adapter.unitMap[identifier])
            let quantity = HKQuantity(unit: unit, doubleValue: 1)
            let sample = HKQuantitySample(type: type, quantity: quantity, start: .now, end: .now)
            XCTAssertEqual(sample.quantity.doubleValue(for: unit), 1, accuracy: 0.000_001)
        }
    }

    func testAvailabilityModelsDeploymentGuardsWithoutUsingHostVersion() throws {
        let rowing = try XCTUnwrap(HealthMetrics.all.first { $0.id == "rowing_speed" })
        XCTAssertTrue(rowing.isArchiveOnly)
        XCTAssertTrue(rowing.selectionDetail.contains("Source records only"))
        XCTAssertTrue(rowing.selectionDetail.contains("m/s"))
        XCTAssertFalse(rowing.availability.isAvailable(
            on: .iOS,
            version: OperatingSystemVersion(majorVersion: 17, minorVersion: 6, patchVersion: 0)
        ))
        XCTAssertTrue(rowing.availability.isAvailable(
            on: .iOS,
            version: OperatingSystemVersion(majorVersion: 18, minorVersion: 0, patchVersion: 0)
        ))

        let hypertension = try XCTUnwrap(HealthMetrics.all.first { $0.id == "hypertension_event" })
        XCTAssertFalse(hypertension.availability.isAvailable(
            on: .macOS,
            version: OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 0)
        ))
        XCTAssertTrue(hypertension.availability.isAvailable(
            on: .macOS,
            version: OperatingSystemVersion(majorVersion: 26, minorVersion: 2, patchVersion: 0)
        ))
    }

    func testSpecializedMetricsHaveExactCatalogKindsSelectionAndLegacyAvailability() throws {
        let expected: [(String, String, HealthKitRecordKind, HealthMetricAvailability)] = [
            ("electrocardiograms", HealthKitRecordCatalog.electrocardiogramIdentifier, .electrocardiogram, .healthKit14),
            ("heartbeat_series", HealthKitRecordCatalog.heartbeatSeriesIdentifier, .heartbeatSeries, .healthKit13),
            ("audiograms", HealthKitRecordCatalog.audiogramIdentifier, .audiogram, .healthKit13),
            ("gad7_assessments", HealthKitRecordCatalog.gad7AssessmentIdentifier, .scoredAssessment, .healthKit18),
            ("phq9_assessments", HealthKitRecordCatalog.phq9AssessmentIdentifier, .scoredAssessment, .healthKit18),
        ]

        for (metricID, identifier, kind, availability) in expected {
            let metric = try XCTUnwrap(HealthMetrics.all.first { $0.id == metricID })
            XCTAssertTrue(metric.isArchiveOnly)
            XCTAssertEqual(metric.availability, availability)
            XCTAssertTrue(metric.selectionDetail.contains("Source records only"))
            let plan = HealthKitRecordCatalog.attributedSelectionPlan(enabledMetricIDs: [metricID])
            XCTAssertEqual(plan.count, 1)
            XCTAssertEqual(plan.first?.objectTypeIdentifier, identifier)
            XCTAssertEqual(plan.first?.recordKind, kind)
            XCTAssertEqual(plan.first?.directMetricIDs, [metricID])
            XCTAssertEqual(plan.first?.dependencyMetricIDs, [])
        }

        let iOS12 = OperatingSystemVersion(majorVersion: 12, minorVersion: 4, patchVersion: 0)
        let iOS13 = OperatingSystemVersion(majorVersion: 13, minorVersion: 0, patchVersion: 0)
        let iOS14 = OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)
        let iOS17 = OperatingSystemVersion(majorVersion: 17, minorVersion: 7, patchVersion: 0)
        let iOS18 = OperatingSystemVersion(majorVersion: 18, minorVersion: 0, patchVersion: 0)
        XCTAssertFalse(HealthMetricAvailability.healthKit13.isAvailable(on: .iOS, version: iOS12))
        XCTAssertTrue(HealthMetricAvailability.healthKit13.isAvailable(on: .iOS, version: iOS13))
        XCTAssertFalse(HealthMetricAvailability.healthKit14.isAvailable(on: .iOS, version: iOS13))
        XCTAssertTrue(HealthMetricAvailability.healthKit14.isAvailable(on: .iOS, version: iOS14))
        XCTAssertFalse(HealthMetricAvailability.healthKit18.isAvailable(on: .iOS, version: iOS17))
        XCTAssertTrue(HealthMetricAvailability.healthKit18.isAvailable(on: .iOS, version: iOS18))
        XCTAssertFalse(HealthMetricAvailability.workoutKit17.isAvailable(on: .iOS, version: iOS14))
        XCTAssertTrue(HealthMetricAvailability.workoutKit17.isAvailable(on: .iOS, version: iOS17))
        XCTAssertFalse(HealthMetricAvailability.workoutKit17.isAvailable(
            on: .macOS,
            version: OperatingSystemVersion(majorVersion: 14, minorVersion: 9, patchVersion: 0)
        ))
        XCTAssertTrue(HealthMetricAvailability.workoutKit17.isAvailable(
            on: .macOS,
            version: OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)
        ))
    }

    func testSpecializedAuthorizationDescriptorsResolveOnlyToTheirProperObjectClasses() throws {
        let specializedMetricIDs = [
            "electrocardiograms", "heartbeat_series", "audiograms",
            "gad7_assessments", "phq9_assessments",
        ]
        let descriptors = HealthKitRecordCatalog.authorizationDescriptors(
            enabledMetricIDs: specializedMetricIDs
        )

        for descriptor in descriptors where HealthKitRecordCatalog.isRuntimeAvailable(descriptor) {
            let objectType = try XCTUnwrap(HealthKitRecordCatalog.resolveObjectType(descriptor))
            XCTAssertEqual(objectType.identifier, descriptor.objectTypeIdentifier)
            switch descriptor.recordKind {
            case .electrocardiogram:
                XCTAssertTrue(objectType is HKElectrocardiogramType)
            case .audiogram:
                XCTAssertTrue(objectType is HKAudiogramSampleType)
            case .heartbeatSeries:
                XCTAssertTrue(objectType is HKSeriesType)
                XCTAssertEqual(objectType.identifier, HKSeriesType.heartbeat().identifier)
            case .scoredAssessment:
                if #available(iOS 18.0, macOS 15.0, *) {
                    XCTAssertTrue(objectType is HKScoredAssessmentType)
                }
            default:
                XCTFail("Unexpected specialized authorization type: \(descriptor.recordKind)")
            }
        }
    }

    func testRuntimeAuthorizationResolutionDropsUnsupportedAndNilObjectTypes() {
        let resolved = HealthKitRecordCatalog.resolvedAuthorizationObjectTypes()
        let resolvedIdentifiers = Set(resolved.map(\.identifier))

        XCTAssertTrue(resolvedIdentifiers.contains("HKQuantityTypeIdentifierStepCount"))
        XCTAssertFalse(resolvedIdentifiers.contains(HealthKitRecordCatalog.medicationDoseEventIdentifier))
        XCTAssertFalse(resolvedIdentifiers.contains(HealthKitRecordCatalog.bloodPressureCorrelationIdentifier))
        XCTAssertFalse(resolvedIdentifiers.contains(HealthKitRecordCatalog.foodCorrelationIdentifier))
        XCTAssertTrue(resolved.allSatisfy { !$0.identifier.isEmpty })

        for descriptor in HealthKitRecordCatalog.runtimeAuthorizationDescriptors {
            guard let type = HealthKitRecordCatalog.resolveObjectType(descriptor) else {
                if HealthKitRecordCatalog.requiresResolvedObjectType(descriptor) {
                    XCTFail("Runtime-available selected type did not resolve: \(descriptor.objectTypeIdentifier)")
                }
                continue
            }
            XCTAssertTrue(resolved.contains(type))
        }
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

    func testCorrelationAuthorizationUsesComponentTypesAndExcludesDisallowedContainers() {
        let bloodPressureDescriptors = HealthKitRecordCatalog.authorizationDescriptors(
            enabledMetricIDs: ["blood_pressure_systolic"]
        )
        let bloodPressureIdentifiers = Set(bloodPressureDescriptors.map(\.objectTypeIdentifier))
        XCTAssertEqual(bloodPressureIdentifiers, [
            "HKQuantityTypeIdentifierBloodPressureDiastolic",
            "HKQuantityTypeIdentifierBloodPressureSystolic",
        ])

        let foodDescriptors = HealthKitRecordCatalog.authorizationDescriptors(
            enabledMetricIDs: ["dietary_energy"]
        )
        let foodIdentifiers = Set(foodDescriptors.map(\.objectTypeIdentifier))
        XCTAssertTrue(foodIdentifiers.contains("HKQuantityTypeIdentifierDietaryEnergyConsumed"))
        XCTAssertTrue(foodIdentifiers.isDisjoint(with: HealthKitRecordCatalog.standardAuthorizationDisallowedIdentifiers))
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
        XCTAssertEqual(standHour.metricIDs, ["stand_hours"])
        XCTAssertEqual(
            standTime.dependencyReasons[HealthKitRecordCatalog.appleStandHourIdentifier],
            .appleStandHourCompatibility
        )
    }

    func testWorkoutSelectionIncludesEveryCanonicalPublicSampleDependency() throws {
        let plan = HealthKitRecordCatalog.selectionPlan(enabledMetricIDs: ["workouts"])
        let attributedPlan = HealthKitRecordCatalog.attributedSelectionPlan(
            enabledMetricIDs: ["workouts"]
        )
        let identifiers = Set(plan.map(\.objectTypeIdentifier))
        let workout = try XCTUnwrap(
            plan.first { $0.objectTypeIdentifier == HealthKitRecordCatalog.workoutTypeIdentifier }
        )

        XCTAssertTrue(identifiers.contains(HealthKitRecordCatalog.workoutRouteTypeIdentifier))
        XCTAssertTrue(identifiers.contains("HKQuantityTypeIdentifierHeartRate"))
        XCTAssertTrue(identifiers.contains("HKQuantityTypeIdentifierDistanceWalkingRunning"))
        XCTAssertTrue(identifiers.contains("HKQuantityTypeIdentifierRunningPower"))
        XCTAssertTrue(identifiers.contains("HKQuantityTypeIdentifierCyclingCadence"))
        XCTAssertTrue(identifiers.contains(HKCategoryTypeIdentifier.headache.rawValue))
        XCTAssertTrue(identifiers.contains(HealthKitRecordCatalog.electrocardiogramIdentifier))
        XCTAssertTrue(identifiers.contains(HealthKitRecordCatalog.foodCorrelationIdentifier))
        XCTAssertFalse(identifiers.contains(HealthKitRecordCatalog.scheduledWorkoutPlanIdentifier))
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
        XCTAssertEqual(
            workout.dependencyReasons[HKCategoryTypeIdentifier.headache.rawValue],
            .workoutAssociatedSample
        )
        XCTAssertTrue(attributedPlan.filter {
            HealthKitRecordCatalog.isWorkoutAssociatedSampleDescriptor($0.descriptor)
        }.allSatisfy(HealthKitRecordCatalog.isWorkoutAssociationOnly))

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

    func testRelationshipDependenciesHaveNoOrdinaryDayAttribution() throws {
        let foodPlan = HealthKitRecordCatalog.attributedSelectionPlan(
            enabledMetricIDs: ["dietary_protein"]
        )
        let protein = try XCTUnwrap(foodPlan.first {
            $0.objectTypeIdentifier == HKQuantityTypeIdentifier.dietaryProtein.rawValue
        })
        XCTAssertEqual(
            HealthKitRecordCatalog.ordinaryDayAttribution(for: protein),
            HealthKitMetricAttribution(directMetricIDs: ["dietary_protein"])
        )
        let unrelatedNutrients = foodPlan.filter {
            $0.objectTypeIdentifier != protein.objectTypeIdentifier &&
                $0.objectTypeIdentifier != HealthKitRecordCatalog.foodCorrelationIdentifier
        }
        XCTAssertTrue(unrelatedNutrients.allSatisfy {
            HealthKitRecordCatalog.isRelationshipAssociationOnly($0)
        })
        let food = try XCTUnwrap(foodPlan.first {
            $0.objectTypeIdentifier == HealthKitRecordCatalog.foodCorrelationIdentifier
        })
        XCTAssertEqual(
            HealthKitRecordCatalog.relationshipOwnerAttribution(for: food),
            HealthKitMetricAttribution(directMetricIDs: ["dietary_protein"])
        )

        let pressurePlan = HealthKitRecordCatalog.attributedSelectionPlan(
            enabledMetricIDs: ["blood_pressure_systolic"]
        )
        let diastolic = try XCTUnwrap(pressurePlan.first {
            $0.objectTypeIdentifier == HKQuantityTypeIdentifier.bloodPressureDiastolic.rawValue
        })
        XCTAssertTrue(HealthKitRecordCatalog.isRelationshipAssociationOnly(diastolic))
        let correlation = try XCTUnwrap(pressurePlan.first {
            $0.objectTypeIdentifier == HealthKitRecordCatalog.bloodPressureCorrelationIdentifier
        })
        XCTAssertEqual(
            HealthKitRecordCatalog.relationshipOwnerAttribution(for: correlation),
            HealthKitMetricAttribution(directMetricIDs: ["blood_pressure_systolic"])
        )
    }

    func testSpecialAuthorizationWorkoutAssociationsRequireTheirOwnMetricSelection() {
        let workoutOnly = HealthKitRecordCatalog.attributedSelectionPlan(
            enabledMetricIDs: ["workouts"]
        )
        let specialIdentifiers: Set<String> = [
            HealthKitRecordCatalog.cdaDocumentIdentifier,
            HealthKitRecordCatalog.verifiableClinicalRecordIdentifier,
            HealthKitRecordCatalog.visionPrescriptionIdentifier,
            HealthKitRecordCatalog.medicationDoseEventIdentifier,
        ]
        XCTAssertTrue(Set(workoutOnly.map(\.objectTypeIdentifier)).isDisjoint(with: specialIdentifiers))

        for metricID in [
            "cda_documents", "verifiable_clinical_records",
            "vision_prescriptions", "medications",
        ] {
            let plan = HealthKitRecordCatalog.attributedSelectionPlan(
                enabledMetricIDs: ["workouts", metricID]
            )
            let special = plan.first { $0.directMetricIDs.contains(metricID) }
            XCTAssertNotNil(special)
            XCTAssertTrue(
                special.map {
                    HealthKitRecordCatalog.requiresDirectSelectionForWorkoutAssociation(
                        $0.recordKind
                    )
                } ?? false
            )
        }
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
        if #available(iOS 18.0, macOS 15.0, *) {
            XCTAssertEqual(
                HealthKitRecordCatalog.stateOfMindIdentifier,
                HKSampleType.stateOfMindType().identifier
            )
        }
        XCTAssertEqual(medication.recordKind, .medicationDoseEvent)
        XCTAssertEqual(medication.metricIDs, ["medications"])
        if #available(iOS 26.0, macOS 26.0, *) {
            XCTAssertEqual(
                HealthKitRecordCatalog.medicationDoseEventIdentifier,
                HKMedicationDoseEventType.medicationDoseEventType().identifier
            )
            XCTAssertEqual(
                HealthKitRecordCatalog.userAnnotatedMedicationIdentifier,
                HKObjectType.userAnnotatedMedicationType().identifier
            )
        }
        XCTAssertTrue(HealthKitRecordCatalog.specialAuthorizationDescriptors.contains(medication))
        XCTAssertFalse(HealthKitRecordCatalog.authorizationDescriptors.contains(medication))
    }

    func testScheduledWorkoutPlansAreExplicitArchiveOnlyWithoutHealthKitAuthorization() throws {
        let metric = try XCTUnwrap(
            HealthMetrics.all.first { $0.id == "scheduled_workout_plans" }
        )
        XCTAssertTrue(metric.isArchiveOnly)
        XCTAssertFalse(metric.isEnabledByDefault)
        XCTAssertEqual(metric.availability, .workoutKit17)

        let plan = HealthKitRecordCatalog.attributedSelectionPlan(
            enabledMetricIDs: [metric.id]
        )
        XCTAssertEqual(plan.count, 1)
        let entry = try XCTUnwrap(plan.first)
        XCTAssertEqual(entry.objectTypeIdentifier, HealthKitRecordCatalog.scheduledWorkoutPlanIdentifier)
        XCTAssertEqual(entry.recordKind, .other("scheduledWorkoutPlan"))
        XCTAssertEqual(entry.directMetricIDs, [metric.id])
        XCTAssertFalse(HealthKitRecordCatalog.requiresResolvedObjectType(entry.descriptor))
        XCTAssertTrue(HealthKitRecordCatalog.authorizationDescriptors(
            enabledMetricIDs: [metric.id]
        ).isEmpty)
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
            HealthKitRecordCatalog.descriptors.filter {
                $0.recordKind != .medicationDoseEvent &&
                $0.recordKind != .document &&
                $0.recordKind != .verifiableClinicalRecord &&
                $0.recordKind != .visionPrescription &&
                $0.objectTypeIdentifier != HealthKitRecordCatalog.scheduledWorkoutPlanIdentifier &&
                !HealthKitRecordCatalog.standardAuthorizationDisallowedIdentifiers.contains($0.objectTypeIdentifier)
            }
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
