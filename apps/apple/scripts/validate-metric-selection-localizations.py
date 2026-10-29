#!/usr/bin/env python3
"""Guard the bounded Health Metrics localization slice, without Xcode or devices.

Reuses the owning catalog's literal/interpolation and token/variation helpers.
This is a reviewed source boundary, not a Swift parser or UI reachability test.
"""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

APPLE_ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = APPLE_ROOT / "scripts/fixtures/metric-selection-localization-keys.json"
CATALOG_PATH = APPLE_ROOT / "HealthMd/Localizable.xcstrings"
SPEC = importlib.util.spec_from_file_location(
    "macos_localization_helpers", APPLE_ROOT / "scripts/validate-macos-localizations.py"
)
assert SPEC and SPEC.loader
helpers = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(helpers)
LOCALES = ["de", "es", "fr", "it", "ja", "ko", "nl", "pt-BR", "zh-Hans"]


def source_keys(source: str, keys: list[str]) -> set[str]:
    """Resolve reviewed literals, including ternary branches and computed returns."""
    found: set[str] = set()
    cursor = 0
    while cursor < len(source):
        quote = source.find('"', cursor)
        if quote < 0:
            break
        extracted = helpers.swift_string_body(source, quote)
        if not extracted:
            cursor = quote + 1
            continue
        raw, cursor = extracted
        found.update(helpers.catalog_key_candidates(raw, keys))
    return found


def validate(catalog: dict, manifest: dict, sources: dict[str, str]) -> list[str]:
    errors: list[str] = []
    keys = manifest["keys"]
    if not keys or keys != sorted(set(keys)):
        errors.append("reviewed keys must be nonempty, unique and sorted")
    if manifest["locales"] != LOCALES:
        errors.append("reviewed locales must match all nine supported non-English locales")
    retained = manifest.get("retainedKeys", {})
    if not set(retained).issubset(keys) or any(not reason.strip() for reason in retained.values()):
        errors.append("retained keys need a reviewed key and an explicit reason")

    found: set[str] = set()
    for path, spec in manifest["sources"].items():
        source = sources[path]
        if "after" in spec:
            if spec["after"] not in source:
                errors.append(f"{path}: missing reviewed source boundary")
            source = source.split(spec["after"], 1)[-1]
        if "before" in spec:
            if spec["before"] not in source:
                errors.append(f"{path}: missing reviewed source boundary")
            source = source.split(spec["before"], 1)[0]
        found.update(source_keys(source, keys))
        explicit_keys: set[str] = set()
        for raw, kind, _ in helpers.scan_source_text(source, scan_computed_returns=False):
            if kind == "String(localized:)":
                explicit_keys.update(helpers.catalog_key_candidates(raw, keys))
        for key in spec.get("localizedStringKeys", []):
            if key not in explicit_keys:
                errors.append(f"{path}: missing String(localized:) binding for {key!r}")
        # These pin the localization-sensitive adapter handoffs, not layout.
        for binding in spec.get("requiredBindings", []):
            if binding not in source:
                errors.append(f"{path}: missing localized binding: {binding}")
        for binding in spec.get("forbiddenBindings", []):
            if binding in source:
                errors.append(f"{path}: unlocalized binding: {binding}")
    for key in sorted(set(keys) - found - set(retained)):
        errors.append(f"reviewed key no longer linked to source: {key!r}")

    strings = catalog["strings"]
    for key in keys:
        localizations = strings.get(key, {}).get("localizations", {})
        for locale in LOCALES:
            localization = localizations.get(locale, {})
            units = helpers.leaves(localization)
            if not units:
                errors.append(f"{locale}: missing localization for {key!r}")
                continue
            errors.extend(helpers.validate_variation_schema(localization, locale, key))
            for path, unit in units.items():
                value = unit.get("value")
                if unit.get("state") != "translated" or not isinstance(value, str) or not value.strip():
                    errors.append(f"{locale}: incomplete translation for {key!r} {path}")
                elif value == key:
                    errors.append(f"{locale}: untranslated English for {key!r}")
                elif helpers.token_signature(key) != helpers.token_signature(value):
                    errors.append(f"{locale}: token mismatch for {key!r} {path}")
    return errors


def load_inputs(manifest_path: Path = MANIFEST_PATH) -> tuple[dict, dict, dict[str, str]]:
    manifest = json.loads(manifest_path.read_text())
    return (
        json.loads(CATALOG_PATH.read_text()),
        manifest,
        {path: (APPLE_ROOT / path).read_text() for path in manifest["sources"]},
    )


def main() -> int:
    catalog, manifest, sources = load_inputs()
    errors = validate(catalog, manifest, sources)
    if errors:
        for error in errors:
            print(f"- {error}")
        return 1
    print(f"Validated {len(manifest['keys'])} Health Metrics keys across {len(LOCALES)} locales and localized adapter bindings.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
