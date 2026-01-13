//
//  AdvancedExportSettings.swift
//  HealthToObsidian
//
//  Created by Claude on 2026-01-13.
//

import Foundation
import Combine

enum ExportFormat: String, CaseIterable, Codable {
    case markdown = "Markdown"
    case json = "JSON"
    case csv = "CSV"

    var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .json: return "json"
        case .csv: return "csv"
        }
    }
}

struct DataTypeSelection: Codable {
    var sleep: Bool = true
    var activity: Bool = true
    var vitals: Bool = true
    var body: Bool = true
    var workouts: Bool = true

    var hasAnySelected: Bool {
        sleep || activity || vitals || body || workouts
    }
}

class AdvancedExportSettings: ObservableObject {
    @Published var dataTypes: DataTypeSelection {
        didSet { save() }
    }

    @Published var exportFormat: ExportFormat {
        didSet { save() }
    }

    @Published var includeMetadata: Bool {
        didSet { save() }
    }

    @Published var groupByCategory: Bool {
        didSet { save() }
    }

    private let userDefaults = UserDefaults.standard
    private let dataTypesKey = "advancedExportSettings.dataTypes"
    private let formatKey = "advancedExportSettings.format"
    private let metadataKey = "advancedExportSettings.metadata"
    private let groupByCategoryKey = "advancedExportSettings.groupByCategory"

    init() {
        // Load data types
        if let data = userDefaults.data(forKey: dataTypesKey),
           let decoded = try? JSONDecoder().decode(DataTypeSelection.self, from: data) {
            self.dataTypes = decoded
        } else {
            self.dataTypes = DataTypeSelection()
        }

        // Load format
        if let formatString = userDefaults.string(forKey: formatKey),
           let format = ExportFormat(rawValue: formatString) {
            self.exportFormat = format
        } else {
            self.exportFormat = .markdown
        }

        // Load metadata option
        self.includeMetadata = userDefaults.bool(forKey: metadataKey)
        if userDefaults.object(forKey: metadataKey) == nil {
            self.includeMetadata = true // Default to true
        }

        // Load group by category option
        self.groupByCategory = userDefaults.bool(forKey: groupByCategoryKey)
        if userDefaults.object(forKey: groupByCategoryKey) == nil {
            self.groupByCategory = true // Default to true
        }
    }

    private func save() {
        // Save data types
        if let encoded = try? JSONEncoder().encode(dataTypes) {
            userDefaults.set(encoded, forKey: dataTypesKey)
        }

        // Save format
        userDefaults.set(exportFormat.rawValue, forKey: formatKey)

        // Save metadata option
        userDefaults.set(includeMetadata, forKey: metadataKey)

        // Save group by category option
        userDefaults.set(groupByCategory, forKey: groupByCategoryKey)
    }

    func reset() {
        dataTypes = DataTypeSelection()
        exportFormat = .markdown
        includeMetadata = true
        groupByCategory = true
    }
}
