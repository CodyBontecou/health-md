#!/usr/bin/env python3
"""Qualify named automation execution from a full xcresult; never select/rerun tests."""
from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path
import sys

SUITE = "AppleContextAutomationTests"
# Explicit identities, not a minimum/stale count. Keep these and the synthetic
# xcresult fixtures in sync with the platform-conditional native test inventory.
COMMON_CASES = (
    "testProductAutomationInventoryIsSeparateFromFrozenMetricAuthorityAndHasConcreteParityTargets",
    "testLegacyCapabilityMissingOrFalseAndUnauthenticatedOrWrongRoleNeverSend",
    "testProductionIngressNegotiatesHelloSynchronouslyAndRejectsForeignOrDisabledFamily",
    "testRequestRejectsHostPathRawPointersUnknownFieldsAndNoncanonicalDates",
    "testDurableIdentityRejectsProfilePeerDateSourceDetailMutationAndRestoresWithoutAck",
    "testReceiptsArePersistedPeerScopeRequestBoundMonotonicAndTerminal",
    "testPostWriteFailuresNeverBecomeAuthorityByLookupOrRestartAndRetryKeepsIdentity",
    "testPostWriteCompletionFailurePreservesPriorReceiptAndCorruptMarkerCannotBeAbsence",
    "testColdDirectoryErrorIsUnavailableNotAbsenceAndRestorationPreservesContents",
)
PLATFORM_CASES = {
    "iOS": (
        "testPhoneProductionAdapterFreezesProfileBeforeSendAndRecoversLostAckWithoutQuota",
        "testPhoneFailedPersistenceUnknownIneligibleUnboundAndLockedProfilesNeverSend",
        "testPhonePostAtomicAdmissionAndReceiptFailuresRequireExplicitDurabilityRepairBeforeStatus",
        "testProductionPhoneHandlerPinsManifestAndRechecksLeaseAcrossAuthorizationAndCaptureAwait",
        "testActualFakeHealthKitCaptureAwaitRechecksPeerCapabilityAndUncertainAuthority",
        "testColdUnavailablePhoneAuthorityBlocksActualHandlerButPreservesOrdinaryFilesAndFirstRunContext",
        "testProtectedStatusCannotTransmitEvenWithProvenAdmission",
        "testRealShortcutProviderRetainsSevenActionsAndRegistersBothContextIntents",
    ),
    "macOS": (
        "testMacFailedMappingAndJobPersistenceNeverAcknowledgeOrDispatch",
        "testMacUnavailableNativeRootNeverAdmitsOrAcquiresAndSameIDRetriesAfterRecovery",
        "testMacNativeResolverRecoveryBeforeAdmissionUsesStableRootAcrossTemporaryPurgeAndRestart",
        "testMacMissingPreviouslyAdmittedNativeJobRemainsUnavailableWithoutRecreation",
        "testMacRoundTripDoesNotBlockIngressAndCompletesOnlyAfterEncryptedCommitWithoutFiles",
        "testMacPostWriteMappingFailureNeverAcksOrAcquiresAndExplicitStatusRepairsSameIdentity",
        "testMacPostWriteJobMappingUpdateFailureSuppressesDispatchUntilExplicitRepair",
        "testColdNativeSentJobStatusResumesOriginalScopeWithoutJournalRepairOrDuplicateWaiter",
        "testColdUnavailableJournalAndRestoredNativeContextJobExcludeDirectAndBoundedFilesButAllowUnownedFiles",
        "testColdUnavailableMacAuthorityBlocksContextButNotOrdinaryFilesAndRecoversWithoutErase",
        "testMacLockedAdmissionAndForeignPeerNeverAcquireOrClaimSuccess",
    ),
}
EXPECTED_IDENTITIES = {
    platform: {f"{SUITE}/{name}()" for name in COMMON_CASES + cases}
    for platform, cases in PLATFORM_CASES.items()
}


def normalized_identity(identifier: str) -> str | None:
    # xcresult can qualify a node with its bundle or module. No arbitrary suite
    # substring, display name, or count can stand in for an executed identity.
    for prefix in ("HealthMdTests/", "HealthMdTests."):
        if identifier.startswith(prefix):
            identifier = identifier[len(prefix):]
            break
    parts = identifier.split("/")
    if len(parts) != 2 or parts[0] != SUITE or not parts[1]:
        return None
    return identifier


def collect_records(tree: object) -> list[dict]:
    records = []

    def visit(value: object, in_suite: bool = False) -> None:
        if isinstance(value, dict):
            name = str(value.get("name", ""))
            identifier = str(value.get("nodeIdentifier", value.get("testIdentifier", "")))
            owned = in_suite or name == SUITE or normalized_identity(identifier) is not None
            if owned and value.get("nodeType") == "Test Case":
                records.append({"name": name, "identifier": identifier, "result": value.get("result", "Unknown")})
            for child in value.values():
                if isinstance(child, (dict, list)):
                    visit(child, owned)
        elif isinstance(value, list):
            for child in value:
                visit(child, in_suite)

    visit(tree)
    return records


def qualification_errors(records: list[dict], platform: str) -> list[str]:
    if platform not in EXPECTED_IDENTITIES:
        return [f"Unsupported platform: {platform}"]
    expected = EXPECTED_IDENTITIES[platform]
    observed = Counter()
    errors = []
    for record in records:
        identity = normalized_identity(record["identifier"])
        if identity is None:
            errors.append(f"Invalid test identity: {record['identifier']!r}")
        else:
            observed[identity] += 1
            if record["name"] != identity.split("/")[1]:
                errors.append(f"Test name/identity mismatch: {record['identifier']}")
        if record["result"] != "Passed":
            errors.append(f"Nonpassing test: {record['identifier']} ({record['result']})")
    errors.extend(f"Missing expected test: {identity}" for identity in sorted(expected - observed.keys()))
    errors.extend(f"Unexpected test: {identity}" for identity in sorted(observed.keys() - expected))
    errors.extend(f"Duplicate test identity: {identity}" for identity, count in sorted(observed.items()) if count != 1)
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("tree")
    parser.add_argument("output")
    parser.add_argument("--head", required=True)
    parser.add_argument("--platform", required=True)
    parser.add_argument("--diagnostics", help="Separate non-qualification artifact, including rejected results")
    args = parser.parse_args()
    output = Path(args.output)
    # A failed invocation must not leave an older receipt available for upload.
    output.unlink(missing_ok=True)
    diagnostics = Path(args.diagnostics) if args.diagnostics else None
    if diagnostics is not None and diagnostics.resolve() == output.resolve():
        parser.error("diagnostics must not use the qualification output path")
    records = []
    try:
        records = collect_records(json.loads(Path(args.tree).read_text()))
        errors = qualification_errors(records, args.platform)
    except (OSError, ValueError) as error:
        errors = [f"Unable to read native test tree: {error}"]
    lines = [f"head: {args.head}", f"platform: {args.platform}",
             "source: xcresulttool get test-results tests (executed full suite)",
             f"scope: {SUITE} only; not whole-suite or device qualification",
             f"named cases: {len(records)}"]
    record_lines = [json.dumps(record, sort_keys=True) for record in records]
    if diagnostics is not None:
        diagnostics.parent.mkdir(parents=True, exist_ok=True)
        diagnostic_lines = ["artifact: diagnostic; NOT qualification evidence", *lines,
                            f"qualification: {'REJECTED' if errors else 'Passed'}",
                            *[f"error: {error}" for error in errors], *record_lines]
        diagnostics.write_text("\n".join(diagnostic_lines) + "\n")
    if errors:
        print("Not a qualification receipt:\n" + "\n".join(errors), file=sys.stderr)
        return 1
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join([*lines, "qualification: Passed", *record_lines]) + "\n")
    print(output.read_text(), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
