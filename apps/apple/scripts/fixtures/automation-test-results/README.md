# Synthetic xcresult test trees

These JSON inputs exercise the production `ci-automation-test-receipt.py` CLI.
They are fixtures, not hosted test receipts or native/device qualification.

Each complete tree names the exact platform-conditional
`AppleContextAutomationTests` inventory and has one `Passed` result per identity.
iOS retains the original 17 cases; macOS includes the original 17 plus the three
stable-storage/admission regressions. An unrelated skipped case verifies that
these receipts qualify only the named automation suite, not the full native run.
The independent full-suite workflow gates remain authoritative.

The Python regressions mutate these inputs to cover skipped, unknown, failed,
missing and duplicate results/identities, wrong platforms and rejected-output
cleanup. A maintenance check compares the explicit receipt allowlists and
fixtures with the native declarations so adding/removing a test requires an
intentional identity update rather than changing a minimum count.
