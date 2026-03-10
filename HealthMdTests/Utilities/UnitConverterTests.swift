//
//  UnitConverterTests.swift
//  HealthMdTests
//
//  Tests for UnitConverter - ensures accurate metric/imperial conversions
//

import XCTest
@testable import Health_md

final class UnitConverterTests: XCTestCase {
    
    // MARK: - Distance Conversion Tests
    
    func testConvertDistance_metersToKilometers() {
        let converter = UnitConverter(preference: .metric)
        XCTAssertEqual(converter.convertDistance(1000, toLarge: true), 1.0, accuracy: 0.001)
        XCTAssertEqual(converter.convertDistance(5000, toLarge: true), 5.0, accuracy: 0.001)
        XCTAssertEqual(converter.convertDistance(2500, toLarge: true), 2.5, accuracy: 0.001)
    }
    
    func testConvertDistance_metersToMiles() {
        let converter = UnitConverter(preference: .imperial)
        // 1609.344 meters = 1 mile
        XCTAssertEqual(converter.convertDistance(1609.344, toLarge: true), 1.0, accuracy: 0.001)
        // 5000 meters ≈ 3.107 miles
        XCTAssertEqual(converter.convertDistance(5000, toLarge: true), 3.107, accuracy: 0.01)
    }
    
    func testConvertDistance_metersToFeet() {
        let converter = UnitConverter(preference: .imperial)
        // 1 meter = 3.28084 feet
        XCTAssertEqual(converter.convertDistance(1, toLarge: false), 3.28084, accuracy: 0.001)
        XCTAssertEqual(converter.convertDistance(100, toLarge: false), 328.084, accuracy: 0.01)
    }
    
    func testFormatDistance_metric_kilometers() {
        let converter = UnitConverter(preference: .metric)
        XCTAssertEqual(converter.formatDistance(1500), "1.50 km")
        XCTAssertEqual(converter.formatDistance(5000), "5.00 km")
    }
    
    func testFormatDistance_metric_meters() {
        let converter = UnitConverter(preference: .metric)
        XCTAssertEqual(converter.formatDistance(500), "500 m")
        XCTAssertEqual(converter.formatDistance(999), "999 m")
    }
    
    func testFormatDistance_imperial_miles() {
        let converter = UnitConverter(preference: .imperial)
        // 1609.344 meters = 1 mile
        XCTAssertEqual(converter.formatDistance(1609.344), "1.00 mi")
        // 5000 meters ≈ 3.11 miles
        XCTAssertTrue(converter.formatDistance(5000).contains("3.1"))
    }
    
    func testFormatDistance_imperial_feet() {
        let converter = UnitConverter(preference: .imperial)
        // 30 meters ≈ 98 feet, less than 0.1 mile so should show feet
        let result = converter.formatDistance(30)
        XCTAssertTrue(result.contains("ft"))
    }
    
    func testDistanceUnit() {
        let metricConverter = UnitConverter(preference: .metric)
        let imperialConverter = UnitConverter(preference: .imperial)
        
        XCTAssertEqual(metricConverter.distanceUnit(large: true), "km")
        XCTAssertEqual(metricConverter.distanceUnit(large: false), "m")
        XCTAssertEqual(imperialConverter.distanceUnit(large: true), "mi")
        XCTAssertEqual(imperialConverter.distanceUnit(large: false), "ft")
    }
    
    // MARK: - Weight Conversion Tests
    
    func testConvertWeight_kgToKg() {
        let converter = UnitConverter(preference: .metric)
        XCTAssertEqual(converter.convertWeight(70), 70, accuracy: 0.001)
    }
    
    func testConvertWeight_kgToLbs() {
        let converter = UnitConverter(preference: .imperial)
        // 70 kg = 154.32 lbs (known value from requirements)
        XCTAssertEqual(converter.convertWeight(70), 154.32, accuracy: 0.01)
        // 1 kg = 2.20462 lbs
        XCTAssertEqual(converter.convertWeight(1), 2.20462, accuracy: 0.001)
        // 100 kg = 220.462 lbs
        XCTAssertEqual(converter.convertWeight(100), 220.462, accuracy: 0.01)
    }
    
    func testFormatWeight_metric() {
        let converter = UnitConverter(preference: .metric)
        XCTAssertEqual(converter.formatWeight(70), "70.0 kg")
        XCTAssertEqual(converter.formatWeight(65.5), "65.5 kg")
    }
    
    func testFormatWeight_imperial() {
        let converter = UnitConverter(preference: .imperial)
        // 70 kg ≈ 154.3 lbs
        XCTAssertTrue(converter.formatWeight(70).contains("154"))
        XCTAssertTrue(converter.formatWeight(70).contains("lbs"))
    }
    
    func testWeightUnit() {
        let metricConverter = UnitConverter(preference: .metric)
        let imperialConverter = UnitConverter(preference: .imperial)
        
        XCTAssertEqual(metricConverter.weightUnit(), "kg")
        XCTAssertEqual(imperialConverter.weightUnit(), "lbs")
    }
    
    // MARK: - Height Conversion Tests
    
    func testConvertHeight_metersToCm() {
        let converter = UnitConverter(preference: .metric)
        XCTAssertEqual(converter.convertHeight(1.75), 175, accuracy: 0.01)
        XCTAssertEqual(converter.convertHeight(1.80), 180, accuracy: 0.01)
    }
    
    func testConvertHeight_metersToInches() {
        let converter = UnitConverter(preference: .imperial)
        // 1.75m = 68.9 inches (5'9" = 69 inches)
        XCTAssertEqual(converter.convertHeight(1.75), 68.9, accuracy: 0.1)
    }
    
    func testFormatHeight_metric() {
        let converter = UnitConverter(preference: .metric)
        XCTAssertEqual(converter.formatHeight(1.75), "175.0 cm")
        XCTAssertEqual(converter.formatHeight(1.80), "180.0 cm")
    }
    
    func testFormatHeight_imperial() {
        let converter = UnitConverter(preference: .imperial)
        // 1.75m = 68.9 inches = 5 feet 8 inches (truncated)
        let result = converter.formatHeight(1.75)
        XCTAssertTrue(result.contains("5'8\""), "Expected 5'8\" but got \(result)")
    }
    
    func testFormatHeight_imperial_roundValues() {
        let converter = UnitConverter(preference: .imperial)
        // 1.83m ≈ 6'0"
        let result = converter.formatHeight(1.8288)
        XCTAssertTrue(result.contains("6'0\""), "Expected 6'0\" but got \(result)")
    }
    
    func testHeightUnit() {
        let metricConverter = UnitConverter(preference: .metric)
        let imperialConverter = UnitConverter(preference: .imperial)
        
        XCTAssertEqual(metricConverter.heightUnit(), "cm")
        XCTAssertEqual(imperialConverter.heightUnit(), "ft/in")
    }
    
    // MARK: - Temperature Conversion Tests
    
    func testConvertTemperature_celsiusToCelsius() {
        let converter = UnitConverter(preference: .metric)
        XCTAssertEqual(converter.convertTemperature(37), 37, accuracy: 0.001)
    }
    
    func testConvertTemperature_celsiusToFahrenheit() {
        let converter = UnitConverter(preference: .imperial)
        // Known values from requirements:
        // 37°C = 98.6°F (body temperature)
        XCTAssertEqual(converter.convertTemperature(37), 98.6, accuracy: 0.1)
        // 0°C = 32°F (freezing point)
        XCTAssertEqual(converter.convertTemperature(0), 32, accuracy: 0.001)
        // 100°C = 212°F (boiling point)
        XCTAssertEqual(converter.convertTemperature(100), 212, accuracy: 0.001)
    }
    
    func testFormatTemperature_metric() {
        let converter = UnitConverter(preference: .metric)
        XCTAssertEqual(converter.formatTemperature(37), "37.0°C")
        XCTAssertEqual(converter.formatTemperature(36.5), "36.5°C")
    }
    
    func testFormatTemperature_imperial() {
        let converter = UnitConverter(preference: .imperial)
        // 37°C = 98.6°F
        XCTAssertEqual(converter.formatTemperature(37), "98.6°F")
    }
    
    func testTemperatureUnit() {
        let metricConverter = UnitConverter(preference: .metric)
        let imperialConverter = UnitConverter(preference: .imperial)
        
        XCTAssertEqual(metricConverter.temperatureUnit(), "°C")
        XCTAssertEqual(imperialConverter.temperatureUnit(), "°F")
    }
    
    // MARK: - Volume Conversion Tests
    
    func testConvertVolume_litersToLiters() {
        let converter = UnitConverter(preference: .metric)
        XCTAssertEqual(converter.convertVolume(2.5), 2.5, accuracy: 0.001)
    }
    
    func testConvertVolume_litersToOunces() {
        let converter = UnitConverter(preference: .imperial)
        // Known value from requirements: 1L = 33.814 oz
        XCTAssertEqual(converter.convertVolume(1), 33.814, accuracy: 0.001)
        // 2L = 67.628 oz
        XCTAssertEqual(converter.convertVolume(2), 67.628, accuracy: 0.01)
    }
    
    func testFormatVolume_metric() {
        let converter = UnitConverter(preference: .metric)
        XCTAssertEqual(converter.formatVolume(2.5), "2.50 L")
        XCTAssertEqual(converter.formatVolume(1.0), "1.00 L")
    }
    
    func testFormatVolume_imperial() {
        let converter = UnitConverter(preference: .imperial)
        // 1L = 33.8 oz
        let result = converter.formatVolume(1)
        XCTAssertTrue(result.contains("33.8"))
        XCTAssertTrue(result.contains("oz"))
    }
    
    func testVolumeUnit() {
        let metricConverter = UnitConverter(preference: .metric)
        let imperialConverter = UnitConverter(preference: .imperial)
        
        XCTAssertEqual(metricConverter.volumeUnit(), "L")
        XCTAssertEqual(imperialConverter.volumeUnit(), "oz")
    }
    
    // MARK: - Speed Conversion Tests
    
    func testFormatSpeed_metric() {
        let converter = UnitConverter(preference: .metric)
        // 1 m/s = 3.6 km/h
        XCTAssertEqual(converter.formatSpeed(1), "3.6 km/h")
        // 10 m/s = 36 km/h
        XCTAssertEqual(converter.formatSpeed(10), "36.0 km/h")
    }
    
    func testFormatSpeed_imperial() {
        let converter = UnitConverter(preference: .imperial)
        // 1 m/s = 2.23694 mph
        XCTAssertEqual(converter.formatSpeed(1), "2.2 mph")
    }
    
    func testSpeedUnit() {
        let metricConverter = UnitConverter(preference: .metric)
        let imperialConverter = UnitConverter(preference: .imperial)
        
        XCTAssertEqual(metricConverter.speedUnit(), "km/h")
        XCTAssertEqual(imperialConverter.speedUnit(), "mph")
    }
    
    // MARK: - Length (Waist/Body Measurements) Tests
    
    func testFormatLength_metric() {
        let converter = UnitConverter(preference: .metric)
        // 0.85 meters = 85 cm
        XCTAssertEqual(converter.formatLength(0.85), "85.0 cm")
    }
    
    func testFormatLength_imperial() {
        let converter = UnitConverter(preference: .imperial)
        // 0.85 meters = 33.46 inches
        let result = converter.formatLength(0.85)
        XCTAssertTrue(result.contains("33.5") || result.contains("33.4"))
        XCTAssertTrue(result.contains("in"))
    }
    
    func testLengthUnit() {
        let metricConverter = UnitConverter(preference: .metric)
        let imperialConverter = UnitConverter(preference: .imperial)
        
        XCTAssertEqual(metricConverter.lengthUnit(), "cm")
        XCTAssertEqual(imperialConverter.lengthUnit(), "in")
    }
    
    // MARK: - Edge Cases
    
    func testZeroValues() {
        let metricConverter = UnitConverter(preference: .metric)
        let imperialConverter = UnitConverter(preference: .imperial)
        
        XCTAssertEqual(metricConverter.convertWeight(0), 0, accuracy: 0.001)
        XCTAssertEqual(imperialConverter.convertWeight(0), 0, accuracy: 0.001)
        XCTAssertEqual(metricConverter.convertDistance(0, toLarge: true), 0, accuracy: 0.001)
        XCTAssertEqual(imperialConverter.convertDistance(0, toLarge: true), 0, accuracy: 0.001)
    }
    
    func testNegativeTemperature() {
        let imperialConverter = UnitConverter(preference: .imperial)
        // -40°C = -40°F (they're equal at this point!)
        XCTAssertEqual(imperialConverter.convertTemperature(-40), -40, accuracy: 0.01)
        // -10°C = 14°F
        XCTAssertEqual(imperialConverter.convertTemperature(-10), 14, accuracy: 0.1)
    }
    
    func testLargeValues() {
        let imperialConverter = UnitConverter(preference: .imperial)
        // Marathon distance: 42,195 meters
        let marathonMiles = imperialConverter.convertDistance(42195, toLarge: true)
        XCTAssertEqual(marathonMiles, 26.22, accuracy: 0.01)
    }
}
