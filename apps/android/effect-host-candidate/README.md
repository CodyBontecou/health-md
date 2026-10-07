# Private Android Play Release host probe

This health-free candidate packages React 19.2.3, React Native 0.87.1 and
Effect 4.0.1 under `com.healthmd.effecthost.androidcandidate.play`. Native
`ReactHost.start()` executes the packaged bundle without a mounted React
surface, Metro, Internet permission, Health Connect, production credentials
or production state. The synthetic owned handle is an in-memory timer.

The independently reviewed ten-case fixture is SHA256
`c4a16f4b200a350f9c41e619af4129e81ad52245fdc79643c67ddf239c301ef6`.
Portable fakes verify orchestration; JVM tests verify native frame admission.
Neither substitutes for installed Release runtime evidence.
Native frame admission is a bounded linear scanner with no encoding/parser
allocation: byte bounds and strict surrogate pairs precede four-member parsing.
This private profile requires canonical unescaped keys/enums and raw numeric
tokens `1`/`0`; fractional/exponential spellings and escaped keys are rejected.
That private restriction makes no public JSON/schema parity claim.

The candidate uses prebuilt RN/Hermes AARs, AGP 9.2.1, Gradle 9.4.1, Kotlin
2.2.10 and JDK 17. It retains minSdk28/target36, compileSdk36 and four ABIs.
RN's exact AAR declares minSdk24 and minCompileSdk34. No RN/NDK/CMake source
build or production Gradle graph is reused. Android Gradle Plugin's built-in
Kotlin is disabled only in this candidate to keep the selected compiler explicit.
RN's source catalog declares Kotlin2.2.0; AGP9.2.1's actual POM requires
KGP2.2.10, so the candidate explicitly pins that resolved compiler instead.

Use Node24.21.0/npm11.19.0. Install the reviewed npm lock with
`npm ci --ignore-scripts --engine-strict --no-audit --no-fund`; no global
blocked-script policy is changed. `npm run check` performs installed graph
guards, type checking and the portable fixture. `npm run build` packages the
Metro Release asset and records its actual physical source inputs. Both read
the coordinator's frozen common emitted files; never rebuild those packages
from this candidate.

Native dependency resolution and artifact hashing precede native compilation:
`./gradlew --no-daemon --write-locks --write-verification-metadata sha256 :app:auditResolvedArtifacts`.
Generated hashes are audit inputs, not automatic provenance approval. Review
the exact Maven/native C++ license provenance before native build execution.

`scripts/prepare-test-signing.sh` creates one ignored candidate-only test key
and retains it for repeat builds, recording its public certificate fingerprint.
The initial key is random, so initial key creation is not bit-reproducible.
The private key never enters source control. This identity signs the
non-debuggable Release target and instrumentation APK only; it establishes
installability, never Play distribution or production signing.

After signing and native graph review, build
`./gradlew --no-daemon :app:assemblePlayRelease :app:testPlayReleaseUnitTest :app:assemblePlayReleaseAndroidTest`.
Invoke `scripts/run-release-probe.sh --channel play --target required-local-device --offline --fresh-process`
only against the component-required connected physical target. It validates
private IDs, signatures and merged manifest, installs only the two candidate
APKs and runs instrumentation in two fresh processes. It never discovers
other devices or substitutes an emulator. Target unavailability leaves the
runtime check unrun.
Every spawned adb/tool command has an explicit deadline and output limit.
A deadline kills only that spawned client/tool; failure cleanup stops only
the private candidate app and never kills the global adb daemon.

The write counters mean candidate-owned health/private state writes; they
exclude OS, Dalvik, RN and JVM caches, APK installation artifacts and harness
report files. Runtime memory is a sampled JVM heap value, not peak resident
memory. PSS/Java heap peaks are sampled every20ms and remain lower bounds
on true peaks; startup measures native initialization through first acquire.
Physical Health Connect, background/reboot/first-unlock behavior,
production adapters, accessibility and signed Play distribution remain
separate qualification tasks. Existing production authority is retained.
