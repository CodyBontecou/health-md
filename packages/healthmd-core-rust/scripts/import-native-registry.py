#!/usr/bin/env python3
"""Rebuild/check the M3 registry from immutable pre-cutover native evidence.

The two native snapshots and reviewed semantic crosswalk are independent migration fixtures.
The canonical output becomes the source of truth; generated adapters and normal builds read
metric-registry-v1.json instead of parsing Swift, Kotlin, or generated documentation.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any

WORKSPACE = Path(__file__).resolve().parents[1]
REPO = WORKSPACE.parents[1]
APPLE_CATALOG = REPO / "apps/apple/docs/reference/generated/core/metric-catalog.md"
ANDROID_METRICS = REPO / "apps/android/app/src/main/java/com/healthmd/domain/model/MetricSelection.kt"
ANDROID_FIELDS = REPO / "apps/android/app/src/main/java/com/healthmd/domain/model/HealthDataFields.kt"
SEMANTIC_CROSSWALK = WORKSPACE / "crates/healthmd-core/registry/native-baseline-semantic-crosswalk-v1.json"
CAPABILITY_MANIFEST = REPO / "packages/contracts/product-capabilities.json"
REGISTRY_DIR = WORKSPACE / "crates/healthmd-core/registry"
REGISTRY_PATH = REGISTRY_DIR / "metric-registry-v1.json"
APPLE_BASELINE = REGISTRY_DIR / "native-baseline-apple-v7.json"
ANDROID_BASELINE = REGISTRY_DIR / "native-baseline-android-v4-v5.json"

ANDROID_ONLY = {
    "hrv",
    "total_calories",
    "elevation_gained",
    "skin_temperature",
    "body_water_mass",
    "bone_mass",
    "unsaturated_fat",
    "trans_fat",
    "folic_acid",
    "steps_cadence",
    "activity_intensity_minutes",
    "energy_from_fat",
    "nutrition_meals",
    "menstruation_periods",
    "menstruation_period_days",
    "planned_workouts",
    "medical_resources",
}

CATEGORY_CAPABILITY = {
    "Sleep": "export.sleep-summary",
    "Activity": "export.activity-basics",
    "Heart": "export.cardiorespiratory-summary",
    "Respiratory": "export.cardiorespiratory-summary",
    "Vitals": "export.vitals-and-body",
    "Body Measurements": "export.vitals-and-body",
    "Body": "export.vitals-and-body",
    "Mobility": "export.mobility-and-performance",
    "Cycling": "export.mobility-and-performance",
    "Nutrition": "export.nutrient-totals",
    "Vitamins": "export.nutrient-totals",
    "Minerals": "export.nutrient-totals",
    "Hearing": "apple.hearing-and-symptoms",
    "Mindfulness": "export.mindfulness-sessions",
    "Reproductive Health": "export.daily-files",
    "Reproductive": "export.daily-files",
    "Symptoms": "apple.hearing-and-symptoms",
    "Clinical Records": "apple.lossless-healthkit-archive",
    "Clinical Documents": "apple.lossless-healthkit-archive",
    "Vision": "apple.lossless-healthkit-archive",
    "Medications": "apple.medication-dose-events",
    "Other": "export.daily-files",
    "Workouts": "export.completed-workouts",
}

ANDROID_CATEGORY_NAMES = {
    "SLEEP": "Sleep",
    "ACTIVITY": "Activity",
    "HEART": "Heart",
    "RESPIRATORY": "Respiratory",
    "VITALS": "Vitals",
    "BODY": "Body",
    "NUTRITION": "Nutrition",
    "MOBILITY": "Mobility",
    "CYCLING": "Cycling",
    "HEARING": "Hearing",
    "MINDFULNESS": "Mindfulness",
    "REPRODUCTIVE": "Reproductive",
    "SYMPTOMS": "Symptoms",
    "MEDICATIONS": "Medications",
    "OTHER": "Other",
    "WORKOUTS": "Workouts",
}


def canonical_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode()


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parse_apple() -> dict[str, Any]:
    # Once captured, the immutable pre-cutover snapshot is migration evidence. The generated
    # Swift catalog now projects the Rust registry and must not become the import authority.
    if not APPLE_BASELINE.exists():
        raise FileNotFoundError("immutable pre-cutover Apple registry baseline is missing")
    return json.loads(APPLE_BASELINE.read_text())

    # Retained below only as archaeological evidence of the one-time Markdown import.
    metrics: list[dict[str, Any]] = []
    output_re = re.compile(r"`([^`]+)` \(([^;]+); daily ([^;]+); roll-up ([^)]+)\)")
    in_metric_table = False
    for line in APPLE_CATALOG.read_text().splitlines():
        if line.startswith("| Metric ID |"):
            in_metric_table = True
            continue
        if in_metric_table and not line.startswith("|"):
            break
        if not in_metric_table or line.startswith("|---"):
            continue
        columns = [part.strip() for part in line.strip().strip("|").split("|")]
        if len(columns) != 11:
            raise ValueError(f"unexpected Apple catalog row: {line}")
        metric_id, name, category, unit, kind, aggregation, archive, default, availability, selector, output_cell = columns
        outputs = [
            {
                "key": match.group(1),
                "unit": match.group(2),
                "daily_aggregation": match.group(3),
                "rollup": match.group(4),
            }
            for match in output_re.finditer(output_cell)
        ]
        if output_cell != "Source archive only" and not outputs:
            raise ValueError(f"could not parse Apple output bindings for {metric_id}: {output_cell}")
        metrics.append(
            {
                "selection_id": metric_id,
                "label_key": metric_id,
                "reference_name": name,
                "category_id": category,
                "unit": unit,
                "kind": kind,
                "source_aggregation": aggregation,
                "archive_only": archive == "yes",
                "default_enabled": default == "yes",
                "availability_key": availability,
                "source_selector": selector,
                "authorization_key": apple_authorization(metric_id, category),
                "outputs": outputs,
            }
        )
    if len(metrics) != 230:
        raise ValueError(f"expected 230 Apple metrics, found {len(metrics)}")
    return {
        "profile_id": "apple_health_data_v7",
        "public_profile_id": "apple-v7",
        "public_schema": "healthmd.health_data",
        "public_schema_version": 7,
        "metrics": metrics,
    }


def apple_authorization(metric_id: str, category: str) -> str:
    if category == "Clinical Records":
        return "health_records"
    return {
        "cda_documents": "cda_query",
        "verifiable_clinical_records": "verifiable_records_query",
        "vision_prescriptions": "per_object_vision",
        "medications": "per_object_medication",
        "scheduled_workout_plans": "workoutkit_no_prompt",
    }.get(metric_id, "standard_healthkit")


def parse_string_collection(source: str, declaration: str) -> list[str]:
    match = re.search(rf"{re.escape(declaration)}[^=]*= (?:listOf|setOf)\((.*?)\n    \)", source, re.S)
    if not match:
        raise ValueError(f"missing Kotlin collection {declaration}")
    return re.findall(r'"([^"\\]*(?:\\.[^"\\]*)*)"', match.group(1))


def parse_android() -> dict[str, Any]:
    # Preserve the immutable pre-cutover Kotlin inventory for differential evidence.
    if not ANDROID_BASELINE.exists():
        raise FileNotFoundError("immutable pre-cutover Android registry baseline is missing")
    return json.loads(ANDROID_BASELINE.read_text())

    # Retained below only as archaeological evidence of the one-time Kotlin import.
    source = ANDROID_METRICS.read_text()
    supported_block = source[source.index("private val ALL_METRICS"):source.index("private val UNAVAILABLE_METRICS")]
    supported = [
        {
            "selection_id": metric_id,
            "label_key": metric_id,
            "category_id": ANDROID_CATEGORY_NAMES[category],
            "unit": bytes(unit, "utf-8").decode("unicode_escape") if "\\" in unit else unit,
            "default_enabled": True,
            "availability_key": android_availability(metric_id),
            "source_aggregation": android_aggregation(metric_id, category),
        }
        for metric_id, category, unit in re.findall(
            r'HealthMetricDefinition\("([^"]+)", HealthMetricCategory\.([A-Z_]+), "([^"]*)"\)',
            supported_block,
        )
    ]
    if len(supported) != 106:
        raise ValueError(f"expected 106 Android metrics, found {len(supported)}")

    unavailable: list[dict[str, Any]] = []
    for match in re.finditer(
        r'UnavailableHealthMetricDefinition\(\s*"([^"]+)",\s*HealthMetricCategory\.([A-Z_]+),\s*"([^"]+)",\s*"([^"]+)",\s*\)',
        source,
        re.S,
    ):
        metric_id, category, display_name, reason = match.groups()
        unavailable.append(
            {
                "selection_id": metric_id,
                "label_key": metric_id,
                "category_id": ANDROID_CATEGORY_NAMES[category],
                "reference_name": display_name,
                "reason": reason,
                "reason_key": f"metric_unavailable_{metric_id}",
            }
        )
    if len(unavailable) != 102:
        raise ValueError(f"expected 102 Android unavailable metrics, found {len(unavailable)}")

    field_source = ANDROID_FIELDS.read_text()
    all_keys = parse_string_collection(field_source, "val allKeys")
    legacy_aliases = parse_string_collection(field_source, "private val legacyAndroidAliasKeys")
    native_fields = parse_string_collection(field_source, "private val androidNativeFieldKeys")
    if len(all_keys) != 161:
        raise ValueError(f"expected 161 Android fields, found {len(all_keys)}")
    frozen_keys = [key for key in all_keys if key not in set(legacy_aliases) | set(native_fields)]
    analytical_keys = [key for key in all_keys if key not in set(legacy_aliases)]

    return {
        "profiles": [
            {
                "profile_id": "android_frozen_v4",
                "public_profile_id": "android-frozen-v4",
                "public_schema": "healthmd.health_data",
                "public_schema_version": 4,
                "metric_ids": [metric["selection_id"] for metric in supported],
                "flat_output_keys": frozen_keys,
            },
            {
                "profile_id": "android_analytical_v5",
                "public_profile_id": "android-analytical-v5",
                "public_schema": "healthmd.health_data",
                "public_schema_version": 5,
                "metric_ids": [metric["selection_id"] for metric in supported],
                "flat_output_keys": analytical_keys,
            },
        ],
        "metrics": supported,
        "unavailable_metrics": unavailable,
        "legacy_alias_keys": legacy_aliases,
        "android_native_field_keys": native_fields,
        "all_flat_output_keys": all_keys,
    }


def android_availability(metric_id: str) -> str:
    return {
        "skin_temperature": "skin_temperature",
        "mindful_minutes": "mindfulness",
        "mindful_sessions": "mindfulness",
        "planned_workouts": "planned_workouts",
        "activity_intensity_minutes": "activity_intensity",
        "menstruation_periods": "menstruation_periods",
        "menstruation_period_days": "menstruation_periods",
        "medical_resources": "personal_health_records",
    }.get(metric_id, "baseline")


def android_aggregation(metric_id: str, category: str) -> str:
    if metric_id in {"min_hr"}:
        return "minimum"
    if metric_id in {"max_hr", "power_max"}:
        return "maximum"
    if metric_id in {"hrv", "resting_hr", "basal_body_temp", "weight", "height", "bmi", "body_fat", "lean_mass", "body_water_mass", "bone_mass", "vo2_max", "menstrual_flow", "cervical_mucus", "ovulation_test"}:
        return "latest"
    if category in {"HEART", "RESPIRATORY", "VITALS", "MOBILITY"}:
        return "average"
    if category in {"WORKOUTS", "REPRODUCTIVE", "MEDICATIONS"}:
        return "record_projection"
    return "sum"


def parse_frozen_crosswalk() -> dict[str, list[str]]:
    payload = json.loads(SEMANTIC_CROSSWALK.read_text())
    if payload.get("schema") != "healthmd.native_semantic_crosswalk" or payload.get("schema_version") != 1:
        raise ValueError("invalid frozen native semantic crosswalk")
    mappings = {
        row["android_selection_id"]: row["apple_semantic_ids"]
        for row in payload["mappings"]
    }
    if len(mappings) != len(payload["mappings"]):
        raise ValueError("duplicate Android selection id in frozen semantic crosswalk")
    return mappings


def metric_capability(metric: dict[str, Any], platform: str) -> str:
    metric_id = metric["selection_id"]
    if platform == "apple":
        return {
            "medications": "apple.medication-dose-events",
            "wrist_temperature": "apple.wrist-temperature",
            "state_of_mind_entries": "apple.state-of-mind",
            "daily_mood": "apple.state-of-mind",
            "average_valence": "apple.state-of-mind",
            "momentary_emotions": "apple.state-of-mind",
        }.get(metric_id, CATEGORY_CAPABILITY[metric["category_id"]])
    return {
        "activity_intensity_minutes": "android.activity-intensity",
        "planned_workouts": "android.planned-workouts",
        "menstruation_periods": "android.menstruation-periods",
        "menstruation_period_days": "android.menstruation-periods",
        "medical_resources": "android.personal-health-records",
        "nutrition_meals": "android.nutrition-meals",
        "skin_temperature": "android.skin-temperature",
    }.get(metric_id, CATEGORY_CAPABILITY[metric["category_id"]])


def output_selection_ids(key: str, supported_ids: set[str]) -> list[str]:
    explicit = {
        "sleep_bedtime": ["sleep_total", "sleep_in_bed"],
        "sleep_wake": ["sleep_total", "sleep_in_bed"],
        "sleep_core_hours": ["sleep_light"],
        "sleep_light_hours": ["sleep_light"],
        "active_calories": ["active_calories"],
        "total_calories": ["total_calories"],
        "basal_calories": ["basal_calories"],
        "exercise_minutes": ["exercise_minutes"],
        "walking_running_km": ["distance"],
        "cycling_km": ["cycling_distance"],
        "cycling_cadence_rpm": ["cycling_cadence"],
        "cycling_power_w": ["power_avg"],
        "elevation_gained_m": ["elevation_gained"],
        "wheelchair_pushes": ["wheelchair_pushes"],
        "swimming_m": ["swimming_distance"],
        "wheelchair_km": ["wheelchair_distance"],
        "downhill_snow_km": ["downhill_snow_distance"],
        "moderate_activity_minutes": ["activity_intensity_minutes"],
        "vigorous_activity_minutes": ["activity_intensity_minutes"],
        "resting_heart_rate": ["resting_hr"],
        "average_heart_rate": ["avg_hr"],
        "walking_heart_rate": ["walking_hr"],
        "heart_rate_min": ["min_hr"],
        "heart_rate_max": ["max_hr"],
        "hrv_ms": ["hrv"],
        "body_temperature": ["body_temp"],
        "body_temperature_avg": ["body_temp"],
        "body_temperature_min": ["body_temp"],
        "body_temperature_max": ["body_temp"],
        "blood_pressure_systolic": ["bp_systolic"],
        "blood_pressure_systolic_avg": ["bp_systolic"],
        "blood_pressure_systolic_min": ["bp_systolic"],
        "blood_pressure_systolic_max": ["bp_systolic"],
        "blood_pressure_diastolic": ["bp_diastolic"],
        "blood_pressure_diastolic_avg": ["bp_diastolic"],
        "blood_pressure_diastolic_min": ["bp_diastolic"],
        "blood_pressure_diastolic_max": ["bp_diastolic"],
        "basal_body_temperature": ["basal_body_temp"],
        "skin_temperature_delta": ["skin_temperature"],
        "lean_body_mass_kg": ["lean_mass"],
        "body_water_mass_kg": ["body_water_mass"],
        "bone_mass_kg": ["bone_mass"],
        "dietary_calories": ["dietary_energy"],
        "carbohydrates_g": ["carbs"],
        "folic_acid_mcg": ["folic_acid"],
        "energy_from_fat_kcal": ["energy_from_fat"],
        "nutrition_meal_count": ["nutrition_meals"],
        "cycling_cadence": ["cycling_cadence"],
        "cycling_cadence_max": ["cycling_cadence"],
        "steps_cadence": ["steps_cadence"],
        "steps_cadence_max": ["steps_cadence"],
        "running_power_w": ["running_power"],
        "running_power_avg": ["running_power"],
        "running_power_max": ["running_power"],
        "cervical_mucus_appearance": ["cervical_mucus"],
        "cervical_mucus_sensation": ["cervical_mucus"],
        "protection_used": ["sexual_activity"],
        "menstruation_period_count": ["menstruation_periods"],
        "menstruation_period_days": ["menstruation_period_days"],
        "menstruation_period_hours": ["menstruation_period_days"],
        "planned_workout_count": ["planned_workouts"],
        "medical_resource_count": ["medical_resources"],
    }
    if key in explicit:
        return explicit[key]
    if key.startswith("workout_") or key == "workouts":
        return ["workouts"]
    candidates = [
        key,
        re.sub(r"_(hours|minutes|count|percent|avg|min|max|kg|km|mg|mcg|ug|g|l|w|rpm|ms)$", "", key),
    ]
    nutrition_prefix = {
        "protein": "protein", "carbohydrates": "carbs", "fat": "fat", "saturated_fat": "saturated_fat",
        "monounsaturated_fat": "monounsaturated_fat", "polyunsaturated_fat": "polyunsaturated_fat",
        "unsaturated_fat": "unsaturated_fat", "trans_fat": "trans_fat", "fiber": "fiber", "sugar": "sugar",
        "sodium": "sodium", "potassium": "potassium", "calcium": "calcium", "iron": "iron", "magnesium": "magnesium",
        "zinc": "zinc", "phosphorus": "phosphorus", "iodine": "iodine", "selenium": "selenium", "copper": "copper",
        "manganese": "manganese", "chromium": "chromium", "molybdenum": "molybdenum", "chloride": "chloride",
        "vitamin_a": "vitamin_a", "vitamin_b6": "vitamin_b6", "vitamin_b12": "vitamin_b12", "vitamin_c": "vitamin_c",
        "vitamin_d": "vitamin_d", "vitamin_e": "vitamin_e", "vitamin_k": "vitamin_k", "thiamin": "thiamin",
        "riboflavin": "riboflavin", "niacin": "niacin", "folate": "folate", "pantothenic_acid": "pantothenic_acid",
        "biotin": "biotin", "cholesterol": "cholesterol", "water": "water", "caffeine": "caffeine",
    }
    for prefix, metric_id in sorted(nutrition_prefix.items(), key=lambda item: -len(item[0])):
        if key == prefix or key.startswith(prefix + "_"):
            return [metric_id]
    for candidate in candidates:
        if candidate in supported_ids:
            return [candidate]
    prefix_matches = [metric_id for metric_id in supported_ids if key.startswith(metric_id + "_")]
    if prefix_matches:
        return [max(prefix_matches, key=len)]
    raise ValueError(f"no Android metric mapping for output key {key}")


def build_registry(apple: dict[str, Any], android: dict[str, Any]) -> dict[str, Any]:
    ledger = parse_frozen_crosswalk()
    apple_by_id = {metric["selection_id"]: metric for metric in apple["metrics"]}
    supported_ids = {metric["selection_id"] for metric in android["metrics"]}
    unavailable_by_id = {metric["selection_id"]: metric for metric in android["unavailable_metrics"]}

    semantic_metrics: list[dict[str, Any]] = []
    for ordinal, apple_metric in enumerate(apple["metrics"]):
        metric_id = apple_metric["selection_id"]
        semantic_metrics.append(
            {
                "semantic_id": metric_id,
                "reference_name": apple_metric["reference_name"],
                "capability_id": metric_capability(apple_metric, "apple"),
                "equivalence": "platform_exact_or_unavailable",
                "apple": {**apple_metric, "status": "backed", "ordinal": ordinal},
                "android": {
                    "status": "unavailable",
                    "reason_key": f"metric_unavailable_{metric_id}",
                    "picker_visibility": "listed" if metric_id in unavailable_by_id else "hidden",
                },
            }
        )
    semantic_by_id = {metric["semantic_id"]: metric for metric in semantic_metrics}

    android_primary: dict[str, str] = {}
    for metric in android["metrics"]:
        android_id = metric["selection_id"]
        candidates = [] if android_id in ANDROID_ONLY else ledger.get(android_id, [])
        if android_id not in ANDROID_ONLY and android_id in apple_by_id:
            candidates = [android_id, *[candidate for candidate in candidates if candidate != android_id]]
        primary = candidates[0] if candidates else None
        if primary is not None and semantic_by_id[primary]["android"]["status"] == "backed":
            # Two independently selectable Android aggregations may project one Apple source
            # metric (currently power_avg/power_max). Preserve both persisted identities.
            candidates = []
        if candidates:
            primary = candidates[0]
            android_primary[android_id] = primary
            semantic = semantic_by_id[primary]
            semantic["android"] = {
                **metric,
                "status": "backed",
                "ordinal": len(android_primary) - 1,
                "related_semantic_ids": candidates[1:],
            }
            if android_id != primary:
                semantic["equivalence"] = "mapped_alias"
        else:
            semantic_id = {
                "hrv": "android.hrv_rmssd",
            }.get(android_id, f"android.{android_id}")
            android_primary[android_id] = semantic_id
            semantic = {
                "semantic_id": semantic_id,
                "reference_name": {
                    "hrv": "Heart Rate Variability (RMSSD)",
                }.get(android_id, android_id.replace("_", " ").title()),
                "capability_id": metric_capability(metric, "android"),
                "equivalence": "platform_distinct",
                "apple": {
                    "status": "unavailable",
                    "reason_key": f"metric_unavailable_{android_id}",
                    "picker_visibility": "hidden",
                },
                "android": {
                    **metric,
                    "status": "backed",
                    "ordinal": len(android_primary) - 1,
                    "related_semantic_ids": {
                        "hrv": ["hrv"],
                        "power_max": ["cycling_power"],
                    }.get(android_id, [primary] if primary is not None else []),
                },
            }
            semantic_metrics.append(semantic)
            semantic_by_id[semantic_id] = semantic

    # Preserve every current unavailable/stale Android picker identity and attach explanations.
    for item in android["unavailable_metrics"]:
        metric_id = item["selection_id"]
        if metric_id in semantic_by_id and semantic_by_id[metric_id]["android"]["status"] == "unavailable":
            semantic_by_id[metric_id]["android"].update(
                {
                    "reason_key": item["reason_key"],
                    "reference_name": item["reference_name"],
                    "category_id": item["category_id"],
                    "picker_visibility": "listed",
                }
            )

    # The native baseline pins the immutable pre-cutover evidence (v7). The live
    # registry contract tracks the current public export schema version instead,
    # so v8 range-summary exports stay pinned to the shipped schema.
    apple_public_schema_version = 8
    profiles: list[dict[str, Any]] = [
        {
            "id": apple["profile_id"],
            "public_profile_id": apple["public_profile_id"],
            "public_schema": apple["public_schema"],
            "public_schema_version": apple_public_schema_version,
            "profile_revision": 1,
            "platform": "apple",
            "ordered_selection_ids": [metric["selection_id"] for metric in apple["metrics"]],
            "outputs": [
                {"selection_id": metric["selection_id"], "surface": "flat", **output}
                for metric in apple["metrics"]
                for output in metric["outputs"]
            ],
            "unavailable_selection_ids": [],
        }
    ]
    alias_set = set(android["legacy_alias_keys"])
    native_set = set(android["android_native_field_keys"])
    for native_profile in android["profiles"]:
        outputs = []
        default_keys = set(native_profile["flat_output_keys"])
        for key in android["all_flat_output_keys"]:
            is_alias = key in alias_set
            is_native = key in native_set
            condition = "legacy_alias_opt_in" if is_alias else (
                "android_native_opt_in" if is_native and native_profile["profile_id"] == "android_frozen_v4" else "default"
            )
            outputs.append(
                {
                    "selection_ids": output_selection_ids(key, supported_ids),
                    "surface": "flat",
                    "key": key,
                    "alias_kind": "legacy_android" if is_alias else "none",
                    "platform_native": is_native,
                    "condition": condition,
                    "enabled_by_default": key in default_keys,
                }
            )
        profiles.append(
            {
                "id": native_profile["profile_id"],
                "public_profile_id": native_profile["public_profile_id"],
                "public_schema": native_profile["public_schema"],
                "public_schema_version": native_profile["public_schema_version"],
                "profile_revision": 1,
                "platform": "android",
                "ordered_selection_ids": native_profile["metric_ids"],
                "outputs": outputs,
                "unavailable_selection_ids": [item["selection_id"] for item in android["unavailable_metrics"]],
            }
        )

    category_rows: list[dict[str, Any]] = []
    seen_categories: set[tuple[str, str]] = set()
    for profile, metric_rows in (("apple", apple["metrics"]), ("android", android["metrics"])):
        for metric in metric_rows:
            key = (profile, metric["category_id"])
            if key not in seen_categories:
                seen_categories.add(key)
                category_rows.append(
                    {
                        "platform": profile,
                        "category_id": metric["category_id"],
                        "label_key": metric["category_id"],
                        "ordinal": sum(1 for row in category_rows if row["platform"] == profile),
                    }
                )

    capability_manifest = json.loads(CAPABILITY_MANIFEST.read_text())
    return {
        "schema": "healthmd.metric_registry",
        "schema_version": 1,
        "registry_version": 1,
        "known_capability_ids": [
            capability["id"] for capability in capability_manifest["capabilities"]
        ],
        "available_capability_ids_by_platform": {
            platform: [
                capability["id"]
                for capability in capability_manifest["capabilities"]
                if capability["platforms"][platform]["state"] == "available"
            ]
            for platform in ("apple", "android")
        },
        "categories": category_rows,
        "metrics": semantic_metrics,
        "profiles": profiles,
        "legacy_unavailable": {"android": android["unavailable_metrics"]},
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="check committed importer outputs")
    args = parser.parse_args()

    apple = parse_apple()
    android = parse_android()
    registry = build_registry(apple, android)
    outputs = {APPLE_BASELINE: apple, ANDROID_BASELINE: android, REGISTRY_PATH: registry}
    if args.check:
        stale = [str(path.relative_to(REPO)) for path, value in outputs.items() if not path.exists() or path.read_bytes() != canonical_bytes(value)]
        if stale:
            raise SystemExit("stale native registry import: " + ", ".join(stale))
        print(f"Native import matches {len(apple['metrics'])} Apple and {len(android['metrics'])} Android metrics")
        return
    REGISTRY_DIR.mkdir(parents=True, exist_ok=True)
    for path, value in outputs.items():
        path.write_bytes(canonical_bytes(value))
        print(f"wrote {path.relative_to(REPO)} ({len(path.read_bytes())} bytes, {sha256(path)})")


if __name__ == "__main__":
    main()
