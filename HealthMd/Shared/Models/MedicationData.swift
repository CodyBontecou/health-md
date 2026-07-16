//
//  MedicationData.swift
//  HealthMd
//
//  Platform-agnostic medication export models populated from HealthKit's
//  read-only medications API on iOS/iPadOS/macOS 26+.
//

import Foundation

// MARK: - Medication Metadata

struct MedicationCoding: Codable, Hashable, Sendable {
    var system: String
    var version: String?
    var code: String
}

struct Medication: Identifiable, Codable, Hashable, Sendable {
    /// Best-effort stable export identifier for the HealthKit medication concept.
    /// The adapter prefers clinical codings such as RxNorm and otherwise hashes
    /// HealthKit's public secure-coded identifier without treating descriptions as identity.
    var conceptIdentifier: String
    var displayName: String
    var nickname: String?
    var generalForm: String
    var isArchived: Bool
    var hasSchedule: Bool
    var relatedCodings: [MedicationCoding]

    var id: String { conceptIdentifier }

    var exportName: String {
        if let nickname, !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nickname
        }
        return displayName
    }

    var rxNormCodes: [String] {
        relatedCodings
            .filter { $0.system == "http://www.nlm.nih.gov/research/umls/rxnorm" }
            .map(\.code)
    }
}

// MARK: - Medication Dose Events

enum MedicationDoseStatus: String, Codable, Sendable {
    case taken
    case skipped
    case snoozed
    case notInteracted = "not_interacted"
    case notificationNotSent = "notification_not_sent"
    case notLogged = "not_logged"
    case unknown

    var displayName: String {
        switch self {
        case .taken: return "Taken"
        case .skipped: return "Skipped"
        case .snoozed: return "Snoozed"
        case .notInteracted: return "Not interacted"
        case .notificationNotSent: return "Notification not sent"
        case .notLogged: return "Not logged"
        case .unknown: return "Unknown"
        }
    }

    /// HealthKit uses several non-`skipped` statuses for scheduled doses that
    /// were not actually taken (for example, a dose that was never logged).
    /// Export summaries only expose taken/skipped counts today, so group every
    /// known non-taken status with skipped rather than letting missed doses look
    /// like successful adherence.
    var countsAsSkippedDose: Bool {
        switch self {
        case .skipped, .snoozed, .notInteracted, .notificationNotSent, .notLogged:
            return true
        case .taken, .unknown:
            return false
        }
    }
}

enum MedicationDoseScheduleType: String, Codable, Sendable {
    case asNeeded = "as_needed"
    case scheduled
    case unknown

    var displayName: String {
        switch self {
        case .asNeeded: return "As needed"
        case .scheduled: return "Scheduled"
        case .unknown: return "Unknown"
        }
    }
}

struct MedicationDoseEvent: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var medicationConceptIdentifier: String
    var medicationName: String?
    var startDate: Date
    var endDate: Date
    var scheduledDate: Date?
    var doseQuantity: Double?
    var scheduledDoseQuantity: Double?
    var unit: String
    var logStatus: MedicationDoseStatus
    var scheduleType: MedicationDoseScheduleType
    var metadata: [String: String]

    init(
        id: UUID,
        medicationConceptIdentifier: String,
        medicationName: String?,
        startDate: Date,
        endDate: Date,
        scheduledDate: Date?,
        doseQuantity: Double?,
        scheduledDoseQuantity: Double?,
        unit: String,
        logStatus: MedicationDoseStatus,
        scheduleType: MedicationDoseScheduleType,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.medicationConceptIdentifier = medicationConceptIdentifier
        self.medicationName = medicationName
        self.startDate = startDate
        self.endDate = endDate
        self.scheduledDate = scheduledDate
        self.doseQuantity = doseQuantity
        self.scheduledDoseQuantity = scheduledDoseQuantity
        self.unit = unit
        self.logStatus = logStatus
        self.scheduleType = scheduleType
        self.metadata = metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        medicationConceptIdentifier = try container.decode(String.self, forKey: .medicationConceptIdentifier)
        medicationName = try container.decodeIfPresent(String.self, forKey: .medicationName)
        startDate = try container.decode(Date.self, forKey: .startDate)
        endDate = try container.decode(Date.self, forKey: .endDate)
        scheduledDate = try container.decodeIfPresent(Date.self, forKey: .scheduledDate)
        doseQuantity = try container.decodeIfPresent(Double.self, forKey: .doseQuantity)
        scheduledDoseQuantity = try container.decodeIfPresent(Double.self, forKey: .scheduledDoseQuantity)
        unit = try container.decode(String.self, forKey: .unit)
        logStatus = try container.decode(MedicationDoseStatus.self, forKey: .logStatus)
        scheduleType = try container.decode(MedicationDoseScheduleType.self, forKey: .scheduleType)
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    }

    var displayMedicationName: String {
        medicationName ?? medicationConceptIdentifier
    }
}

// MARK: - Medication Export Container

struct MedicationsData: Codable, Hashable, Sendable {
    var medications: [Medication] = []
    var doseEvents: [MedicationDoseEvent] = []

    var hasData: Bool {
        !medications.isEmpty || !doseEvents.isEmpty
    }

    var activeMedications: [Medication] {
        medications.filter { !$0.isArchived }
    }

    var archivedMedications: [Medication] {
        medications.filter(\.isArchived)
    }

    var takenDoseEvents: [MedicationDoseEvent] {
        doseEvents.filter { $0.logStatus == .taken }
    }

    var skippedDoseEvents: [MedicationDoseEvent] {
        doseEvents.filter { $0.logStatus.countsAsSkippedDose }
    }
}
