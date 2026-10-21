#!/usr/bin/env python3
"""Regression policies for caller/reusable Apple workflow concurrency."""

import unittest

from workflow_policy import context, evaluate, render, workflow


class AppleCIConcurrencyTests(unittest.TestCase):
    def test_qualification_cannot_cancel_its_parent_release(self):
        ci = workflow("apple-ci.yml")
        for name in ("release-ios.yml", "release-macos.yml"):
            caller = workflow(name)
            for release_tag in ("", "v3.0"):
                with self.subTest(workflow=name, release_tag=release_tag):
                    inherited = context(caller["name"], release_tag=release_tag)
                    inherited["inputs"]["release_sha"] = "qualified-sha"
                    parent_group = render(caller["concurrency"]["group"], inherited)
                    child_group = render(ci["concurrency"]["group"], inherited)
                    self.assertNotEqual(parent_group, child_group,
                                        "reusable github.workflow inherits the caller's name")

    def test_two_store_platforms_have_distinct_qualification_groups(self):
        ci = workflow("apple-ci.yml")
        groups = []
        for name in ("release-ios.yml", "release-macos.yml"):
            inherited = context(workflow(name)["name"], release_tag="v3.0")
            inherited["inputs"]["release_sha"] = "qualified-sha"
            groups.append(render(ci["concurrency"]["group"], inherited))
        self.assertNotEqual(*groups)

    def test_new_qualification_does_not_cancel_an_existing_release(self):
        ci = workflow("apple-ci.yml")
        inherited = context("Apple Release iOS", release_tag="v3.0")
        inherited["inputs"]["release_sha"] = "qualified-sha"
        cancel = ci["concurrency"]["cancel-in-progress"]
        self.assertFalse(evaluate(cancel, inherited) if cancel.startswith("${{") else cancel == "true")
        first_group = render(ci["concurrency"]["group"], inherited)
        inherited["github"]["run_id"] = "124"
        self.assertNotEqual(first_group, render(ci["concurrency"]["group"], inherited),
                            "a queued qualification must not replace another release's child run")

    def test_regular_apple_ci_still_cancels_superseded_branch_runs(self):
        ci = workflow("apple-ci.yml")
        regular = context(ci["name"], event="push")
        regular["github"]["ref"] = "refs/heads/main"
        group = render(ci["concurrency"]["group"], regular)
        regular["github"]["run_id"] = "124"
        self.assertEqual(group, render(ci["concurrency"]["group"], regular))
        cancel = ci["concurrency"]["cancel-in-progress"]
        self.assertTrue(evaluate(cancel, regular) if cancel.startswith("${{") else cancel == "true")


if __name__ == "__main__":
    unittest.main()
