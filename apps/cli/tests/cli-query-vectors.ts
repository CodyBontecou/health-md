/** Independently literal expectations from Rust QueryArgs/direct_query and accepted common modules.
 * Private argv/error projection only; decoder/admission are trusted host capabilities.
 * The raw serializer corpus is ASCII + safe integral JSON, not general serde/lossless parity.
 */
export const inputText = '{"dates":{"type":"all_available"},"metrics":{"type":"explicit","metric_ids":["steps"]}}';
export const decodedArguments = { dates: { type: "all_available" }, metrics: { type: "explicit", metric_ids: ["steps"] } } as const;
export const baseArgv = ["query", "healthmd_metric_chart", "--arguments", inputText] as const;
export const expectedInvocation = {
  query: { schema: "healthmd.query_request", schema_version: 1,
    dates: { type: "all_available" }, metrics: { type: "explicit", metric_ids: ["steps"] },
    sources: { type: "all_available" }, operation: { type: "metric_series" },
    page: { max_items: 250, max_bytes: 262144, cursor: null } },
  detail_level: "summary", all_pages: false,
} as const;
export const argvVectors = [
  { case_id: "defaults", argv: baseArgv, timeoutSeconds: 1200 },
  { case_id: "timeout_minimum", argv: [...baseArgv, "--timeout", "1", "--json"], timeoutSeconds: 1 },
  { case_id: "timeout_maximum", argv: [...baseArgv, "--timeout", "3600"], timeoutSeconds: 3600 },
] as const;
export const parseNegatives = [
  { case_id: "unknown_flag", argv: [...baseArgv, "--grant", "healthmd:read"] },
  { case_id: "caller_flag", argv: [...baseArgv, "--caller", "synthetic-other"] },
  { case_id: "source_flag", argv: [...baseArgv, "--source", "synthetic-other"] },
  { case_id: "dataset_flag", argv: [...baseArgv, "--dataset", "synthetic-other"] },
  { case_id: "missing_arguments", argv: ["query", "healthmd_metric_chart"] },
  { case_id: "duplicate_arguments", argv: [...baseArgv, "--arguments", inputText] },
  { case_id: "unknown_operation", argv: ["query", "synthetic-private-operation", "--arguments", inputText] },
  { case_id: "timeout_not_unsigned", argv: [...baseArgv, "--timeout", "-1"] },
] as const;
export const timeoutNegatives = ["0", "3601"] as const;
export const trustedAdmission = {
  binding: { caller: "synthetic-cli-owner", source: "synthetic-reviewed-source", profile: "local_read_only", coverage: "partial", logicalQuery: "synthetic-logical-query", dataset: "synthetic-dataset" },
  grants: ["healthmd:read"],
} as const;
export const losslessArguments = { ...decodedArguments, detail_level: "lossless", all_pages: true } as const;
export const singleBody = { items: [{ count: 0 }], next_cursor: null, coverage: "partial" } as const;
export const singleStdout = '{\n  "coverage": "partial",\n  "items": [\n    {\n      "count": 0\n    }\n  ],\n  "next_cursor": null\n}\n';
export const receiptValue = {
  schema: "healthmd.mcp_query_pages", schema_version: 1, pages: [singleBody],
  receipt: { page_count: 1, item_count: 1, packet_fact_count: 0, traversal_complete: true, next_cursor: null, limit_reason: null },
} as const;
export const receiptStdout = '{\n  "pages": [\n    {\n      "coverage": "partial",\n      "items": [\n        {\n          "count": 0\n        }\n      ],\n      "next_cursor": null\n    }\n  ],\n  "receipt": {\n    "item_count": 1,\n    "limit_reason": null,\n    "next_cursor": null,\n    "packet_fact_count": 0,\n    "page_count": 1,\n    "traversal_complete": true\n  },\n  "schema": "healthmd.mcp_query_pages",\n  "schema_version": 1\n}\n';
export const expectedErrors = {
  parse: { exitCode: 2, error: { code: "invalid_request", message: "Unsupported candidate query arguments." } },
  timeout: { exitCode: 1, error: { code: "invalid_request", message: "query timeout must be between 1 and 3600 seconds" } },
  decode: { exitCode: 1, error: { code: "invalid_request", message: "--arguments must be one valid JSON object" } },
  normalize: { exitCode: 1, error: { code: "invalid_request", message: "invalid typed query arguments" } },
  query: { exitCode: 1, error: { code: "healthmd_query_failed", message: "The candidate query failed." } },
  presentation: { exitCode: 1, error: { code: "candidate_presentation_unavailable", message: "The candidate JSON presentation is unavailable." } },
} as const;
export const unsafePresentations = [{ count: 9007199254740992 }, { count: -0 }, { count: 0.5 }, { label: "é" }] as const;
export const expectedCounts = { admitted: 1, opened: 1, read: 1, released: 1 } as const;
