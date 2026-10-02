#!/usr/bin/env python3
"""Regression coverage for contributor pointers, placeholders, and link boundaries."""

import importlib.util
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    "documentation_links", Path(__file__).resolve().parents[1] / "check-documentation-links.py"
)
check = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(check)


class NavigationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.document = self.file("AGENTS.md", "")
        self.target = self.file("apps/apple/docs/guide.md", "# Guide\n")

    def file(self, relative, text):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def validate(self, text, inline=True):
        self.document.write_text(text)
        return check.check_documents([self.document], self.root, {self.document} if inline else set())

    def test_existing_link_and_root_literal_pass(self):
        errors, count = self.validate("[Guide](apps/apple/docs/guide.md#section) and `apps/apple/docs/guide.md`.\n")
        self.assertEqual(errors, [])
        self.assertEqual(count, 2)

    def test_missing_task_pointer_reports_line_and_target(self):
        errors, _ = self.validate("# Tasks\n[Guide](apps/apple/docs/moved.md)\n")
        self.assertEqual(errors, ["AGENTS.md:2: missing local target apps/apple/docs/moved.md"])

    def test_old_pre_monorepo_literal_is_rejected(self):
        self.document = self.file("apps/website/docs-src/README.md", "")
        errors, _ = self.validate("Reference owner: `../app/docs/reference/`.\n")
        self.assertEqual(len(errors), 1)
        self.assertIn("missing literal navigation path ../app/docs/reference/", errors[0])

    def test_component_relative_literal_passes(self):
        self.document = self.file("apps/apple/AGENTS.md", "")
        errors, _ = self.validate("Read `docs/guide.md`.\n")
        self.assertEqual(errors, [])

    def test_root_convention_from_component_guide_passes(self):
        self.document = self.file("packages/core/AGENTS.md", "")
        self.file("docs/architecture/policy.md", "# Policy\n")
        errors, _ = self.validate("Read `docs/architecture/policy.md`.\n")
        self.assertEqual(errors, [])

    def test_fenced_commands_and_parameterized_examples_are_not_claims(self):
        errors, count = self.validate(
            "```bash\n[Example](missing.md)\ncd apps/future\n```\n"
            "~~~markdown\n`apps/absent/README.md`\n~~~\n"
            "`/absolute/path/to/health-md/app`, `~/vault/note.md`, "
            "`apps/<component>/README.md`, `apps/*/AGENTS.md`, "
            "`$ROOT/apps/other`, `https://example.com/guide.md`.\n"
        )
        self.assertEqual(errors, [])
        self.assertEqual(count, 0)

    def test_short_linked_code_label_is_not_a_second_path_claim(self):
        errors, count = self.validate("[`guide.md`](apps/apple/docs/guide.md)\n")
        self.assertEqual(errors, [])
        self.assertEqual(count, 1)

    def test_url_fragment_and_empty_destination_are_skipped(self):
        errors, count = self.validate("[Web](https://example.com) [Mail](mailto:user@example.com) [App](obsidian://open) [Here](#section) [Empty]()\n")
        self.assertEqual(errors, [])
        self.assertEqual(count, 0)

    def test_encoded_filename_and_markdown_title_pass(self):
        self.file("note with spaces.md", "# Note\n")
        errors, _ = self.validate('[Note](note%20with%20spaces.md "Title")\n')
        self.assertEqual(errors, [])

    def test_link_escaping_repository_fails(self):
        errors, _ = self.validate("[Outside](../outside.md)\n")
        self.assertIn("link escapes repository", errors[0])

    def test_symlink_escaping_repository_fails(self):
        with tempfile.TemporaryDirectory() as outside:
            target = Path(outside) / "outside.md"
            target.write_text("# Outside\n")
            try:
                (self.root / "linked.md").symlink_to(target)
            except OSError:
                self.skipTest("symlinks unavailable")
            errors, _ = self.validate("[Outside](linked.md)\n")
            self.assertIn("link escapes repository", errors[0])

    def test_deleted_required_navigation_document_is_not_silently_skipped(self):
        missing = self.root / "apps/website/docs-src/README.md"
        errors, _ = check.check_documents([missing], self.root)
        self.assertEqual(errors, ["apps/website/docs-src/README.md: missing navigation document"])

    def test_inventory_includes_nested_ownership_and_component_entry_points(self):
        ownership = self.file("apps/website/docs-src/README.md", "# Ownership\n")
        android = self.file("apps/android/AGENTS.md", "# Android\n")
        readme = self.file("apps/cli/README.md", "# CLI\n")
        documents, inline = check.navigation_documents(self.root)
        for path in (ownership, android, readme, self.document):
            self.assertIn(path, documents)
        self.assertIn(ownership, inline)
        self.assertIn(android, inline)
        self.assertNotIn(readme, inline)


if __name__ == "__main__":
    unittest.main()
