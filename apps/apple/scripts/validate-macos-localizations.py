#!/usr/bin/env python3
"""Validate the reviewed production macOS localization surface without Xcode.

The source scan is intentionally enforceable rather than advertised as a Swift parser: it
covers known localization APIs, AppKit text assignments, and reviewed display producers.
Exact exclusions document technical strings that must remain verbatim.
"""

from __future__ import annotations

from collections import Counter
import ast
import json
from pathlib import Path
import re
import sys
from typing import Iterable

APPLE_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = APPLE_ROOT.parents[1]
CATALOG_PATH = APPLE_ROOT / "HealthMd/Localizable.xcstrings"
MANIFEST_PATH = APPLE_ROOT / "scripts/fixtures/macos-localization-keys.json"
PROJECT_PATH = APPLE_ROOT / "HealthMd.xcodeproj/project.pbxproj"
MAC_ROOT = APPLE_ROOT / "HealthMd/macOS"
SHARED_MAC_DISPLAY = (
    APPLE_ROOT / "HealthMd/Shared/Theme/DesignSystem.swift",
    APPLE_ROOT / "HealthMd/Shared/Views/ExportPreviewView.swift",
    APPLE_ROOT / "HealthMd/Shared/Views/ExportFormatHelpSheet.swift",
    APPLE_ROOT / "HealthMd/Shared/Export/ExportRolloutCopy.swift",
    APPLE_ROOT / "HealthMd/Shared/Export/HealthRollupModels.swift",
    APPLE_ROOT / "HealthMd/Shared/Managers/ExportOrchestrator.swift",
    APPLE_ROOT / "HealthMd/Shared/Managers/VaultManager.swift",
    APPLE_ROOT / "HealthMd/Shared/Models/AdvancedExportSettings.swift",
    APPLE_ROOT / "HealthMd/Shared/Models/ExportDateRangePreset.swift",
    APPLE_ROOT / "HealthMd/Shared/Models/ExportHistory.swift",
    APPLE_ROOT / "HealthMd/Shared/Models/ExportSchedule.swift",
    APPLE_ROOT / "HealthMd/Shared/Models/FormatPreferences.swift",
    APPLE_ROOT / "HealthMd/Shared/Models/HealthData.swift",
    APPLE_ROOT / "HealthMd/Shared/Models/HealthMetrics.swift",
    APPLE_ROOT / "HealthMd/Shared/Models/SyncEventHistory.swift",
)
MAC_VISIBLE_PARTIAL_FAILURE_UI = {
    APPLE_ROOT / "HealthMd/Shared/Views/ExportPreviewView.swift",
    APPLE_ROOT / "HealthMd/macOS/Views/MacHistoryView.swift",
}
RAW_PARTIAL_FAILURE_SUMMARY = re.compile(r"\b(?:failure|first)\.summary\b")

# Controls, identifiers, and output-contract values—not linguistic UI copy.
FIXED_LITERAL_EXCLUSIONS = {
    "": "empty SwiftUI accessibility value",
    "·": "visual separator",
    "⌘Q": "standard keyboard shortcut glyph",
    "Reopens the iPad navigation sidebar": "iPad-only shared design-system control",
}
COMPUTED_PROPERTY_EXCLUSIONS = {
    "accessibilityIdentifierSuffix": "UI-test identifier",
    "folderName": "public export path component",
    "iconName": "SF Symbol identifier",
    "formatFolderName": "public export path component",
    "sizeLabel": "locale-neutral byte count formatted separately",
}
LOCALIZING_APIS = (
    "Text", "Label", "Button", "Toggle", "Picker", "Section", "Menu", "Link",
    "BrandLabel", "navigationTitle", "accessibilityLabel", "accessibilityValue",
    "accessibilityHint", "alert", "help",
)
LOCALIZED_PREFIX = re.compile(r'\bString\s*\(\s*localized\s*:\s*(")')
UI_LITERAL_PREFIX = re.compile(
    r'\b(?:' + "|".join(LOCALIZING_APIS) + r')\s*\(\s*(")'
)
APPKIT_PREFIX = re.compile(
    r'\b[A-Za-z_]\w*\.(?:title|message|prompt|informativeText|messageText)\s*=\s*(")'
)
RETURN_PREFIX = re.compile(r'\breturn\s+(")')
DECLARATION = re.compile(r"\b(?:var|func)\s+([A-Za-z_]\w*)")
DISPLAY_NAME_SUFFIXES = (
    "Text", "Title", "Description", "Label", "Message", "Subtitle", "Detail", "Name", "Status",
)
PRINTF_TOKEN = re.compile(r"%(?:(\d+)\$)?(lld|ld|d|@|f|s)")
OTHER_TOKEN = re.compile(r"\{\{[^{}]+\}\}|\{[^{}]+\}|`[^`]+`")
METRIC_ROW = re.compile(
    r'HealthMetricDefinition\(id: "(?:[^"\\]|\\.)*", name: "((?:[^"\\]|\\.)*)", '
    r'category: \.[A-Za-z]+, unit: "((?:[^"\\]|\\.)*)"'
)
EXPECTED_PLURAL_BRANCHES = {
    "en": {"one", "other"},
    "de": {"one", "other"},
    "es": {"one", "other"},
    "fr": {"one", "other"},
    "it": {"one", "other"},
    "ja": {"other"},
    "ko": {"other"},
    "nl": {"one", "other"},
    "pt-BR": {"one", "other"},
    "zh-Hans": {"other"},
}


def source_files() -> list[Path]:
    mac_files = [path for path in MAC_ROOT.rglob("*.swift") if "Debug" not in path.parts]
    return sorted(set(mac_files).union(SHARED_MAC_DISPLAY))


def metric_registry_terms(source: str | None = None) -> tuple[list[str], list[str]]:
    if source is None:
        source = (APPLE_ROOT / "HealthMd/Shared/Models/HealthMetrics.swift").read_text()
    generated = source.split("// BEGIN GENERATED SHARED RUST METRIC REGISTRY", 1)[1]
    generated = generated.split("// END GENERATED SHARED RUST METRIC REGISTRY", 1)[0]
    rows = METRIC_ROW.findall(generated)
    names = sorted({decode_swift_literal(name) for name, _ in rows})
    units = sorted({decode_swift_literal(unit) for _, unit in rows if unit})
    return names, units


def decode_swift_literal(raw: str) -> str:
    if r"\(" in raw:
        return raw.replace(r'\"', '"').replace(r"\n", "\n")
    try:
        return ast.literal_eval('"' + raw + '"')
    except (SyntaxError, ValueError):
        return raw.replace(r'\"', '"').replace(r"\n", "\n")


def split_interpolations(raw: str) -> list[tuple[str, str]]:
    """Return ('literal'|'expression', text) parts for a Swift string body."""
    parts: list[tuple[str, str]] = []
    literal_start = 0
    index = 0
    while index < len(raw) - 1:
        if raw[index:index + 2] != r"\(":
            index += 1
            continue
        if literal_start < index:
            parts.append(("literal", raw[literal_start:index]))
        depth = 1
        cursor = index + 2
        in_string = False
        escaped = False
        while cursor < len(raw) and depth:
            char = raw[cursor]
            if in_string:
                if escaped:
                    escaped = False
                elif char == "\\":
                    escaped = True
                elif char == '"':
                    in_string = False
            else:
                if char == '"':
                    in_string = True
                elif char == "(":
                    depth += 1
                elif char == ")":
                    depth -= 1
            cursor += 1
        if depth:
            # Let catalog resolution report the malformed/unresolved literal.
            parts.append(("literal", raw[index:]))
            return parts
        parts.append(("expression", raw[index + 2:cursor - 1]))
        literal_start = cursor
        index = cursor
    if literal_start < len(raw):
        parts.append(("literal", raw[literal_start:]))
    return parts


def catalog_key_candidates(raw: str, catalog_keys: Iterable[str]) -> list[str]:
    if r"\(" not in raw:
        key = decode_swift_literal(raw)
        return [key] if key in catalog_keys else []
    pattern = "^"
    expression_count = 0
    for kind, value in split_interpolations(raw):
        if kind == "literal":
            pattern += re.escape(decode_swift_literal(value))
        else:
            expression_count += 1
            pattern += r"%(?:\d+\$)?(?:lld|ld|d|@|f|s)"
    pattern += "$"
    matcher = re.compile(pattern)
    candidates = sorted(key for key in catalog_keys if matcher.fullmatch(key))
    # A source key must retain exactly one printf argument per interpolation.
    candidates = [key for key in candidates if len(PRINTF_TOKEN.findall(key)) == expression_count]
    if len(candidates) <= 1:
        return candidates

    expressions = [value for kind, value in split_interpolations(raw) if kind == "expression"]
    inferred_types = []
    for expression in expressions:
        lowered = expression.lower()
        numeric = bool(re.search(
            r"(?:^|\.)(?:count|total|processed|written|enabled|percent|port|days?|files?|records?)\b",
            lowered,
        )) or any(term in lowered for term in (
            "count", "total", "processed", "written", "enabled", "percent", "port"
        )) or bool(re.search(r"\b\d+\b|\s[+*/%-]\s", expression))
        inferred_types.append("lld" if numeric else "@")
    return [
        key for key in candidates
        if [token_type for _, token_type in PRINTF_TOKEN.findall(key)] == inferred_types
    ]


def latest_declaration_name(source: str, position: int) -> str | None:
    matches = list(DECLARATION.finditer(source, 0, position))
    return matches[-1].group(1) if matches else None


def swift_string_body(source: str, opening_quote: int) -> tuple[str, int] | None:
    """Extract a Swift string body, including quoted expressions inside interpolation."""
    cursor = opening_quote + 1
    interpolation_depth = 0
    expression_string = False
    escaped = False
    while cursor < len(source):
        char = source[cursor]
        if interpolation_depth:
            if expression_string:
                if escaped:
                    escaped = False
                elif char == "\\":
                    escaped = True
                elif char == '"':
                    expression_string = False
            else:
                if char == '"':
                    expression_string = True
                elif char == "(":
                    interpolation_depth += 1
                elif char == ")":
                    interpolation_depth -= 1
            cursor += 1
            continue
        if char == '"':
            return source[opening_quote + 1:cursor], cursor + 1
        if source[cursor:cursor + 2] == r"\(":
            interpolation_depth = 1
            cursor += 2
            continue
        if char == "\\":
            cursor += 2
            continue
        cursor += 1
    return None


def scan_source_text(source: str, *, scan_computed_returns: bool = True) -> list[tuple[str, str, int]]:
    """Return (raw string body, scan kind, line) for the reviewed regex surface."""
    found: list[tuple[str, str, int]] = []
    occupied_quotes: set[int] = set()
    for kind, pattern in (
        ("String(localized:)", LOCALIZED_PREFIX),
        ("localized UI call", UI_LITERAL_PREFIX),
        ("AppKit assignment", APPKIT_PREFIX),
    ):
        for match in pattern.finditer(source):
            quote = match.start(1)
            if quote in occupied_quotes:
                continue
            extracted = swift_string_body(source, quote)
            if not extracted:
                continue
            occupied_quotes.add(quote)
            found.append((extracted[0], kind, source.count("\n", 0, match.start()) + 1))

    if not scan_computed_returns:
        return found

    for match in RETURN_PREFIX.finditer(source):
        property_name = latest_declaration_name(source, match.start())
        if not property_name or property_name in COMPUTED_PROPERTY_EXCLUSIONS:
            continue
        if not property_name.endswith(DISPLAY_NAME_SUFFIXES):
            continue
        extracted = swift_string_body(source, match.start(1))
        if not extracted:
            continue
        found.append((
            extracted[0],
            f"computed display producer {property_name}",
            source.count("\n", 0, match.start()) + 1,
        ))
    return found


def scanned_catalog_keys(strings: dict) -> tuple[dict[str, list[str]], list[str], int]:
    found: dict[str, list[str]] = {}
    errors: list[str] = []
    scanned_count = 0
    # Raw computed-return scanning is limited to Views and reviewed shared display
    # producers. Manager completion strings can be verbatim protocol payload detail;
    # explicit String(localized:) calls and AppKit assignments are still scanned there.
    computed_display_files = {
        APPLE_ROOT / "HealthMd/Shared/Managers/VaultManager.swift",
        APPLE_ROOT / "HealthMd/Shared/Models/AdvancedExportSettings.swift",
        APPLE_ROOT / "HealthMd/Shared/Models/ExportHistory.swift",
        APPLE_ROOT / "HealthMd/Shared/Models/SyncEventHistory.swift",
        APPLE_ROOT / "HealthMd/Shared/Export/HealthRollupModels.swift",
        APPLE_ROOT / "HealthMd/Shared/Views/ExportPreviewView.swift",
    }
    for path in source_files():
        source = path.read_text()
        scan_computed = "Views" in path.parts or path in computed_display_files
        for raw, kind, line in scan_source_text(source, scan_computed_returns=scan_computed):
            scanned_count += 1
            location = f"{path.relative_to(REPO_ROOT)}:{line}"
            candidates = catalog_key_candidates(raw, strings)
            if not candidates:
                rendered = decode_swift_literal(raw)
                if rendered in FIXED_LITERAL_EXCLUSIONS:
                    continue
                errors.append(f"{kind} has no catalog key for {rendered!r} at {location}")
                continue
            if len(candidates) > 1:
                errors.append(f"{kind} is ambiguous at {location}: {candidates}")
                continue
            key = candidates[0]
            if key in FIXED_LITERAL_EXCLUSIONS:
                continue
            found.setdefault(key, []).append(location)
    return found, errors, scanned_count


def token_signature(value: str) -> Counter[tuple[object, ...]]:
    """Preserve printf argument index and type while permitting translated order."""
    signature: Counter[tuple[object, ...]] = Counter()
    implicit_index = 0
    for match in PRINTF_TOKEN.finditer(value):
        implicit_index += 1
        index = int(match.group(1)) if match.group(1) else implicit_index
        signature[("printf", index, match.group(2))] += 1
    for token in OTHER_TOKEN.findall(value):
        signature[("literal", token)] += 1
    return signature


def leaves(localization: dict) -> dict[tuple[str, ...], dict]:
    result: dict[tuple[str, ...], dict] = {}

    def walk(node: object, path: tuple[str, ...]) -> None:
        if not isinstance(node, dict):
            return
        unit = node.get("stringUnit")
        if isinstance(unit, dict):
            result[path] = unit
        for key, value in node.items():
            if key != "stringUnit":
                walk(value, path + (key,))

    walk(localization, ())
    return result


def variation_schemas(localization: dict) -> dict[tuple[str, ...], set[str]]:
    schemas: dict[tuple[str, ...], set[str]] = {}

    def walk(node: object, path: tuple[str, ...]) -> None:
        if not isinstance(node, dict):
            return
        variations = node.get("variations")
        if isinstance(variations, dict):
            for kind, branches in variations.items():
                if isinstance(branches, dict):
                    schemas[path + (kind,)] = set(branches)
                    for branch, child in branches.items():
                        walk(child, path + (kind, branch))
        for key, child in node.items():
            if key not in {"variations", "stringUnit"}:
                walk(child, path + (key,))

    walk(localization, ())
    return schemas


def validate_variation_schema(localization: dict, locale: str, key: str) -> list[str]:
    errors: list[str] = []
    schemas = variation_schemas(localization)
    for path, branches in schemas.items():
        kind = path[-1]
        if "other" not in branches:
            errors.append(f"{locale}: variation {key!r} {path} is missing 'other'")
        if kind == "plural":
            expected = EXPECTED_PLURAL_BRANCHES[locale]
            if branches != expected:
                errors.append(
                    f"{locale}: variation branches for {key!r} {path} must be "
                    f"{sorted(expected)}, found {sorted(branches)}"
                )
        else:
            errors.append(f"{locale}: unsupported variation kind {kind!r} for {key!r} {path}")

    def require_branch_leaves(node: object, path: tuple[str, ...] = ()) -> None:
        if not isinstance(node, dict):
            return
        variations = node.get("variations")
        if isinstance(variations, dict):
            for kind, branches in variations.items():
                if not isinstance(branches, dict):
                    continue
                for branch, child in branches.items():
                    branch_path = path + (kind, branch)
                    if not leaves(child):
                        errors.append(
                            f"{locale}: variation branch for {key!r} {branch_path} has no stringUnit leaf"
                        )
                    require_branch_leaves(child, branch_path)
        for child_key, child in node.items():
            if child_key not in {"variations", "stringUnit"}:
                require_branch_leaves(child, path + (child_key,))

    require_branch_leaves(localization)
    return errors


def source_unit_for_path(english: dict[tuple[str, ...], dict], path: tuple[str, ...]) -> dict | None:
    if path in english:
        return english[path]
    # Locales without singular morphology map their `other` leaf to English `other`.
    other_path = tuple("other" if part in {"zero", "one", "two", "few", "many"} else part for part in path)
    return english.get(other_path) or english.get(())


def normalized_source_equal_value(value: str) -> str:
    return PRINTF_TOKEN.sub(lambda match: f"%{match.group(2)}", value)


def requires_source_equal_review(value: str) -> bool:
    return bool(re.search(r"[A-Za-z0-9µ°%]", value))


def validate_source_equal(
    key: str,
    locale: str,
    source_value: str,
    target_value: str,
    allowlist: set[str],
) -> list[str]:
    if (normalized_source_equal_value(target_value) != normalized_source_equal_value(source_value)
            or not requires_source_equal_review(source_value)):
        return []
    if key not in allowlist:
        return [f"{locale}: source-equal value is not reviewed for {key!r}: {target_value!r}"]
    return []


def validate_partial_failure_ui_summary(path: Path, source: str) -> list[str]:
    """Keep raw protocol/query failure detail out of Mac-visible warning UI."""
    if path.resolve() not in {candidate.resolve() for candidate in MAC_VISIBLE_PARTIAL_FAILURE_UI}:
        return []
    return [
        f"raw ExportPartialFailure.summary used in Mac-visible UI at "
        f"{path.relative_to(REPO_ROOT)}:{source.count(chr(10), 0, match.start()) + 1}; "
        "use localizedSummary"
        for match in RAW_PARTIAL_FAILURE_SUMMARY.finditer(source)
    ]


def main() -> int:
    errors: list[str] = []
    catalog = json.loads(CATALOG_PATH.read_text())
    strings = catalog.get("strings", {})
    manifest = json.loads(MANIFEST_PATH.read_text())
    locales = manifest.get("locales", [])
    keys = manifest.get("keys", [])
    source_equal_allowlist = manifest.get("sourceEqualAllowlist", {})

    expected_locales = ["de", "es", "fr", "it", "ja", "ko", "nl", "pt-BR", "zh-Hans"]
    if locales != expected_locales:
        errors.append(f"manifest locales must be {expected_locales}, found {locales}")
    if keys != sorted(set(keys)):
        errors.append("manifest keys must be unique and sorted")
    if set(source_equal_allowlist) != set(expected_locales):
        errors.append("sourceEqualAllowlist must contain exactly every reviewed locale")
    for locale in expected_locales:
        allowed = source_equal_allowlist.get(locale, [])
        if allowed != sorted(set(allowed)):
            errors.append(f"{locale}: sourceEqualAllowlist must be unique and sorted")

    project = PROJECT_PATH.read_text()
    for locale in expected_locales:
        project_token = f'"{locale}"' if "-" in locale else locale
        if not re.search(rf"^\s*{re.escape(project_token)},\s*$", project, re.MULTILINE):
            errors.append(f"Xcode knownRegions is missing {locale}")

    scanned, scan_errors, scanned_count = scanned_catalog_keys(strings)
    errors.extend(scan_errors)
    for key, locations in sorted(scanned.items()):
        if key not in keys:
            errors.append(f"scanned macOS key missing from reviewed manifest: {key!r} at {locations[0]}")

    metric_names, metric_units = metric_registry_terms()
    if len(metric_names) != 230:
        errors.append(f"generated HealthMetrics registry must contain 230 unique names, found {len(metric_names)}")
    for term in metric_names + metric_units + ["Source records only"]:
        if term not in strings:
            errors.append(f"metric picker term missing from catalog: {term!r}")
        elif term not in keys:
            errors.append(f"metric picker term missing from reviewed manifest: {term!r}")

    actual_source_equal: dict[str, set[str]] = {locale: set() for locale in expected_locales}
    checked_units = 0
    for key in keys:
        entry = strings.get(key)
        if not isinstance(entry, dict):
            errors.append(f"manifest key missing from catalog: {key!r}")
            continue
        localizations = entry.get("localizations", {})
        english_localization = localizations.get("en", {})
        english_leaves = leaves(english_localization)
        errors.extend(validate_variation_schema(english_localization, "en", key))
        english_schemas = variation_schemas(english_localization)
        for locale in expected_locales:
            localization = localizations.get(locale)
            if not isinstance(localization, dict):
                errors.append(f"{locale}: missing localization for {key!r}")
                continue
            target_leaves = leaves(localization)
            if not target_leaves:
                errors.append(f"{locale}: no string units or variations for {key!r}")
                continue
            errors.extend(validate_variation_schema(localization, locale, key))
            target_schemas = variation_schemas(localization)
            if set(english_schemas) != set(target_schemas):
                errors.append(
                    f"{locale}: variation schema paths differ from English for {key!r}: "
                    f"source={sorted(english_schemas)}, target={sorted(target_schemas)}"
                )
            for path, unit in target_leaves.items():
                checked_units += 1
                value = unit.get("value")
                if unit.get("state") != "translated":
                    errors.append(f"{locale}: state is {unit.get('state')!r} for {key!r} {path}")
                if not isinstance(value, str) or not value.strip():
                    errors.append(f"{locale}: empty value for {key!r} {path}")
                    continue
                source_unit = source_unit_for_path(english_leaves, path)
                source_value = source_unit.get("value", key) if source_unit else key
                if token_signature(source_value) != token_signature(value):
                    errors.append(
                        f"{locale}: token mismatch for {key!r} {path}: "
                        f"source={dict(token_signature(source_value))}, "
                        f"target={dict(token_signature(value))}"
                    )
                allowed = set(source_equal_allowlist.get(locale, []))
                equal_errors = validate_source_equal(key, locale, source_value, value, allowed)
                errors.extend(equal_errors)
                if (normalized_source_equal_value(value) == normalized_source_equal_value(source_value)
                        and requires_source_equal_review(source_value)):
                    actual_source_equal[locale].add(key)

    for locale in expected_locales:
        allowed = set(source_equal_allowlist.get(locale, []))
        stale = allowed - actual_source_equal[locale]
        for key in sorted(stale):
            errors.append(f"{locale}: stale source-equal allowlist key {key!r}")

    # State must never depend on translated display copy, and Mac-visible partial
    # failure warnings must use localized UI framing rather than raw protocol detail.
    for path in source_files():
        source = path.read_text()
        if re.search(r"(?:readiness|status)[A-Za-z]*Text\s*==\s*\"", source):
            errors.append(f"English display string used as state in {path.relative_to(REPO_ROOT)}")
        errors.extend(validate_partial_failure_ui_summary(path, source))

    if errors:
        print("macOS localization validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print(
        f"Validated {len(keys)} production macOS keys across {len(expected_locales)} locales "
        f"({checked_units} translated units; {scanned_count} source literals scanned; "
        f"{len(metric_names)} registry metric names checked)."
    )
    print(
        "Exact source-equal allowlist entries: "
        + ", ".join(f"{locale}={len(actual_source_equal[locale])}" for locale in expected_locales)
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
