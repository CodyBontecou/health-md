# F-Droid dependency and asset license audit

**Scope:** `fdroidRelease` production runtime/source boundary for Android 1.8.1 (version code 30). Re-run this review whenever the F-Droid runtime classpath, Rust `Cargo.lock`, fonts, native libraries, or report renderer changes.

## Application and shared source

| Material | License | Evidence |
| --- | --- | --- |
| `apps/android` application | AGPL-3.0-only | `apps/android/LICENSE`; full text packaged at `app/src/main/assets/licenses/healthmd-agpl-3.0.txt` |
| `packages/healthmd-core-rust` and in-tree protocol/core crates | AGPL-3.0-only | root `LICENSE`, crate metadata, and workspace lockfile |
| `packages/contracts` schemas/fixtures consumed during source builds/tests | AGPL-3.0-only | `packages/contracts/LICENSE`, `packages/contracts/README.md`, and root `LICENSES.md` |
| Android direct/wearable contract modules | AGPL-3.0-only | repository/component license boundary |

The contracts package license was explicitly resolved before F-Droid submission; it is no longer an unspecified source-boundary item.

## Android/JVM runtime families

The exact resolved graph is produced by:

```bash
./gradlew :app:dependencies --configuration fdroidReleaseRuntimeClasspath \
  > app/build/reports/fdroid-release-runtime-classpath.txt
```

| Family | License evidence/result |
| --- | --- |
| AndroidX (Compose, Activity, Lifecycle, Navigation, Health Connect client, WorkManager, DataStore, Room, Security, Glance) | Apache-2.0 project/artifact licenses |
| Kotlin standard library and kotlinx serialization/coroutines | Apache-2.0 |
| Dagger/Hilt | Apache-2.0 |
| Guava | Apache-2.0 |
| Timber | Apache-2.0 |
| PDFBox-Android and Apache PDFBox transitive code | Apache-2.0; retained notice at `app/src/main/assets/licenses/pdfbox-android-notice.txt` |
| Bouncy Castle provider | MIT-style Bouncy Castle license |
| JNA / packaged `libjnidispatch.so` | LGPL-2.1-or-later or Apache-2.0 dual-license; distributed under the Apache-2.0 option |

All are free-software compatible. Google namespaces alone are not treated as evidence of a non-free dependency: AndroidX, Guava, and Dagger/Hilt remain allowed.

## Rust native graph

`packages/healthmd-core-rust/Cargo.lock` is mandatory and all Android ABIs are built from source. `cargo metadata --locked --format-version 1` reports only these license expressions across the locked workspace graph:

- `AGPL-3.0-only` for Health.md crates;
- `MIT`, `Apache-2.0`, `MIT OR Apache-2.0`, and compatible BSD/Zlib/Unlicense alternatives;
- `MPL-2.0` for UniFFI crates;
- `Unicode-3.0` in `unicode-ident`'s compound expression;
- optional LGPL alternatives where a permissive MIT/Apache option is also offered.

No crate has an unspecified license in the locked graph. The F-Droid recipe pins Rust 1.88.0, `cargo-ndk` 4.1.2, NDK r27b, and all four native targets.

## Bundled assets

| Asset | License/evidence |
| --- | --- |
| Geist Sans and Geist Mono TTF files | SIL Open Font License 1.1; full OFL and source notice at `app/src/main/assets/licenses/geist-ofl.txt` and `geist-source.txt` |
| Health.md icons, Compose resources, schemas, templates, and synthetic fixtures | AGPL-3.0-only under their component boundary unless a more specific file notice applies |
| PDFBox notice | Packaged unchanged at `app/src/main/assets/licenses/pdfbox-android-notice.txt` |

## Deliberately excluded components

`verify-fdroid-artifact.sh` rejects the following coordinates, manifest components, and DEX package references:

- Google Play Billing (`com.android.billingclient`);
- Play Install Referrer (`com.android.installreferrer`);
- Play In-App Review (`com.google.android.play:review`);
- Google Play services Wearable/Data Layer (`play-services-wearable`);
- Play-only OAuth callback and Wear services.

The F-Droid source set also omits direct vendor-provider definitions/adapters, provider-specific Direct CLI request rules, and Health.md attribution/onboarding telemetry implementations. Vendor names and package IDs can still appear in the shared Health Connect record-source attribution map so an exported on-device record truthfully identifies the app that wrote it; those labels do not provide a cloud adapter, OAuth flow, package query, or network path. A broad `com.google.*` prohibition is intentionally not used.

## F-Droid disclosures

- **`NonFreeDep`: yes** — Health Connect runtime availability can depend on Google's proprietary Android system/provider component, especially on Android 9–13. The AndroidX client library itself remains Apache-2.0.
- **`Tracking`: no** — the F-Droid APK contains no Health.md telemetry code, endpoint, identifier, queue, worker, or state store.
- **`NonFreeNet`: no** — direct Fitbit/Oura/WHOOP/Withings cloud providers and OAuth callbacks are absent. User-configured API destinations and explicit paired Direct CLI sessions are user-directed product functions, not a required vendor network service.

Reviewer findings must be fixed in upstream source or this audit; do not use downstream source patches to hide a dependency.
