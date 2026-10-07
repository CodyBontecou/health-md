// Independent literal oracle from registry.rs project_snapshot and validator; no candidate reader used.
// Mutation successes are validator-only, not authentication of changed asset bytes.
export const registryAuthority = {
  "sha256": "56def644baa3d81e0c6c2eda3733bfdd7ceee6554ca9ec609da80356c6578c99",
  "bytes": 501908,
  "metrics": 248,
  "categories": 33,
  "capabilities": 34
} as const;
export const profileVectors = [
  {
    "id": "apple_health_data_v8",
    "snapshot_sha256": "52f52e93298afc1caf62714f2bf8999abf35183a0a772a84421e5ca735d8cd41",
    "metrics": 230,
    "outputs": 226,
    "unavailable": 0,
    "enabled": 226,
    "first": "sleep_total",
    "last": "scheduled_workout_plans",
    "schema_version": 8
  },
  {
    "id": "android_frozen_v4",
    "snapshot_sha256": "f05d043d53cb75dd5ef34d03fe00f74c3fe8cd57e869adaddd97149814776892",
    "metrics": 106,
    "outputs": 161,
    "unavailable": 102,
    "enabled": 132,
    "first": "sleep_total",
    "last": "medical_resources",
    "schema_version": 4
  },
  {
    "id": "android_analytical_v5",
    "snapshot_sha256": "c3eab8396354c63766908f541d4b532ba31f2b7f1f9e9f22e077c6b29ca9bf01",
    "metrics": 106,
    "outputs": 161,
    "unavailable": 102,
    "enabled": 148,
    "first": "sleep_total",
    "last": "medical_resources",
    "schema_version": 5
  }
] as const;
export const semanticVectors = [
  {
    "semantic_id": "sleep_core",
    "equivalence": "mapped_alias",
    "apple": {
      "status": "backed",
      "selection_id": "sleep_core",
      "unit": "hours"
    },
    "android": {
      "status": "backed",
      "selection_id": "sleep_light",
      "unit": "hours"
    }
  },
  {
    "semantic_id": "hrv",
    "equivalence": "platform_exact_or_unavailable",
    "apple": {
      "status": "backed",
      "selection_id": "hrv",
      "unit": "ms"
    },
    "android": {
      "status": "unavailable",
      "selection_id": null,
      "unit": null
    }
  },
  {
    "semantic_id": "body_temperature",
    "equivalence": "mapped_alias",
    "apple": {
      "status": "backed",
      "selection_id": "body_temperature",
      "unit": "°C"
    },
    "android": {
      "status": "backed",
      "selection_id": "body_temp",
      "unit": "°"
    }
  },
  {
    "semantic_id": "wrist_temperature",
    "equivalence": "platform_exact_or_unavailable",
    "apple": {
      "status": "backed",
      "selection_id": "wrist_temperature",
      "unit": "°C"
    },
    "android": {
      "status": "unavailable",
      "selection_id": null,
      "unit": null
    }
  },
  {
    "semantic_id": "android.hrv_rmssd",
    "equivalence": "platform_distinct",
    "apple": {
      "status": "unavailable",
      "selection_id": null,
      "unit": null
    },
    "android": {
      "status": "backed",
      "selection_id": "hrv",
      "unit": "ms"
    }
  },
  {
    "semantic_id": "android.skin_temperature",
    "equivalence": "platform_distinct",
    "apple": {
      "status": "unavailable",
      "selection_id": null,
      "unit": null
    },
    "android": {
      "status": "backed",
      "selection_id": "skin_temperature",
      "unit": "°"
    }
  }
] as const;
export const mutationVectors = [
  {
    "id": "duplicate-semantic",
    "path": [
      "metrics",
      1,
      "semantic_id"
    ],
    "value": "sleep_total",
    "valid": false
  },
  {
    "id": "unknown-root",
    "path": [
      "extra"
    ],
    "value": true,
    "valid": false
  },
  {
    "id": "unknown-binding",
    "path": [
      "metrics",
      0,
      "apple",
      "extra"
    ],
    "value": true,
    "valid": false
  },
  {
    "id": "unknown-output",
    "path": [
      "profiles",
      0,
      "outputs",
      0,
      "extra"
    ],
    "value": true,
    "valid": false
  },
  {
    "id": "invalid-alias",
    "path": [
      "profiles",
      1,
      "outputs",
      0,
      "alias_kind"
    ],
    "value": "unknown",
    "valid": false
  },
  {
    "id": "contradictory-unavailable",
    "path": [
      "metrics",
      1,
      "android",
      "status"
    ],
    "value": "backed",
    "valid": false
  },
  {
    "id": "wrong-capability",
    "path": [
      "metrics",
      0,
      "capability_id"
    ],
    "value": "android.activity-intensity",
    "valid": false
  },
  {
    "id": "bad-aggregation",
    "path": [
      "metrics",
      0,
      "apple",
      "source_aggregation"
    ],
    "value": "guessed",
    "valid": false
  },
  {
    "id": "fraction-ordinal",
    "path": [
      "metrics",
      0,
      "apple",
      "ordinal"
    ],
    "value": 0.5,
    "valid": false
  },
  {
    "id": "overflow-version",
    "path": [
      "schema_version"
    ],
    "value": 4294967296,
    "valid": false
  },
  {
    "id": "null-vector",
    "path": [
      "metrics",
      0,
      "apple",
      "outputs"
    ],
    "value": null,
    "valid": false
  },
  {
    "id": "unknown-category",
    "path": [
      "categories",
      0,
      "extra"
    ],
    "value": true,
    "valid": false
  },
  {
    "id": "duplicate-output",
    "path": [
      "profiles",
      0,
      "outputs",
      1,
      "key"
    ],
    "value": "sleep_total_hours",
    "valid": false
  },
  {
    "id": "self-related",
    "path": [
      "metrics",
      0,
      "android",
      "related_semantic_ids"
    ],
    "value": [
      "sleep_total"
    ],
    "valid": false
  },
  {
    "id": "empty-unit-android",
    "path": [
      "metrics",
      0,
      "android",
      "unit"
    ],
    "value": "",
    "valid": true
  },
  {
    "id": "opaque-equivalence",
    "path": [
      "metrics",
      0,
      "equivalence"
    ],
    "value": "future_class",
    "valid": true
  },
  {
    "id": "null-optional-reference",
    "path": [
      "metrics",
      0,
      "android",
      "reference_name"
    ],
    "value": null,
    "valid": true
  },
  {
    "id": "default-output-option",
    "path": [
      "profiles",
      1,
      "outputs",
      0,
      "platform_native"
    ],
    "value": "DELETE",
    "valid": true
  }
] as const;
