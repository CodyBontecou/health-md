# Apple and Android unification policy

## Status

This is the default product and contract policy for Health.md.

Health.md should provide one coherent product across Apple and Android whenever the operating systems expose semantically compatible capabilities. Platform differences are permitted only when they are required by SDK availability, permission models, background-execution rules, destination APIs, source-data semantics, security constraints, or native interaction conventions.

**Parity is the default. Divergence requires evidence. False equivalence is forbidden.**

This policy applies to new features and changes to existing features. It does not rewrite shipped Apple or Android contracts in place. Current historical profiles remain supported, and the proposed unified public successor is [`healthmd.health_data` v9](../../packages/contracts/proposals/unified-health-data-v9/contract.md).

## What “unified” means

When both platforms can support a capability with the same meaning, Health.md should align:

- user-visible capability and outcome;
- terminology and documentation;
- setting identity, defaults, and persistence semantics;
- public semantic IDs, units, statistics, missingness, and provenance;
- capture-completeness and safe-error behavior;
- export and automation behavior;
- API and CLI meaning;
- deterministic ordering and boundedness;
- compatibility fixtures and consumer expectations.

Unification does **not** require identical Swift and Kotlin implementations or pixel-identical interfaces. Apple and Android should use their native SDKs, lifecycle models, navigation patterns, permission prompts, background facilities, and destination APIs. Native UI may differ while the capability, terminology, data meaning, and observable result remain aligned.

## What may differ

A platform-specific outcome is acceptable when one of these conditions is documented:

1. The OS does not expose the data type or operation.
2. The OS exposes a related value with different semantics or statistics.
3. Permission, entitlement, background, storage, or transport rules make the same behavior impossible.
4. A native interaction pattern must differ for accessibility, security, or platform conventions.
5. The capability is intentionally staged, with the other platform recorded as `planned` and assigned a concrete target.
6. Preserving a shipped compatibility contract temporarily requires different output profiles.

A difference must not be justified only by implementation convenience, team ownership, existing file location, or whichever platform shipped first.

## Required decision order

For every new or changed Apple/Android capability:

1. **Define the platform-neutral outcome first.** Describe what the user or consumer can observe without referring to HealthKit, Health Connect, Swift, Kotlin, or a particular UI control.
2. **Inspect both platform sources.** Record Apple and Android API availability, permission requirements, units, statistics, timestamps, owner-day behavior, provenance, limits, and failure states.
3. **Choose the narrowest truthful classification.** Use the product capability inventory classifications `shared`, `apple_only`, `android_only`, `unavailable`, or `planned`. For metric mappings, use the registry evidence classes `platform_exact_or_unavailable`, `mapped_alias`, or `platform_distinct`.
4. **Prefer one language-neutral contract.** When semantics match, define shared IDs, units, reducers, capture states, and fixtures before adding platform projections.
5. **Keep native adapters thin.** Native code owns SDK querying, permissions, lifecycle, destinations, and platform UI. Shared semantics and deterministic rendering should use the shared contract/core where practical.
6. **Represent unavoidable differences explicitly.** Use independently versioned Apple/Android sections, distinct semantic IDs, or an unavailable/planned capability state. Never fill a shared field with an approximation merely to claim parity.
7. **Validate every consumer.** Exercise Apple, Android, shared Rust, CLI, contracts, website, API, automation, and the pinned external Obsidian integration whenever their boundary is affected.

## Semantic-equivalence rules

Two values may share a public semantic ID only when all relevant dimensions agree or have an approved lossless normalization:

- physiological or product meaning;
- source statistic and reducer;
- canonical unit and scale;
- owner-date and time-window behavior;
- missing-value and explicit-zero behavior;
- source/provenance meaning;
- duplicate and precedence behavior;
- precision and timestamp fidelity.

Similar labels are not sufficient evidence.

Examples:

- HealthKit HRV SDNN and Health Connect or WHOOP HRV RMSSD remain distinct identities.
- Apple Core sleep and Android Light sleep require an explicit reviewed mapping; label similarity alone is insufficient.
- A fraction on `0...1` and a percentage on `0...100` require an explicit scale conversion and canonical unit.
- An unsupported metric is omitted and reported as unsupported; it is never exported as zero.
- Provider data does not silently populate primary Apple Health or Health Connect summaries.

The unified-v9 [`mapping ledger`](../../packages/contracts/proposals/unified-health-data-v9/mapping-ledger.md) is the current review surface for shared metric claims.

## Product-capability rules

[`packages/contracts/product-capabilities.json`](../../packages/contracts/product-capabilities.json) is the machine-readable parity ledger.

For each affected capability:

- `shared` means both platforms provide the same user-facing outcome, even if native implementation details differ;
- `apple_only` or `android_only` requires an evidence path and a concrete platform limitation or approved product reason;
- `unavailable` requires a non-empty explanation;
- `planned` requires a named target rather than an indefinite parity promise.

Platform-only data remains a supported capability, not a defect. However, every platform-only classification must be revisited when the other OS adds a suitable API or when the shared contract evolves.

## Contract and version policy

- New shared behavior should target the common contract when truthful and available.
- Shipped profile bytes are immutable. Do not retrofit parity by changing Apple v5/v6/v7/v8 or Android v4/v5 in place.
- Schema versions identify one grammar and meaning. Never assign two incompatible contracts the same schema/version pair.
- API envelopes, direct protocols, raw snapshots, platform archives, semantic input, render input, and daily public schemas version independently.
- Readers should support the common successor before writers make it a default.
- A temporary platform-specific version must include a documented convergence or long-term-extension plan.

The proposed common daily schema is v9 rather than v8 because Apple v8 already identifies a shipped Apple grammar. See [RFC-0004](rfc-0004-unified-health-data-v9.md).

## Feature workflow

A cross-platform feature change should include, in the same reviewed workstream when practical:

1. A neutral capability statement and affected producer/consumer list.
2. Apple and Android source/API analysis.
3. Capability-inventory and metric-registry updates where applicable.
4. A common contract or a documented reason for platform sections.
5. Native Apple and Android implementation, or an explicit unavailable/planned state.
6. Cross-language fixtures and negative tests for semantic hazards.
7. Documentation that describes the shared outcome first and platform differences second.
8. Migration and compatibility notes for existing jobs, files, APIs, vaults, and scripts.
9. Validation receipts for every affected product and external consumer.

Do not merge a nominally shared capability with one platform silently omitted. If implementation must be staged, say so in the capability inventory and user-facing documentation.

## Definition of done

A feature or contract change affecting Apple or Android is complete only when reviewers can answer all of the following:

- Is the user-facing outcome unified wherever both OSes permit it?
- Are identical public IDs used only for semantically equivalent values?
- Are units, scales, reducers, timestamps, owner-day rules, and missingness explicit?
- Is every platform difference represented in the capability inventory or mapping ledger?
- Does an unavailable platform report absence honestly without fabricated placeholders?
- Are shared settings/defaults aligned, or is the difference documented?
- Are historical contracts and fixtures preserved?
- Have Apple, Android, shared-core, CLI, website, API/automation, and external-consumer effects been checked?
- Is there a convergence target for temporary divergence?

If any answer is unknown, the change remains incomplete or must be explicitly scoped as a platform-only proposal.

## Review and maintenance

Cross-platform parity is continuous, not a one-time migration. Review the capability inventory and mapping ledger:

- when either OS adds or deprecates a health API;
- when a feature is added to one mobile app;
- when public units, reducers, or owner-day behavior change;
- before promoting a platform-specific output to a shared profile;
- during major Apple and Android release planning.

The review should seek convergence first, preserve truthful platform distinctions second, and never trade semantic correctness for matching field counts.
