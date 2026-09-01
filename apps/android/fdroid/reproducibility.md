# F-Droid clean-build and reproducibility procedure

The initial F-Droid publication is source reproducibility, not Play-signature-compatible binary publication: F-Droid builds and signs the APK. Nevertheless, the unsigned upstream build should be deterministic and the fdroiddata recipe must succeed twice from clean source.

## Pinned inputs

| Input | Pin |
| --- | --- |
| fdroidserver | 2.4.5 |
| JDK | 17 |
| Gradle | repository wrapper / `gradle-wrapper.properties` |
| Android NDK | `27.1.12297006` (`r27b`) |
| Rust | 1.88.0 (`packages/healthmd-core-rust/rust-toolchain.toml`) |
| cargo-ndk | 4.1.2, installed with `--locked` |
| Rust Android targets | `aarch64-linux-android`, `armv7-linux-androideabi`, `x86_64-linux-android`, `i686-linux-android` |
| JVM/Rust dependency locks | Gradle version catalog/wrapper plus `packages/healthmd-core-rust/Cargo.lock` |

## Upstream clean-clone comparison

After the release implementation is committed, run:

```bash
cd apps/android
FDROID_SOURCE_REF=android/v1.8.1 ./scripts/check-fdroid-reproducibility.sh
```

The script creates two independent clones and Gradle homes, sets `SOURCE_DATE_EPOCH` from the exact commit, builds `assembleFdroidRelease` twice without `local.properties`, runs artifact/dependency/manifest checks, and compares SHA-256 hashes. It retains both APKs, hashes, and an optional diffoscope report under `app/build/reports/fdroid-reproducibility/`.

A matching checksum demonstrates deterministic upstream unsigned APKs for the pinned local toolchain. It does not demonstrate the F-Droid buildserver recipe or a Play/F-Droid signing match.

## fdroiddata recipe validation

Use two fresh fdroiddata workspaces with fdroidserver 2.4.5. In each workspace:

1. copy `com.healthmd.android.yml` to `metadata/com.healthmd.android.yml`;
2. copy this repository's `metadata/<locale>` directories to `metadata/com.healthmd.android/<locale>`;
3. run `fdroid readmeta` and `fdroid lint com.healthmd.android`;
4. run `fdroid build --server --verbose com.healthmd.android:30`;
5. run `fdroid scanner --json unsigned/com.healthmd.android_30.apk`;
6. inspect package/version/minSdk/targetSdk and compare the two unsigned APK SHA-256 values.

Example orchestration (run once per disposable workspace/container):

```bash
python3 -m venv .venv
.venv/bin/pip install 'fdroidserver==2.4.5'
.venv/bin/fdroid readmeta
.venv/bin/fdroid lint com.healthmd.android
.venv/bin/fdroid build --server --verbose com.healthmd.android:30
.venv/bin/fdroid scanner --json unsigned/com.healthmd.android_30.apk \
  > unsigned/com.healthmd.android_30.scanner.json
sha256sum unsigned/com.healthmd.android_30.apk \
  > unsigned/com.healthmd.android_30.apk.sha256
```

The canonical acceptance evidence is two clean `fdroid build --server` logs from the tagged source, not a build tree reused from Android Studio.

## Expected result and failure handling

- Output package: `com.healthmd.android`
- Version: derived from the tagged `app/build.gradle.kts`
- Minimum SDK: 28
- Target SDK: 35
- Upstream output: `app-fdroid-release-unsigned.apk`
- Signing: absent upstream; fdroidserver supplies the published signature
- Forbidden Play dependency/manifest/DEX findings: zero
- Scanner errors: zero; Health Connect is disclosed as `NonFreeDep` in metadata

If hashes differ, keep both APKs and run diffoscope before changing build flags. Fix timestamps, archive order, absolute paths, generated native metadata, or toolchain drift upstream. Never add a metadata source patch merely to make the scanner/build pass.
