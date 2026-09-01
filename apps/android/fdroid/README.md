# Proposed F-Droid metadata

This directory is the upstream review copy for `com.healthmd.android`. The canonical published recipe belongs in F-Droid's `fdroiddata` repository.

- [`com.healthmd.android.yml`](com.healthmd.android.yml) checks out the repository root, builds from `apps/android`, pins NDK r27b, Rust 1.88.0, all four Android Rust targets, and `cargo-ndk` 4.1.2, and outputs the unsigned F-Droid APK.
- [`metadata/`](metadata/) contains channel-accurate localized listing text and screenshots. The screenshots show only shared/F-Droid capabilities (Health Connect export, metric selection, and scheduling).
- [`dependency-license-audit.md`](dependency-license-audit.md) records the production source/dependency and bundled-asset licensing boundary.
- [`reproducibility.md`](reproducibility.md) documents clean fdroidserver recipe validation and two-build comparison.

The initial recipe targets the next annotated Android release tag, `android/v1.8.1`. It cannot be submitted or called build-proven until that tag exists and points to the committed implementation. Before opening the fdroiddata merge request:

1. verify that the tag's version name/code equal the recipe;
2. run the clean F-Droid CI gate and `scripts/verify-fdroid-artifact.sh`;
3. run `fdroid lint`, `fdroid scanner`, and two clean `fdroid build` executions in the pinned environment;
4. replace downstream reviewer fixes upstream rather than carrying permanent source patches;
5. attach the resulting fdroiddata merge-request URL and build logs to the Android release record.

No Play credentials, OAuth/API properties, Cloudflare tokens, signing files, or private Gradle properties are part of the recipe.
