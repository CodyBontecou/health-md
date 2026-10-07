// Fixed source-derived expectations: registry.rs query_invocation/typed_query/detail_level/ensure_keys.
// This stage preserves nested selections/page verbatim; downstream query validation is separate.
// The non-string detail fallback and duplicate metrics are intentional source behavior.
export interface CatalogVector { readonly id: string; readonly arguments: unknown; readonly valid: boolean; readonly expected?: unknown; }
export const catalogVectors: readonly CatalogVector[] = [
  {
    "id": "defaults",
    "arguments": {
      "dates": {
        "type": "all_available"
      },
      "metrics": {
        "type": "all_available"
      }
    },
    "valid": true,
    "expected": {
      "query": {
        "schema": "healthmd.query_request",
        "schema_version": 1,
        "metrics": {
          "type": "all_available"
        },
        "sources": {
          "type": "all_available"
        },
        "dates": {
          "type": "all_available"
        },
        "operation": {
          "type": "metric_series"
        },
        "page": {
          "max_items": 250,
          "max_bytes": 262144,
          "cursor": null
        }
      },
      "detail_level": "summary",
      "all_pages": false
    }
  },
  {
    "id": "explicit-lossless-pagination",
    "arguments": {
      "dates": {
        "type": "exact",
        "range": {
          "start_date": "2026-07-01",
          "end_date": "2026-07-07"
        }
      },
      "metrics": {
        "type": "explicit",
        "metric_ids": [
          "sleep_total",
          "steps"
        ]
      },
      "sources": {
        "type": "explicit",
        "source_ids": [
          "apple_health"
        ]
      },
      "page": {
        "max_items": 1,
        "max_bytes": 1024,
        "cursor": "opaque-fixed"
      },
      "detail_level": "lossless",
      "all_pages": true
    },
    "valid": true,
    "expected": {
      "query": {
        "schema": "healthmd.query_request",
        "schema_version": 1,
        "metrics": {
          "type": "explicit",
          "metric_ids": [
            "sleep_total",
            "steps"
          ]
        },
        "sources": {
          "type": "explicit",
          "source_ids": [
            "apple_health"
          ]
        },
        "dates": {
          "type": "exact",
          "range": {
            "start_date": "2026-07-01",
            "end_date": "2026-07-07"
          }
        },
        "operation": {
          "type": "metric_series"
        },
        "page": {
          "max_items": 1,
          "max_bytes": 1024,
          "cursor": "opaque-fixed"
        }
      },
      "detail_level": "lossless",
      "all_pages": true
    }
  },
  {
    "id": "missing-dates",
    "arguments": {
      "metrics": {
        "type": "all_available"
      }
    },
    "valid": false
  },
  {
    "id": "missing-metrics",
    "arguments": {
      "dates": {
        "type": "all_available"
      }
    },
    "valid": false
  },
  {
    "id": "unknown-field",
    "arguments": {
      "dates": {},
      "metrics": {},
      "extra": 1
    },
    "valid": false
  },
  {
    "id": "invalid-detail",
    "arguments": {
      "dates": {},
      "metrics": {},
      "detail_level": "full"
    },
    "valid": false
  },
  {
    "id": "all-pages-null",
    "arguments": {
      "dates": {},
      "metrics": {},
      "all_pages": null
    },
    "valid": false
  },
  {
    "id": "all-pages-string",
    "arguments": {
      "dates": {},
      "metrics": {},
      "all_pages": "true"
    },
    "valid": false
  },
  {
    "id": "arguments-array",
    "arguments": [],
    "valid": false
  },
  {
    "id": "arguments-null",
    "arguments": null,
    "valid": false
  },
  {
    "id": "numeric-detail-falls-back",
    "arguments": {
      "dates": {},
      "metrics": {},
      "detail_level": 42
    },
    "valid": true,
    "expected": {
      "query": {
        "schema": "healthmd.query_request",
        "schema_version": 1,
        "metrics": {},
        "sources": {
          "type": "all_available"
        },
        "dates": {},
        "operation": {
          "type": "metric_series"
        },
        "page": {
          "max_items": 250,
          "max_bytes": 262144,
          "cursor": null
        }
      },
      "detail_level": "summary",
      "all_pages": false
    }
  },
  {
    "id": "null-detail-falls-back",
    "arguments": {
      "dates": {},
      "metrics": {},
      "detail_level": null
    },
    "valid": true,
    "expected": {
      "query": {
        "schema": "healthmd.query_request",
        "schema_version": 1,
        "metrics": {},
        "sources": {
          "type": "all_available"
        },
        "dates": {},
        "operation": {
          "type": "metric_series"
        },
        "page": {
          "max_items": 250,
          "max_bytes": 262144,
          "cursor": null
        }
      },
      "detail_level": "summary",
      "all_pages": false
    }
  },
  {
    "id": "opaque-nested-values-deferred",
    "arguments": {
      "dates": null,
      "metrics": 7,
      "sources": null,
      "page": {
        "cursor": "verbatim",
        "max_items": 0
      }
    },
    "valid": true,
    "expected": {
      "query": {
        "schema": "healthmd.query_request",
        "schema_version": 1,
        "metrics": 7,
        "sources": null,
        "dates": null,
        "operation": {
          "type": "metric_series"
        },
        "page": {
          "cursor": "verbatim",
          "max_items": 0
        }
      },
      "detail_level": "summary",
      "all_pages": false
    }
  },
  {
    "id": "metric-order-and-duplicates-retained",
    "arguments": {
      "dates": {
        "type": "all_available"
      },
      "metrics": {
        "type": "explicit",
        "metric_ids": [
          "steps",
          "sleep_total",
          "steps"
        ]
      }
    },
    "valid": true,
    "expected": {
      "query": {
        "schema": "healthmd.query_request",
        "schema_version": 1,
        "metrics": {
          "type": "explicit",
          "metric_ids": [
            "steps",
            "sleep_total",
            "steps"
          ]
        },
        "sources": {
          "type": "all_available"
        },
        "dates": {
          "type": "all_available"
        },
        "operation": {
          "type": "metric_series"
        },
        "page": {
          "max_items": 250,
          "max_bytes": 262144,
          "cursor": null
        }
      },
      "detail_level": "summary",
      "all_pages": false
    }
  }
];
