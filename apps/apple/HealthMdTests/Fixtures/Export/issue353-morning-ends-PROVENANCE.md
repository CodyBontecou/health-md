# Issue #353 golden fixtures: provenance

`issue353-morning-ends-default/` and `issue353-morning-ends-partly-off/` hold the "Morning ends"
export of one synthetic day in every format, written by the exporter **before** #353 (commit
`cfdceb3b659445a20bc14377ee8a645780fc004a`, "Drop the per-task opt-in for device and Argent QA
(#358)"). `AppleWakeDateExportPlannerTests` requires the current exporter to reproduce them byte
for byte:

- `testDefaultConfigurationMorningEndsOutputIsUnchangedByFrontmatterOwnership` (no fields off)
- `testPartlyDisabledConfigurationMorningEndsOutputIsUnchangedByFrontmatterOwnership` (`steps`,
  `heart_rate_min`, `heart_rate_max`, `workout_details`, `workout_calories`, `mood_labels`,
  `sleep_total_hours` off; every native record family keeps an owner on)

How they were generated:

1. In the #353 branch, reverse-apply its `apps/apple/HealthMd` changes against `cfdceb3b6`
   (`git diff cfdceb3b6 -- apps/apple/HealthMd ':!…/WakeDateNativeFrontmatterOwners.swift' | git apply -R`).
   The owner table stays because the tests reference it; it is a list of keys with no behavior.
   `WakeDateNativeFrontmatterOwnershipTests.swift` is set aside (it calls the new projection API).
2. Run the test with `TEST_RUNNER_HEALTHMD_WRITE_353_GOLDEN=<default|partly-off>`, which writes the
   files instead of comparing:
   `xcodebuild test -scheme HealthMd-Tests-iOS -configuration Debug-iOS -only-testing:HealthMdTests/AppleWakeDateExportPlannerTests/<test>`
3. Restore the branch sources. In the run that wrote `partly-off`, the `default` test also compared
   the committed `default` fixtures against the pre-#353 code and passed.

## Intentional change in #465

`partly-off-bases.md` no longer holds the `native_workout_details` block (three lines, the block
and its blank separator, removed by hand; nothing else changed). Each record in that block holds
every workout property, including `calories` while `workout_calories` is off, so a customized
Workouts group in Format → Custom added frontmatter keys the user had not selected. Since #465 the
block is written only while every Workouts field is on. The other partly-off files and every
`default` file are unchanged and still match the pre-#353 output.

SHA-256 of the committed files:

```
issue353-morning-ends-default/
    109e61ede93844d9bda079877c8ed78e601b01126ff7775f2034a81bff780753  default-bases.md
    b33ab8d41593abd41203ac1c21b69672e1c3b979dd7ac8a82f64701d66b3a9a5  default.csv
    d8e526776e21bb9888a6bdbac7862ed731fff5564071177f56fe7d51069fdeef  default.json
    1de391ab98fb6a321e585730d1f19d408596eb5c76de8344319db93052ddac71  default.md
issue353-morning-ends-partly-off/
    63aca6efe2e7d95bed6a4167ea88c189b13a4bbe74a9bad0f27c245410f16a30  partly-off-bases.md
    1c27bd89bd45746d3ed441bc9c52cb88e333426a30f9015534891de96d435797  partly-off.csv
    d8e526776e21bb9888a6bdbac7862ed731fff5564071177f56fe7d51069fdeef  partly-off.json
    7712792455909c244742e6f13342fed8464391923b911f9587d22ec4ff57de08  partly-off.md
```
