package com.healthmd.domain.model

import kotlinx.serialization.Serializable
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

// MARK: - Date Format

@Serializable
enum class DateFormatPreference(val pattern: String, val displayName: String) {
    ISO8601("yyyy-MM-dd", "ISO 8601 (2026-01-13)"),
    US_SHORT("MM/dd/yyyy", "US Short (01/13/2026)"),
    US_LONG("MMMM d, yyyy", "US Long (January 13, 2026)"),
    EU_SHORT("dd/MM/yyyy", "EU Short (13/01/2026)"),
    EU_LONG("d MMMM yyyy", "EU Long (13 January 2026)"),
    COMPACT("yyyyMMdd", "Compact (20260113)"),
    FRIENDLY("EEE, MMM d, yyyy", "Friendly (Mon, Jan 13, 2026)");

    fun format(date: LocalDate): String {
        val formatter = DateTimeFormatter.ofPattern(pattern, Locale.getDefault())
        return date.format(formatter)
    }
}

// MARK: - Time Format

@Serializable
enum class TimeFormatPreference(val pattern: String, val displayName: String) {
    HOUR_24("HH:mm", "24-hour (14:30)"),
    HOUR_24_SECONDS("HH:mm:ss", "24-hour with seconds (14:30:45)"),
    HOUR_12("h:mm a", "12-hour (2:30 PM)"),
    HOUR_12_SECONDS("h:mm:ss a", "12-hour with seconds (2:30:45 PM)");

    fun format(dateTime: LocalDateTime): String {
        val formatter = DateTimeFormatter.ofPattern(pattern, Locale.getDefault())
        return dateTime.format(formatter)
    }
}

// MARK: - Unit Preferences

@Serializable
enum class UnitPreference(val displayName: String, val description: String) {
    METRIC("Metric", "Kilometers, kilograms, Celsius"),
    IMPERIAL("Imperial", "Miles, pounds, Fahrenheit"),
}

// MARK: - Unit Converter

data class UnitConverter(val preference: UnitPreference) {

    // Distance
    fun formatDistance(meters: Double): String = when (preference) {
        UnitPreference.METRIC -> {
            if (meters >= 1000) String.format("%.2f km", meters / 1000)
            else "${meters.toInt()} m"
        }
        UnitPreference.IMPERIAL -> {
            val miles = meters / 1609.344
            if (miles >= 0.1) String.format("%.2f mi", miles)
            else "${(meters * 3.28084).toInt()} ft"
        }
    }

    fun distanceUnit(large: Boolean = true): String = when (preference) {
        UnitPreference.METRIC -> if (large) "km" else "m"
        UnitPreference.IMPERIAL -> if (large) "mi" else "ft"
    }

    fun convertDistance(meters: Double, toLarge: Boolean = true): Double = when (preference) {
        UnitPreference.METRIC -> if (toLarge) meters / 1000 else meters
        UnitPreference.IMPERIAL -> if (toLarge) meters / 1609.344 else meters * 3.28084
    }

    // Weight
    fun formatWeight(kg: Double): String = when (preference) {
        UnitPreference.METRIC -> String.format("%.1f kg", kg)
        UnitPreference.IMPERIAL -> String.format("%.1f lbs", kg * 2.20462)
    }

    fun weightUnit(): String = when (preference) {
        UnitPreference.METRIC -> "kg"
        UnitPreference.IMPERIAL -> "lbs"
    }

    fun convertWeight(kg: Double): Double = when (preference) {
        UnitPreference.METRIC -> kg
        UnitPreference.IMPERIAL -> kg * 2.20462
    }

    // Height
    fun formatHeight(meters: Double): String = when (preference) {
        UnitPreference.METRIC -> String.format("%.1f cm", meters * 100)
        UnitPreference.IMPERIAL -> {
            val totalInches = meters * 39.3701
            val feet = (totalInches / 12).toInt()
            val inches = (totalInches % 12).toInt()
            "$feet'$inches\""
        }
    }

    fun heightUnit(): String = when (preference) {
        UnitPreference.METRIC -> "cm"
        UnitPreference.IMPERIAL -> "ft/in"
    }

    fun convertHeight(meters: Double): Double = when (preference) {
        UnitPreference.METRIC -> meters * 100 // to cm
        UnitPreference.IMPERIAL -> meters * 39.3701 // to inches
    }

    // Temperature
    fun formatTemperature(celsius: Double): String = when (preference) {
        UnitPreference.METRIC -> String.format("%.1f\u00B0C", celsius)
        UnitPreference.IMPERIAL -> String.format("%.1f\u00B0F", celsius * 9.0 / 5.0 + 32)
    }

    fun temperatureUnit(): String = when (preference) {
        UnitPreference.METRIC -> "\u00B0C"
        UnitPreference.IMPERIAL -> "\u00B0F"
    }

    fun convertTemperature(celsius: Double): Double = when (preference) {
        UnitPreference.METRIC -> celsius
        UnitPreference.IMPERIAL -> celsius * 9.0 / 5.0 + 32
    }

    // Speed
    fun formatSpeed(metersPerSecond: Double): String = when (preference) {
        UnitPreference.METRIC -> String.format("%.1f km/h", metersPerSecond * 3.6)
        UnitPreference.IMPERIAL -> String.format("%.1f mph", metersPerSecond * 2.23694)
    }

    fun speedUnit(): String = when (preference) {
        UnitPreference.METRIC -> "km/h"
        UnitPreference.IMPERIAL -> "mph"
    }

    // Length (waist, etc.)
    fun formatLength(meters: Double): String = when (preference) {
        UnitPreference.METRIC -> String.format("%.1f cm", meters * 100)
        UnitPreference.IMPERIAL -> String.format("%.1f in", meters * 39.3701)
    }

    fun lengthUnit(): String = when (preference) {
        UnitPreference.METRIC -> "cm"
        UnitPreference.IMPERIAL -> "in"
    }

    // Volume (water)
    fun formatVolume(liters: Double): String = when (preference) {
        UnitPreference.METRIC -> String.format("%.2f L", liters)
        UnitPreference.IMPERIAL -> String.format("%.1f oz", liters * 33.814)
    }

    fun volumeUnit(): String = when (preference) {
        UnitPreference.METRIC -> "L"
        UnitPreference.IMPERIAL -> "oz"
    }

    fun convertVolume(liters: Double): Double = when (preference) {
        UnitPreference.METRIC -> liters
        UnitPreference.IMPERIAL -> liters * 33.814
    }
}
