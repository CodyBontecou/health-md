#!/usr/bin/env python3
"""Validate Android's explicit, locale-pinned Clinician Report vocabulary."""

from __future__ import annotations

import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

LOCALE_DIRECTORIES = {
    "en": "values",
    "ar": "values-ar",
    "bn": "values-bn",
    "zh-Hans": "values-b+zh+Hans",
    "de": "values-de",
    "es": "values-es",
    "fr": "values-fr",
    "hi": "values-hi",
    "ja": "values-ja",
    "kk": "values-kk",
    "nl": "values-nl",
    "pa-Guru": "values-b+pa+Guru",
    "pt-BR": "values-pt-rBR",
    "ro": "values-ro",
    "ru": "values-ru",
    "uk": "values-uk",
}
PLACEHOLDER = re.compile(r"%\d+\$[sd]")
WORKOUT_KEYS = {
    "RUNNING": "running", "WALKING": "walking", "CYCLING": "cycling",
    "SWIMMING": "swimming", "HIKING": "hiking", "YOGA": "yoga",
    "STRENGTH_TRAINING": "strength_training", "CORE_TRAINING": "core_training",
    "HIIT": "hiit", "ELLIPTICAL": "elliptical", "ROWING": "rowing",
    "STAIR_CLIMBING": "stair_climbing", "PILATES": "pilates", "DANCE": "dance",
    "COOLDOWN": "cooldown", "MIXED_CARDIO": "mixed_cardio", "PICKLEBALL": "pickleball",
    "TENNIS": "tennis", "BADMINTON": "badminton", "TABLE_TENNIS": "table_tennis",
    "GOLF": "golf", "SOCCER": "soccer", "BASKETBALL": "basketball",
    "BASEBALL": "baseball", "SOFTBALL": "softball", "VOLLEYBALL": "volleyball",
    "AMERICAN_FOOTBALL": "american_football", "RUGBY": "rugby", "HOCKEY": "hockey",
    "LACROSSE": "lacrosse", "SKATING": "skating", "SNOW_SPORTS": "snow_sports",
    "WATER_SPORTS": "water_sports", "WHEELCHAIR": "wheelchair",
    "MARTIAL_ARTS": "martial_arts", "BOXING": "boxing", "KICKBOXING": "kickboxing",
    "WRESTLING": "wrestling", "CLIMBING": "climbing", "JUMP_ROPE": "jump_rope",
    "FLEXIBILITY": "flexibility", "OTHER": "other",
}


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def android_unescape(value: str) -> str:
    return value.replace("\\'", "'").replace('\\"', '"').replace("\\\\", "\\")


def strings(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for item in ET.parse(path).getroot().findall("string"):
        name = item.attrib["name"]
        if not name.startswith("clinician_report_"):
            continue
        value = "".join(item.itertext())
        if name in result:
            fail(f"{path}: duplicate {name}")
        result[name] = android_unescape(value)
    return result


def workout_enum_values(source: str) -> set[str]:
    match = re.search(r"enum class WorkoutType\s*\{(.*?)\n\}", source, re.S)
    if not match:
        fail("could not find WorkoutType enum")
    return set(re.findall(r"^\s*([A-Z][A-Z0-9_]*)\s*,?\s*$", match.group(1), re.M))


def main() -> None:
    android = Path(__file__).resolve().parents[1]
    manifest = json.loads((android / "scripts/fixtures/clinician-report-localization-en.json").read_text())
    if len(manifest) != 152:
        fail(f"English report manifest has {len(manifest)} keys; expected 152")
    expected = set(manifest)
    if len([key for key in expected if key.startswith("clinician_report_workout_type_")]) != 42:
        fail("manifest must contain exactly 42 normalized workout labels")

    model = (android / "app/src/main/java/com/healthmd/domain/model/HealthData.kt").read_text()
    vocabulary_path = android / "app/src/main/java/com/healthmd/domain/clinicianreport/ClinicianReportVocabulary.kt"
    vocabulary_source = vocabulary_path.read_text()
    enum_values = workout_enum_values(model)
    if enum_values != set(WORKOUT_KEYS):
        fail(f"WorkoutType mapping drift: missing={sorted(enum_values - set(WORKOUT_KEYS))}, extra={sorted(set(WORKOUT_KEYS) - enum_values)}")
    mapped_keys = {f"clinician_report_workout_type_{suffix}" for suffix in WORKOUT_KEYS.values()}
    if mapped_keys != {key for key in expected if key.startswith("clinician_report_workout_type_")}:
        fail("manifest workout resources differ from the exact WorkoutType mapping")
    declared_keys = set(re.findall(r'^[ ]+[A-Z0-9_]+\("(clinician_report_[^"]+)"\),$', vocabulary_source, re.M))
    if declared_keys != expected:
        fail("ClinicianReportText differs from the reviewed manifest")
    actual_workout_mapping = dict(re.findall(
        r"WorkoutType\.([A-Z0-9_]+)\s*->\s*ClinicianReportText\.WORKOUT_TYPE_([A-Z0-9_]+)",
        vocabulary_source,
    ))
    expected_workout_mapping = {enum: suffix.upper() for enum, suffix in WORKOUT_KEYS.items()}
    if actual_workout_mapping != expected_workout_mapping:
        fail("workoutName mapping does not match the exact normalized WorkoutType/resource mapping")
    resource_provider = (android / "app/src/main/java/com/healthmd/data/clinicianreport/AndroidClinicianReportVocabulary.kt").read_text()
    provider_resources = set(re.findall(r"-> R\.string\.(clinician_report_[A-Za-z0-9_]+)", resource_provider))
    if provider_resources != expected:
        fail("Android resource vocabulary provider differs from the reviewed manifest")

    res = android / "app/src/main/res"
    for locale, directory in LOCALE_DIRECTORIES.items():
        path = res / directory / "strings.xml"
        localized = strings(path)
        if set(localized) != expected:
            fail(f"{locale}: report keys differ; missing={sorted(expected - set(localized))}, extra={sorted(set(localized) - expected)}")
        for key, english in manifest.items():
            value = localized[key]
            if not value.strip():
                fail(f"{locale}/{key}: empty value")
            if PLACEHOLDER.findall(value) != PLACEHOLDER.findall(english):
                fail(f"{locale}/{key}: placeholder mismatch")
        if locale == "en" and localized != manifest:
            fail("default English resources differ from reviewed manifest")

    allowed = set(LOCALE_DIRECTORIES.values())
    for path in res.glob("values*/strings.xml"):
        if path.parent.name not in allowed and strings(path):
            fail(f"orphan report strings found in unsupported resource directory {path.parent.name}")

    print(f"Clinician Report localization validation passed: {len(expected)} keys × {len(LOCALE_DIRECTORIES)} explicit locales; {len(WORKOUT_KEYS)} workout types mapped.")


if __name__ == "__main__":
    main()
