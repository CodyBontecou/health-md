import Foundation

/// Portable symbolic names for the public integer values of every category type
/// currently present in `HealthKitRecordCatalog`.
///
/// HealthKit's category payload always keeps the original integer. This table is
/// only an additive index for values documented by the SDK and deliberately
/// returns nil for future integers instead of guessing or replacing the raw value.
enum HealthKitCategoryValueSymbol {
    nonisolated static func symbol(
        objectTypeIdentifier: String,
        rawValue: Int64
    ) -> String? {
        knownValuesByObjectTypeIdentifier[objectTypeIdentifier]?[rawValue]
    }

    nonisolated static let knownObjectTypeIdentifiers: Set<String> =
        Set(knownValuesByObjectTypeIdentifier.keys)

    nonisolated static let knownValuesByObjectTypeIdentifier: [String: [Int64: String]] = {
        var result: [String: [Int64: String]] = [:]

        func assign(_ identifiers: [String], _ values: [Int64: String]) {
            for identifier in identifiers {
                result[identifier] = values
            }
        }

        assign([
            "HKCategoryTypeIdentifierHighHeartRateEvent",
            "HKCategoryTypeIdentifierHypertensionEvent",
            "HKCategoryTypeIdentifierIrregularHeartRhythmEvent",
            "HKCategoryTypeIdentifierLowHeartRateEvent",
            "HKCategoryTypeIdentifierMindfulSession",
            "HKCategoryTypeIdentifierHandwashingEvent",
            "HKCategoryTypeIdentifierToothbrushingEvent",
            "HKCategoryTypeIdentifierInfrequentMenstrualCycles",
            "HKCategoryTypeIdentifierIntermenstrualBleeding",
            "HKCategoryTypeIdentifierIrregularMenstrualCycles",
            "HKCategoryTypeIdentifierLactation",
            "HKCategoryTypeIdentifierPersistentIntermenstrualBleeding",
            "HKCategoryTypeIdentifierPregnancy",
            "HKCategoryTypeIdentifierProlongedMenstrualPeriods",
            "HKCategoryTypeIdentifierSexualActivity",
            "HKCategoryTypeIdentifierSleepApneaEvent",
        ], [
            0: "notApplicable",
        ])

        assign([
            "HKCategoryTypeIdentifierAbdominalCramps",
            "HKCategoryTypeIdentifierAcne",
            "HKCategoryTypeIdentifierBladderIncontinence",
            "HKCategoryTypeIdentifierBloating",
            "HKCategoryTypeIdentifierBreastPain",
            "HKCategoryTypeIdentifierChestTightnessOrPain",
            "HKCategoryTypeIdentifierChills",
            "HKCategoryTypeIdentifierConstipation",
            "HKCategoryTypeIdentifierCoughing",
            "HKCategoryTypeIdentifierDiarrhea",
            "HKCategoryTypeIdentifierDizziness",
            "HKCategoryTypeIdentifierDrySkin",
            "HKCategoryTypeIdentifierFainting",
            "HKCategoryTypeIdentifierFatigue",
            "HKCategoryTypeIdentifierFever",
            "HKCategoryTypeIdentifierGeneralizedBodyAche",
            "HKCategoryTypeIdentifierHairLoss",
            "HKCategoryTypeIdentifierHeadache",
            "HKCategoryTypeIdentifierHeartburn",
            "HKCategoryTypeIdentifierHotFlashes",
            "HKCategoryTypeIdentifierLossOfSmell",
            "HKCategoryTypeIdentifierLossOfTaste",
            "HKCategoryTypeIdentifierLowerBackPain",
            "HKCategoryTypeIdentifierMemoryLapse",
            "HKCategoryTypeIdentifierNausea",
            "HKCategoryTypeIdentifierNightSweats",
            "HKCategoryTypeIdentifierPelvicPain",
            "HKCategoryTypeIdentifierRapidPoundingOrFlutteringHeartbeat",
            "HKCategoryTypeIdentifierRunnyNose",
            "HKCategoryTypeIdentifierShortnessOfBreath",
            "HKCategoryTypeIdentifierSinusCongestion",
            "HKCategoryTypeIdentifierSkippedHeartbeat",
            "HKCategoryTypeIdentifierSoreThroat",
            "HKCategoryTypeIdentifierVaginalDryness",
            "HKCategoryTypeIdentifierVomiting",
            "HKCategoryTypeIdentifierWheezing",
        ], [
            0: "unspecified",
            1: "notPresent",
            2: "mild",
            3: "moderate",
            4: "severe",
        ])

        assign([
            "HKCategoryTypeIdentifierMoodChanges",
            "HKCategoryTypeIdentifierSleepChanges",
        ], [
            0: "present",
            1: "notPresent",
        ])

        assign(["HKCategoryTypeIdentifierAppetiteChanges"], [
            0: "unspecified",
            1: "noChange",
            2: "decreased",
            3: "increased",
        ])
        assign(["HKCategoryTypeIdentifierAppleStandHour"], [
            0: "stood",
            1: "idle",
        ])
        assign(["HKCategoryTypeIdentifierAppleWalkingSteadinessEvent"], [
            1: "initialLow",
            2: "initialVeryLow",
            3: "repeatLow",
            4: "repeatVeryLow",
        ])
        assign(["HKCategoryTypeIdentifierCervicalMucusQuality"], [
            1: "dry",
            2: "sticky",
            3: "creamy",
            4: "watery",
            5: "eggWhite",
        ])
        assign(["HKCategoryTypeIdentifierContraceptive"], [
            1: "unspecified",
            2: "implant",
            3: "injection",
            4: "intrauterineDevice",
            5: "intravaginalRing",
            6: "oral",
            7: "patch",
        ])
        // The SDK resolves the historical AudioExposureEvent raw identifier on
        // some runtimes. Keep both public spellings mapped to the same enum.
        assign([
            "HKCategoryTypeIdentifierAudioExposureEvent",
            "HKCategoryTypeIdentifierEnvironmentalAudioExposureEvent",
        ], [
            1: "momentaryLimit",
        ])
        assign(["HKCategoryTypeIdentifierHeadphoneAudioExposureEvent"], [
            1: "sevenDayLimit",
        ])
        assign(["HKCategoryTypeIdentifierLowCardioFitnessEvent"], [
            1: "lowFitness",
        ])
        assign([
            "HKCategoryTypeIdentifierBleedingAfterPregnancy",
            "HKCategoryTypeIdentifierBleedingDuringPregnancy",
            "HKCategoryTypeIdentifierMenstrualFlow",
        ], [
            1: "unspecified",
            2: "light",
            3: "medium",
            4: "heavy",
            5: "none",
        ])
        assign(["HKCategoryTypeIdentifierOvulationTestResult"], [
            1: "negative",
            2: "luteinizingHormoneSurge",
            3: "indeterminate",
            4: "estrogenSurge",
        ])
        assign(["HKCategoryTypeIdentifierPregnancyTestResult"], [
            1: "negative",
            2: "positive",
            3: "indeterminate",
        ])
        assign(["HKCategoryTypeIdentifierProgesteroneTestResult"], [
            1: "negative",
            2: "positive",
            3: "indeterminate",
        ])
        assign(["HKCategoryTypeIdentifierSleepAnalysis"], [
            0: "inBed",
            1: "asleepUnspecified",
            2: "awake",
            3: "asleepCore",
            4: "asleepDeep",
            5: "asleepREM",
        ])

        return result
    }()
}
