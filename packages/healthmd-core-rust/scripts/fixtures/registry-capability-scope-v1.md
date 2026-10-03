# Immutable metric-registry v1 capability scope

`registry-capability-scope-v1.json` captures the exact `known_capability_ids` in registry SHA `56def644baa3d81e0c6c2eda3733bfdd7ceee6554ca9ec609da80356c6578c99` at repository base `b8fd904f4d299f5af4a22111d2fdccf829705ea7`. This is an independent importer input, like the existing frozen native metric/crosswalk evidence, not a new runtime registry or a rewritten public fixture.

Product capabilities are broader than pure metric/profile authority. Adding Watch networking/setup to `product-capabilities.json` must not alter an embedded metric registry fingerprint, native renderer pins, or immutable semantic-result v1 bytes when no metric, reducer, unit, profile, or output changes. A cloud generation diagnostic for #171 demonstrated that unconstrained copying of the whole product inventory would repin Swift/Kotlin and include an unrelated previously added direct-corpus capability. That generated patch was **not adopted**.

The importer now projects only this explicit v1 scope from the **current** product inventory, retaining its available/unavailable/planned decisions for scoped entries. It fails closed if a scoped entry disappears or a metric references a capability outside the scope. New registry-visible capabilities require explicit scope/version and compatibility review; they cannot sneak in as a side effect of a non-metric feature. Product consumers must use the product inventory for capabilities outside this scope, including manual Watch API export.

The capability snapshot preserves the current registry bytes and fingerprints exactly; no generated Swift/Kotlin files, metric/profile mappings, runtime Rust constants, frozen schema signatures, or differential fixtures change. `scripts/tests/test_registry_capability_scope.py` verifies byte-exact reproduction, the baseline SHA, product-only addition invariance, missing-scope failure, new-metric rejection and scoped availability propagation. Both the dedicated Watch projection check and Core Rust CI execute these behavior tests on hosted runners.

Refs https://github.com/CodyBontecou/health-md/issues/171.
