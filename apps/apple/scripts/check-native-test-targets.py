#!/usr/bin/env python3
"""Check complete Xcode target nodes, including independently inferred app hosts."""
import argparse
from pathlib import Path
import re


def qualify_targets(text: str, platform: str) -> list[str]:
    targets = set(re.findall(r"^\s*Target '([^']+)' in project 'HealthMd'(?: \(no dependencies\))?\s*$", text, re.MULTILINE))
    hosts = {'iOS': ('HealthMd', 'HealthMd-macOS'), 'macOS': ('HealthMd-macOS', 'HealthMd')}
    if platform not in hosts:
        raise ValueError('Unknown native test platform')
    expected, unexpected = hosts[platform]
    if not {'HealthMdTests', expected}.issubset(targets) or unexpected in targets:
        raise ValueError(f'{platform} test graph has missing or cross-platform hosts: {sorted(targets)}')
    return sorted(targets)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--log', type=Path, required=True)
    parser.add_argument('--platform', choices=('iOS', 'macOS'), required=True)
    args = parser.parse_args()
    try:
        targets = qualify_targets(args.log.read_text(), args.platform)
    except (OSError, ValueError) as error:
        parser.exit(1, f'Native test target qualification failed: {error}\n')
    print(f'Qualified {args.platform} test target nodes: {targets}')


if __name__ == '__main__':
    main()
