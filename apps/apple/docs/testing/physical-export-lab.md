# Physical export performance lab

The physical export lab is a supervised Debug-only environment for repeatedly measuring the production Apple export paths on a real iPhone and Mac. It covers:

- standalone Rust CLI strict raw and generated-file exports;
- local iPhone Files exports;
- API Endpoint exports to a private HTTPS sink;
- connected-Mac corpus exports into a dedicated Mac vault.

It does not introduce an exporter, health-data schema, direct-protocol message, or arbitrary command server. Manual confirmation is the default. A private installation may enable Debug-only autonomous mode after one-time folder selection, pairing, and API setup; the first staged API secret requires an explicit on-device confirmation, while later changes must authenticate with that existing secret. Every run request is HMAC-authenticated and still accepts only fixed targets and scenarios. HealthKit authorization, foreground state, protected-data availability, and destination bindings remain enforced.

## Safety model

- Debug links accept only a bounded run ID, fixed target, and fixed scenario.
- Confirmation mode presents an iPhone sheet before every run. Private autonomous mode suppresses that sheet only for a valid HMAC-authenticated fixed request; unauthenticated URLs are rejected.
- Local and Mac runs require folders with the exact lab names below plus the private lab-binding marker. The Mac controller also attests the connected installation UUID and canonical, non-symlinked vault before the iPhone captures data.
- API runs require HTTPS on port `18443`, path `/export`, an authorization header, and an HMAC proof that the runner and iPhone hold the same endpoint URL and bearer token. The private autonomous lab may additionally pin the exact Debug sink leaf certificate, avoiding broad CA trust.
- Telemetry contains phases, outcomes, query counts, byte counts, thermal state, free space, and process footprint. HealthKit query rows aggregate only fixed operation labels; persisted lab evidence omits type identifiers as well as dates, health values, record UUIDs, predicates, paths, URLs, tokens, payloads, and error descriptions.
- API request bodies are hashed and discarded incrementally. Receipts and any temporary output are private (`0700` directories and `0600` files).
- Timeouts and disconnects are unknown outcomes. Inspect or resume the existing durable job; do not start a replacement blindly.
- Release builds must pass `make check-export-lab-release`, which scans both iOS and macOS binaries for Debug control and telemetry strings.

## One-time setup

### 1. Device state

1. Install a current Debug build on the physical iPhone.
2. Grant the intended HealthKit and local-network permissions.
3. Keep Health.md foregrounded, the iPhone powered, and Auto-Lock disabled only during supervised runs.
4. Open **Sync → CLI**, enable **Direct CLI Access**, and select **Manual IP**.
5. Keep the configured CLI port fixed. The local lab configuration defaults to `17648`.

### 2. Dedicated destinations

Create and select these exact roots once:

- iPhone Files destination: `HealthMdPerformanceLab`
- Mac destination: `~/HealthMdPerformanceLab/MacVault`

The Mac app must hold the real security-scoped bookmark for `MacVault`. `export-performance-lab.py init` creates a private binding shared by the runner and the Mac marker. The iPhone creates the same marker in `HealthMdPerformanceLab` only after the user confirms its first local run. Do not point the lab at an existing health vault.

### 3. Stable CLI identity

Build and atomically install a consistently signed CLI:

```bash
apps/apple/scripts/install-export-lab-cli.sh
```

The installed path is:

```text
~/Library/Application Support/HealthMdPerformanceLab/bin/healthmd
```

The fixed signing identifier allows future replacements to retain one designated requirement. A previously ad-hoc CLI is a different Keychain principal. Moving to the stable identity therefore requires one explicit supervised trust reset/re-pair; the installer never performs it.

After that approved one-time transition:

```bash
python3 apps/apple/scripts/export-performance-lab.py pair
```

Pairing instructions are health-free and appear on stderr. Keep the iPhone pairing screen foregrounded.

### 4. Private API sink

Create a local CA, server certificate, and bearer token:

```bash
apps/apple/scripts/setup-export-lab-api-tls.sh --host <MAC_LAN_IP>
```

On iPhone:

1. Install `ca-certificate.pem` as a profile.
2. Enable full trust under **Certificate Trust Settings**.
3. Configure the Health.md API Endpoint as `https://<MAC_LAN_IP>:18443/export`.
4. Copy the private token from the generated `api-token` file into the bearer-token field.

Start and inspect the sink:

```bash
python3 apps/apple/scripts/export-performance-lab.py sink-start --fault success
python3 apps/apple/scripts/export-performance-lab.py sink-status
```

The runner can restart it with one startup-selected fault:

- `delay-read`
- `delay-response`
- `status-429`
- `status-500`
- `close-after-bytes`
- `oversized-response`

There is no runtime fault-control endpoint.

## Preflight

```bash
python3 apps/apple/scripts/export-performance-lab.py preflight
```

Preflight checks host platform, free disk, CLI signing, direct trust, HTTPS sink readiness, Mac vault containment, and CoreDevice tooling. A failure pauses the run; it does not switch identity, peer, target, port, or destination.

## Running scenarios

Dry-run compatible matrices without touching the iPhone:

```bash
python3 apps/apple/scripts/export-performance-lab.py --dry-run run \
  --targets direct-files,local-iphone,api-endpoint,connected-mac \
  --scenario saved-full --repeat 3
python3 apps/apple/scripts/export-performance-lab.py --dry-run run \
  --targets direct-raw --scenario raw-full --repeat 3
python3 apps/apple/scripts/export-performance-lab.py --dry-run run \
  --targets direct-files --scenario thirty-day --repeat 1
```

Add `--supervised-ready` and remove `--dry-run` for a confirmation-mode physical run. When `allow_autonomous_runs` is enabled in the private `0600` config, the flag and per-run tap are unnecessary; the HMAC, unlock/foreground checks, thermal/disk limits, destination attestations, and target/scenario compatibility checks still apply.

The runner activates Health.md with a fixed Debug URL. Confirmation mode waits up to two minutes for **Start Supervised Run**; private autonomous mode starts immediately after HMAC and readiness verification. Direct targets then use the standalone signed CLI. App targets call the existing production orchestrator, API runner, or connected-corpus producer.

Available scenarios:

| Scenario | Compatible targets | Scope |
|---|---|---|
| `raw-full` | `direct-raw` | One strict native raw day; strict raw intentionally accepts no canonical selector |
| `sleep-summary` | `direct-files`, local, API, Mac | One selected summary day without provider sidecars |
| `saved-full` | `direct-files`, local, API, Mac | One day using current iPhone settings |
| `saved-full-provider-enabled` | local, API, Mac | One saved-settings day with eligible provider sidecars |
| `saved-full-provider-disabled` | local, API, Mac | One all-metrics lossless day without provider sidecars |
| `lossless-dense` | `direct-files`, local, API, Mac | One lossless Heart day |
| `multi-day` | `direct-files`, local, API, Mac | Seven-day saved-settings range |
| `thirty-day` | `direct-files` | Thirty complete requested days ending yesterday, using current iPhone settings and a fixed 585-second CLI waiter |
| `interrupt-resume` | `direct-files` | Interrupt after the first committed partition, then resume the same durable job |
| `cancel` | `direct-files`, local, API, Mac | Cancel an observed seven-day operation and require a terminal cancellation outcome |
| `large-file-backed-blob` | local iPhone serializer target | Debug-only 256 MiB file-backed serializer stress |

The stress scenario creates and removes deterministic temporary files inside the app container. It does not claim to emulate a real HealthKit attachment provider; real provider, lock, and low-disk coverage remains separate.

## Results and comparison

Private evidence lives under:

```text
~/Library/Application Support/HealthMdPerformanceLab/Runs/<run-id>/
```

A public-safe report omits job IDs, destination paths, and local digests:

```bash
python3 apps/apple/scripts/export-performance-lab.py report <run-or-suite-id>
python3 apps/apple/scripts/export-performance-lab.py compare <candidate-id> <baseline-id>
```

Fault-mode API runs are complete only when both the app failure/success and sink receipt match the startup-selected fault; they are grouped separately from success runs.

A comparison refuses incomplete suites and requires the private, unsanitized candidate and baseline artifact maps to have identical relative paths and SHA-256 values. Compare before scrubbing; digest evidence is intentionally removed by `scrub`. A comparison flags:

- median wall-time increase greater than `max(15%, 1 second)`;
- matching phase median increase greater than `max(25%, 100 milliseconds)` so one-digit-millisecond query noise cannot fail an otherwise faster run;
- iPhone footprint increase greater than `max(20%, 16 MiB)`;
- physical iPhone footprint above 256 MiB;
- missing telemetry, invalid receipts, output/schema mismatch, new Health.md/jetsam reports, or nonterminal runs.

Direct generated-file runs additionally require a job- and destination-bound success receipt whose completed and requested day counts match the fixed scenario scope, relative paths match the destination, and target-specific `direct-file/job` telemetry contains footprint, capacity, and thermal evidence. The 30-day scenario therefore passes only at 30/30 requested days with no failed dates, exact file/byte receipt totals, complete schema-v7 telemetry, and schema-v7 output; roll-up support days may increase internal capture work without changing that requirement. While a run is armed, the Debug coordinator preserves the prior idle-timer setting and temporarily prevents automatic lock; it restores the setting on completion, disarm, backgrounding, or a fixed 12-minute abandoned-arm deadline. Foreground loss still invalidates the telemetry even if finite background execution later commits a valid receipt.

Use one warm-up and at least three measured runs. Do not compare serious/critical thermal runs with nominal baselines.

## Resume, cleanup, and stops

```bash
python3 apps/apple/scripts/export-performance-lab.py resume <run-id>
python3 apps/apple/scripts/export-performance-lab.py scrub <run-or-suite-id>
python3 apps/apple/scripts/export-performance-lab.py cleanup <run-or-suite-id>
```

`Scrub` removes terminal health payloads, progress logs, destination files, API receipts, and terminal CLI jobs while retaining health-free state, phase telemetry, and crash indexes for comparison. `Cleanup` removes the entire private run. Both refuse nonterminal runs unless cleanup's `--force` is explicit. Preserve paused, cancellation-pending, or unknown direct jobs until the iPhone acknowledges a terminal state or the seven-day job lifetime expires. Local and Mac output is isolated under `Runs/<run-id>` and removed only inside the bound destination.

Stop the matrix on:

- iPhone lock/backgrounding or protected-data loss;
- permission or trust prompts;
- serious/critical thermal state;
- insufficient iPhone or Mac disk;
- provider rate limiting;
- peer, port, destination, schema, digest, or telemetry mismatch;
- unexpected output files.

## Agent optimization loop

1. Run preflight and a warm-up.
2. Record a three-run baseline for `sleep-summary`, provider-disabled selection, and `saved-full`.
3. Change one implementation variable.
4. Build/install the exact Debug iPhone worktree and open the exact Debug Mac app.
5. Run a one-target smoke test.
6. Run the full matrix only after the smoke test passes.
7. Compare phase medians, query-operation counts, provider transport waits, transfer time, and peak footprints.
8. For serializer regressions, copy a captured CITEM only into the private run payload directory and run the opt-in `HEALTHMD_PHYSICAL_CITEM_REPLAY_PATH` benchmark. Expected JSON and CSV paths are required so the replay verifies exact physical SHA-256 values.
9. Keep only changes that improve the matched physical workload without weakening byte parity, durability, privacy, or stop conditions; scrub the replay payload afterward.

The first intended use is separating the previously observed 295-second saved-settings run into HealthKit, provider transport/token refresh, CITEM spool, render, partition, transfer, acknowledgement, and Mac/API commit phases.
