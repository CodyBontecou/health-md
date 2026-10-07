/** Literal Rust application/jsonrpc/result projections; private adapter only, before implementation. */
export const toolCall = { name: "healthmd_metric_chart", arguments: { dates: { type: "all_available" }, metrics: { type: "explicit", metric_ids: ["steps"] } } } as const;
export const caller = { id: "synthetic-mcp-owner", profile: "local_read_only", grants: ["healthmd:read"], allowedTools: ["healthmd_metric_chart"] } as const;
export const binding = { caller: "synthetic-mcp-owner", source: "synthetic-reviewed-source", profile: "local_read_only", coverage: "partial", logicalQuery: "synthetic-logical-query", dataset: "synthetic-dataset" } as const;
export const invocation = {
  query: { schema: "healthmd.query_request", schema_version: 1,
    dates: { type: "all_available" }, metrics: { type: "explicit", metric_ids: ["steps"] },
    sources: { type: "all_available" }, operation: { type: "metric_series" },
    page: { max_items: 250, max_bytes: 262144, cursor: null } },
  detail_level: "summary", all_pages: false,
} as const;
export const body = { items: [{ count: 0 }], next_cursor: null, coverage: "partial" } as const;
export const bodyText = '{"coverage":"partial","items":[{"count":0}],"next_cursor":null}';
export const success = { result: { content: [{ type: "text", text: bodyText }], isError: false } } as const;
export const allPagesArguments = { ...toolCall.arguments, detail_level: "lossless", all_pages: true } as const;
export const receipt = { schema: "healthmd.mcp_query_pages", schema_version: 1, pages: [body], receipt: { page_count: 1, item_count: 1, packet_fact_count: 0, traversal_complete: true, next_cursor: null, limit_reason: null } } as const;
export const receiptText = '{"pages":[{"coverage":"partial","items":[{"count":0}],"next_cursor":null}],"receipt":{"item_count":1,"limit_reason":null,"next_cursor":null,"packet_fact_count":0,"page_count":1,"traversal_complete":true},"schema":"healthmd.mcp_query_pages","schema_version":1}';
export const receiptResult = { result: { content: [{ type: "text", text: receiptText }], isError: false } } as const;
export const applicationErrors = {
  method: { error: { code: -32601, message: "Method not found" } },
  unknown: { error: { code: -32602, message: "Unknown tool" } },
  forbidden: { error: { code: -32003, message: "The caller lacks the required Health.md read scope." } },
  arguments: { error: { code: -32602, message: "Invalid tool arguments" } },
} as const;
export const methodNegatives = ["tools/list", "synthetic/guess"] as const;
export const toolNegatives = ["healthmd_pairing_start", "healthmd_export_raw", "healthmd_query", "synthetic-private-tool"] as const;
export const normalizationNegatives = [null, [], {}, { ...toolCall.arguments, request_id: "synthetic_private_id" }, { ...toolCall.arguments, caller: "synthetic-other-owner" }] as const;
export const unavailableText = '{"error":"healthmd_query_unavailable","message":"The candidate query failed."}';
export const unavailableResult = { result: { content: [{ type: "text", text: unavailableText }], isError: true } } as const;
export const protocolText = '{"error":"healthmd_protocol_error","message":"The candidate query failed."}';
export const protocolResult = { result: { content: [{ type: "text", text: protocolText }], isError: true } } as const;
export const expectedCounts = { caller: 1, decoded: 1, admitted: 1, opened: 1, read: 1, released: 1, encoded: 1 } as const;
export const traversalBounds = { aggregateBytes: 2097152, receiptReserveBytes: 16384, pages: 4096, pageBytes: 1048576, pageItems: 1000 } as const;
