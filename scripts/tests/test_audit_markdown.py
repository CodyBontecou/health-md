"""Tests for the read-only Markdown inventory; no product builds or devices."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "audit-markdown.py"
spec = importlib.util.spec_from_file_location("audit_markdown", SCRIPT)
assert spec is not None and spec.loader is not None
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class MarkdownAuditTests(unittest.TestCase):
    def test_classification_protects_contracts_and_publications(self):
        expected = {
            "AGENTS.md": "agent-instructions",
            "LICENSES.md": "legal",
            "packages/contracts/direct-protocol/v1/protocol.md": "contract",
            "packages/contracts/rollup-summary/v9/fixtures/range-v9.md": "fixture-or-sample",
            "docs/architecture/adr-0007-healthmd-cloud.md": "policy-or-decision",
            "docs/migration/source-revisions.md": "migration-provenance",
            "apps/apple/docs/reference/generated/core/metric-catalog.md": "generated-reference",
            "apps/website/docs-src/src/content/docs/reference/index.md": "publication-snapshot",
            "apps/website/docs-src/src/content/docs/fr/quickstart.md": "published-guide",
            "apps/website/assets/samples/health-data-sample.md": "fixture-or-sample",
            "apps/apple/docs/testing/WAVE1-EXECUTION-PLAN.md": "planning-or-evidence",
            "apps/cloud/docs/production-design-interview.md": "planning-or-evidence",
            "apps/cli/docs/releasing.md": "maintained-document",
        }
        for path, category in expected.items():
            with self.subTest(path=path):
                self.assertEqual(audit.classify(path, "tracked"), category)
        self.assertEqual(audit.classify(".pi/todos/123.md", "local-agent"), "local-agent-state")

    def test_links_ignore_code_fences_and_resolve_reference_definitions(self):
        text = '# Example\n[Guide](guide.md "Title")\n```markdown\n[x](missing.md)\n```\n~~~\n[x](also-missing.md)\n~~~\n[id]: <other%20guide.md> "Title"\n'
        self.assertEqual(list(audit.markdown_links(text)), [(2, "guide.md"), (9, "other%20guide.md")])

    def test_fence_requires_matching_character_and_sufficient_length(self):
        text = '````markdown\n[x](not-a-link.md)\n```\n[x](still-not-a-link.md)\n````\n[x](live.md)\n'
        self.assertEqual(list(audit.markdown_links(text)), [(6, "live.md")])

    def test_local_links_allow_cross_component_and_skip_routes_and_schemes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            document = root / "apps/apple/docs/index.md"
            document.parent.mkdir(parents=True)
            target = root / "packages/contracts/README.md"
            target.parent.mkdir(parents=True)
            target.write_text("# Contracts\n")
            spaced = document.parent / "other guide.md"
            spaced.write_text("# Other\n")
            self.assertIsNone(audit.missing_link(root, document, "../../../packages/contracts/README.md#anchor"))
            self.assertIsNone(audit.missing_link(root, document, "other%20guide.md"))
            for link in ["#anchor", "/docs/quickstart/", "https://example.com/x.md", "healthmd://setup", "mailto:x@example.com"]:
                self.assertIsNone(audit.missing_link(root, document, link))
            self.assertEqual(audit.missing_link(root, document, "missing.md"), "apps/apple/docs/missing.md")
            self.assertEqual(audit.missing_link(root, document, "../../../../outside.md"), "outside-repository")

    def test_extensionless_links_only_resolve_for_published_content(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            website = root / "apps/website/docs-src/src/content/docs"
            website.mkdir(parents=True)
            (website / "guide.md").write_text("# Guide\n")
            self.assertIsNone(audit.missing_link(root, website / "index.md", "guide"))
            self.assertEqual(audit.missing_link(root, root / "README.md", "guide"), "guide")

    def test_backlinks_include_code_consumers_and_ambiguous_names_are_not_guessed(self):
        docs = {"apps/apple/docs/guide.md", "apps/apple/README.md", "README.md"}
        self.assertEqual(audit.reference_targets("apps/apple/scripts/check.py", "../docs/guide.md", docs), {"apps/apple/docs/guide.md"})
        self.assertEqual(audit.reference_targets(".github/workflows/test.yml", "apps/apple/docs/guide.md", docs), {"apps/apple/docs/guide.md"})
        self.assertEqual(audit.reference_targets("unknown.py", "README.md", docs), {"README.md"})
        self.assertEqual(audit.reference_targets("unknown.py", "guide.md", docs), {"apps/apple/docs/guide.md"})
        self.assertEqual(audit.reference_targets("unknown.py", "README.md", {"apps/apple/README.md", "apps/android/README.md"}), set())

    def test_reference_scan_is_bounded_for_long_non_path_tokens(self):
        # Export fixtures can contain long synthetic/base64 strings. A path
        # search must not retry from every character of a non-matching token.
        program = (
            "import importlib.util; "
            f"spec=importlib.util.spec_from_file_location('audit', {str(SCRIPT)!r}); "
            "m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m); "
            "assert m.REFERENCE.findall('x' * 100000 + ' docs/guide.md') == ['docs/guide.md']"
        )
        subprocess.run([sys.executable, "-c", program], check=True, timeout=3)

    def test_git_inventory_includes_local_state_but_not_dependencies(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            for path, text in {
                ".gitignore": ".pi/\nnode_modules/\n",
                "README.md": "# Root\n",
                "new.md": "# New\n",
                ".pi/todos/task.md": "# Task\n",
                ".pi/subagents/artifacts/report.md": "# Report\n",
                "node_modules/vendor/README.md": "# Vendor\n",
            }.items():
                file = root / path
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text(text)
            subprocess.run(["git", "add", ".gitignore", "README.md"], cwd=root, check=True)
            self.assertEqual(audit.inventory_paths(root), {
                "README.md": "tracked", "new.md": "untracked",
                ".pi/todos/task.md": "local-agent", ".pi/subagents/artifacts/report.md": "local-agent",
            })

    def test_report_covers_every_file_with_duplicates_and_non_markdown_consumers(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            for path, text in {
                "README.md": "# Root\n[Guide](docs/guide.md)\n[Missing](docs/missing.md)\n",
                "docs/guide.md": "# Shared\n",
                "docs/copy.md": "# Shared\n",
                "check.py": 'load("docs/guide.md")\n',
            }.items():
                file = root / path
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text(text)
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            report = audit.build_report(root)
            self.assertEqual(report["summary"]["files"], 3)
            rows = {row["path"]: row for row in report["files"]}
            self.assertEqual(rows["docs/guide.md"]["identical_files"], ["docs/copy.md"])
            sources = {item["source"] for item in rows["docs/guide.md"]["references"]}
            self.assertEqual(sources, {"README.md", "check.py"})
            self.assertEqual(rows["README.md"]["missing_local_links"], [{"line": 3, "target": "docs/missing.md", "resolved": "docs/missing.md"}])
            json.dumps(report)
            self.assertEqual((root / "docs/guide.md").read_text(), "# Shared\n")


if __name__ == "__main__":
    unittest.main()
