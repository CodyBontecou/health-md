#!/usr/bin/env python3
"""Validate Apple documentation and monorepo contributor navigation.

Markdown links are document-relative. Literal inline paths in AGENTS.md and the
website ownership guide may also use repository-root conventions. Fenced code,
URLs, home/absolute paths, globs, and parameterized examples are not path claims.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
LINK = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
INLINE = re.compile(r"(?<!`)`([^`\n]+)`(?!`)")
REPOSITORY_PREFIXES = ("apps/", "packages/", ".agents/", ".github/")
FILE_SUFFIXES = {".md", ".json", ".toml", ".yml", ".yaml", ".py", ".mjs", ".swift", ".kt", ".rs"}


def monorepo_root() -> Path | None:
    try:
        output = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"], cwd=ROOT,
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None
    return Path(output).resolve() if output else None


def destination(raw: str) -> str:
    value = raw.strip()
    if value.startswith("<") and ">" in value:
        return value[1:value.index(">")]
    return value.split(maxsplit=1)[0] if value else ""


def prose_only(text: str) -> str:
    """Mask fenced examples while preserving offsets for line diagnostics."""
    result = []
    fence = None
    for line in text.splitlines(keepends=True):
        marker = re.match(r"^ {0,3}(`{3,}|~{3,})(.*)$", line.rstrip("\r\n"))
        if fence is None and marker:
            fence = (marker[1][0], len(marker[1]))
            result.append(re.sub(r"[^\r\n]", " ", line))
        elif fence is not None:
            result.append(re.sub(r"[^\r\n]", " ", line))
            if marker and marker[1][0] == fence[0] and len(marker[1]) >= fence[1] and not marker[2].strip():
                fence = None
        else:
            result.append(line)
    return "".join(result)


def literal_path(value: str) -> bool:
    if not value or value.startswith(("/", "~", "#")) or re.search(r"\s|[<>*{}$?\[\]()\\]", value):
        return False
    if ":" in value or "..." in value:
        return False
    return (
        value.startswith((*REPOSITORY_PREFIXES, "./", "../"))
        or value.endswith("/") and "/" in value
        or Path(value).suffix in FILE_SUFFIXES
    )


def inside(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def navigation_documents(repository: Path) -> tuple[list[Path], set[Path]]:
    agents = {repository / "AGENTS.md", *repository.glob("apps/*/AGENTS.md"), *repository.glob("packages/*/AGENTS.md")}
    ownership = repository / "apps/website/docs-src/README.md"
    documents = {
        *agents, repository / "README.md", repository / "CONTRIBUTING.md", ownership,
        *repository.glob("apps/*/README.md"), *repository.glob("packages/*/README.md"),
        repository / "docs/agents/skills.md",
        repository / "docs/architecture/monorepo.md",
        *repository.glob("docs/experiments/*.md"),
        repository / "apps/cli/docs/qa.md",
        repository / "apps/apple/worker/pricing-analytics/README.md",
        repository / ".agents/skills/healthmd-cli-development/SKILL.md",
        repository / ".agents/skills/healthmd-cli-qa/SKILL.md",
    }
    return sorted(documents), agents | {ownership}


def check_documents(documents: list[Path], repository: Path, inline_documents: set[Path] = frozenset()) -> tuple[list[str], int]:
    errors, checked = [], 0
    for document in sorted(set(documents)):
        label = str(document.relative_to(repository))
        if not document.is_file():
            errors.append(f"{label}: missing navigation document")
            continue
        text = prose_only(document.read_text(encoding="utf-8"))
        links = list(LINK.finditer(text))
        for match in links:
            target = destination(match[1])
            if not target or target.startswith("#") or re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", target):
                continue
            relative = unquote(target.split("#", 1)[0].split("?", 1)[0])
            if not relative:
                continue
            checked += 1
            resolved = (document.parent / relative).resolve()
            line = text.count("\n", 0, match.start()) + 1
            if not inside(resolved, repository):
                errors.append(f"{label}:{line}: link escapes repository: {target}")
            elif not resolved.exists():
                errors.append(f"{label}:{line}: missing local target {target}")
        if document not in inline_documents:
            continue
        for match in INLINE.finditer(text):
            # A linked code label can be shorter than its real destination.
            if any(link.start() <= match.start() < link.end() for link in links):
                continue
            target = match[1]
            if not literal_path(target):
                continue
            checked += 1
            if target.startswith(REPOSITORY_PREFIXES):
                candidates = [(repository / target).resolve()]
            else:
                candidates = [(document.parent / target).resolve(), (repository / target).resolve()]
            line = text.count("\n", 0, match.start()) + 1
            if not any(inside(path, repository) and path.exists() for path in candidates):
                errors.append(f"{label}:{line}: missing literal navigation path {target}")
    return errors, checked


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--navigation-only", action="store_true", help="check contributor entry points without scanning all Apple docs")
    arguments = parser.parse_args()
    repository = monorepo_root()
    if arguments.navigation_only and repository is None:
        parser.error("--navigation-only requires a monorepo checkout")
    documents, inline = navigation_documents(repository) if repository else ([], set())
    if not arguments.navigation_only:
        documents.extend([ROOT / "README.md", *sorted(DOCS.rglob("*.md"))])
    errors, checked = check_documents(documents, repository or ROOT, inline)
    if errors:
        print("Documentation navigation check failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print(f"Documentation navigation valid: {checked} local links/literal paths checked")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
