/** Fixed independent cross-adapter expectations from accepted Rust/common fixtures.
 * Review raw bytes and interface before tests; no candidate-derived expected results.
 * Literal safe ASCII texts were independently constructed for the restricted corpus. */
export const binding = {
  "caller": "synthetic-parity-owner",
  "source": "synthetic-parity-source",
  "profile": "local_read_only",
  "coverage": "partial",
  "logicalQuery": "synthetic-parity-query",
  "dataset": "synthetic-parity-dataset"
} as const;
export const grants = [
  "healthmd:read"
] as const;
export const profiles = [
  "local_direct",
  "local_read_only",
  "remote_read_only"
] as const;
export const flowVectors = [
  {
    "case_id": "summary-single",
    "arguments": {
      "dates": {
        "type": "all_available"
      },
      "metrics": {
        "type": "explicit",
        "metric_ids": [
          "steps"
        ]
      }
    },
    "argv": [
      "query",
      "healthmd_metric_chart",
      "--arguments",
      "{\"dates\":{\"type\":\"all_available\"},\"metrics\":{\"type\":\"explicit\",\"metric_ids\":[\"steps\"]}}",
      "--json"
    ],
    "invocation": {
      "query": {
        "schema": "healthmd.query_request",
        "schema_version": 1,
        "dates": {
          "type": "all_available"
        },
        "metrics": {
          "type": "explicit",
          "metric_ids": [
            "steps"
          ]
        },
        "sources": {
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
    },
    "pages": [
      {
        "coverage": "partial",
        "items": [
          {
            "count": 0
          }
        ],
        "next_cursor": null
      }
    ],
    "encodedBytes": [
      64
    ],
    "cursors": [
      null
    ],
    "value": {
      "coverage": "partial",
      "items": [
        {
          "count": 0
        }
      ],
      "next_cursor": null
    },
    "cliText": "{\n  \"coverage\": \"partial\",\n  \"items\": [\n    {\n      \"count\": 0\n    }\n  ],\n  \"next_cursor\": null\n}\n",
    "mcpText": "{\"coverage\":\"partial\",\"items\":[{\"count\":0}],\"next_cursor\":null}",
    "commonTrace": [
      "open",
      "read:null",
      "release"
    ],
    "counts": {
      "decoded": 1,
      "admitted": 1,
      "opened": 1,
      "read": 1,
      "released": 1
    },
    "deadlineMilliseconds": 1200000
  },
  {
    "case_id": "summary-continuation",
    "arguments": {
      "dates": {
        "type": "all_available"
      },
      "metrics": {
        "type": "explicit",
        "metric_ids": [
          "steps"
        ]
      }
    },
    "argv": [
      "query",
      "healthmd_metric_chart",
      "--arguments",
      "{\"dates\":{\"type\":\"all_available\"},\"metrics\":{\"type\":\"explicit\",\"metric_ids\":[\"steps\"]}}",
      "--json"
    ],
    "invocation": {
      "query": {
        "schema": "healthmd.query_request",
        "schema_version": 1,
        "dates": {
          "type": "all_available"
        },
        "metrics": {
          "type": "explicit",
          "metric_ids": [
            "steps"
          ]
        },
        "sources": {
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
    },
    "pages": [
      {
        "coverage": "partial",
        "items": [
          {
            "count": 0
          }
        ],
        "next_cursor": "synthetic-cursor-a"
      }
    ],
    "encodedBytes": [
      64
    ],
    "cursors": [
      null
    ],
    "value": {
      "coverage": "partial",
      "items": [
        {
          "count": 0
        }
      ],
      "next_cursor": "synthetic-cursor-a"
    },
    "cliText": "{\n  \"coverage\": \"partial\",\n  \"items\": [\n    {\n      \"count\": 0\n    }\n  ],\n  \"next_cursor\": \"synthetic-cursor-a\"\n}\n",
    "mcpText": "{\"coverage\":\"partial\",\"items\":[{\"count\":0}],\"next_cursor\":\"synthetic-cursor-a\"}",
    "commonTrace": [
      "open",
      "read:null",
      "release"
    ],
    "counts": {
      "decoded": 1,
      "admitted": 1,
      "opened": 1,
      "read": 1,
      "released": 1
    },
    "deadlineMilliseconds": 1200000
  },
  {
    "case_id": "lossless-two-pages",
    "arguments": {
      "dates": {
        "type": "all_available"
      },
      "metrics": {
        "type": "explicit",
        "metric_ids": [
          "steps"
        ]
      },
      "all_pages": true,
      "detail_level": "lossless",
      "page": {
        "max_items": 2,
        "max_bytes": 256,
        "cursor": null
      }
    },
    "argv": [
      "query",
      "healthmd_metric_chart",
      "--arguments",
      "{\"dates\":{\"type\":\"all_available\"},\"metrics\":{\"type\":\"explicit\",\"metric_ids\":[\"steps\"]},\"all_pages\":true,\"detail_level\":\"lossless\",\"page\":{\"max_items\":2,\"max_bytes\":256,\"cursor\":null}}",
      "--json"
    ],
    "invocation": {
      "query": {
        "schema": "healthmd.query_request",
        "schema_version": 1,
        "dates": {
          "type": "all_available"
        },
        "metrics": {
          "type": "explicit",
          "metric_ids": [
            "steps"
          ]
        },
        "sources": {
          "type": "all_available"
        },
        "operation": {
          "type": "metric_series"
        },
        "page": {
          "max_items": 2,
          "max_bytes": 256,
          "cursor": null
        }
      },
      "detail_level": "lossless",
      "all_pages": true
    },
    "pages": [
      {
        "coverage": "partial",
        "items": [
          {
            "count": 0
          }
        ],
        "next_cursor": "synthetic-cursor-a"
      },
      {
        "coverage": "partial",
        "items": [
          {
            "count": 1
          }
        ],
        "next_cursor": null,
        "packet": {
          "facts": [
            {
              "kind": "synthetic"
            },
            {
              "kind": "synthetic"
            }
          ]
        }
      }
    ],
    "encodedBytes": [
      64,
      64
    ],
    "cursors": [
      null,
      "synthetic-cursor-a"
    ],
    "value": {
      "schema": "healthmd.mcp_query_pages",
      "schema_version": 1,
      "pages": [
        {
          "coverage": "partial",
          "items": [
            {
              "count": 0
            }
          ],
          "next_cursor": "synthetic-cursor-a"
        },
        {
          "coverage": "partial",
          "items": [
            {
              "count": 1
            }
          ],
          "next_cursor": null,
          "packet": {
            "facts": [
              {
                "kind": "synthetic"
              },
              {
                "kind": "synthetic"
              }
            ]
          }
        }
      ],
      "receipt": {
        "page_count": 2,
        "item_count": 2,
        "packet_fact_count": 2,
        "traversal_complete": true,
        "next_cursor": null,
        "limit_reason": null
      }
    },
    "cliText": "{\n  \"pages\": [\n    {\n      \"coverage\": \"partial\",\n      \"items\": [\n        {\n          \"count\": 0\n        }\n      ],\n      \"next_cursor\": \"synthetic-cursor-a\"\n    },\n    {\n      \"coverage\": \"partial\",\n      \"items\": [\n        {\n          \"count\": 1\n        }\n      ],\n      \"next_cursor\": null,\n      \"packet\": {\n        \"facts\": [\n          {\n            \"kind\": \"synthetic\"\n          },\n          {\n            \"kind\": \"synthetic\"\n          }\n        ]\n      }\n    }\n  ],\n  \"receipt\": {\n    \"item_count\": 2,\n    \"limit_reason\": null,\n    \"next_cursor\": null,\n    \"packet_fact_count\": 2,\n    \"page_count\": 2,\n    \"traversal_complete\": true\n  },\n  \"schema\": \"healthmd.mcp_query_pages\",\n  \"schema_version\": 1\n}\n",
    "mcpText": "{\"pages\":[{\"coverage\":\"partial\",\"items\":[{\"count\":0}],\"next_cursor\":\"synthetic-cursor-a\"},{\"coverage\":\"partial\",\"items\":[{\"count\":1}],\"next_cursor\":null,\"packet\":{\"facts\":[{\"kind\":\"synthetic\"},{\"kind\":\"synthetic\"}]}}],\"receipt\":{\"item_count\":2,\"limit_reason\":null,\"next_cursor\":null,\"packet_fact_count\":2,\"page_count\":2,\"traversal_complete\":true},\"schema\":\"healthmd.mcp_query_pages\",\"schema_version\":1}",
    "commonTrace": [
      "open",
      "read:null",
      "read:synthetic-cursor-a",
      "release"
    ],
    "counts": {
      "decoded": 1,
      "admitted": 1,
      "opened": 1,
      "read": 2,
      "released": 1
    },
    "deadlineMilliseconds": 1200000
  },
  {
    "case_id": "aggregate-bound-partial",
    "arguments": {
      "dates": {
        "type": "all_available"
      },
      "metrics": {
        "type": "explicit",
        "metric_ids": [
          "steps"
        ]
      },
      "all_pages": true,
      "page": {
        "max_items": 2,
        "max_bytes": 1048576,
        "cursor": null
      }
    },
    "argv": [
      "query",
      "healthmd_metric_chart",
      "--arguments",
      "{\"dates\":{\"type\":\"all_available\"},\"metrics\":{\"type\":\"explicit\",\"metric_ids\":[\"steps\"]},\"all_pages\":true,\"page\":{\"max_items\":2,\"max_bytes\":1048576,\"cursor\":null}}",
      "--json"
    ],
    "invocation": {
      "query": {
        "schema": "healthmd.query_request",
        "schema_version": 1,
        "dates": {
          "type": "all_available"
        },
        "metrics": {
          "type": "explicit",
          "metric_ids": [
            "steps"
          ]
        },
        "sources": {
          "type": "all_available"
        },
        "operation": {
          "type": "metric_series"
        },
        "page": {
          "max_items": 2,
          "max_bytes": 1048576,
          "cursor": null
        }
      },
      "detail_level": "summary",
      "all_pages": true
    },
    "pages": [
      {
        "coverage": "partial",
        "items": [
          {
            "count": 0
          }
        ],
        "next_cursor": "synthetic-cursor-a"
      },
      {
        "coverage": "partial",
        "items": [
          {
            "count": 1
          }
        ],
        "next_cursor": null,
        "packet": {
          "facts": [
            {
              "kind": "synthetic"
            },
            {
              "kind": "synthetic"
            }
          ]
        }
      }
    ],
    "encodedBytes": [
      1048576,
      1048576
    ],
    "cursors": [
      null,
      "synthetic-cursor-a"
    ],
    "value": {
      "schema": "healthmd.mcp_query_pages",
      "schema_version": 1,
      "pages": [
        {
          "coverage": "partial",
          "items": [
            {
              "count": 0
            }
          ],
          "next_cursor": "synthetic-cursor-a"
        }
      ],
      "receipt": {
        "page_count": 1,
        "item_count": 1,
        "packet_fact_count": 0,
        "traversal_complete": false,
        "next_cursor": "synthetic-cursor-a",
        "limit_reason": "maximum_aggregate_bytes"
      }
    },
    "cliText": "{\n  \"pages\": [\n    {\n      \"coverage\": \"partial\",\n      \"items\": [\n        {\n          \"count\": 0\n        }\n      ],\n      \"next_cursor\": \"synthetic-cursor-a\"\n    }\n  ],\n  \"receipt\": {\n    \"item_count\": 1,\n    \"limit_reason\": \"maximum_aggregate_bytes\",\n    \"next_cursor\": \"synthetic-cursor-a\",\n    \"packet_fact_count\": 0,\n    \"page_count\": 1,\n    \"traversal_complete\": false\n  },\n  \"schema\": \"healthmd.mcp_query_pages\",\n  \"schema_version\": 1\n}\n",
    "mcpText": "{\"pages\":[{\"coverage\":\"partial\",\"items\":[{\"count\":0}],\"next_cursor\":\"synthetic-cursor-a\"}],\"receipt\":{\"item_count\":1,\"limit_reason\":\"maximum_aggregate_bytes\",\"next_cursor\":\"synthetic-cursor-a\",\"packet_fact_count\":0,\"page_count\":1,\"traversal_complete\":false},\"schema\":\"healthmd.mcp_query_pages\",\"schema_version\":1}",
    "commonTrace": [
      "open",
      "read:null",
      "read:synthetic-cursor-a",
      "release"
    ],
    "counts": {
      "decoded": 1,
      "admitted": 1,
      "opened": 1,
      "read": 2,
      "released": 1
    },
    "deadlineMilliseconds": 1200000
  }
] as const;
export const bounds = {
  "aggregateBytes": 2097152,
  "receiptReserveBytes": 16384,
  "pages": 4096,
  "pageBytes": 1048576,
  "pageItems": 1000
} as const;
export const fullIds = [
  "healthmd_status",
  "healthmd_doctor",
  "healthmd_capabilities",
  "healthmd_metrics",
  "healthmd_metric_chart",
  "healthmd_sleep_sessions",
  "healthmd_training_alignment",
  "healthmd_workouts",
  "healthmd_coverage",
  "healthmd_compare_periods",
  "healthmd_training_evidence",
  "healthmd_query",
  "healthmd_evidence_packet",
  "healthmd_pairing_start",
  "healthmd_pairing_status",
  "healthmd_export_files",
  "healthmd_export_raw",
  "healthmd_raw_artifact_read",
  "healthmd_export_job_status",
  "healthmd_export_job_resume",
  "healthmd_export_job_cancel"
] as const;
export const readOnlyIds = [
  "healthmd_status",
  "healthmd_doctor",
  "healthmd_capabilities",
  "healthmd_metrics",
  "healthmd_metric_chart",
  "healthmd_sleep_sessions",
  "healthmd_training_alignment",
  "healthmd_workouts",
  "healthmd_coverage",
  "healthmd_compare_periods",
  "healthmd_training_evidence",
  "healthmd_query",
  "healthmd_evidence_packet"
] as const;
export const localOnlyIds = [
  "healthmd_pairing_start",
  "healthmd_pairing_status",
  "healthmd_export_files",
  "healthmd_export_raw",
  "healthmd_raw_artifact_read",
  "healthmd_export_job_status",
  "healthmd_export_job_resume",
  "healthmd_export_job_cancel"
] as const;
export const catalogSha = "31377cf8ac0494d8410a2bd9cf69be0c65d1f0394517730e960f0f9a9016f52d" as const;
export const availability = {
  "normalization": "available",
  "execution": "not_implemented"
} as const;
export const otherAvailability = {
  "normalization": "not_implemented",
  "execution": "not_implemented"
} as const;
export const lifecycleVectors = [
  {
    "case_id": "read-ack",
    "phase": "read",
    "cleanupDefect": false
  },
  {
    "case_id": "read-mixed-ack",
    "phase": "read",
    "cleanupDefect": true
  },
  {
    "case_id": "final-allocation-ack",
    "phase": "allocation",
    "cleanupDefect": false
  },
  {
    "case_id": "final-allocation-mixed-ack",
    "phase": "allocation",
    "cleanupDefect": true
  },
  {
    "case_id": "admission-interrupt",
    "phase": "admission",
    "cleanupDefect": false
  }
] as const;
export const errorExpectations = {
  "cli": {
    "exitCode": 1,
    "error": {
      "code": "healthmd_query_failed",
      "message": "The candidate query failed."
    }
  },
  "mcpDenied": {
    "error": {
      "code": -32003,
      "message": "The caller lacks the required Health.md read scope."
    }
  },
  "mcpUnknown": {
    "error": {
      "code": -32602,
      "message": "Unknown tool"
    }
  },
  "mcpProtocol": {
    "result": {
      "content": [
        {
          "type": "text",
          "text": "{\"error\":\"healthmd_protocol_error\",\"message\":\"The candidate query failed.\"}"
        }
      ],
      "isError": true
    }
  }
} as const;
export const authorityCases = [
  "current-host-grants-denied",
  "binding-profile-rejected-before-open",
  "read-profile-local-tool-guesses-denied",
  "typed-and-defective-provider-errors-sanitized"
] as const;
export const proofLimits = [
  "Pure catalog only: CLI/MCP public discovery routes unimplemented.",
  "Trusted reviewed raw decoder/encoder test seams; literal ASCII texts only, no general serde/lexical/realhealth byte equivalence.",
  "Synthetic binding/encodedBytes attestations not native authentication/health completeness/frame or memory proof.",
  "Fiber scope only; no process/transport/durable/native/public/family/distribution qualification."
] as const;
