# Shared Rust core native packaging baseline

**Recorded:** 2026-07-25
**Milestone:** M2 native packaging
**Source revision:** `00c812ae5c7ad6946660758c2c044a658ad8c74b-dirty` during development packaging

These measurements are health-free engineering baselines, not public product guarantees. They make later shared-core growth visible before Rust becomes authoritative for exports.

## Build identity

Native `CoreBuildInfo` reports independent core API, semantic-input, registry, and persisted-state versions. It also reports the packaging source revision and the SHA-256 of the embedded registry inventory. At this milestone all internal versions are `1`; the registry hash is `612dad41d0d20d236faf916b2cd70d1042bc0a46e1ab82ad8dd0442be6c4c05a`, identifying the bootstrap registry. It will change when M3 installs the complete metric registry.

Apple preparation additionally stamped source-input digest:

```text
5a6c51a8415f7ea12800258aea0dbd9d9a81c9585a0abbe372b6f497d212bb9f
```

Release builds from a clean tag report the exact Git revision without the `-dirty` suffix.

## Apple static artifact

Source-built `HealthmdCore.xcframework`:

| Slice | Static archive bytes |
|---|---:|
| iOS arm64 | 17,113,184 |
| iOS Simulator arm64 + x86_64 | 34,100,640 |
| macOS arm64 + x86_64 | 34,332,456 |
| Complete XCFramework files | 85,616,619 |

The distribution artifact contains static archives only. Unsigned archive validation found no standalone Rust dylib or framework. The iOS and macOS application executables from the initial unsigned archive pass were 12,882,416 and 17,179,800 bytes respectively; compare future release archives using the same Xcode configuration before treating those executable numbers as regressions.

The focused macOS smoke suite executed build-info, embedded self-test, and malformed-input handling in 0.004 seconds total. The package is not referenced by watchOS, widgets, UI tests, or the bundled CLI.

## Android release artifact

Minified signed release AAB:

```text
18,449,868 bytes
SHA-256 4c429c10e1f05fa180f6e454eb3ff55d4b5727084b4bf9395c930dc535759755
```

Uncompressed native entries:

| ABI | Rust core | JNA dispatcher |
|---|---:|---:|
| arm64-v8a | 531,400 | 157,720 |
| armeabi-v7a | 372,732 | 112,188 |
| x86 | 588,680 | 112,108 |
| x86_64 | 589,656 | 108,632 |

The AAB inspector verified both libraries and retained Health.md core symbols for all four ABIs after R8/minification. No `.so` file is tracked in Git.

The API-35 arm64 emulator instrumentation test exercised native library loading, checksum validation, build info, self-test, and stable malformed-input handling in 0.041 seconds. `HealthMdCoreService` is lazy; constructing it does not load JNA or Rust, and application startup does not construct or call the service.

## Reproduction

```bash
make -C apps/apple prepare-healthmd-core-rust
packages/healthmd-core-rust/scripts/validate-apple-xcframework.sh

cd apps/android
./gradlew :healthmd-core:connectedDebugAndroidTest
./gradlew :app:bundleRelease
../../packages/healthmd-core-rust/scripts/inspect-android-aab.sh \
  app/build/outputs/bundle/release/app-release.aab
```
