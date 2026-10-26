#!/usr/bin/env python3
"""Diagnostic-only cross-revision reuse; never a qualification comparator."""
import importlib.util
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
PRODUCER = '7d129fd301ef361f1d68b0c66563b8bbd775320e'
# Run40398490439 checked out GitHub's temporary PR merge. Its tree is exactly
# the producer branch-head tree; retain and verify both identities separately.
ARTIFACT_HEAD = 'fa1dfddeb92acc7f0f42b10cb6d17ed78be4f8a6'
ARTIFACT_TREE = '39ae0d07ca17072fca08ce9c2cce14f8995d60c3'
spec = importlib.util.spec_from_file_location(
    'canonical_sdk27_receipt',
    ROOT / 'apps/apple/scripts/compare-history-sdk27-receipts.py',
)
canonical = importlib.util.module_from_spec(spec)
spec.loader.exec_module(canonical)


def identity(text: str, head: str, tree: str) -> str:
    lines = text.splitlines(keepends=True)
    for label, value in [('HEAD', head), ('TREE', tree)]:
        matched = [line.rstrip('\n') for line in lines if line.startswith(label + '=')]
        if matched != [f'{label}={value}']:
            raise ValueError(f'diagnostic {label} provenance mismatch')
    return canonical.build_identity(''.join(
        line for line in lines if not line.startswith(('HEAD=', 'TREE='))
    ))


def git(*args: str) -> str:
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()


def main() -> None:
    consumer, producer = map(Path, sys.argv[1:])
    # The diagnostic changes only GitHub helpers and the previously reviewed CLI test.
    # Reject changed Apple, contract or core inputs before reusing compiled core bytes.
    subprocess.run([
        'git', 'diff', '--exit-code', PRODUCER, 'HEAD', '--',
        'apps/apple', 'packages/healthmd-core-rust', 'packages/contracts',
    ], cwd=ROOT, check=True)
    current = identity(consumer.read_text(), git('rev-parse', 'HEAD'), git('rev-parse', 'HEAD^{tree}'))
    if git('rev-parse', PRODUCER + '^{tree}') != ARTIFACT_TREE:
        raise ValueError('producer branch/merge tree mismatch')
    retained = identity(producer.read_text(), ARTIFACT_HEAD, ARTIFACT_TREE)
    if current != retained:
        raise ValueError('diagnostic SDK/compiler/OS provenance mismatch')
    print('PASS DIAGNOSTIC cross-revision core reuse only; both original receipts retained unchanged')


if __name__ == '__main__':
    main()
