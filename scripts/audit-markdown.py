#!/usr/bin/env python3
"""Read-only, dependency-aware Markdown inventory. Findings are not deletion rules.

Run from any directory in the checkout:
    python3 scripts/audit-markdown.py

Reports go to ignored .pi/markdown-audit/{inventory.json,inventory.csv} by default.
Only reports are written; source documents, task records, and Git are never edited.
"""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import csv
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import posixpath
import re
import subprocess
from urllib.parse import unquote, urlsplit

LINK = re.compile(r"!?\[[^\]\n]*\]\((<[^>]+>|[^)\n]+)\)")
DEFINITION = re.compile(r"^ {0,3}\[[^\]\n]+\]:\s*(<[^>]+>|\S+)", re.MULTILINE)
REFERENCE = re.compile(r"(?<![\w./%+@-])[\w./%+@-]+\.md\b", re.IGNORECASE)
FENCE = re.compile(r"^\s*(`{3,}|~{3,})(.*)$")
LOCAL_DIRS = (".pi", ".scratch")
EXCLUDED_LOCAL_DIRS = {".git", "node_modules", "target", "build", "dist", "DerivedData", ".derived", ".gradle", ".build"}


def git_paths(root: Path, *args: str) -> list[str]:
    result = subprocess.check_output(["git", "ls-files", "-z", *args], cwd=root)
    return [os.fsdecode(path) for path in result.split(b"\0") if path]


def inventory_paths(root: Path) -> dict[str, str]:
    paths = {}
    for scope, arguments in [("tracked", ()), ("untracked", ("--others", "--exclude-standard"))]:
        for path in git_paths(root, *arguments):
            if path.lower().endswith(".md") and (root / path).is_file():
                paths[path] = scope
    # Agent-local material is a separate scope, never a deletion candidate.
    for name in LOCAL_DIRS:
        for directory, dirs, files in os.walk(root / name):
            dirs[:] = sorted(set(dirs) - EXCLUDED_LOCAL_DIRS)
            for filename in files:
                file = Path(directory) / filename
                if filename.lower().endswith(".md") and file.is_file():
                    paths.setdefault(file.relative_to(root).as_posix(), "local-agent")
    return dict(sorted(paths.items()))


def classify(path: str, scope: str) -> str:
    parts = PurePosixPath(path).parts
    name = parts[-1].lower()
    if scope == "local-agent":
        return "local-agent-state"
    if name in {"agents.md", "claude.md", "skill.md"} or "/AgentSkills/" in path:
        return "agent-instructions"
    if name.startswith(("license", "attribution")):
        return "legal"
    if "/fixtures/" in path or "/samples/" in path:
        return "fixture-or-sample"
    if path.startswith("apps/website/docs-src/src/content/docs/reference/") or path.startswith("apps/website/docs-src/public/reference/"):
        return "publication-snapshot"
    if "/reference/generated/" in path or path.startswith("apps/website/docs-src/src/content/docs/cli-reference/"):
        return "generated-reference"
    if path.startswith("apps/website/docs-src/src/content/docs/") or path.startswith("apps/website/content/blog/"):
        return "published-guide"
    if path.startswith("packages/contracts/") or path.startswith("apps/cli/docs/protocol/") or path.startswith("apps/android/docs/export-contract/"):
        return "contract"
    if path.startswith("docs/migration/"):
        return "migration-provenance"
    if name.startswith(("adr-", "rfc-", "design")) or path.startswith("docs/product/practice/") or name in {"cross-platform-unification-policy.md", "glossary.md"}:
        return "policy-or-decision"
    if name == "changelog.md":
        return "release-history"
    if any(word in name for word in ("audit", "roadmap", "baseline", "execution-plan", "session-prompt", "implementation-prompt", "todo-index", "interview", "campaign-brief")) or "/reports/" in path or "/experiments/" in path:
        return "planning-or-evidence"
    return "maintained-document"


def outside_fences(text: str) -> str:
    """Mask fenced examples while preserving offsets and line numbers."""
    result = []
    fence_char = ""
    fence_length = 0
    for line in text.splitlines(keepends=True):
        match = FENCE.match(line)
        if fence_char:
            if match and match[1][0] == fence_char and len(match[1]) >= fence_length and not match[2].strip():
                fence_char = ""
            result.append(re.sub(r"[^\r\n]", " ", line))
        elif match:
            fence_char = match[1][0]
            fence_length = len(match[1])
            result.append(re.sub(r"[^\r\n]", " ", line))
        else:
            result.append(line)
    return "".join(result)


def destination(raw: str) -> str:
    value = raw.strip()
    return value[1:value.index(">")] if value.startswith("<") and ">" in value else value.split(maxsplit=1)[0] if value else ""


def markdown_links(text: str):
    source = outside_fences(text)
    matches = sorted([*LINK.finditer(source), *DEFINITION.finditer(source)], key=lambda match: match.start())
    for match in matches:
        yield source.count("\n", 0, match.start()) + 1, destination(match[1])


def missing_link(root: Path, document: Path, target: str) -> str | None:
    # Absolute routes are checked by the component's built-site validator, not
    # interpreted as filesystem paths. External/custom-scheme links are not fetched.
    parsed = urlsplit(target)
    if not target or parsed.scheme or parsed.netloc or target.startswith(("#", "/")):
        return None
    relative = unquote(parsed.path)
    if not relative:
        return None
    resolved = (document.parent / relative).resolve()
    try:
        label = resolved.relative_to(root.resolve()).as_posix()
    except ValueError:
        return "outside-repository"
    if resolved.exists():
        return None
    if "apps/website/docs-src/src/content/docs" in document.as_posix() and not resolved.suffix:
        if any(candidate.exists() for candidate in [resolved.with_suffix(".md"), resolved.with_suffix(".mdx"), resolved / "index.md", resolved / "index.mdx"]):
            return None
    return label


def reference_targets(source: str, token: str, documents: set[str]) -> set[str]:
    token = unquote(token)
    relative = posixpath.normpath(posixpath.join(posixpath.dirname(source), token))
    if relative in documents:
        return {relative}
    if token in documents:
        return {token}
    # Component docs and code frequently name paths relative to their component.
    parts = PurePosixPath(source).parts
    if len(parts) > 2 and parts[0] in {"apps", "packages"}:
        component = posixpath.normpath(posixpath.join(*parts[:2], token))
        if component in documents:
            return {component}
    # A unique suffix provides an investigative backlink, not proof of consumption.
    suffix = token.removeprefix("./")
    matches = {path for path in documents if path.endswith("/" + suffix)}
    return matches if len(matches) == 1 else set()


def build_report(root: Path) -> dict:
    paths = inventory_paths(root)
    documents = set(paths)
    rows = {}
    errors = []
    hashes = defaultdict(list)
    for path, scope in paths.items():
        try:
            data = (root / path).read_bytes()
            text = data.decode("utf-8")
        except (OSError, UnicodeError) as error:
            errors.append({"path": path, "error": type(error).__name__})
            continue
        digest = hashlib.sha256(data).hexdigest()
        hashes[digest].append(path)
        missing = []
        links = list(markdown_links(text))
        for line, target in links:
            resolved = missing_link(root, root / path, target)
            if resolved is not None:
                missing.append({"line": line, "target": target, "resolved": resolved})
        title = next((line.lstrip("# ").strip() for line in text.splitlines() if line.startswith("# ")), "")
        signals = []
        if re.search(r"/Users/[^\s`]+|/home/[^\s`]+", text):
            signals.append("machine-specific-path")
        if re.search(r"\bTODO-[0-9a-f]{8}\b", text):
            signals.append("task-snapshot")
        if re.search(r"\b(?:\d+ tests passing|Test count:|Wave \d.*(?:COMPLETE|IN PROGRESS))", text):
            signals.append("execution-status-snapshot")
        rows[path] = {"path": path, "scope": scope, "category": classify(path, scope), "title": title,
                      "bytes": len(data), "sha256": digest, "link_count": len(links), "missing_local_links": missing,
                      "review_signals": signals, "references": [], "identical_files": []}
    for path, row in rows.items():
        row["identical_files"] = [other for other in hashes[row["sha256"]] if other != path]
    sources = sorted(set(git_paths(root)) | set(git_paths(root, "--others", "--exclude-standard")) | documents)
    for source in sources:
        file = root / source
        if not file.is_file():
            continue
        try:
            data = file.read_bytes()
            if b"\0" in data:
                continue
            text = data.decode("utf-8")
        except (OSError, UnicodeError):
            continue
        seen = set()
        for match in REFERENCE.finditer(text):
            # A URL mentioning a filename is not a local repository dependency.
            start = max(text.rfind(" ", 0, match.start()), text.rfind("\n", 0, match.start()), text.rfind('"', 0, match.start()), text.rfind("`", 0, match.start())) + 1
            if "://" in text[start:match.end()]:
                continue
            for target in reference_targets(source, match[0], documents):
                line = text.count("\n", 0, match.start()) + 1
                key = (target, line)
                if source != target and target in rows and key not in seen:
                    rows[target]["references"].append({"source": source, "line": line})
                    seen.add(key)
    removed = [path for path in git_paths(root) if path.lower().endswith(".md") and not (root / path).exists()]
    return {"format_version": 1,
            "limitations": ["Categories and signals are heuristics, not semantic review or deletion recommendations.",
                            "Backlinks infer literal path references; dynamic paths and external consumers require investigation.",
                            "Filesystem links only: anchors, absolute website routes, MDX, and external URLs need component checks.",
                            "Ignored .pi/.scratch Markdown is inventoried separately; dependencies/build output are excluded."],
            "summary": {"files": len(rows), "scopes": dict(Counter(row["scope"] for row in rows.values())),
                        "categories": dict(Counter(row["category"] for row in rows.values())),
                        "missing_local_links": sum(len(row["missing_local_links"]) for row in rows.values()),
                        "read_errors": len(errors)},
            "removed_tracked_markdown": removed, "errors": errors, "files": list(rows.values())}


def write_report(report: dict, output: Path):
    output.mkdir(parents=True, exist_ok=True)
    (output / "inventory.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    with (output / "inventory.csv").open("w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, fieldnames=["path", "scope", "category", "title", "bytes", "references", "missing_local_links", "identical_files", "review_signals"])
        writer.writeheader()
        for row in report["files"]:
            writer.writerow({"path": row["path"], "scope": row["scope"], "category": row["category"], "title": row["title"], "bytes": row["bytes"],
                             "references": len(row["references"]), "missing_local_links": len(row["missing_local_links"]),
                             "identical_files": ";".join(row["identical_files"]), "review_signals": ";".join(row["review_signals"])})


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--output", type=Path, help="Report directory (default: ignored .pi/markdown-audit)")
    args = parser.parse_args()
    root = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip()).resolve()
    output = args.output or root / ".pi/markdown-audit"
    report = build_report(root)
    write_report(report, output)
    print(json.dumps(report["summary"], indent=2))
    print(f"Reports: {output.resolve()}")
    print("Review findings against source and consumers before changing documents. No documents were modified.")
    return 1 if report["errors"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
