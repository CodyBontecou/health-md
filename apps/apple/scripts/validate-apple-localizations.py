#!/usr/bin/env python3
"""Full Apple catalog coverage/token guard; nonlinguistic artifacts are explicit.

This proves catalog resource coverage, not UI reachability or visual correctness.
"""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('reviewed_catalog_merge', ROOT / 'scripts/merge-reviewed-localizations.py')
assert SPEC and SPEC.loader
merger = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(merger)
LOCALES = merger.LOCALES
CATALOG = ROOT / 'HealthMd/Localizable.xcstrings'
EXEMPTIONS = ROOT / 'scripts/fixtures/apple-localization-literals.json'


def leaves(node):
    if not isinstance(node, dict):
        return
    if 'stringUnit' in node:
        yield node['stringUnit']
    for key, value in node.items():
        if key != 'stringUnit':
            yield from leaves(value)


def validate(catalog, exemptions):
    errors = []
    strings = catalog['strings']
    if catalog.get('sourceLanguage') != 'en':
        errors.append('source language must stay en')
    for key, reason in exemptions.items():
        if key not in strings or not isinstance(reason, str) or not reason.strip():
            errors.append(f'invalid literal exemption: {key!r}')
        # A prose exemption must not become a back door for untranslated UI copy.
        if any(c.isalpha() for c in key.replace('%lld', '').replace('%@', '')) and not key.startswith('https://'):
            errors.append(f'language-bearing exemption: {key!r}')
    for key, entry in strings.items():
        if key in exemptions:
            continue
        english = list(leaves(entry.get('localizations', {}).get('en', {})))
        source = english[0]['value'] if english else key
        for locale in LOCALES:
            units = list(leaves(entry.get('localizations', {}).get(locale, {})))
            if not units:
                errors.append(f'{locale}: missing localization: {key!r}')
            for unit in units:
                value = unit.get('value')
                if unit.get('state') != 'translated' or not isinstance(value, str) or not value.strip():
                    errors.append(f'{locale}: incomplete translation: {key!r}')
                elif merger.token_signature(source) != merger.token_signature(value):
                    errors.append(f'{locale}: placeholder mismatch: {key!r}')
    return errors


def main():
    errors = validate(merger.load_json(CATALOG.read_text()), merger.load_json(EXEMPTIONS.read_text()))
    for error in errors:
        print(error)
    if not errors:
        print(f'All language-bearing Apple catalog entries have complete translations in {len(LOCALES)} locales; literal exemptions reviewed.')
    return bool(errors)


if __name__ == '__main__':
    raise SystemExit(main())
