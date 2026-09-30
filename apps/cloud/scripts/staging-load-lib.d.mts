export const TWO_X_CONCURRENCY: number;
export const TWO_X_UPLOADS_PER_SECOND: number;
export const DEFAULT_DURATION_SECONDS: number;
export const MAX_REQUESTS_PER_ACCOUNT: number;
export const MAX_EXPORT_BYTES: number;
export interface StagingLoadConfig {
  endpoint: URL;
  expectedRevision: string;
  concurrency: number;
  uploadsPerSecond: number;
  durationSeconds: number;
  largeConcurrency: number;
}
export function parseStagingLoadConfig(environment?: Record<string, string | undefined>): StagingLoadConfig;
export function readDistinctAccountTokens(path: string | undefined, requiredCount: number): string[];
export function requiredDistinctAccounts(config: StagingLoadConfig): number;
export function buildSyntheticEnvelope(targetBytes?: number, marker?: string): Uint8Array;
export function percentile(values: number[], quantile: number): number | null;
