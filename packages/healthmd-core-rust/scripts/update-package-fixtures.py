#!/usr/bin/env python3
"""Mirror canonical contract bytes needed by the standalone core source archive."""
import argparse
import re
from pathlib import Path

root = Path(__file__).resolve().parents[3]
crate = root / 'packages/healthmd-core-rust/crates/healthmd-core'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
paths = set()
for source in sorted((crate / 'tests').glob('*.rs')):
    paths.update(re.findall(r'"fixtures/contracts/([^"\n]+)"', source.read_text()))
if not paths:
    raise SystemExit('No core package contract fixtures declared')
for relative in sorted(paths):
    source = root / 'packages/contracts' / relative
    target = crate / 'tests/fixtures/contracts' / relative
    if args.check:
        if not target.is_file() or target.read_bytes() != source.read_bytes():
            raise SystemExit(f'Core package fixture drift: {relative}')
    else:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(source.read_bytes())
actual = {str(path.relative_to(crate / 'tests/fixtures/contracts'))
          for path in (crate / 'tests/fixtures/contracts').rglob('*') if path.is_file()}
if actual != paths:
    raise SystemExit('Unexpected core package fixture mirror')
print(f'Core package fixtures match {len(paths)} canonical contract files')
