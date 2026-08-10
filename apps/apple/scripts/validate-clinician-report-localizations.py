#!/usr/bin/env python3
"""Validate the manually managed Clinician Report string-catalog slice."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

APPLE_LOCALES = {
    "en",
    "de",
    "es",
    "fr",
    "it",
    "ja",
    "ko",
    "nl",
    "pt-BR",
    "zh-Hans",
}
PLACEHOLDER = re.compile(r"%\d+\$[@d]")
EXPECTED_KEY_COUNT = 205
LEGACY_UNREVIEWED_KEYS = {
    "%lld individual readings will be included in the PDF.",
    "Blood Glucose",
    "Blood Pressure",
    "Body Temperature",
    "Close",
    "Exercise / Workouts",
    "Heart Rate",
    "Oxygen Saturation",
    "Respiratory Rate",
    "Resting Heart Rate",
    "Select a date range and measurements, preview a factual summary, then share or save it privately.",
    "Sleep Duration",
    "Sources: %@",
    "Steps",
    "Summary + readings",
    "Weight",
}


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def apple_catalog_value(value: str) -> str:
    """Translate platform-neutral string placeholders into Apple catalog syntax."""
    return re.sub(r"%(\d+)\$s", r"%\1$@", value)


def main() -> None:
    apple = Path(__file__).resolve().parents[1]
    manifest_path = apple / "scripts/fixtures/clinician-report-localization-en.json"
    catalog_path = apple / "HealthMd/Localizable.xcstrings"
    copy_path = apple / "HealthMd/Shared/ClinicianReport/ClinicianReportCopy.swift"
    health_data_path = apple / "HealthMd/Shared/Models/HealthData.swift"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))

    if len(manifest) != EXPECTED_KEY_COUNT:
        fail(f"English manifest has {len(manifest)} keys; expected {EXPECTED_KEY_COUNT}")
    expected_keys = set(manifest)
    provider_keys = set(re.findall(r'case\s+[A-Za-z0-9_]+\s*=\s*"(clinician_report_[^"]+)"', copy_path.read_text(encoding="utf-8")))
    if provider_keys != expected_keys:
        fail(
            "ClinicianReportCopy.Key differs from the manifest; "
            f"missing={sorted(expected_keys - provider_keys)}, extra={sorted(provider_keys - expected_keys)}"
        )
    catalog_keys = {key for key in catalog["strings"] if key.startswith("clinician_report_")}
    legacy_keys = LEGACY_UNREVIEWED_KEYS.intersection(catalog["strings"])
    if legacy_keys:
        fail(f"legacy unreviewed report keys remain in catalog: {sorted(legacy_keys)}")
    if catalog_keys != expected_keys:
        fail(
            "stable catalog keys differ from the manifest; "
            f"missing={sorted(expected_keys - catalog_keys)}, extra={sorted(catalog_keys - expected_keys)}"
        )

    health_data = health_data_path.read_text(encoding="utf-8")
    workout_block = health_data.split("nonisolated enum WorkoutType:", 1)[1].split("var displayName:", 1)[0]
    workout_cases = set(re.findall(r"^\s*case\s+([A-Za-z0-9]+)\s*$", workout_block, re.MULTILINE))
    expected_workout_keys = {f"clinician_report_workout_type_{case}" for case in workout_cases}
    manifest_workout_keys = {key for key in expected_keys if key.startswith("clinician_report_workout_type_")}
    if manifest_workout_keys != expected_workout_keys:
        fail(
            "WorkoutType localization coverage differs; "
            f"missing={sorted(expected_workout_keys - manifest_workout_keys)}, "
            f"extra={sorted(manifest_workout_keys - expected_workout_keys)}"
        )
    if "clinician_report_unit_respiratory_rate" not in expected_keys:
        fail("missing localized respiratory-rate unit")

    report_source = "\n".join(
        path.read_text(encoding="utf-8")
        for path in (apple / "HealthMd").rglob("*.swift")
        if "ClinicianReport" in str(path)
    )
    forbidden_source_patterns = {
        "workout.workoutType.displayName": "ambient English workout label",
        "converter.formatWeight(": "ambient-locale weight formatter",
        'case .respiratoryRate: return "breaths/min"': "hardcoded respiratory-rate unit",
    }
    for pattern, description in forbidden_source_patterns.items():
        if pattern in report_source:
            fail(f"report source still contains {description}: {pattern}")

    for key, english in manifest.items():
        entry = catalog["strings"][key]
        if entry.get("extractionState") != "manual":
            fail(f"{key}: expected extractionState=manual")
        localizations = entry.get("localizations", {})
        if set(localizations) != APPLE_LOCALES:
            fail(
                f"{key}: locale coverage differs; "
                f"missing={sorted(APPLE_LOCALES - set(localizations))}, "
                f"extra={sorted(set(localizations) - APPLE_LOCALES)}"
            )
        expected_apple_value = apple_catalog_value(english)
        expected_placeholders = PLACEHOLDER.findall(expected_apple_value)
        for locale, localization in localizations.items():
            unit = localization.get("stringUnit", {})
            value = unit.get("value", "")
            if unit.get("state") != "translated" or not value:
                fail(f"{key}/{locale}: missing explicit translated value")
            if PLACEHOLDER.findall(value) != expected_placeholders:
                fail(
                    f"{key}/{locale}: placeholder mismatch; "
                    f"expected={expected_placeholders}, actual={PLACEHOLDER.findall(value)}"
                )
        if localizations["en"]["stringUnit"]["value"] != expected_apple_value:
            fail(f"{key}/en: differs from the reviewed English manifest")

    print(
        f"Clinician Report localization validation passed: "
        f"{len(expected_keys)} keys × {len(APPLE_LOCALES)} explicit locales."
    )


if __name__ == "__main__":
    main()
