// Independent source-derived synthetic pages; no native evaluator/parity claim.
// service.rs query: original page for single-page; all-pages receipt and excluded-page replay.
// limits.rs: 2MiB -16384 aggregate,4096 pages,1MiB/1000 page bounds.
// encodedBytes are controlled fake adapter accounting values, not claimed payload serialization.
// Binding negatives supplement K05/C13 source obligations; actual cursor crypto remains native.
export interface PageVector { readonly id: string; readonly pages: readonly { readonly body: unknown; readonly encodedBytes: number }[]; readonly allPages: boolean; readonly initialCursor: string | null; readonly expected?: unknown; readonly expectedFailure?: string; }
export const traversalVectors: readonly PageVector[] = [
  {
    "id": "two-page-complete",
    "pages": [
      {
        "body": {
          "items": [
            {
              "synthetic": "one"
            }
          ],
          "packet": {
            "facts": [
              {
                "synthetic": "fact"
              }
            ]
          },
          "next_cursor": "opaque-a"
        },
        "encodedBytes": 80
      },
      {
        "body": {
          "items": [],
          "packet": null,
          "next_cursor": null
        },
        "encodedBytes": 48
      }
    ],
    "allPages": true,
    "initialCursor": null,
    "expected": {
      "schema": "healthmd.mcp_query_pages",
      "schema_version": 1,
      "pages": [
        {
          "items": [
            {
              "synthetic": "one"
            }
          ],
          "packet": {
            "facts": [
              {
                "synthetic": "fact"
              }
            ]
          },
          "next_cursor": "opaque-a"
        },
        {
          "items": [],
          "packet": null,
          "next_cursor": null
        }
      ],
      "receipt": {
        "page_count": 2,
        "item_count": 1,
        "packet_fact_count": 1,
        "traversal_complete": true,
        "next_cursor": null,
        "limit_reason": null
      }
    }
  },
  {
    "id": "single-page-forward-cursor",
    "pages": [
      {
        "body": {
          "items": [
            {
              "synthetic": "one"
            }
          ],
          "packet": {
            "facts": [
              {
                "synthetic": "fact"
              }
            ]
          },
          "next_cursor": "opaque-a"
        },
        "encodedBytes": 80
      }
    ],
    "allPages": false,
    "initialCursor": null,
    "expected": {
      "items": [
        {
          "synthetic": "one"
        }
      ],
      "packet": {
        "facts": [
          {
            "synthetic": "fact"
          }
        ]
      },
      "next_cursor": "opaque-a"
    }
  },
  {
    "id": "byte-limit-replay-excluded-page",
    "pages": [
      {
        "body": {
          "items": [
            {
              "synthetic": "one"
            }
          ],
          "packet": {
            "facts": [
              {
                "synthetic": "fact"
              }
            ]
          },
          "next_cursor": "opaque-a"
        },
        "encodedBytes": 1048576
      },
      {
        "body": {
          "items": [],
          "packet": null,
          "next_cursor": null
        },
        "encodedBytes": 1048576
      }
    ],
    "allPages": true,
    "initialCursor": null,
    "expected": {
      "schema": "healthmd.mcp_query_pages",
      "schema_version": 1,
      "pages": [
        {
          "items": [
            {
              "synthetic": "one"
            }
          ],
          "packet": {
            "facts": [
              {
                "synthetic": "fact"
              }
            ]
          },
          "next_cursor": "opaque-a"
        }
      ],
      "receipt": {
        "page_count": 1,
        "item_count": 1,
        "packet_fact_count": 1,
        "traversal_complete": false,
        "next_cursor": "opaque-a",
        "limit_reason": "maximum_aggregate_bytes"
      }
    }
  },
  {
    "id": "empty-coverage-preserved",
    "pages": [
      {
        "body": {
          "items": [],
          "packet": null,
          "next_cursor": null,
          "coverage": {
            "state": "empty",
            "source": "synthetic-source"
          }
        },
        "encodedBytes": 90
      }
    ],
    "allPages": true,
    "initialCursor": null,
    "expected": {
      "schema": "healthmd.mcp_query_pages",
      "schema_version": 1,
      "pages": [
        {
          "items": [],
          "packet": null,
          "next_cursor": null,
          "coverage": {
            "state": "empty",
            "source": "synthetic-source"
          }
        }
      ],
      "receipt": {
        "page_count": 1,
        "item_count": 0,
        "packet_fact_count": 0,
        "traversal_complete": true,
        "next_cursor": null,
        "limit_reason": null
      }
    }
  },
  {
    "id": "unavailable-coverage-preserved",
    "pages": [
      {
        "body": {
          "items": [],
          "packet": null,
          "next_cursor": null,
          "coverage": {
            "state": "unavailable",
            "source": "synthetic-source"
          }
        },
        "encodedBytes": 90
      }
    ],
    "allPages": true,
    "initialCursor": null,
    "expected": {
      "schema": "healthmd.mcp_query_pages",
      "schema_version": 1,
      "pages": [
        {
          "items": [],
          "packet": null,
          "next_cursor": null,
          "coverage": {
            "state": "unavailable",
            "source": "synthetic-source"
          }
        }
      ],
      "receipt": {
        "page_count": 1,
        "item_count": 0,
        "packet_fact_count": 0,
        "traversal_complete": true,
        "next_cursor": null,
        "limit_reason": null
      }
    }
  },
  {
    "id": "partial-coverage-preserved",
    "pages": [
      {
        "body": {
          "items": [],
          "packet": null,
          "next_cursor": null,
          "coverage": {
            "state": "partial",
            "source": "synthetic-source"
          }
        },
        "encodedBytes": 90
      }
    ],
    "allPages": true,
    "initialCursor": null,
    "expected": {
      "schema": "healthmd.mcp_query_pages",
      "schema_version": 1,
      "pages": [
        {
          "items": [],
          "packet": null,
          "next_cursor": null,
          "coverage": {
            "state": "partial",
            "source": "synthetic-source"
          }
        }
      ],
      "receipt": {
        "page_count": 1,
        "item_count": 0,
        "packet_fact_count": 0,
        "traversal_complete": true,
        "next_cursor": null,
        "limit_reason": null
      }
    }
  },
  {
    "id": "cursor-cycle",
    "pages": [
      {
        "body": {
          "items": [
            {
              "synthetic": "one"
            }
          ],
          "packet": {
            "facts": [
              {
                "synthetic": "fact"
              }
            ]
          },
          "next_cursor": "opaque-a"
        },
        "encodedBytes": 80
      },
      {
        "body": {
          "items": [
            {
              "synthetic": "one"
            }
          ],
          "packet": {
            "facts": [
              {
                "synthetic": "fact"
              }
            ]
          },
          "next_cursor": "opaque-a"
        },
        "encodedBytes": 80
      }
    ],
    "allPages": true,
    "initialCursor": null,
    "expectedFailure": "healthmd_protocol_error"
  },
  {
    "id": "initial-nonadvancing-cursor",
    "pages": [
      {
        "body": {
          "items": [
            {
              "synthetic": "one"
            }
          ],
          "packet": {
            "facts": [
              {
                "synthetic": "fact"
              }
            ]
          },
          "next_cursor": "opaque-a"
        },
        "encodedBytes": 80
      }
    ],
    "allPages": true,
    "initialCursor": "opaque-a",
    "expectedFailure": "healthmd_protocol_error"
  }
];
export const authorityVectors = [
  {
    "id": "missing-read-grant",
    "mutation": "grant",
    "expectedFailure": "healthmd_not_authorized"
  },
  {
    "id": "wrong-caller",
    "mutation": "caller",
    "expectedFailure": "healthmd_query_binding_mismatch"
  },
  {
    "id": "wrong-source",
    "mutation": "source",
    "expectedFailure": "healthmd_query_binding_mismatch"
  },
  {
    "id": "wrong-profile",
    "mutation": "profile",
    "expectedFailure": "healthmd_query_binding_mismatch"
  },
  {
    "id": "wrong-coverage",
    "mutation": "coverage",
    "expectedFailure": "healthmd_query_binding_mismatch"
  },
  {
    "id": "wrong-logicalQuery",
    "mutation": "logicalQuery",
    "expectedFailure": "healthmd_query_binding_mismatch"
  },
  {
    "id": "wrong-dataset",
    "mutation": "dataset",
    "expectedFailure": "healthmd_query_binding_mismatch"
  }
] as const;
