import type { PracticeMetaResponse, SyntheticCatalogResponse } from "../contracts/api";
import { assertRelativeApiPath, practiceApiPaths } from "../contracts/api";
import { SYNTHETIC_OPERATION_VERSION, type OperationName, type OperationResponse, type ValidationIssue } from "../contracts/clinical";

for (const path of Object.values(practiceApiPaths)) assertRelativeApiPath(path);

export class PracticeClientError extends Error {
  constructor(readonly code: string, readonly status: number, readonly issues: readonly ValidationIssue[] = []) {
    super("The requested operation is unavailable");
    this.name = "PracticeClientError";
  }
}

async function getJson<T>(path: string): Promise<T> {
  assertRelativeApiPath(path);
  const response = await fetch(path, { method: "GET", credentials: "same-origin", cache: "no-store", headers: { Accept: "application/json" } });
  if (!response.ok) throw new PracticeClientError("operation_unavailable", response.status);
  return (await response.json()) as T;
}

export const practiceApi = Object.freeze({
  meta: (): Promise<PracticeMetaResponse> => getJson(practiceApiPaths.meta),
  catalog: (): Promise<SyntheticCatalogResponse> => getJson(practiceApiPaths.catalog),
});

export interface OperationClient {
  invoke(operation: OperationName, payload?: Record<string, unknown>): Promise<unknown>;
  clear(): void;
}

/** CSRF and every clinical selection remain closure-memory only and are cleared at logout. */
export function createSyntheticOperationClient(fetcher: typeof fetch = fetch): OperationClient {
  let csrfToken: string | undefined;
  return Object.freeze({
    async invoke(operation: OperationName, payload: Record<string, unknown> = {}): Promise<unknown> {
      const response = await fetcher(practiceApiPaths.operation, {
        method: "POST", credentials: "same-origin", cache: "no-store",
        headers: { "Content-Type": "application/json", Accept: "application/json" },
        body: JSON.stringify({ version: SYNTHETIC_OPERATION_VERSION, operation, payload, ...(csrfToken === undefined ? {} : { csrfToken }) }),
      });
      const body: unknown = await response.json().catch(() => null);
      if (!response.ok) {
        const error = isErrorEnvelope(body) ? body.error : undefined;
        throw new PracticeClientError(error?.code ?? "operation_unavailable", response.status, validIssues(error?.issues));
      }
      if (!isOperationResponse(body)) throw new PracticeClientError("invalid_response", 502);
      if (body.csrfToken) csrfToken = body.csrfToken;
      if (operation === "logout") csrfToken = undefined;
      return body.data;
    },
    clear(): void { csrfToken = undefined; },
  });
}

export const operationClient = createSyntheticOperationClient();

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
function isErrorEnvelope(value: unknown): value is { error: { code?: string; issues?: unknown } } {
  return isRecord(value) && isRecord(value.error) && (value.error.code === undefined || typeof value.error.code === "string");
}
function validIssues(value: unknown): readonly ValidationIssue[] {
  if (!Array.isArray(value)) return [];
  return value.filter((issue): issue is ValidationIssue => isRecord(issue) && typeof issue.code === "string" && typeof issue.field === "string") as ValidationIssue[];
}
function isOperationResponse(value: unknown): value is OperationResponse {
  if (!isRecord(value) || value.version !== SYNTHETIC_OPERATION_VERSION || value.ok !== true || !("data" in value)) return false;
  if (value.csrfToken !== undefined && typeof value.csrfToken !== "string") return false;
  return true;
}
