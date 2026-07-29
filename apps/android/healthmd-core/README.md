# Health.md shared core for Android

`:healthmd-core` packages the source-built `healthmd-core-uniffi` cdylib and its committed UniFFI 0.32 Kotlin binding. The Android app depends on this module, but it does not construct or call `HealthMdCoreService` during startup. The wrapper loads JNA and checks the UniFFI ABI only on its first method call.

`HealthMdCoreService` creates bounded ephemeral semantic and render sessions (`CORE_API_VERSION` 4) from `healthmd.semantic_input` v1 and `healthmd.render_input` v1 bytes. `HealthMdCoreSemanticSession` and `HealthMdCoreRenderSession` process coarse `ByteArray` batches with idempotent cancellation and stable health-free errors. `HealthMdCoreLosslessArtifactStream` returns bounded output chunks while retaining only sequence/checksum state; planned streams finalize with artifact ID, validated path, media type, write mode, byte count, and checksum. Profile-specific Markdown merge preserves the distinct shipped Android and Apple behavior.

The same handwritten wrapper exposes synchronous pure direct-protocol API revision 1 for exact
Apple-v1/Android-v2 request fixtures, complete control-envelope canonicalization, opaque
`HMDDIRCT` chunks, existing transfer negotiation, reviewed new-pairing client verification, and
reviewed session-key derivation. It does not replace Android networking, pairing/trust lifecycle,
Keystore state, secure-channel sequence/seal/open authority, sockets, or persistence. Returned key
bytes are caller-owned and must be wiped promptly; stateful migration remains security-review
gated. None of these wrappers owns Health Connect access, app persistence, SAF, ZIP, or HTTP
behavior.

Pinned native inputs:

- Rust `1.88.0` from `packages/healthmd-core-rust/rust-toolchain.toml`
- `cargo-ndk 4.1.2`
- Android NDK `27.1.12297006`
- minimum Android API 28
- ABIs `arm64-v8a`, `armeabi-v7a`, `x86_64`, and `x86`

Gradle builds native libraries from the current Rust source into ignored module build output:

```bash
./gradlew :healthmd-core:prepareRustDebug
./gradlew :healthmd-core:prepareRustRelease
```

Debug and release pre-build tasks depend on the matching Rust preparation task. No compiled `.so` files belong in source control.

Regenerate the committed Kotlin source from the repository root, then verify it is unchanged:

```bash
packages/healthmd-core-rust/scripts/generate-kotlin-bindings.sh \
  apps/android/healthmd-core/src/main/kotlin
cd apps/android
./gradlew :healthmd-core:checkHealthMdCoreKotlinBindings
```

The Gradle task and `GeneratedBindingsDriftTest` both compare the committed source with a fresh generation from the pinned Rust/UniFFI inputs. Generation also applies the checked-in `normalize-kotlin-bindings.py` transform, which masks UniFFI's `u16` checksum returns to 16 bits before comparing them. This is required because JNA direct mapping can observe sign-extended return-register bits on Android when checksum bit 15 is set.
