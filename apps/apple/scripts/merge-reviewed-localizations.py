#!/usr/bin/env python3
"""Add reviewed locale maps without rewriting unrelated catalog entries/units.

Usage: merge-reviewed-localizations.py --catalog PATH --locale-map de=PATH [...]
Maps are English catalog keys -> translated strings. Existing units are immutable;
new English keys may be added, but unknown locales or placeholder drift fail closed.
"""
from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path
import re

LOCALES = ['de', 'es', 'fr', 'it', 'ja', 'ko', 'nl', 'pt-BR', 'zh-Hans']
PRINTF = re.compile(r'%%|%(?:(\d+)\$)?[-+#0 ]*(?:\d+|\*)?(?:\.\d+)?((?:hh|h|ll|l|z|t|j|L)?[diuoxXfFeEgGaAcsp@])')
BRACE = re.compile(r'\$?\{[^{}]+\}')


def token_signature(text: str) -> Counter:
    # Positional arguments permit natural translated order, but preserve the
    # original argument identity/type/multiplicity. %% consumes no argument.
    signature = Counter()
    implicit = 0
    for match in PRINTF.finditer(text):
        if match.group() == '%%':
            continue
        implicit += 1
        index = int(match.group(1)) if match.group(1) else implicit
        signature[('printf', index, match.group(2))] += 1
    for marker in BRACE.findall(text):
        signature[('literal', marker)] += 1
    return signature


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f'duplicate JSON key: {key!r}')
        result[key] = value
    return result


def load_json(text: str):
    return json.loads(text, object_pairs_hook=unique_object)


def entry_spans(text: str):
    """Locate JSON values structurally, never via English-key substring matching."""
    match = re.search(r'"strings"\s*:\s*\{', text)
    if not match:
        raise ValueError('missing catalog strings object')
    decoder = json.JSONDecoder()
    cursor = match.end()
    spans = {}
    while True:
        while text[cursor].isspace():
            cursor += 1
        if text[cursor] == '}':
            return spans, cursor
        key, cursor = decoder.raw_decode(text, cursor)
        while text[cursor].isspace():
            cursor += 1
        if text[cursor] != ':':
            raise ValueError('invalid catalog entry')
        cursor += 1
        while text[cursor].isspace():
            cursor += 1
        start = cursor
        _, cursor = decoder.raw_decode(text, cursor)
        spans[key] = (start, cursor)
        while text[cursor].isspace():
            cursor += 1
        if text[cursor] == ',':
            cursor += 1
        elif text[cursor] != '}':
            raise ValueError('invalid catalog entry separator')


def render_entry(value: dict) -> str:
    # Compact units keep a large coverage update readable without catalog-wide churn.
    if set(value) == {'localizations'}:
        lines = ['{', '      "localizations" : {']
        for index, (locale, localization) in enumerate(value['localizations'].items()):
            comma = ',' if index + 1 < len(value['localizations']) else ''
            lines.append('        ' + json.dumps(locale) + ': ' + json.dumps(localization, ensure_ascii=False, separators=(',', ':')) + comma)
        return '\n'.join(lines + ['      }', '    }'])
    return json.dumps(value, ensure_ascii=False, indent=2).replace('\n', '\n    ')


def merge(text: str, maps: dict[str, dict[str, str]]) -> str:
    catalog = load_json(text)
    before = catalog['strings']
    spans, end = entry_spans(text)
    changes = {}
    for locale, mapping in maps.items():
        if locale not in LOCALES or not isinstance(mapping, dict):
            raise ValueError(f'unsupported locale/map: {locale}')
        for key, value in mapping.items():
            if not isinstance(key, str) or not key or not isinstance(value, str) or not value.strip():
                raise ValueError(f'{locale}: invalid key/value: {key!r}')
            if token_signature(key) != token_signature(value):
                raise ValueError(f'{locale}: placeholder mismatch: {key!r}')
            entry = changes.setdefault(key, json.loads(json.dumps(before.get(key, {}))))
            localized = entry.setdefault('localizations', {})
            new_unit = {'stringUnit': {'state': 'translated', 'value': value}}
            if locale in localized:
                if localized[locale] != new_unit:
                    raise ValueError(f'{locale}: refusing to overwrite existing unit: {key!r}')
            else:
                localized[locale] = new_unit
    replacements = [(spans[k][0], spans[k][1], render_entry(e)) for k, e in changes.items() if k in spans and e != before[k]]
    added = [(k, e) for k, e in changes.items() if k not in spans]
    if added:
        # Insert before the closing strings brace; leave all original entries intact.
        prefix_end = end
        while text[prefix_end - 1].isspace():
            prefix_end -= 1
        payload = (',' if before else '') + '\n' + ',\n'.join('    ' + json.dumps(k, ensure_ascii=False) + ' : ' + render_entry(e) for k, e in sorted(added))
        replacements.append((prefix_end, end, payload + '\n  '))
    for start, stop, replacement in sorted(replacements, reverse=True):
        text = text[:start] + replacement + text[stop:]
    after = load_json(text)['strings']
    for key, original in before.items():
        for locale, unit in original.get('localizations', {}).items():
            if after[key].get('localizations', {}).get(locale) != unit:
                raise ValueError(f'changed original unit: {locale}/{key}')
        for field, value in original.items():
            if field != 'localizations' and after[key].get(field) != value:
                raise ValueError(f'changed original metadata: {key}/{field}')
    return text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--catalog', type=Path, required=True)
    parser.add_argument('--locale-map', action='append', required=True)
    args = parser.parse_args()
    maps = {}
    for item in args.locale_map:
        locale, filename = item.split('=', 1)
        if locale in maps:
            raise ValueError(f'duplicate locale argument: {locale}')
        maps[locale] = load_json(Path(filename).read_text())
    original = args.catalog.read_text()
    updated = merge(original, maps)
    if args.catalog.read_text() != original:
        raise ValueError('catalog changed during merge')
    args.catalog.write_text(updated)
    print(f'Merged {sum(map(len, maps.values()))} reviewed locale entries; all existing units/metadata preserved.')


if __name__ == '__main__':
    main()
