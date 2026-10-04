export function scenarioOutcome(scenario: Record<string, unknown>): string;
export function runConformance(codec: typeof import("../../../../apps/cloud/src/profile-sync-v1-contract"), root: string): Promise<{ fixtures: number; parserCases: number; scenarios: number; readRequests: number; fixedErrors: number; scope: string }>;
