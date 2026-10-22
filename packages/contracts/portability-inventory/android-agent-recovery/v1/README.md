# Android private recovery coverage v1

This independently versioned, build-time inventory supplements the immutable
[Shared Setup v2 Android field ledger](../../../shared-setup/v2/android-profile-field-coverage.json).
It does not change Shared Setup, any public export profile, or native recovery authority.

The original ledger's bytes are SHA-256 pinned. The supplement adds five serialized private
recovery fields and two transient execution fields. Every addition is `prohibited`, with no
portable contract path. Endpoint/credential proofs, prepared-artifact markers, generation fences,
and callbacks must never become imported configuration or transferable permission.

`packages/contracts/validate.py` checks closed inventory keys, immutable pins, private-only
classification, evidence, uniqueness, and ordering. Android's strict descriptor coverage test
checks the union of the frozen ledger and these additions against actual serializers and
explicit transient fields; missing, stale, or duplicated fields still fail. Neither historical
fixtures nor the historical ledger are regenerated to satisfy that test.

```sh
python3 packages/contracts/validate.py
python3 -m unittest discover -s packages/contracts -p 'test_validate_android_recovery_coverage.py'
# From apps/android:
./gradlew :app:testPlayDebugUnitTest :app:testFdroidDebugUnitTest \
  --tests 'com.healthmd.sharedsetup.SharedSetupAndroidProfileFieldCoverageTest' --max-workers=2
```

No runtime configuration, permission, credential, schedule, or health data is carried here.
