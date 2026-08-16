export type JsonScalar = string | number | bigint | boolean | null;
export type JsonValue = JsonScalar | JsonValue[] | { [key: string]: JsonValue };

export type ContractKind =
  | "unified_v9" | "apple_health_data" | "android_frozen_v4" | "android_analytical_v5"
  | "android_unversioned" | "healthkit_archive" | "android_raw_snapshot" | "android_raw_manifest"
  | "android_merge_reference" | "android_raw_reference" | "whoop_typed_daily" | "external_provider_daily"
  | "rollup" | "api_envelope" | "raw_envelope" | "query_response" | "mcp_query_pages"
  | "generic_healthmd" | "generic_json";

export type DocumentOrigin = "file" | "healthmd-cli" | "healthmd-mcp";

export interface LoadedDocument {
  id: string;
  path: string;
  origin: DocumentOrigin;
  operation?: string;
  bytes: number;
  sha256: string;
  schema?: string;
  schemaVersion?: string | number | bigint;
  profile?: string;
  ownerDate?: string;
  platform?: string;
  captureStatus?: string;
  contractKind: ContractKind;
  contractValid: boolean;
  contractErrors: string[];
  experimentalV9: boolean;
  value: JsonValue;
}

export interface IndexEntry {
  documentId: string;
  file: string;
  path: string;
  value: JsonValue;
  kind: "scalar" | "object" | "array";
  contractKind: ContractKind;
  schema?: string;
  schemaVersion?: string | number | bigint;
  contractValid: boolean;
  contractErrors: string[];
  date?: string;
  ownerDate?: string;
  recordTimestamp?: string;
  unit?: string;
  statistic?: string;
  semanticId?: string;
  provenance?: JsonValue;
  platform?: string;
  provider?: string;
  source?: string;
  origin: DocumentOrigin;
  operation?: string;
  captureStatus?: string;
}

export interface ReferenceResolution {
  documentId: string;
  path: string;
  schema: string;
  schemaVersion: string | number | bigint;
  sha256: string;
  expectedBytes?: number;
  status: "resolved" | "unresolved" | "digest_mismatch" | "byte_count_mismatch";
  resolvedDocumentId?: string;
  detail: string;
}

export interface HealthStore {
  documents: LoadedDocument[];
  entries: IndexEntry[];
  references: ReferenceResolution[];
  warnings: string[];
  limits: LoadLimits;
}

export interface LoadLimits {
  maxFiles: number;
  maxDirectoryEntries: number;
  maxFileBytes: number;
  maxTotalBytes: number;
  maxLeaves: number;
  maxNodes: number;
  maxDepth: number;
  maxPathBytes: number;
  maxIndexedPathBytes: number;
  maxReferences: number;
}

export const DEFAULT_LIMITS: LoadLimits = {
  maxFiles: 256,
  maxDirectoryEntries: 100_000,
  maxFileBytes: 32 * 1024 * 1024,
  maxTotalBytes: 128 * 1024 * 1024,
  maxLeaves: 500_000,
  maxNodes: 1_000_000,
  maxDepth: 256,
  maxPathBytes: 4_096,
  maxIndexedPathBytes: 64 * 1024 * 1024,
  maxReferences: 10_000,
};

export interface QueryOptions {
  path?: string;
  search?: string;
  metric?: string;
  limit?: number;
  offset?: number;
}

export interface QueryResult {
  matches: IndexEntry[];
  totalMatches: number;
  truncated: boolean;
  evidenceChars: number;
  evidenceBytes: number;
}

export type ViewMode = "chart" | "table";
export interface ViewState {
  visible: boolean;
  target?: string;
  targetKind: "metric" | "path" | "search";
  mode: ViewMode;
  startDate?: string;
  endDate?: string;
  offset: number;
  windowSize: number;
}

export const initialView = (): ViewState => ({
  visible: true,
  targetKind: "metric",
  mode: "table",
  offset: 0,
  windowSize: 30,
});
