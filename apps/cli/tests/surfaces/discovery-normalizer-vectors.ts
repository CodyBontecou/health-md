// Stage1 frozen literal/interface proposal. No candidate implementation or executable test.
// Public Rust/clap/serde/render authority remains separate. These are private normalized decision bytes.
// Parser fakes are explicit source-derived stimuli, not a completed TypeScript/clap parity proof.
import type * as Effect from "effect/Effect";
import type * as Result from "effect/Result";
declare const parsedBrand: unique symbol;
declare const decisionBrand: unique symbol;
export interface OwnedParsed { readonly [parsedBrand]: true; }
export interface OwnedDecision extends DecisionFields { readonly [decisionBrand]: true; }
export interface FixedFailure { readonly code: "private_discovery_input" | "private_discovery_parser" | "private_discovery_owned"; }
export type QueryOperation = typeof discoveryCatalog.queries[number]["name"];
export type GuidancePath = "query" | "export" | "extract" | "resume" | "cancel" | "direct" | "direct unpair" | "direct reset-trust" | "mcp" | "setup";
export type ParserErrorKind = "invalid_value" | "unknown_argument" | "invalid_subcommand" | "missing_equals" | "value_validation" | "too_many_values" | "too_few_values" | "wrong_number_of_values" | "argument_conflict" | "missing_required_argument" | "missing_subcommand" | "display_help" | "display_help_on_missing" | "display_version" | "io" | "format" | "unknown";
export type DecisionKind = "local_query_catalog" | "local_operation_schema" | "local_guidance" | "deferred_command" | "retained_text" | "parser_failure" | "private_input_failure" | "parser_contract_failure";
export interface DecisionFields {
 readonly kind: DecisionKind; readonly exit: 0 | 2 | null; readonly output: "json" | "human";
 readonly transport: "manual-ip" | "nearby" | null; readonly port: number | null;
 readonly recognized_operation: boolean; readonly request_sent: false; readonly authority_granted: false;
 readonly catalog: "query" | "operation" | null; readonly operation: QueryOperation | null; readonly guidance: GuidancePath | null; readonly text_reference: "welcome" | "help" | "version" | null;
 readonly missing_dates: boolean | null; readonly missing_mode: boolean | null; readonly missing_scope: boolean | null;
 readonly error: "invalid_request" | "private_discovery_input" | "private_discovery_parser" | null;
 readonly error_kind: ParserErrorKind | null;
}
export interface DiscoveryIssuer {
  // primitive closed tuple JSON only; null on malformed/nonprimitive/out-of-bounds fields.
  // Captured trusted parser may issue values; caller cannot provide an issuer to normalize.
  issue(fieldsWire: unknown): OwnedParsed | null;
}
export interface TrustedParser {
  // Must be local/pure: no credentials/network/store/native/acquisition/rendering.
  // argv is a new frozen private snapshot; no caller object properties inspected.
  parse(argv: readonly string[], issuer: DiscoveryIssuer): unknown;
}
export interface PrivateDiscovery {
  normalize(argvJson: unknown, tty: unknown): Effect.Effect<OwnedDecision, never>;
  // WeakSet membership before ANY properties/coercion; same instance only, fixed error otherwise.
  encode(value: unknown): Result.Result<string, FixedFailure>;
}
export interface DiscoveryFactory {
  // Trusted initialization only: parser and reviewed static catalog are host capabilities,
  // not caller JSON/grants. Static catalog host must bind exact source mirror raw hash.
  create(parser: TrustedParser, reviewedCatalog: typeof discoveryCatalog): PrivateDiscovery;
}

export const discoveryCatalog = {
  "mirror_path": "apps/cli/crates/healthmd-mcp/assets/mcp-tools-v1.json",
  "mirror_raw_sha256": "31377cf8ac0494d8410a2bd9cf69be0c65d1f0394517730e960f0f9a9016f52d",
  "full": [
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
  ],
  "read_only": [
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
  ],
  "queries": [
    {
      "name": "healthmd_metric_chart",
      "title": "Chart a health metric",
      "description": "Preferred operation for factual metric-series questions. Supply dates and canonical metrics; results retain units, coverage, missingness, evidence, and limitations.",
      "kind": "Query"
    },
    {
      "name": "healthmd_sleep_sessions",
      "title": "List sleep sessions",
      "description": "Preferred operation for sleep questions. Canonical sleep metrics and lossless session detail are supplied automatically. Supports an optional fixed session-relative physiology window.",
      "kind": "Query"
    },
    {
      "name": "healthmd_training_alignment",
      "title": "Align workouts and sleep",
      "description": "Align workouts with nearest preceding and following sleep sessions using factual timing only.",
      "kind": "Query"
    },
    {
      "name": "healthmd_workouts",
      "title": "List workouts",
      "description": "List factual workout sessions for an explicit or all-available date selection.",
      "kind": "Query"
    },
    {
      "name": "healthmd_coverage",
      "title": "Inspect health data coverage",
      "description": "Inspect factual metric/date coverage and explicit missingness.",
      "kind": "Query"
    },
    {
      "name": "healthmd_compare_periods",
      "title": "Compare health periods",
      "description": "Compare two exact periods using explicit per-metric aggregation semantics.",
      "kind": "Query"
    },
    {
      "name": "healthmd_training_evidence",
      "title": "Build training evidence",
      "description": "Create a factual training evidence packet with selected workout details.",
      "kind": "Query"
    },
    {
      "name": "healthmd_query",
      "title": "Run a typed health query",
      "description": "Advanced fallback for a complete healthmd.query_request/1 when no typed operation matches.",
      "kind": "Query"
    },
    {
      "name": "healthmd_evidence_packet",
      "title": "Build a health evidence packet",
      "description": "Advanced fallback for a directly scoped factual evidence packet.",
      "kind": "Query"
    }
  ],
  "normal_commands": [
    "status",
    "export",
    "extract",
    "query",
    "resume",
    "cancel",
    "direct pair",
    "direct devices",
    "direct unpair",
    "direct reset-trust",
    "mcp serve",
    "mcp serve-read-only",
    "mcp schema",
    "setup codex"
  ],
  "feature_commands": [
    "mcp serve-http"
  ],
  "groups": [
    "direct",
    "mcp",
    "setup"
  ],
  "donor40": "separate split-usage-desktop obligations, not these21/13 operations"
} as const;

export const discoveryContract = {
  "interface_version": "private-discovery-v1",
  "entry": "normalize(primitive argvJson, primitive boolean tty)",
  "argv_wire": "JSON array of strings only; ordinary JSON whitespace and escapes accepted; no objects/numbers/booleans/null/nesting; reject malformedUTF16/lone surrogate/U+0000; no coercion",
  "budgets": {
    "wire_utf8_bytes": 4096,
    "argv_count": 64,
    "token_utf8_bytes": 1024,
    "decoded_aggregate_utf8_bytes": 4096,
    "depth": 1,
    "nodes": 65
  },
  "budgets_status": "new private unmeasured deterministic admission bounds; not public CLI grammar/restrictions",
  "parsed_wire": {
    "invocation": [
      "invocation",
      "closed command path",
      "manual-ip|nearby",
      "canonical raw integer0..65535",
      "forceJson boolean",
      "forceHuman boolean",
      "operation string|null <=1024UTF8",
      "arguments_present boolean",
      "identifier_present boolean",
      "date_present boolean",
      "mode_present boolean",
      "scope_present boolean",
      "confirm boolean"
    ],
    "failure": [
      "failure",
      "closed command path including emptyroot",
      "closed error_kind from guidance.rs",
      "forceJson boolean",
      "forceHuman boolean"
    ],
    "text": [
      "text",
      "welcome|help|version",
      "forceJson boolean",
      "forceHuman boolean"
    ],
    "command_paths": [
      "status",
      "export",
      "extract",
      "query",
      "resume",
      "cancel",
      "direct pair",
      "direct devices",
      "direct unpair",
      "direct reset-trust",
      "mcp serve",
      "mcp serve-read-only",
      "mcp schema",
      "setup codex",
      "mcp serve-http",
      "direct",
      "mcp",
      "setup"
    ],
    "feature_profile": "trusted parser owns compilefeature availability; gate recognizes descriptor serve-http as deferred only, never claims enabled",
    "error_kinds": [
      "invalid_value",
      "unknown_argument",
      "invalid_subcommand",
      "missing_equals",
      "value_validation",
      "too_many_values",
      "too_few_values",
      "wrong_number_of_values",
      "argument_conflict",
      "missing_required_argument",
      "missing_subcommand",
      "display_help",
      "display_help_on_missing",
      "display_version",
      "io",
      "format",
      "unknown"
    ],
    "max_utf8_bytes": 4096,
    "duplicate_fields": "tuples avoid duplicate object keys; exact tuplelength required",
    "integer_policy": "new private issuer canonicalinteger0|[1-9][0-9]* before Number; port u16; this does not restrict actual clap accepted option lexemes"
  },
  "ownership": "per factory issuer parsedWeakSet and decisionWeakSet; foreign/proxy/rawrecord fails membership BEFORE property reads; malformed input no parser callback; parse callback cause discarded; encode foreign/proxy no traps and no callbacks",
  "catalog_binding": "host-owned static reviewed exact mirror raw bytes and21ordered declarations; runtime schema equality not authentication; callerargv/toolname/tty/catalogmetadata grants none",
  "trusted_descriptor_constraints": "invocation transportclosed/u16 canonical; exactbool flags; forceJson/forceHuman cannotbothtrue on successful invocation; operation onlyquery, othersnull; source grammar/parser supplies allpresence flags; no grant claim; textreference preserved fornext renderer; fixed commandpath error enums not arbitrary strings",
  "harness_protocol": {
    "inputs": "argv_json passed exactly as primitive; tty boolean; input_stimulus replaces argv except tty_proxy uses primitive [query] and replaces tty; proxy/object hooks increment traps/coercion then throw if touched",
    "repeat_wire": "repeat unit/count into primitive wire, not array",
    "argv_repeat": "JSON array count repeated tokenstrings",
    "token_repeat": "JSON single token unit repeated count",
    "literal": "pass wire exactly",
    "array": "pass JS array [query] asnonprimitive",
    "proxy": "pass Proxy object with all traps counted; do not inspect before normalize",
    "object_with_coercion": "pass object with toPrimitive/toString/valueOf counters",
    "parser_issue": "captured fake returns issuer.issue(exact wire); null => fixed contractfailure; records/factoryforeign/proxy rejected before properties; throwprivateprovider => fixed no cause",
    "effects": "fake parser callbackcount plus forbidden I/O fake spies; normalizer never has network/credential/mutation/source/acquire capability; stdout writecountzero because returns primitive privatebytes, never writes",
    "encode": "every successful owneddecision encoded by samefactory and comparedexactexpectedUTF8; foreignclone/proxy/otherfactory encode yields fixed private_discovery_owned withzero traps/callbacks"
  },
  "selection_order": "parse source failure first; then local incomplete source route before platform validation; known Query kind only =>schema; unknown/nonquery noarguments =>catalog; complete request =>deferred no execution; parser text =>retained_text no public bytes generated",
  "error_and_output": "private normalized JSON fixed key order as literalvectors plus LF; no publicguidance/error envelope/human byte parity; source output resolve(forceJson,forceHuman,tty), jsonwins on parserconflict; invalid private input always fixedjson; no unknownoperation/argument/provider value in emitteddecision",
  "catalog_references": "query =>source9queryrows; operation =>exact knownname/full pinnedmirror schema pointer; guidance =>fixed source command reference; no cloning health data/schema rewriting",
  "cancellation": "no resource acquisition or asynchronous parser/finalizer in this gate; Effect interruption preserved, no cancellation convertedto success; Scope/ACK obligations deferred to actual acquisition/transport children",
  "remaining": {
    "full_parser": {
      "owner": "core_cli coordinator",
      "next_packet": "SPLIT-CLI-PARSER-GRAMMAR",
      "trigger": "before any TypeScript parser production replacement or public command grammar parity claim",
      "proof": "full clap token/default/alias/UUID/u16/u64/date/selection/feature/help/version source-derived vectors, explicit OsString/nonUnicode profile, exact parser/error contracts; not completed by sourcefake descriptors"
    },
    "rendering": {
      "owner": "CLI-RESULT-ENVELOPE",
      "trigger": "before exact public stdout/error/schema/human/color/TTY byte parity",
      "proof": "full source documents/serializer/renderer/environment profiles independently frozen"
    },
    "query_export_execution": {
      "owner": "full_common_operations remaining SPLIT-SURFACES scope",
      "trigger": "before executing deferred route",
      "proof": "common OP-CATALOG/query/export owner; complete evaluator/state/source authorization separate"
    },
    "core_cohort": {
      "owner": "root separately reviewed core cohort refresh",
      "trigger": "before CLI build/install/check on changed core",
      "proof": "immutable40/24 predecessor retained; no self-update/guard relaxation"
    }
  }
} as const;

export const discoveryGrammarReconciliation = {
  "source_main": "main.rs70..545,599..630,663..668,841..890",
  "global": [
    "--transport default manual-ip; value manual-ip|nearby",
    "--device UUID",
    "--port u16 default17647",
    "--json/--human conflict; global placement clap authority"
  ],
  "dates": [
    "--yesterday conflicts last/from/to/all",
    "--last u32",
    "--from and --to require each other, conflict yesterday/last/all",
    "--all conflicts yesterday/last/from/to",
    "date_present checks any date flag, calendar/range validity delegated execution"
  ],
  "selection": [
    "repeat --metric/--category/--object/--field/--source preserve order/duplicates",
    "--all-metrics conflicts metrics/categories, not objects",
    "detail summary|lossless defaultsummary",
    "extract scope only metrics/categories/objects/all_metrics; field/source alone insufficient"
  ],
  "aliases": [
    "export --use-device-settings visible alias --use-iphone-settings, not extract",
    "objects: sleep, activity, heart, vitals, body, nutrition, mindfulness, mobility, hearing, reproductive-health, cycling, vitamins, minerals, symptoms, medications, other, workouts, archive, records, external-records, query-results, warnings"
  ],
  "defaults": {
    "port": 17647,
    "transport": "manual-ip",
    "export_timeout": 300,
    "extract_timeout": 300,
    "query_timeout": 1200,
    "wake_timeout": 120,
    "pair_timeout": 120,
    "setup_pairing_timeout": 180,
    "mcp_timeout_seconds": 1200,
    "provider": "health_connect",
    "raw_format": "ndjson",
    "extract_format": "json",
    "detail": "summary"
  },
  "parser_semantics": "full clap remains authority: option equals/placement/terminator/duplicate/abbreviations/numeric lexemes/help/version/OsString are not reconstructed by this gate. descriptor flags source parser owns, cannot supplied by operation caller."
} as const;

export const discoverySourcePins = [
  {
    "path": "AGENTS.md",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 6129,
    "sha256": "563ac20e38bf5e62d636f5e3a4f15e1f8a0b4d96c67d8150de0badcf89bef456",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "GLOSSARY.md",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 3868,
    "sha256": "c128162016990d3f2dca7233808e36867ce683019828acb803acace9736d6a65",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "docs/architecture/javascript-unified-layer-research.md",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 13361,
    "sha256": "feac64a79a2a9967cabd07f4155ed1b5eaa1f05fae2aa6ea37d468eddf87bba3",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "docs/architecture/javascript-unified-layer-design-reference.md",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 284562,
    "sha256": "2c3acaf2df187e1a78516eddfb3d82958092b71894b669aabfc7c86d569039bd",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "docs/migration/effect-refactor/core-cli.md",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 5578,
    "sha256": "4b33f46482c9c3fe26b50badc07a0a604e5c97345cb7f5eb6526580ced249749",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "docs/migration/effect-refactor/templates.md",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 10054,
    "sha256": "53c198716d79bae941c55caa634712c9fdc60a451da6f8c58847a110a8ec077e",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "docs/migration/effect-refactor/inventories/cli.json",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 347600,
    "sha256": "d013adcb657d2b190a75506ddef1adc85a3181c4eb3cf5180a8834789961fbe3",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "docs/migration/effect-refactor/inventories/core.json",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 95633,
    "sha256": "56536fc5f207a1f8508542ca98fd7d01cff3b882db002a3df8521bdb59d39ac7",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "docs/migration/effect-refactor/receipts/BASE-CLI.json",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 12304,
    "sha256": "be25457e7c1672dfacc706702a47c762e3bb9781ecb978391412195247d824f1",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "docs/migration/effect-refactor/receipts/BASE-CORE.json",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 26431,
    "sha256": "839b110fc881fdbf73d2bb9f06b6bab3f35c74eaf0f7c6f3d8d63d8b42c19c9a",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "docs/migration/effect-refactor/expansions/split-protocol.json",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 145883,
    "sha256": "a0bbbf6ed6db434c957488fa37cb8ef9c92f3ac6334c0a63736c935034439c67",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "docs/migration/effect-refactor/receipts/SPLIT-PROTOCOL.json",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 33855,
    "sha256": "6ba1dbaed77ed7a024f94ed7b008b6c0001b1cabf7e493d66dfa7cb298f8620d",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "docs/migration/effect-refactor/receipts/SLICE-PARITY.json",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 27886,
    "sha256": "c8f395b086606b685c3f539d105a74036a4f42608534a1eb80d11c2ecf67a4f4",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "docs/migration/effect-refactor/cohorts/core-ts-personal-slices-v1.json",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 34945,
    "sha256": "1dbee84851fb08b26a66d436014496f097fc94fafeeef880846897ca13ba4853",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "docs/migration/effect-refactor/receipts/CORE-COHORT-PERSONAL-SLICES.json",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 124059,
    "sha256": "faaa45e7d1d19a2cd4b69eec7f05d29bd332a4beacc1fcff36111259a462c602",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "docs/migration/effect-refactor/expansions/split-usage-desktop.json",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 139864,
    "sha256": "8aeedc538783d9e0373adec386f0bd9f1ce7a92c8a368c3d6ab2711e7ce2097f",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "packages/healthmd-core-ts/AGENTS.md",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 860,
    "sha256": "14b3f153a9eb9d2087992b7fa90b722fc8538845f1e33c0dfdf55de32c3fca67",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "apps/cli/docs/typescript-candidate.md",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 7580,
    "sha256": "1b7898390cf04c276a285b60fee5c09215640ca95618b94c9abb73f756c3490b",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "apps/cli/package.json",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 880,
    "sha256": "baa07d8b88444ac74a7de411384e5ee84133a90f91fa255bf07c3fc0d61c9fd2",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "apps/cli/package-lock.json",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 28291,
    "sha256": "3be9fb54116c58d89421e7bd43d2f5c5bb4b0f98f818a0ef3ba18c77f4903cbf",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "apps/cli/scripts/build-candidate.mjs",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 1574,
    "sha256": "0f4bd85e16b9462d265a370ec132c27b9655c21e22e634c68545e5e4ee70bcfa",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "apps/cli/scripts/check-candidate.mjs",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 35746,
    "sha256": "aca2e32e0047fc397c9bde572f3464b17a4482589d6a1a986a6b0bda3efd8de3",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "apps/cli/tsconfig.build.json",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 144,
    "sha256": "2f9f05c0822a03a2e63d07171e58988d39c55be6582c562f36e5b85690d1e42b",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "apps/cli/tsconfig.test.json",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 123,
    "sha256": "db9dfadaa7870e3134056444efbe00eaf427c8ee0ed43f6369cbcfd61c39b4c0",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "apps/cli/crates/healthmd-cli/src/main.rs",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 110543,
    "sha256": "7f6be243c49085ea188adf739b829d968d8330b196a7e2317a043d4a8e2ddf32",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "apps/cli/crates/healthmd-cli/src/guidance.rs",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 42824,
    "sha256": "f71d47555df981fbbc27f70bec6746a40846b6287f3f1200f2d9a6aac95456e0",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "apps/cli/crates/healthmd-cli/src/mcp/mod.rs",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 27301,
    "sha256": "2d727be8830adfe639faa536b875b0f0ac91690de7872d233577b0fccead6fa0",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "apps/cli/crates/healthmd-mcp/src/jsonrpc.rs",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 17008,
    "sha256": "b7082b9dc860f5b20509ae0517bb76db2f6cb29d06525e463ac4342b081284ae",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "apps/cli/crates/healthmd-cli/src/output.rs",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 29781,
    "sha256": "7ffedba6a33ee4111a993c5b6091da1b309d6e3ccc02d7a3ed64374b42e62afb",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "apps/cli/crates/healthmd-cli/src/onboarding.rs",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 17363,
    "sha256": "ea1cc76fdb08f44bfba6f482e079cd121ffe6c2a49636470f919aa7bd51c7eba",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "apps/cli/crates/healthmd-mcp/src/result.rs",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 2531,
    "sha256": "2d56e254c0af85537eca102adebaf1140fc9c77ceea0b9f1a881800f73b1d28f",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "apps/cli/crates/healthmd-operations/src/registry.rs",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 52174,
    "sha256": "0d16820bf891bd5ac71741f7ac955887c3be289201a01893100f1886f3a2a827",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "apps/cli/crates/healthmd-mcp/src/application.rs",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 58209,
    "sha256": "989bfd02c8c243237628343cf4500a07cce3731facb00565735ef35863657d8a",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "apps/cli/crates/healthmd-operations/src/model.rs",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 1129,
    "sha256": "a60a1163ab5861ce062d010045e2e6bad8f1c6fccbea2094ead3f0c0980850ad",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "apps/cli/src/cli/query.ts",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 7155,
    "sha256": "a7b83690886d6d643ce5a72f98514739eadb6a34178148ad6111c7caf50d98a2",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "apps/cli/src/mcp/query.ts",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 6487,
    "sha256": "97ba3ed0c2a0c60872ce3a6eda757e8ecc08f9391848a74bb06c2be7ea2b50b9",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "packages/healthmd-core-ts/src/operations/normalize.ts",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 2808,
    "sha256": "bfa2b22abba44e22bbfc60d50dac8df5654acf3f296b49b59ed812d8cd11fa45",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "packages/healthmd-core-ts/src/operations/query.ts",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 8929,
    "sha256": "143c5a9c123a1febe0ac67b6fd46eefb578e669f8263aec11e2b553544add100",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "apps/cli/crates/healthmd-mcp/assets/mcp-tools-v1.json",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 116261,
    "sha256": "31377cf8ac0494d8410a2bd9cf69be0c65d1f0394517730e960f0f9a9016f52d",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "apps/cli/tests/cli-query-vectors.ts",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 4412,
    "sha256": "315098960cd4b7afdccd9c8d19a9f330495e33940f5954f4ea3026921b1f3bd2",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "apps/cli/tests/mcp-query-vectors.ts",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 3586,
    "sha256": "4fddfa0b53eba0402bde2239b995bde2ea1e019f7f1076041b8dcc963df6b154",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "apps/cli/tests/candidate-api-vectors.ts",
    "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
    "bytes": 3176,
    "sha256": "e866e706c0cb71c4d782f5c9bcc9e12059f86897e7974cce60844c2c0a3f0cc6",
    "assigned_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "assigned_git_current_equal": true
  },
  {
    "path": "docs/migration/effect-refactor/receipts/OP-CATALOG.json",
    "source_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "bytes": 17512,
    "sha256": "a3ce7294241c2bd32051d0a296977e73eda01197b40a04666dee35edb9e6f758",
    "assigned_git_current_equal": true
  },
  {
    "path": "packages/healthmd-core-ts/src/operations/catalog.ts",
    "source_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "bytes": 5539,
    "sha256": "eee557683d518595545797ed228e6e56e6659ea0d2325270059c1a13d89a0db7",
    "assigned_git_current_equal": true
  },
  {
    "path": "packages/healthmd-core-ts/tests/catalog.test.ts",
    "source_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "bytes": 6926,
    "sha256": "a3751d2bc08ab1b855db9b7ab318430cf927d5b00f7104124448f820168e1b27",
    "assigned_git_current_equal": true
  },
  {
    "path": "packages/healthmd-core-ts/README.md",
    "source_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "bytes": 2988,
    "sha256": "e8c4f43bbd82db28f995d342589c66de8a3d1f5443d173d81ee3b40df5d1e606",
    "assigned_git_current_equal": true
  },
  {
    "path": "apps/cli/tsconfig.json",
    "source_revision": "aa563e6de291e7da746268e4fddef4296d70e35d",
    "bytes": 342,
    "sha256": "ad34c0e91c3a575d3278af944148bdccc83ef90413050250d7ca629431c20c6c",
    "assigned_git_current_equal": true
  }
] as const;

export const discoveryVectors = [
  {
    "id": "discovery-query-no-operation",
    "argv_json": "[\"query\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"query\",\"manual-ip\",17647,false,false,null,false,false,false,false,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"local_query_catalog\",\"exit\":0,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":\"query\",\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "discovery-query-synopsis-no-arguments",
    "argv_json": "[\"query\",\"healthmd_sleep_sessions\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"query\",\"manual-ip\",17647,false,false,\"healthmd_sleep_sessions\",false,false,false,false,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"local_operation_schema\",\"exit\":0,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":true,\"request_sent\":false,\"authority_granted\":false,\"catalog\":\"operation\",\"operation\":\"healthmd_sleep_sessions\",\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "discovery-reset-trust-incomplete",
    "argv_json": "[\"direct\",\"reset-trust\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"direct reset-trust\",\"manual-ip\",17647,false,false,null,false,false,false,false,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"local_guidance\",\"exit\":0,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":\"direct reset-trust\",\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "discovery-json-human-conflict",
    "argv_json": "[\"status\",\"--json\",\"--human\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"failure\",\"status\",\"argument_conflict\",true,true]"
    },
    "expected_decision_utf8": "{\"kind\":\"parser_failure\",\"exit\":2,\"output\":\"json\",\"transport\":null,\"port\":null,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":\"invalid_request\",\"error_kind\":\"argument_conflict\"}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "discovery-fixed-defaults",
    "argv_json": "[\"status\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"status\",\"manual-ip\",17647,false,false,null,false,false,false,false,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"deferred_command\",\"exit\":null,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "discovery-unknown-operation-not-echoed",
    "argv_json": "[\"query\",\"SYNTHETIC_SECRET_UNKNOWN\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"query\",\"manual-ip\",17647,false,false,\"SYNTHETIC_SECRET_UNKNOWN\",false,false,false,false,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"local_query_catalog\",\"exit\":0,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":\"query\",\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "query-schema-healthmd_metric_chart",
    "argv_json": "[\"query\",\"healthmd_metric_chart\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"query\",\"manual-ip\",17647,false,false,\"healthmd_metric_chart\",false,false,false,false,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"local_operation_schema\",\"exit\":0,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":true,\"request_sent\":false,\"authority_granted\":false,\"catalog\":\"operation\",\"operation\":\"healthmd_metric_chart\",\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "query-schema-healthmd_training_alignment",
    "argv_json": "[\"query\",\"healthmd_training_alignment\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"query\",\"manual-ip\",17647,false,false,\"healthmd_training_alignment\",false,false,false,false,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"local_operation_schema\",\"exit\":0,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":true,\"request_sent\":false,\"authority_granted\":false,\"catalog\":\"operation\",\"operation\":\"healthmd_training_alignment\",\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "query-schema-healthmd_workouts",
    "argv_json": "[\"query\",\"healthmd_workouts\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"query\",\"manual-ip\",17647,false,false,\"healthmd_workouts\",false,false,false,false,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"local_operation_schema\",\"exit\":0,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":true,\"request_sent\":false,\"authority_granted\":false,\"catalog\":\"operation\",\"operation\":\"healthmd_workouts\",\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "query-schema-healthmd_coverage",
    "argv_json": "[\"query\",\"healthmd_coverage\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"query\",\"manual-ip\",17647,false,false,\"healthmd_coverage\",false,false,false,false,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"local_operation_schema\",\"exit\":0,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":true,\"request_sent\":false,\"authority_granted\":false,\"catalog\":\"operation\",\"operation\":\"healthmd_coverage\",\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "query-schema-healthmd_compare_periods",
    "argv_json": "[\"query\",\"healthmd_compare_periods\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"query\",\"manual-ip\",17647,false,false,\"healthmd_compare_periods\",false,false,false,false,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"local_operation_schema\",\"exit\":0,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":true,\"request_sent\":false,\"authority_granted\":false,\"catalog\":\"operation\",\"operation\":\"healthmd_compare_periods\",\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "query-schema-healthmd_training_evidence",
    "argv_json": "[\"query\",\"healthmd_training_evidence\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"query\",\"manual-ip\",17647,false,false,\"healthmd_training_evidence\",false,false,false,false,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"local_operation_schema\",\"exit\":0,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":true,\"request_sent\":false,\"authority_granted\":false,\"catalog\":\"operation\",\"operation\":\"healthmd_training_evidence\",\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "query-schema-healthmd_query",
    "argv_json": "[\"query\",\"healthmd_query\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"query\",\"manual-ip\",17647,false,false,\"healthmd_query\",false,false,false,false,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"local_operation_schema\",\"exit\":0,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":true,\"request_sent\":false,\"authority_granted\":false,\"catalog\":\"operation\",\"operation\":\"healthmd_query\",\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "query-schema-healthmd_evidence_packet",
    "argv_json": "[\"query\",\"healthmd_evidence_packet\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"query\",\"manual-ip\",17647,false,false,\"healthmd_evidence_packet\",false,false,false,false,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"local_operation_schema\",\"exit\":0,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":true,\"request_sent\":false,\"authority_granted\":false,\"catalog\":\"operation\",\"operation\":\"healthmd_evidence_packet\",\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "query-nonquery-operation-is-catalog",
    "argv_json": "[\"query\",\"healthmd_status\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"query\",\"manual-ip\",17647,false,false,\"healthmd_status\",false,false,false,false,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"local_query_catalog\",\"exit\":0,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":\"query\",\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "query-unknown-with-arguments-deferred",
    "argv_json": "[\"query\",\"SYNTHETIC_SECRET_UNKNOWN\",\"--arguments\",\"{}\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"query\",\"manual-ip\",17647,false,false,\"SYNTHETIC_SECRET_UNKNOWN\",true,false,false,false,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"deferred_command\",\"exit\":null,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "query-no-operation-with-arguments-is-catalog",
    "argv_json": "[\"query\",\"--arguments\",\"{}\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"query\",\"manual-ip\",17647,false,false,null,true,false,false,false,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"local_query_catalog\",\"exit\":0,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":\"query\",\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "query-nearby-before-platform-validation",
    "argv_json": "[\"--transport\",\"nearby\",\"query\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"query\",\"nearby\",17647,false,false,null,false,false,false,false,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"local_query_catalog\",\"exit\":0,\"output\":\"json\",\"transport\":\"nearby\",\"port\":17647,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":\"query\",\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "query-terminal-human",
    "argv_json": "[\"query\"]",
    "tty": true,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"query\",\"manual-ip\",17647,false,false,null,false,false,false,false,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"local_query_catalog\",\"exit\":0,\"output\":\"human\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":\"query\",\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "query-forced-json-terminal",
    "argv_json": "[\"query\",\"--json\"]",
    "tty": true,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"query\",\"manual-ip\",17647,true,false,null,false,false,false,false,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"local_query_catalog\",\"exit\":0,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":\"query\",\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "query-forced-human-pipe",
    "argv_json": "[\"query\",\"--human\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"query\",\"manual-ip\",17647,false,true,null,false,false,false,false,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"local_query_catalog\",\"exit\":0,\"output\":\"human\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":\"query\",\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "incomplete-direct",
    "argv_json": "[\"direct\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"direct\",\"manual-ip\",17647,false,false,null,false,false,false,false,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"local_guidance\",\"exit\":0,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":\"direct\",\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "incomplete-mcp",
    "argv_json": "[\"mcp\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"mcp\",\"manual-ip\",17647,false,false,null,false,false,false,false,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"local_guidance\",\"exit\":0,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":\"mcp\",\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "incomplete-setup",
    "argv_json": "[\"setup\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"setup\",\"manual-ip\",17647,false,false,null,false,false,false,false,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"local_guidance\",\"exit\":0,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":\"setup\",\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "incomplete-resume",
    "argv_json": "[\"resume\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"resume\",\"manual-ip\",17647,false,false,null,false,false,false,false,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"local_guidance\",\"exit\":0,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":\"resume\",\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "incomplete-cancel",
    "argv_json": "[\"cancel\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"cancel\",\"manual-ip\",17647,false,false,null,false,false,false,false,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"local_guidance\",\"exit\":0,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":\"cancel\",\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "incomplete-direct-unpair",
    "argv_json": "[\"direct\",\"unpair\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"direct unpair\",\"manual-ip\",17647,false,false,null,false,false,false,false,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"local_guidance\",\"exit\":0,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":\"direct unpair\",\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "incomplete-export",
    "argv_json": "[\"export\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"export\",\"manual-ip\",17647,false,false,null,false,false,false,false,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"local_guidance\",\"exit\":0,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":\"export\",\"text_reference\":null,\"missing_dates\":true,\"missing_mode\":true,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "incomplete-extract",
    "argv_json": "[\"extract\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"extract\",\"manual-ip\",17647,false,false,null,false,false,false,false,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"local_guidance\",\"exit\":0,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":\"extract\",\"text_reference\":null,\"missing_dates\":true,\"missing_mode\":null,\"missing_scope\":true,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "export-dates-no-mode",
    "argv_json": "[\"export\",\"--all\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"export\",\"manual-ip\",17647,false,false,null,false,false,true,false,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"local_guidance\",\"exit\":0,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":\"export\",\"text_reference\":null,\"missing_dates\":false,\"missing_mode\":true,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "export-mode-no-dates",
    "argv_json": "[\"export\",\"--raw\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"export\",\"manual-ip\",17647,false,false,null,false,false,false,true,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"local_guidance\",\"exit\":0,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":\"export\",\"text_reference\":null,\"missing_dates\":true,\"missing_mode\":false,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "extract-date-no-scope",
    "argv_json": "[\"extract\",\"--yesterday\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"extract\",\"manual-ip\",17647,false,false,null,false,false,true,false,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"local_guidance\",\"exit\":0,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":\"extract\",\"text_reference\":null,\"missing_dates\":false,\"missing_mode\":null,\"missing_scope\":true,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "extract-scope-no-date",
    "argv_json": "[\"extract\",\"--object\",\"sleep\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"extract\",\"manual-ip\",17647,false,false,null,false,false,false,false,true,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"local_guidance\",\"exit\":0,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":\"extract\",\"text_reference\":null,\"missing_dates\":true,\"missing_mode\":null,\"missing_scope\":false,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "export-complete-deferred",
    "argv_json": "[\"export\",\"--all\",\"--raw\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"export\",\"manual-ip\",17647,false,false,null,false,false,true,true,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"deferred_command\",\"exit\":null,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "extract-alias-complete-deferred",
    "argv_json": "[\"extract\",\"--last\",\"7\",\"--object\",\"sleep\",\"--use-iphone-settings\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"failure\",\"extract\",\"unknown_argument\",false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"parser_failure\",\"exit\":2,\"output\":\"json\",\"transport\":null,\"port\":null,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":\"invalid_request\",\"error_kind\":\"unknown_argument\"}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "export-device-settings-alias-deferred",
    "argv_json": "[\"export\",\"--all\",\"--destination\",\"SYNTHETIC_DIR\",\"--use-iphone-settings\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"export\",\"manual-ip\",17647,false,false,null,false,false,true,true,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"deferred_command\",\"exit\":null,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "reset-confirm-deferred",
    "argv_json": "[\"direct\",\"reset-trust\",\"--confirm\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"direct reset-trust\",\"manual-ip\",17647,false,false,null,false,false,false,false,false,true]"
    },
    "expected_decision_utf8": "{\"kind\":\"deferred_command\",\"exit\":null,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "mcp-schema-deferred-local-owner",
    "argv_json": "[\"mcp\",\"schema\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"mcp schema\",\"manual-ip\",17647,false,false,null,false,false,false,false,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"deferred_command\",\"exit\":null,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "unknown-argument-no-echo",
    "argv_json": "[\"query\",\"--SYNTHETIC_SECRET_FLAG\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"failure\",\"query\",\"unknown_argument\",false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"parser_failure\",\"exit\":2,\"output\":\"json\",\"transport\":null,\"port\":null,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":\"invalid_request\",\"error_kind\":\"unknown_argument\"}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "status-port-zero-deferred",
    "argv_json": "[\"status\",\"--port\",\"0\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"status\",\"manual-ip\",0,false,false,null,false,false,false,false,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"deferred_command\",\"exit\":null,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":0,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "status-port-max-deferred",
    "argv_json": "[\"status\",\"--port\",\"65535\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"status\",\"manual-ip\",65535,false,false,null,false,false,false,false,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"deferred_command\",\"exit\":null,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":65535,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "retained-text-welcome",
    "argv_json": "[]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"text\",\"welcome\",false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"retained_text\",\"exit\":0,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":null,\"text_reference\":\"welcome\",\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "retained-text-help",
    "argv_json": "[\"--help\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"text\",\"help\",false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"retained_text\",\"exit\":0,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":null,\"text_reference\":\"help\",\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "retained-text-version",
    "argv_json": "[\"--version\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"text\",\"version\",false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"retained_text\",\"exit\":0,\"output\":\"json\",\"transport\":\"manual-ip\",\"port\":17647,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":null,\"text_reference\":\"version\",\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":null,\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "retained source semantics; private decision bytes only, no public rendered stdout parity"
  },
  {
    "id": "private-nonprimitive-proxy",
    "input_stimulus": {
      "kind": "proxy"
    },
    "tty": false,
    "parser_stimulus": {
      "behavior": "must_not_call"
    },
    "expected_decision_utf8": "{\"kind\":\"private_input_failure\",\"exit\":2,\"output\":\"json\",\"transport\":null,\"port\":null,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":\"private_discovery_input\",\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 0,
      "proxy_traps": 0,
      "coercion_calls": 0,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "new private unmeasured gate budgets/grammar; NOT production CLI restrictions"
  },
  {
    "id": "private-nonprimitive-array",
    "input_stimulus": {
      "kind": "array"
    },
    "tty": false,
    "parser_stimulus": {
      "behavior": "must_not_call"
    },
    "expected_decision_utf8": "{\"kind\":\"private_input_failure\",\"exit\":2,\"output\":\"json\",\"transport\":null,\"port\":null,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":\"private_discovery_input\",\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 0,
      "proxy_traps": 0,
      "coercion_calls": 0,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "new private unmeasured gate budgets/grammar; NOT production CLI restrictions"
  },
  {
    "id": "private-nonprimitive-object-coercion",
    "input_stimulus": {
      "kind": "object_with_coercion"
    },
    "tty": false,
    "parser_stimulus": {
      "behavior": "must_not_call"
    },
    "expected_decision_utf8": "{\"kind\":\"private_input_failure\",\"exit\":2,\"output\":\"json\",\"transport\":null,\"port\":null,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":\"private_discovery_input\",\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 0,
      "proxy_traps": 0,
      "coercion_calls": 0,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "new private unmeasured gate budgets/grammar; NOT production CLI restrictions"
  },
  {
    "id": "private-invalid-tty-proxy",
    "input_stimulus": {
      "kind": "tty_proxy"
    },
    "tty": false,
    "parser_stimulus": {
      "behavior": "must_not_call"
    },
    "expected_decision_utf8": "{\"kind\":\"private_input_failure\",\"exit\":2,\"output\":\"json\",\"transport\":null,\"port\":null,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":\"private_discovery_input\",\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 0,
      "proxy_traps": 0,
      "coercion_calls": 0,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "new private unmeasured gate budgets/grammar; NOT production CLI restrictions"
  },
  {
    "id": "private-wire-over4096",
    "input_stimulus": {
      "kind": "repeat_wire",
      "unit": " ",
      "count": 4097
    },
    "tty": false,
    "parser_stimulus": {
      "behavior": "must_not_call"
    },
    "expected_decision_utf8": "{\"kind\":\"private_input_failure\",\"exit\":2,\"output\":\"json\",\"transport\":null,\"port\":null,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":\"private_discovery_input\",\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 0,
      "proxy_traps": 0,
      "coercion_calls": 0,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "new private unmeasured gate budgets/grammar; NOT production CLI restrictions"
  },
  {
    "id": "private-argv-over64",
    "input_stimulus": {
      "kind": "argv_repeat",
      "token": "q",
      "count": 65
    },
    "tty": false,
    "parser_stimulus": {
      "behavior": "must_not_call"
    },
    "expected_decision_utf8": "{\"kind\":\"private_input_failure\",\"exit\":2,\"output\":\"json\",\"transport\":null,\"port\":null,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":\"private_discovery_input\",\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 0,
      "proxy_traps": 0,
      "coercion_calls": 0,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "new private unmeasured gate budgets/grammar; NOT production CLI restrictions"
  },
  {
    "id": "private-token-over1024",
    "input_stimulus": {
      "kind": "token_repeat",
      "unit": "q",
      "count": 1025
    },
    "tty": false,
    "parser_stimulus": {
      "behavior": "must_not_call"
    },
    "expected_decision_utf8": "{\"kind\":\"private_input_failure\",\"exit\":2,\"output\":\"json\",\"transport\":null,\"port\":null,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":\"private_discovery_input\",\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 0,
      "proxy_traps": 0,
      "coercion_calls": 0,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "new private unmeasured gate budgets/grammar; NOT production CLI restrictions"
  },
  {
    "id": "private-malformed-json",
    "input_stimulus": {
      "kind": "literal",
      "wire": "[\"query\",]"
    },
    "tty": false,
    "parser_stimulus": {
      "behavior": "must_not_call"
    },
    "expected_decision_utf8": "{\"kind\":\"private_input_failure\",\"exit\":2,\"output\":\"json\",\"transport\":null,\"port\":null,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":\"private_discovery_input\",\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 0,
      "proxy_traps": 0,
      "coercion_calls": 0,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "new private unmeasured gate budgets/grammar; NOT production CLI restrictions"
  },
  {
    "id": "private-nested-json",
    "input_stimulus": {
      "kind": "literal",
      "wire": "[[\"query\"]]"
    },
    "tty": false,
    "parser_stimulus": {
      "behavior": "must_not_call"
    },
    "expected_decision_utf8": "{\"kind\":\"private_input_failure\",\"exit\":2,\"output\":\"json\",\"transport\":null,\"port\":null,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":\"private_discovery_input\",\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 0,
      "proxy_traps": 0,
      "coercion_calls": 0,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "new private unmeasured gate budgets/grammar; NOT production CLI restrictions"
  },
  {
    "id": "private-number-token",
    "input_stimulus": {
      "kind": "literal",
      "wire": "[1]"
    },
    "tty": false,
    "parser_stimulus": {
      "behavior": "must_not_call"
    },
    "expected_decision_utf8": "{\"kind\":\"private_input_failure\",\"exit\":2,\"output\":\"json\",\"transport\":null,\"port\":null,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":\"private_discovery_input\",\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 0,
      "proxy_traps": 0,
      "coercion_calls": 0,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "new private unmeasured gate budgets/grammar; NOT production CLI restrictions"
  },
  {
    "id": "private-lone-surrogate",
    "input_stimulus": {
      "kind": "literal",
      "wire": "[\"\\ud800\"]"
    },
    "tty": false,
    "parser_stimulus": {
      "behavior": "must_not_call"
    },
    "expected_decision_utf8": "{\"kind\":\"private_input_failure\",\"exit\":2,\"output\":\"json\",\"transport\":null,\"port\":null,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":\"private_discovery_input\",\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 0,
      "proxy_traps": 0,
      "coercion_calls": 0,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "new private unmeasured gate budgets/grammar; NOT production CLI restrictions"
  },
  {
    "id": "private-nul-token",
    "input_stimulus": {
      "kind": "literal",
      "wire": "[\"\\u0000\"]"
    },
    "tty": false,
    "parser_stimulus": {
      "behavior": "must_not_call"
    },
    "expected_decision_utf8": "{\"kind\":\"private_input_failure\",\"exit\":2,\"output\":\"json\",\"transport\":null,\"port\":null,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":\"private_discovery_input\",\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 0,
      "proxy_traps": 0,
      "coercion_calls": 0,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "new private unmeasured gate budgets/grammar; NOT production CLI restrictions"
  },
  {
    "id": "private-issuer-fractional-port",
    "argv_json": "[\"query\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"query\",\"manual-ip\",1.0000000000000001,false,false,null,false,false,false,false,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"parser_contract_failure\",\"exit\":2,\"output\":\"json\",\"transport\":null,\"port\":null,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":\"private_discovery_parser\",\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "proxy_traps": 0,
      "coercion_calls": 0,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "private raw canonical port integer before conversion; no public clap numeric grammar claim"
  },
  {
    "id": "private-issuer-underflow-port",
    "argv_json": "[\"query\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"query\",\"manual-ip\",1e-9999,false,false,null,false,false,false,false,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"parser_contract_failure\",\"exit\":2,\"output\":\"json\",\"transport\":null,\"port\":null,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":\"private_discovery_parser\",\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "proxy_traps": 0,
      "coercion_calls": 0,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "private raw canonical port integer before conversion; no public clap numeric grammar claim"
  },
  {
    "id": "private-issuer-noncanonical-zero",
    "argv_json": "[\"query\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"query\",\"manual-ip\",-0,false,false,null,false,false,false,false,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"parser_contract_failure\",\"exit\":2,\"output\":\"json\",\"transport\":null,\"port\":null,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":\"private_discovery_parser\",\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "proxy_traps": 0,
      "coercion_calls": 0,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "private raw canonical port integer before conversion; no public clap numeric grammar claim"
  },
  {
    "id": "private-issuer-oversize-port",
    "argv_json": "[\"query\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "issue",
      "wire": "[\"invocation\",\"query\",\"manual-ip\",65536,false,false,null,false,false,false,false,false,false]"
    },
    "expected_decision_utf8": "{\"kind\":\"parser_contract_failure\",\"exit\":2,\"output\":\"json\",\"transport\":null,\"port\":null,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":\"private_discovery_parser\",\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "proxy_traps": 0,
      "coercion_calls": 0,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "private raw canonical port integer before conversion; no public clap numeric grammar claim"
  },
  {
    "id": "private-parser-foreign-owned",
    "argv_json": "[\"query\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "foreign_issuer"
    },
    "expected_decision_utf8": "{\"kind\":\"parser_contract_failure\",\"exit\":2,\"output\":\"json\",\"transport\":null,\"port\":null,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":\"private_discovery_parser\",\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "proxy_traps": 0,
      "coercion_calls": 0,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "same-factory ownership before property reads; fixed error, provider causes never published"
  },
  {
    "id": "private-parser-proxy-result",
    "argv_json": "[\"query\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "proxy"
    },
    "expected_decision_utf8": "{\"kind\":\"parser_contract_failure\",\"exit\":2,\"output\":\"json\",\"transport\":null,\"port\":null,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":\"private_discovery_parser\",\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "proxy_traps": 0,
      "coercion_calls": 0,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "same-factory ownership before property reads; fixed error, provider causes never published"
  },
  {
    "id": "private-parser-raw-record-result",
    "argv_json": "[\"query\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "record"
    },
    "expected_decision_utf8": "{\"kind\":\"parser_contract_failure\",\"exit\":2,\"output\":\"json\",\"transport\":null,\"port\":null,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":\"private_discovery_parser\",\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "proxy_traps": 0,
      "coercion_calls": 0,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "same-factory ownership before property reads; fixed error, provider causes never published"
  },
  {
    "id": "private-parser-throw-redacted",
    "argv_json": "[\"query\"]",
    "tty": false,
    "parser_stimulus": {
      "behavior": "throw_private_provider_error"
    },
    "expected_decision_utf8": "{\"kind\":\"parser_contract_failure\",\"exit\":2,\"output\":\"json\",\"transport\":null,\"port\":null,\"recognized_operation\":false,\"request_sent\":false,\"authority_granted\":false,\"catalog\":null,\"operation\":null,\"guidance\":null,\"text_reference\":null,\"missing_dates\":null,\"missing_mode\":null,\"missing_scope\":null,\"error\":\"private_discovery_parser\",\"error_kind\":null}\n",
    "expected_effects": {
      "parser_calls": 1,
      "proxy_traps": 0,
      "coercion_calls": 0,
      "network": 0,
      "credentials": 0,
      "mutations": 0,
      "source_calls": 0,
      "acquires": 0,
      "releases": 0,
      "stdout_writes": 0
    },
    "source_policy": "same-factory ownership before property reads; fixed error, provider causes never published"
  }
] as const;
