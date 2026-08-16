import { spawn, type ChildProcess } from "node:child_process";
import { StringDecoder } from "node:string_decoder";
import { jsonStringify, parseJsonLossless, parseJsonNumberTokens, truncateUtf8, utf8ByteLength } from "./json.js";
import type { JsonValue } from "./model.js";
import { validateQueryContract } from "./query-contract.js";

export const HEALTHMD_QUERY_OPERATIONS = [
  "healthmd_metric_chart",
  "healthmd_sleep_sessions",
  "healthmd_training_alignment",
  "healthmd_workouts",
  "healthmd_coverage",
  "healthmd_compare_periods",
  "healthmd_training_evidence",
  "healthmd_query",
  "healthmd_evidence_packet",
] as const;

export const HEALTHMD_READ_OPERATIONS = [
  "healthmd_status", "healthmd_doctor", "healthmd_capabilities", "healthmd_metrics",
  ...HEALTHMD_QUERY_OPERATIONS,
] as const;

export type HealthMdQueryOperation = typeof HEALTHMD_QUERY_OPERATIONS[number];
export type HealthMdReadOperation = typeof HEALTHMD_READ_OPERATIONS[number];
export type HealthMdFetchTransport = "cli" | "mcp";

export interface HealthMdSourceConfig {
  cliExecutable?: string;
  /** Standalone stdio helper, such as the Mac app's healthmd-mcp. Omit to use `healthmd mcp serve-read-only`. */
  mcpExecutable?: string;
  deviceId?: string;
  port?: number;
  defaultTransport?: HealthMdFetchTransport;
  maxOutputBytes?: number;
}

export interface HealthMdFetchOptions {
  operation: HealthMdReadOperation;
  arguments: { [key: string]: JsonValue };
  transport?: HealthMdFetchTransport;
  timeoutSeconds?: number;
}

export interface HealthMdFetchResult {
  operation: HealthMdReadOperation;
  transport: HealthMdFetchTransport;
  text: string;
  bytes: number;
  syntheticPath: string;
}

const DEFAULT_MAX_OUTPUT_BYTES = 32 * 1024 * 1024;
const MAX_ARGUMENT_BYTES = 2 * 1024 * 1024;
const MAX_DIAGNOSTIC_BYTES = 1_024;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SOURCE_ENVIRONMENT_KEYS = [
  "PATH", "HOME", "USERPROFILE", "LOCALAPPDATA", "APPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_RUNTIME_DIR",
  "DBUS_SESSION_BUS_ADDRESS", "HEALTHMD_CLI_DATA_DIR", "HEALTHMD_MCP_BASE_URL", "TMPDIR", "TEMP", "TMP",
  "SystemRoot", "WINDIR", "PATHEXT", "LANG", "LC_ALL",
] as const;

function sourceEnvironment(): NodeJS.ProcessEnv {
  const environment: NodeJS.ProcessEnv = { NO_COLOR: "1" };
  for (const key of SOURCE_ENVIRONMENT_KEYS) if (process.env[key] !== undefined) environment[key] = process.env[key];
  return environment;
}

function signalProcessTree(child: ChildProcess, signal: NodeJS.Signals): void {
  try {
    if (process.platform !== "win32" && child.pid) process.kill(-child.pid, signal);
    else child.kill(signal);
  } catch { child.kill(signal); }
}

function terminateProcessTree(child: ChildProcess): void {
  signalProcessTree(child, "SIGTERM");
  const escalation = setTimeout(() => {
    if (child.exitCode === null && child.signalCode === null) signalProcessTree(child, "SIGKILL");
  }, 250);
  escalation.unref();
}

function validateExecutable(value: string, label: string): string {
  const executable = value.trim();
  if (!executable || executable.length > 4_096 || executable.includes("\0")) throw new Error(`${label} is invalid`);
  return executable;
}

function validatedConfig(config: HealthMdSourceConfig): Required<Pick<HealthMdSourceConfig, "cliExecutable" | "defaultTransport" | "maxOutputBytes">> & HealthMdSourceConfig {
  const cliExecutable = validateExecutable(config.cliExecutable ?? "healthmd", "Health.md CLI executable");
  const defaultTransport = config.defaultTransport ?? "mcp";
  if (defaultTransport !== "cli" && defaultTransport !== "mcp") throw new Error("Health.md fetch transport must be cli or mcp");
  const maxOutputBytes = config.maxOutputBytes ?? DEFAULT_MAX_OUTPUT_BYTES;
  if (!Number.isSafeInteger(maxOutputBytes) || maxOutputBytes < 1 || maxOutputBytes > 128 * 1024 * 1024) throw new Error("Health.md fetch output limit is invalid");
  if (config.deviceId && !UUID.test(config.deviceId)) throw new Error("Health.md device ID must be a UUID");
  if (config.port !== undefined && (!Number.isInteger(config.port) || config.port < 1 || config.port > 65_535)) throw new Error("Health.md direct port must be between 1 and 65535");
  return { ...config, cliExecutable, defaultTransport, maxOutputBytes, ...(config.mcpExecutable ? { mcpExecutable: validateExecutable(config.mcpExecutable, "Health.md MCP executable") } : {}) };
}

function queryOperation(value: string): value is HealthMdQueryOperation {
  return (HEALTHMD_QUERY_OPERATIONS as readonly string[]).includes(value);
}
function readOperation(value: string): value is HealthMdReadOperation {
  return (HEALTHMD_READ_OPERATIONS as readonly string[]).includes(value);
}

function validateArguments(value: { [key: string]: JsonValue }): void {
  const seen = new WeakSet<object>();
  const stack: Array<{ value: JsonValue; depth: number }> = [{ value, depth: 0 }];
  let nodes = 0;
  while (stack.length) {
    const item = stack.pop()!;
    if (++nodes > 100_000) throw new Error("Health.md query arguments exceed the node limit");
    if (item.depth > 128) throw new Error("Health.md query arguments exceed the depth limit");
    if (typeof item.value === "number" && !Number.isFinite(item.value)) throw new Error("Health.md query arguments contain a non-finite number");
    if (typeof item.value === "bigint") throw new Error("Health.md query arguments cannot contain bigint values");
    if (item.value === null || typeof item.value !== "object") continue;
    if (seen.has(item.value)) throw new Error("Health.md query arguments contain a cycle");
    seen.add(item.value);
    const children = Array.isArray(item.value) ? item.value : Object.values(item.value);
    for (const child of children) stack.push({ value: child, depth: item.depth + 1 });
  }
  if (utf8ByteLength(jsonStringify(value)) > MAX_ARGUMENT_BYTES) throw new Error(`Health.md query arguments exceed ${MAX_ARGUMENT_BYTES} bytes`);
}

function globalArguments(config: HealthMdSourceConfig): string[] {
  return [
    ...(config.deviceId ? ["--device", config.deviceId] : []),
    ...(config.port !== undefined ? ["--port", String(config.port)] : []),
  ];
}

function diagnostic(value: unknown): string {
  return truncateUtf8(String(value ?? "").replace(/[\r\n\t\0-\x1f\x7f]/g, " "), MAX_DIAGNOSTIC_BYTES);
}

function errorFromPayload(text: string): string | undefined {
  try {
    const value = parseJsonLossless(text);
    if (value === null || typeof value !== "object" || Array.isArray(value)) return undefined;
    const code = typeof value.error === "string" ? value.error : typeof value.code === "string" ? value.code : undefined;
    const message = typeof value.message === "string" ? value.message : undefined;
    return [code, message].filter(Boolean).map(diagnostic).join(": ") || undefined;
  } catch { return undefined; }
}

interface ProcessOutput { code: number | null; stdout: string; stderr: string }
async function collectProcess(command: string, args: string[], timeoutSeconds: number, maxOutputBytes: number, signal?: AbortSignal): Promise<ProcessOutput> {
  if (signal?.aborted) throw new Error("Health.md fetch cancelled");
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { shell: false, detached: process.platform !== "win32", stdio: ["ignore", "pipe", "pipe"], env: sourceEnvironment() });
    const stdout: Buffer[] = [], stderr: Buffer[] = [];
    let stdoutBytes = 0, stderrBytes = 0, settled = false;
    let timer: NodeJS.Timeout | undefined;
    const cleanup = () => {
      if (timer) clearTimeout(timer);
      signal?.removeEventListener("abort", cancel);
    };
    const stop = (error: Error) => {
      if (settled) return;
      settled = true; cleanup(); terminateProcessTree(child); reject(error);
    };
    const cancel = () => stop(new Error("Health.md fetch cancelled"));
    signal?.addEventListener("abort", cancel, { once: true });
    timer = setTimeout(() => stop(new Error(`Health.md fetch timed out after ${timeoutSeconds} seconds`)), timeoutSeconds * 1_000 + 500);
    child.stdout.on("data", (chunk: Buffer) => {
      if (settled) return;
      stdoutBytes += chunk.byteLength;
      if (stdoutBytes > maxOutputBytes) { stop(new Error(`Health.md output exceeds ${maxOutputBytes} bytes`)); return; }
      stdout.push(chunk);
    });
    child.stderr.on("data", (chunk: Buffer) => {
      if (settled || stderrBytes >= MAX_DIAGNOSTIC_BYTES) return;
      const retained = chunk.subarray(0, MAX_DIAGNOSTIC_BYTES - stderrBytes);
      stderr.push(retained); stderrBytes += retained.byteLength;
    });
    child.on("error", error => stop(new Error(`Unable to start Health.md executable: ${diagnostic(error.message)}`)));
    child.on("close", code => {
      if (settled) return;
      settled = true; cleanup();
      resolve({ code, stdout: Buffer.concat(stdout, stdoutBytes).toString("utf8"), stderr: Buffer.concat(stderr, stderrBytes).toString("utf8") });
    });
  });
}

async function fetchViaCli(config: ReturnType<typeof validatedConfig>, operation: HealthMdQueryOperation, argumentsValue: { [key: string]: JsonValue }, timeoutSeconds: number, signal?: AbortSignal): Promise<string> {
  const output = await collectProcess(config.cliExecutable, [
    ...globalArguments(config), "query", operation, "--arguments", jsonStringify(argumentsValue), "--timeout", String(timeoutSeconds),
  ], timeoutSeconds, config.maxOutputBytes, signal);
  const text = output.stdout.trim();
  if (output.code !== 0) throw new Error(`Health.md CLI query failed${errorFromPayload(text) ? `: ${errorFromPayload(text)}` : ` with exit code ${output.code ?? "unknown"}`}`);
  if (!text) throw new Error("Health.md CLI returned no JSON");
  const parsed = parseJsonLossless(text);
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("Health.md CLI returned a non-object JSON result");
  return text;
}

function mcpPayloadText(result: unknown): string {
  if (result === null || typeof result !== "object" || Array.isArray(result)) throw new Error("Health.md MCP returned an invalid tool result");
  const object = result as Record<string, unknown>;
  const content = Array.isArray(object.content) ? object.content : [];
  const text = content.find(item => item !== null && typeof item === "object" && !Array.isArray(item) && (item as Record<string, unknown>).type === "text");
  const payload = text && typeof (text as Record<string, unknown>).text === "string" ? (text as Record<string, unknown>).text as string : undefined;
  if (!payload) throw new Error("Health.md MCP returned no authoritative JSON text");
  if (object.isError === true) throw new Error(`Health.md MCP query failed${errorFromPayload(payload) ? `: ${errorFromPayload(payload)}` : ""}`);
  const parsed = parseJsonLossless(payload);
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("Health.md MCP returned a non-object JSON result");
  return payload;
}

type JsonObject = { [key: string]: JsonValue };
function jsonObject(value: JsonValue | undefined): value is JsonObject { return value !== null && typeof value === "object" && !Array.isArray(value); }

function requestedPage(operation: HealthMdReadOperation, argumentsValue: JsonObject): JsonObject | undefined {
  const request = operation === "healthmd_query" || operation === "healthmd_evidence_packet" ? argumentsValue.request : argumentsValue;
  return jsonObject(request) && jsonObject(request.page) ? request.page : undefined;
}
function requestedPageMaximum(operation: HealthMdReadOperation, argumentsValue: JsonObject): number {
  const page = requestedPage(operation, argumentsValue);
  if (page?.max_items === undefined) return 250;
  if (typeof page.max_items !== "number" || !Number.isSafeInteger(page.max_items) || page.max_items < 1 || page.max_items > 1_000) throw new Error("Health.md page.max_items must be an integer between 1 and 1000");
  return page.max_items;
}

function validateFetchedPayload(operation: HealthMdReadOperation, argumentsValue: JsonObject, text: string): void {
  const value = parseJsonLossless(text);
  if (!jsonObject(value)) throw new Error("Health.md returned a non-object JSON result");
  if (queryOperation(operation)) {
    const allPages = argumentsValue.all_pages === true;
    if (allPages !== (value.schema === "healthmd.mcp_query_pages")) throw new Error("Health.md query response shape disagrees with the requested all_pages mode");
    const page = requestedPage(operation, argumentsValue);
    const initialCursor = page && typeof page.cursor === "string" ? page.cursor : undefined;
    const errors = validateQueryContract(value, requestedPageMaximum(operation, argumentsValue), parseJsonNumberTokens(text), initialCursor);
    if (errors.length) throw new Error(errors[0]);
    return;
  }
  const expectedSchemas: Partial<Record<HealthMdReadOperation, readonly string[]>> = {
    healthmd_doctor: ["healthmd.direct_readiness", "healthmd.local_readiness"],
    healthmd_capabilities: ["healthmd.mcp_capabilities", "healthmd.local_capabilities"],
    healthmd_metrics: ["healthmd.metric_catalog"],
  };
  const expected = expectedSchemas[operation];
  if (expected && (!expected.includes(String(value.schema)) || value.schema_version !== 1)) throw new Error(`${operation} returned an unsupported contract identity`);
  if (operation === "healthmd_metrics" && !Array.isArray(value.metrics)) throw new Error("healthmd_metrics returned an invalid catalog");
}

async function fetchViaMcp(config: ReturnType<typeof validatedConfig>, operation: HealthMdReadOperation, argumentsValue: { [key: string]: JsonValue }, timeoutSeconds: number, signal?: AbortSignal): Promise<string> {
  if (signal?.aborted) throw new Error("Health.md fetch cancelled");
  const standalone = config.mcpExecutable;
  if (standalone && (config.deviceId || config.port !== undefined)) throw new Error("A standalone Health.md MCP helper cannot accept portable CLI device/port selection");
  const command = standalone ?? config.cliExecutable;
  const args = standalone ? [] : [...globalArguments(config), "mcp", "serve-read-only", "--timeout-seconds", String(timeoutSeconds)];
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { shell: false, detached: process.platform !== "win32", stdio: ["pipe", "pipe", "pipe"], env: sourceEnvironment() });
    let buffer = "", outputBytes = 0, stderr = "", settled = false, initialized = false;
    const decoder = new StringDecoder("utf8");
    let timer: NodeJS.Timeout | undefined;
    const cleanup = () => {
      if (timer) clearTimeout(timer);
      signal?.removeEventListener("abort", cancel);
    };
    const finish = (error?: Error, value?: string) => {
      if (settled) return;
      settled = true; cleanup(); child.stdin.end(); terminateProcessTree(child);
      if (error) reject(error); else resolve(value!);
    };
    const cancel = () => {
      try { child.stdin.write(`${jsonStringify({ jsonrpc: "2.0", method: "notifications/cancelled", params: { requestId: 2, reason: "cancelled" } })}\n`); } catch {}
      finish(new Error("Health.md fetch cancelled"));
    };
    signal?.addEventListener("abort", cancel, { once: true });
    timer = setTimeout(() => finish(new Error(`Health.md fetch timed out after ${timeoutSeconds} seconds`)), timeoutSeconds * 1_000 + 500);
    child.stderr.on("data", chunk => { if (utf8ByteLength(stderr) < MAX_DIAGNOSTIC_BYTES) stderr += Buffer.from(chunk).subarray(0, MAX_DIAGNOSTIC_BYTES - utf8ByteLength(stderr)).toString("utf8"); });
    child.stdin.on("error", error => { if (!settled) finish(new Error(`Health.md MCP stdin failed: ${diagnostic(error.message)}`)); });
    child.on("error", error => finish(new Error(`Unable to start Health.md MCP executable: ${diagnostic(error.message)}`)));
    child.on("close", code => { if (!settled) finish(new Error(`Health.md MCP exited before replying (code ${code ?? "unknown"}${stderr ? `; ${diagnostic(stderr)}` : ""})`)); });
    child.stdout.on("data", chunk => {
      outputBytes += Buffer.byteLength(chunk);
      if (outputBytes > config.maxOutputBytes) { finish(new Error(`Health.md MCP output exceeds ${config.maxOutputBytes} bytes`)); return; }
      buffer += decoder.write(chunk);
      while (!settled) {
        const newline = buffer.indexOf("\n");
        if (newline < 0) break;
        const line = buffer.slice(0, newline).replace(/\r$/, "");
        buffer = buffer.slice(newline + 1);
        if (!line) continue;
        let response: Record<string, unknown>;
        try { response = JSON.parse(line) as Record<string, unknown>; }
        catch { finish(new Error("Health.md MCP returned invalid JSON-RPC")); return; }
        if (response.id !== 1 && response.id !== 2) continue;
        if (response.jsonrpc !== "2.0") { finish(new Error("Health.md MCP returned an invalid JSON-RPC version")); return; }
        if (response.error) {
          const error = response.error as Record<string, unknown>;
          finish(new Error(`Health.md MCP ${response.id === 1 ? "initialization" : "query"} failed: ${diagnostic(error.message ?? error.code ?? "unknown error")}`));
          return;
        }
        if (response.id === 1) {
          if (initialized) { finish(new Error("Health.md MCP returned duplicate initialization responses")); return; }
          const result = response.result as Record<string, unknown> | undefined;
          if (!result || result.protocolVersion !== "2025-11-25") { finish(new Error("Health.md MCP negotiated an unexpected protocol version")); return; }
          initialized = true;
          child.stdin.write(`${jsonStringify({ jsonrpc: "2.0", method: "notifications/initialized", params: {} })}\n`);
          child.stdin.write(`${jsonStringify({ jsonrpc: "2.0", id: 2, method: "tools/call", params: { name: operation, arguments: argumentsValue } })}\n`);
        } else {
          if (!initialized) { finish(new Error("Health.md MCP replied before initialization completed")); return; }
          try { finish(undefined, mcpPayloadText(response.result)); }
          catch (error) { finish(error instanceof Error ? error : new Error(String(error))); }
        }
      }
    });
    child.once("spawn", () => child.stdin.write(`${jsonStringify({ jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-11-25", capabilities: {}, clientInfo: { name: "pi-healthmd-dashboard", version: "0.1.0" } } })}\n`));
  });
}

export async function fetchHealthMd(configValue: HealthMdSourceConfig, options: HealthMdFetchOptions, signal?: AbortSignal): Promise<HealthMdFetchResult> {
  const config = validatedConfig(configValue);
  if (!readOperation(options.operation)) throw new Error(`Unsupported read-only Health.md operation: ${String(options.operation)}`);
  if (options.arguments === null || typeof options.arguments !== "object" || Array.isArray(options.arguments)) throw new Error("Health.md query arguments must be one JSON object");
  validateArguments(options.arguments);
  const timeoutSeconds = options.timeoutSeconds ?? 1_200;
  if (!Number.isInteger(timeoutSeconds) || timeoutSeconds < 1 || timeoutSeconds > 3_600) throw new Error("Health.md query timeout must be between 1 and 3600 seconds");
  const transport = options.transport ?? config.defaultTransport;
  if (transport !== "cli" && transport !== "mcp") throw new Error("Health.md fetch transport must be cli or mcp");
  let text: string;
  if (transport === "cli") {
    if (!queryOperation(options.operation)) throw new Error(`${options.operation} requires the MCP transport; no transport fallback was attempted`);
    text = await fetchViaCli(config, options.operation, options.arguments, timeoutSeconds, signal);
  } else {
    text = await fetchViaMcp(config, options.operation, options.arguments, timeoutSeconds, signal);
  }
  validateFetchedPayload(options.operation, options.arguments, text);
  if (utf8ByteLength(text) > config.maxOutputBytes) throw new Error(`Health.md result exceeds ${config.maxOutputBytes} bytes`);
  return { operation: options.operation, transport, text, bytes: utf8ByteLength(text), syntheticPath: `${transport === "cli" ? "healthmd-cli" : "healthmd-mcp"}://${options.operation}` };
}
