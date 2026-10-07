import * as Effect from "effect/Effect";
import * as Result from "effect/Result";
import { fullOperationIds, readOnlyOperationIds } from "@healthmd/core-ts/candidate/catalog";

declare const parsedBrand: unique symbol;
declare const decisionBrand: unique symbol;
export interface OwnedParsed { readonly [parsedBrand]: true }
export type QueryOperation = "healthmd_metric_chart" | "healthmd_sleep_sessions" | "healthmd_training_alignment" | "healthmd_workouts" | "healthmd_coverage" | "healthmd_compare_periods" | "healthmd_training_evidence" | "healthmd_query" | "healthmd_evidence_packet";
export type GuidancePath = "query" | "export" | "extract" | "resume" | "cancel" | "direct" | "direct unpair" | "direct reset-trust" | "mcp" | "setup";
export type ParserErrorKind = "invalid_value" | "unknown_argument" | "invalid_subcommand" | "missing_equals" | "value_validation" | "too_many_values" | "too_few_values" | "wrong_number_of_values" | "argument_conflict" | "missing_required_argument" | "missing_subcommand" | "display_help" | "display_help_on_missing" | "display_version" | "io" | "format" | "unknown";
export type DecisionKind = "local_query_catalog" | "local_operation_schema" | "local_guidance" | "deferred_command" | "retained_text" | "parser_failure" | "private_input_failure" | "parser_contract_failure";
export interface DecisionFields {
  readonly kind: DecisionKind; readonly exit: 0 | 2 | null; readonly output: "json" | "human";
  readonly transport: "manual-ip" | "nearby" | null; readonly port: number | null;
  readonly recognized_operation: boolean; readonly request_sent: false; readonly authority_granted: false;
  readonly catalog: "query" | "operation" | null; readonly operation: QueryOperation | null;
  readonly guidance: GuidancePath | null; readonly text_reference: "welcome" | "help" | "version" | null;
  readonly missing_dates: boolean | null; readonly missing_mode: boolean | null; readonly missing_scope: boolean | null;
  readonly error: "invalid_request" | "private_discovery_input" | "private_discovery_parser" | null;
  readonly error_kind: ParserErrorKind | null;
}
export interface OwnedDecision extends DecisionFields { readonly [decisionBrand]: true }
export interface FixedFailure { readonly code: "private_discovery_input" | "private_discovery_parser" | "private_discovery_owned" }
export interface DiscoveryIssuer { issue(fieldsWire: unknown): OwnedParsed | null }
export interface TrustedParser { parse(argv: readonly string[], issuer: DiscoveryIssuer): unknown }
export interface ReviewedDiscoveryCatalog {
  readonly mirror_path: string; readonly mirror_raw_sha256: string;
  readonly full: readonly string[]; readonly read_only: readonly string[];
  readonly queries: readonly { readonly name: string; readonly title: string; readonly description: string; readonly kind: "Query" }[];
  readonly normal_commands: readonly string[]; readonly feature_commands: readonly string[]; readonly groups: readonly string[]; readonly donor40: string;
}
export interface PrivateDiscovery {
  normalize(argvJson: unknown, tty: unknown): Effect.Effect<OwnedDecision, never>;
  encode(value: unknown): Result.Result<string, FixedFailure>;
}
export interface DiscoveryFactory { create(parser: TrustedParser, reviewedCatalog: ReviewedDiscoveryCatalog): PrivateDiscovery }

type Primitive = string | number | boolean | null;
const commandPaths = new Set(["status", "export", "extract", "query", "resume", "cancel", "direct pair", "direct devices", "direct unpair", "direct reset-trust", "mcp serve", "mcp serve-read-only", "mcp schema", "setup codex", "mcp serve-http", "direct", "mcp", "setup"]);
const queryNames: readonly QueryOperation[] = ["healthmd_metric_chart", "healthmd_sleep_sessions", "healthmd_training_alignment", "healthmd_workouts", "healthmd_coverage", "healthmd_compare_periods", "healthmd_training_evidence", "healthmd_query", "healthmd_evidence_packet"];
const errorKinds: readonly ParserErrorKind[] = ["invalid_value", "unknown_argument", "invalid_subcommand", "missing_equals", "value_validation", "too_many_values", "too_few_values", "wrong_number_of_values", "argument_conflict", "missing_required_argument", "missing_subcommand", "display_help", "display_help_on_missing", "display_version", "io", "format", "unknown"];
const invalid = Object.freeze({});
const ownedFailure: FixedFailure = Object.freeze({ code: "private_discovery_owned" });
function reject(): never { throw invalid }
/** Private unmeasured admission budgets, not a restriction on the retained public CLI. */
function utf8(text: string, maximum: number): number {
  if (text.length > maximum) reject();
  let bytes = 0;
  for (let index = 0; index < text.length; index++) {
    const code = text.charCodeAt(index);
    if (code === 0) reject();
    if (code >= 0xd800 && code <= 0xdbff) {
      const low = text.charCodeAt(++index);
      if (!(low >= 0xdc00 && low <= 0xdfff)) reject();
      bytes += 4;
    } else if (code >= 0xdc00 && code <= 0xdfff) reject();
    else bytes += code < 128 ? 1 : code < 2048 ? 2 : 3;
    if (bytes > maximum) reject();
  }
  return bytes;
}
/** Flat closed arrays only: no object property access, recursion, or JSON numeric rounding. */
function parseArray(input: unknown, stringsOnly: boolean): readonly Primitive[] {
  if (typeof input !== "string") reject();
  const text = input;
  utf8(text, 4096);
  let position = 0, decodedBytes = 0;
  const values: Primitive[] = [];
  const whitespace = () => { while (position < text.length && /[\x20\t\r\n]/.test(text[position]!)) position++; };
  const string = (): string => {
    const begin = position++;
    while (position < text.length) {
      const next = text[position++]!;
      if (next === '"') {
        const parsed: unknown = JSON.parse(text.slice(begin, position));
        if (typeof parsed !== "string") reject();
        decodedBytes += utf8(parsed, 1024);
        if (decodedBytes > 4096) reject();
        return parsed;
      }
      if (next === "\\") position++;
      else if (next.charCodeAt(0) < 32) reject();
    }
    return reject();
  };
  whitespace(); if (text[position++] !== "[") reject(); whitespace();
  if (text[position] !== "]") while (true) {
    if (values.length === 64) reject();
    if (text[position] === '"') values.push(string());
    else if (stringsOnly) reject();
    else {
      let found = false;
      for (const [token, value] of [["true", true], ["false", false], ["null", null]] as const) {
        if (text.startsWith(token, position)) { position += token.length; values.push(value); found = true; break; }
      }
      if (!found) {
        const begin = position;
        if (text[position] === "0") position++;
        else {
          if (!/[1-9]/.test(text[position] ?? "")) reject();
          while (/[0-9]/.test(text[position] ?? "")) { if (position - begin >= 5) reject(); position++; }
        }
        // Prove raw canonical u16 token before Number. Fraction/exponent/-0 never convert.
        const raw = text.slice(begin, position);
        if (raw.length > 5 || (raw.length === 5 && raw > "65535")) reject();
        if (/[.eE0-9]/.test(text[position] ?? "")) reject();
        values.push(Number(raw));
      }
    }
    whitespace();
    if (text[position] === "]") break;
    if (text[position++] !== ",") reject(); whitespace();
  }
  if (text[position++] !== "]") reject(); whitespace();
  if (position !== text.length) reject();
  return Object.freeze(values);
}
interface Invocation {
  readonly type: "invocation"; readonly path: string; readonly transport: "manual-ip" | "nearby"; readonly port: number;
  readonly json: boolean; readonly human: boolean; readonly operation: string | null;
  readonly argumentsPresent: boolean; readonly identifierPresent: boolean; readonly datePresent: boolean;
  readonly modePresent: boolean; readonly scopePresent: boolean; readonly confirm: boolean;
}
interface ParseFailure { readonly type: "failure"; readonly errorKind: ParserErrorKind; readonly json: boolean; readonly human: boolean }
interface Text { readonly type: "text"; readonly reference: "welcome" | "help" | "version"; readonly json: boolean; readonly human: boolean }
type Parsed = Invocation | ParseFailure | Text;
function descriptor(wire: unknown): Parsed {
  const values = parseArray(wire, false);
  if (values[0] === "invocation") {
    const [type, path, transport, port, json, human, operation, argumentsPresent, identifierPresent, datePresent, modePresent, scopePresent, confirm] = values;
    if (values.length !== 13 || typeof path !== "string" || !commandPaths.has(path)
      || (transport !== "manual-ip" && transport !== "nearby") || typeof port !== "number"
      || typeof json !== "boolean" || typeof human !== "boolean" || (json && human)
      || !(operation === null || typeof operation === "string") || (path !== "query" && operation !== null)
      || typeof argumentsPresent !== "boolean" || typeof identifierPresent !== "boolean" || typeof datePresent !== "boolean"
      || typeof modePresent !== "boolean" || typeof scopePresent !== "boolean" || typeof confirm !== "boolean") reject();
    return Object.freeze({ type: type as "invocation", path, transport, port, json, human, operation, argumentsPresent, identifierPresent, datePresent, modePresent, scopePresent, confirm });
  }
  if (values[0] === "failure") {
    const [, path, errorKind, json, human] = values;
    if (values.length !== 5 || typeof path !== "string" || (path !== "" && !commandPaths.has(path)) || typeof errorKind !== "string"
      || !errorKinds.includes(errorKind as ParserErrorKind) || typeof json !== "boolean" || typeof human !== "boolean") reject();
    return Object.freeze({ type: "failure", errorKind: errorKind as ParserErrorKind, json, human });
  }
  if (values[0] === "text") {
    const [, reference, json, human] = values;
    if (values.length !== 4 || (reference !== "welcome" && reference !== "help" && reference !== "version") || typeof json !== "boolean" || typeof human !== "boolean") reject();
    return Object.freeze({ type: "text", reference, json, human });
  }
  return reject();
}
const outputMode = (json: boolean, human: boolean, tty: boolean): "json" | "human" => json || (!human && !tty) ? "json" : "human";
function fields(kind: DecisionKind, output: "json" | "human" = "json"): DecisionFields {
  return { kind, exit: kind === "deferred_command" ? null : kind.endsWith("failure") ? 2 : 0, output,
    transport: null, port: null, recognized_operation: false, request_sent: false, authority_granted: false,
    catalog: null, operation: null, guidance: null, text_reference: null,
    missing_dates: null, missing_mode: null, missing_scope: null,
    error: kind === "private_input_failure" ? "private_discovery_input" : kind === "parser_contract_failure" ? "private_discovery_parser" : null, error_kind: null };
}
/** Static host setup is trusted and must bind actual reviewed catalog bytes outside this module.
 * Parser is a pure local coarse capability; this module performs no full clap parsing or I/O.
 * No caller-provided catalog, issuer, descriptor, output hint, or command name grants authority. */
export function createDiscovery(parser: TrustedParser, reviewedCatalog: ReviewedDiscoveryCatalog): PrivateDiscovery {
  const parsed = new WeakMap<object, Parsed>(), decisions = new WeakSet<object>();
  let catalogValid = false;
  const queries = new Set<string>();
  try {
    catalogValid = reviewedCatalog.mirror_raw_sha256 === "31377cf8ac0494d8410a2bd9cf69be0c65d1f0394517730e960f0f9a9016f52d"
      && reviewedCatalog.mirror_path === "apps/cli/crates/healthmd-mcp/assets/mcp-tools-v1.json"
      && reviewedCatalog.full.length === fullOperationIds.length && reviewedCatalog.full.every((name, index) => name === fullOperationIds[index])
      && reviewedCatalog.read_only.length === readOnlyOperationIds.length && reviewedCatalog.read_only.every((name, index) => name === readOnlyOperationIds[index])
      && reviewedCatalog.queries.length === queryNames.length && reviewedCatalog.queries.every((row, index) => row.kind === "Query" && row.name === queryNames[index]);
    if (catalogValid) for (const row of reviewedCatalog.queries) queries.add(row.name);
  } catch { /* Fixed private parser failure on use; catalog identity is not authentication. */ }
  const own = (value: DecisionFields): OwnedDecision => { const decision = Object.freeze(value); decisions.add(decision); return decision as OwnedDecision; };
  const issuer: DiscoveryIssuer = Object.freeze({ issue(wire: unknown): OwnedParsed | null {
    try { const value = descriptor(wire); const token = Object.freeze({}); parsed.set(token, value); return token as OwnedParsed; }
    catch { return null; }
  } });
  return Object.freeze({
    normalize(argvJson: unknown, tty: unknown): Effect.Effect<OwnedDecision, never> {
      return Effect.sync(() => {
        let argv: readonly string[];
        try { if (typeof tty !== "boolean") reject(); argv = parseArray(argvJson, true) as readonly string[]; }
        catch { return own(fields("private_input_failure")); }
        if (!catalogValid) return own(fields("parser_contract_failure"));
        let invocation: Parsed | undefined;
        try { const returned = parser.parse(argv, issuer); if (returned !== null && typeof returned === "object") invocation = parsed.get(returned); }
        catch { /* No provider errors or user arguments escape. */ }
        if (!invocation) return own(fields("parser_contract_failure"));
        const output = outputMode(invocation.json, invocation.human, tty as boolean);
        if (invocation.type === "failure") return own({ ...fields("parser_failure", output), error: "invalid_request", error_kind: invocation.errorKind });
        if (invocation.type === "text") return own({ ...fields("retained_text", output), transport: "manual-ip", port: 17647, text_reference: invocation.reference });
        let kind: DecisionKind = "deferred_command", operation: QueryOperation | null = null, guidance: GuidancePath | null = null;
        if (invocation.path === "query" && (invocation.operation === null || !invocation.argumentsPresent)) {
          if (invocation.operation !== null && queries.has(invocation.operation)) { kind = "local_operation_schema"; operation = invocation.operation as QueryOperation; }
          else kind = "local_query_catalog";
        } else if ((invocation.path === "export" && (!invocation.datePresent || !invocation.modePresent))
          || (invocation.path === "extract" && (!invocation.datePresent || !invocation.scopePresent))
          || (["resume", "cancel", "direct unpair"].includes(invocation.path) && !invocation.identifierPresent)
          || (invocation.path === "direct reset-trust" && !invocation.confirm)
          || ["direct", "mcp", "setup"].includes(invocation.path)) { kind = "local_guidance"; guidance = invocation.path as GuidancePath; }
        return own({ ...fields(kind, output), transport: invocation.transport, port: invocation.port,
          recognized_operation: kind === "local_operation_schema", catalog: kind === "local_query_catalog" ? "query" : kind === "local_operation_schema" ? "operation" : null,
          operation, guidance, missing_dates: guidance === "export" || guidance === "extract" ? !invocation.datePresent : null,
          missing_mode: guidance === "export" ? !invocation.modePresent : null, missing_scope: guidance === "extract" ? !invocation.scopePresent : null });
      });
    },
    encode(value: unknown): Result.Result<string, FixedFailure> {
      // WeakSet checks never invoke Proxy/property/coercion hooks, including revoked Proxies.
      if (value === null || typeof value !== "object" || !decisions.has(value)) return Result.fail(ownedFailure);
      return Result.succeed(JSON.stringify(value) + "\n");
    },
  });
}
export const discoveryFactory: DiscoveryFactory = Object.freeze({ create: createDiscovery });
