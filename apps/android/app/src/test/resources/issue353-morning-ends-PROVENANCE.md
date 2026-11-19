# Issue #353 golden fixtures: provenance

`issue353-morning-ends-default/` and `issue353-morning-ends-partly-off/` hold the "Morning ends"
export of one synthetic day in every format, written by the exporter **before** #353 (commit
`cfdceb3b659445a20bc14377ee8a645780fc004a`). `HostCoreDailyAggregatePlannerTest` requires the
current exporter to reproduce them byte for byte:

- `defaultConfigurationMorningEndsOutputIsUnchangedByFrontmatterOwnership` (no fields off)
- `partlyDisabledConfigurationMorningEndsOutputIsUnchangedByFrontmatterOwnership` (`steps`,
  `heart_rate_min`, `heart_rate_max`, `workout_calories`, `workout_avg_heart_rate` off; every
  native record family keeps an owner on)

How they were generated:

1. In the #353 branch, reverse-apply its `apps/android/app/src/main` changes against `cfdceb3b6`
   (`git diff cfdceb3b6 -- apps/android/app/src/main ':!…/NativeFrontmatterOwners.kt' | git apply -R`).
   The owner object stays because tests reference it; it is a list of keys with no behavior. Tests
   that call the new detail-builder API are set aside.
2. Run the test with the Rust host core and `HEALTHMD_WRITE_353_GOLDEN=<default|partly-off>`:
   `HEALTHMD_HOST_CORE_LIBRARY=<libhealthmd_core_uniffi.dylib> ./gradlew :app:testPlayDebugUnitTest --tests '*HostCoreDailyAggregatePlannerTest.<test>'`
   (the host-core tests skip without `HEALTHMD_HOST_CORE_LIBRARY`).
3. Restore the branch sources. In the run that wrote `partly-off`, the `default` test also compared
   the committed `default` fixtures against the pre-#353 code and passed.

The CSV and JSON files are the same in both folders: on Android, Format → Custom changes only
Markdown and Bases frontmatter.

SHA-256 of the committed files:

```
issue353-morning-ends-default/
    787f8988dd7f234c12e6bcd66d6f637b55cb9a5dfbf7c75fbd6561e3d9a3f6a1  2026-11-01-bases.md
    fed83c00849af153c8178085f1515a3c54f4d034fad9f5dce6575bb95ffd1cf0  2026-11-01.csv
    60b39d5f864b93154bb5f99bce507fd6fd540439f5801ab41b16b821a806a148  2026-11-01.json
    aa8dbc6bdabd23cefc1af1577534f7d6565411cdbebca4dc5113c793c85f559c  2026-11-01.md
issue353-morning-ends-partly-off/
    5469c58197ae7012630d4f846d771909c73646a341b58bdbddd166cad83b3554  2026-11-01-bases.md
    fed83c00849af153c8178085f1515a3c54f4d034fad9f5dce6575bb95ffd1cf0  2026-11-01.csv
    60b39d5f864b93154bb5f99bce507fd6fd540439f5801ab41b16b821a806a148  2026-11-01.json
    626d3625b9327b21611b5132932059aecf14f780648a330a5eec63998ea696df  2026-11-01.md
```
